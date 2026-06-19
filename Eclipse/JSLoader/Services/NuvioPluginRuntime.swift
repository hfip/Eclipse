//
//  NuvioPluginRuntime.swift
//  Eclipse
//

import CommonCrypto
import CryptoKit
import Foundation
import JavaScriptCore
import SwiftSoup

@MainActor
enum NuvioPluginRuntime {
    private static let timeoutSeconds: TimeInterval = 60
    // Truncate by character count on an already-decoded string (matching the Nuvio
    // reference runtime) instead of slicing raw bytes — slicing bytes could split a
    // multi-byte UTF-8 sequence and, combined with a strict decode, collapse the whole
    // body to "" so multi-step scrapers found nothing. Generous limit for large pages/JSON.
    private static let maxFetchBodyChars = 1024 * 1024
    // Defensive cap on how many raw bytes we decode, so a plugin that accidentally
    // fetches a huge payload can't blow up memory while building the string.
    private static let maxFetchBodyDecodeBytes = 4 * 1024 * 1024
    private static let maxHeaderValueCharacters = 8 * 1024
    // Stable desktop User-Agent used only when a plugin doesn't set its own. Scraper
    // sites frequently serve different/blocked content to the rotating (often mobile)
    // app User-Agent, so plugins need a predictable desktop identity like the reference.
    private static let defaultDesktopUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"

    static func execute(
        code: String,
        tmdbId: String,
        mediaType: String,
        season: Int?,
        episode: Int?,
        scraper: NuvioPluginScraper,
        source: NuvioPluginSource,
        scraperSettings: [String: Any]
    ) async throws -> [NuvioPluginStream] {
        try await withCheckedThrowingContinuation { continuation in
            let box = NuvioPluginRuntimeCompletion(continuation: continuation)
            box.timeout = DispatchWorkItem {
                box.fail(NuvioPluginError.runtimeTimeout)
            }
            if let timeout = box.timeout {
                DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
            }

            let context = JSContext()
            box.context = context
            let cheerio = NuvioCheerioBridge()

            context?.exceptionHandler = { _, exception in
                if let exception {
                    Logger.shared.log("Nuvio plugin JS exception provider=\(scraper.name): \(exception)", type: "Plugin")
                }
            }

            configure(context, box: box, cheerio: cheerio, scraper: scraper, source: source)

            let settingsJSON = jsonLiteral(scraperSettings) ?? "{}"
            context?.evaluateScript(polyfillCode(scraperId: scraper.id, settingsJSON: settingsJSON))
            context?.evaluateScript(moduleWrapped(code))

            if let exception = context?.exception {
                box.fail(NuvioPluginError.runtimeFailed(exception.toString() ?? "Plugin failed to load."))
                return
            }

            let invocation = invocationCode(
                tmdbId: tmdbId,
                mediaType: mediaType,
                season: season,
                episode: episode
            )
            context?.evaluateScript(invocation)

            if let exception = context?.exception {
                box.fail(NuvioPluginError.runtimeFailed(exception.toString() ?? "Plugin failed to run."))
            }
        }
    }

    private static func configure(
        _ context: JSContext?,
        box: NuvioPluginRuntimeCompletion,
        cheerio: NuvioCheerioBridge,
        scraper: NuvioPluginScraper,
        source: NuvioPluginSource
    ) {
        guard let context else { return }

        let captureResult: @convention(block) (String) -> Void = { rawJSON in
            do {
                let streams = try parseStreams(rawJSON: rawJSON, scraper: scraper, source: source)
                box.succeed(streams)
            } catch {
                box.fail(error)
            }
        }
        context.setObject(captureResult, forKeyedSubscript: "__capture_result" as NSString)

        let captureError: @convention(block) (String) -> Void = { message in
            box.fail(NuvioPluginError.runtimeFailed(message))
        }
        context.setObject(captureError, forKeyedSubscript: "__capture_error" as NSString)

        let console = JSValue(newObjectIn: context)
        let log: @convention(block) (String) -> Void = { message in
            Logger.shared.log("Nuvio plugin console provider=\(scraper.name): \(message)", type: "Plugin")
        }
        console?.setObject(log, forKeyedSubscript: "log" as NSString)
        console?.setObject(log, forKeyedSubscript: "info" as NSString)
        console?.setObject(log, forKeyedSubscript: "debug" as NSString)
        console?.setObject(log, forKeyedSubscript: "warn" as NSString)
        console?.setObject(log, forKeyedSubscript: "error" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)

        let nativeFetch: @convention(block) (String, String, JSValue?, String?, ObjCBool, JSValue, JSValue) -> Void = { urlString, method, headersValue, body, followRedirects, resolve, reject in
            Task {
                do {
                    let response = try await fetch(
                        urlString: urlString,
                        method: method,
                        headers: headers(from: headersValue),
                        body: body,
                        followRedirects: followRedirects.boolValue,
                        scraperName: scraper.name
                    )
                    DispatchQueue.main.async {
                        resolve.call(withArguments: [response])
                    }
                } catch {
                    DispatchQueue.main.async {
                        reject.call(withArguments: [error.localizedDescription])
                    }
                }
            }
        }
        context.setObject(nativeFetch, forKeyedSubscript: "__native_fetch" as NSString)

        // Back the setTimeout polyfill: JavaScriptCore has no timers, and several scrapers
        // wrap fetch in a setTimeout-based timeout (Promise.race) — without this they die
        // with "Can't find variable: setTimeout" and return nothing. Delay is clamped to the
        // overall runtime budget, and callbacks are dropped once the plugin has completed.
        let scheduleTimeout: @convention(block) (JSValue?, Double) -> Void = { callback, milliseconds in
            guard let callback, !callback.isUndefined, !callback.isNull else { return }
            let clamped = min(max(0, milliseconds), timeoutSeconds * 1000)
            DispatchQueue.main.asyncAfter(deadline: .now() + clamped / 1000.0) {
                guard !box.isFinished else { return }
                callback.call(withArguments: [])
            }
        }
        context.setObject(scheduleTimeout, forKeyedSubscript: "__schedule_timeout" as NSString)

        let hash: @convention(block) (String, String) -> String = { algorithm, value in
            digestHex(algorithm: algorithm, value: value)
        }
        context.setObject(hash, forKeyedSubscript: "__crypto_hash" as NSString)

        let hmac: @convention(block) (String, String, String) -> String = { algorithm, value, key in
            hmacHex(algorithm: algorithm, value: value, key: key)
        }
        context.setObject(hmac, forKeyedSubscript: "__crypto_hmac" as NSString)

        let base64Encode: @convention(block) (String) -> String = { value in
            Data(value.utf8).base64EncodedString()
        }
        context.setObject(base64Encode, forKeyedSubscript: "__base64_encode" as NSString)

        let base64Decode: @convention(block) (String) -> String = { value in
            guard let data = Data(base64Encoded: value) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
        context.setObject(base64Decode, forKeyedSubscript: "__base64_decode" as NSString)

        let utf8ToHex: @convention(block) (String) -> String = { value in
            Data(value.utf8).map { String(format: "%02x", $0) }.joined()
        }
        context.setObject(utf8ToHex, forKeyedSubscript: "__utf8_to_hex" as NSString)

        let hexToUTF8: @convention(block) (String) -> String = { value in
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "")
                .lowercased()
            let evenHex = normalized.count.isMultiple(of: 2) ? normalized : "0\(normalized)"
            var bytes: [UInt8] = []
            var index = evenHex.startIndex
            while index < evenHex.endIndex {
                let next = evenHex.index(index, offsetBy: 2)
                if let byte = UInt8(evenHex[index..<next], radix: 16) {
                    bytes.append(byte)
                }
                index = next
            }
            return String(data: Data(bytes), encoding: .utf8) ?? ""
        }
        context.setObject(hexToUTF8, forKeyedSubscript: "__hex_to_utf8" as NSString)

        let parseURL: @convention(block) (String, String?) -> [String: Any] = { value, base in
            Self.parseURL(value, base: base)
        }
        context.setObject(parseURL, forKeyedSubscript: "__parse_url" as NSString)

        let cheerioLoad: @convention(block) (String) -> Int32 = { html in
            Int32(cheerio.load(html))
        }
        context.setObject(cheerioLoad, forKeyedSubscript: "__cheerio_load" as NSString)

        let cheerioSelect: @convention(block) (Int32, String) -> [Int32] = { handle, selector in
            cheerio.select(handle: Int(handle), selector: selector).map(Int32.init)
        }
        context.setObject(cheerioSelect, forKeyedSubscript: "__cheerio_select" as NSString)

        let cheerioText: @convention(block) (Int32) -> String = { handle in
            cheerio.text(handle: Int(handle))
        }
        context.setObject(cheerioText, forKeyedSubscript: "__cheerio_text" as NSString)

        let cheerioHTML: @convention(block) (Int32) -> String = { handle in
            cheerio.html(handle: Int(handle))
        }
        context.setObject(cheerioHTML, forKeyedSubscript: "__cheerio_html" as NSString)

        let cheerioInnerHTML: @convention(block) (Int32) -> String = { handle in
            cheerio.innerHTML(handle: Int(handle))
        }
        context.setObject(cheerioInnerHTML, forKeyedSubscript: "__cheerio_inner_html" as NSString)

        let cheerioAttr: @convention(block) (Int32, String) -> String? = { handle, name in
            cheerio.attr(handle: Int(handle), name: name)
        }
        context.setObject(cheerioAttr, forKeyedSubscript: "__cheerio_attr" as NSString)

        let cheerioNext: @convention(block) (Int32) -> Int32 = { handle in
            Int32(cheerio.next(handle: Int(handle)) ?? 0)
        }
        context.setObject(cheerioNext, forKeyedSubscript: "__cheerio_next" as NSString)

        let cheerioPrevious: @convention(block) (Int32) -> Int32 = { handle in
            Int32(cheerio.previous(handle: Int(handle)) ?? 0)
        }
        context.setObject(cheerioPrevious, forKeyedSubscript: "__cheerio_prev" as NSString)
    }

    private static func fetch(
        urlString: String,
        method: String,
        headers: [String: String],
        body: String?,
        followRedirects: Bool,
        scraperName: String
    ) async throws -> [String: Any] {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw NuvioPluginError.runtimeFailed("Invalid fetch URL.")
        }
        guard !ServiceSandboxState.isBlockedTrackingURL(url.absoluteString) else {
            Logger.shared.log("Nuvio plugin blocked tracking fetch provider=\(scraperName) target=\(ServiceSandboxState.redactedURL(url.absoluteString))", type: "ServiceSandbox")
            throw NuvioPluginError.runtimeFailed("Plugin network request blocked by sandbox.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.isEmpty ? "GET" : method.uppercased()
        request.timeoutInterval = 30
        for (key, value) in headers {
            let headerName = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let headerValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !headerName.isEmpty && !headerValue.isEmpty {
                request.setValue(String(headerValue.prefix(maxHeaderValueCharacters)), forHTTPHeaderField: headerName)
            }
        }
        // Mirror the reference runtime: only inject a default desktop User-Agent when the
        // plugin didn't provide one (request headers override the session's rotating UA),
        // and don't force DNT/Sec-GPC — some hosts vary or block responses based on them.
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(defaultDesktopUserAgent, forHTTPHeaderField: "User-Agent")
        }
        if let body, !body.isEmpty, request.httpMethod != "GET" {
            request.httpBody = Data(body.utf8)
        }

        let session = URLSession.fetchData(allowRedirects: followRedirects)
        defer { session.finishTasksAndInvalidate() }
        Logger.shared.log("Nuvio plugin fetch provider=\(scraperName) target=\(ServiceSandboxState.redactedURL(url.absoluteString))", type: "Plugin")
        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let text = decodeResponseBody(data)
        var responseHeaders: [String: String] = [:]
        httpResponse?.allHeaderFields.forEach { key, value in
            let headerName = String(describing: key)
            let headerValue = String(describing: value)
            responseHeaders[headerName] = String(headerValue.prefix(maxHeaderValueCharacters))
        }

        return [
            "ok": (200...299).contains(httpResponse?.statusCode ?? 0),
            "status": httpResponse?.statusCode ?? 0,
            "statusText": HTTPURLResponse.localizedString(forStatusCode: httpResponse?.statusCode ?? 0),
            "url": httpResponse?.url?.absoluteString ?? url.absoluteString,
            "headers": responseHeaders,
            "body": text
        ]
    }

    /// Decode a response body for plugin consumption. Uses lossy UTF-8 decoding over the
    /// full payload so a multi-byte boundary or a non-UTF-8 byte never collapses the entire
    /// body to an empty string (the previous strict `String(data:encoding:) ?? ""` silently
    /// emptied any response > 256 KB, which made multi-step scrapers "find nothing"). The
    /// raw decode is bounded for memory, then the result is truncated by character count.
    private static func decodeResponseBody(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        let limited = data.count > maxFetchBodyDecodeBytes ? Data(data.prefix(maxFetchBodyDecodeBytes)) : data
        var text = String(decoding: limited, as: UTF8.self)
        if text.count > maxFetchBodyChars {
            text = String(text.prefix(maxFetchBodyChars)) + "\n...[truncated]"
        }
        return text
    }

    private static func parseStreams(
        rawJSON: String,
        scraper: NuvioPluginScraper,
        source: NuvioPluginSource
    ) throws -> [NuvioPluginStream] {
        guard let data = rawJSON.data(using: .utf8) else {
            throw NuvioPluginError.invalidResponse
        }
        let decoded = try JSONSerialization.jsonObject(with: data)

        let array: [[String: Any]]
        if let direct = decoded as? [[String: Any]] {
            array = direct
        } else if let object = decoded as? [String: Any],
                  let streams = object["streams"] as? [[String: Any]] {
            array = streams
        } else {
            throw NuvioPluginError.invalidResponse
        }

        return array.enumerated().compactMap { index, item in
            let urlString = streamURL(from: item["url"])
            guard let urlString,
                  !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !urlString.lowercased().hasPrefix("magnet:"),
                  NuvioPluginSupport.isDirectHTTPURL(urlString) else {
                return nil
            }

            let title = cleanString(item["title"]) ?? cleanString(item["name"]) ?? "Stream"
            let headers = cleanHeaders(item["headers"])
            return NuvioPluginStream(
                id: NuvioPluginSupport.streamID(scraperId: scraper.id, sourceId: source.id, url: urlString, title: title, index: index),
                scraperId: scraper.id,
                scraperName: scraper.name,
                sourceId: source.id,
                sourceName: source.name,
                title: title,
                name: cleanString(item["name"]),
                url: urlString,
                quality: cleanString(item["quality"]),
                size: cleanString(item["size"]),
                language: cleanString(item["language"]),
                provider: cleanString(item["provider"]),
                type: cleanString(item["type"]),
                seeders: intValue(item["seeders"]),
                peers: intValue(item["peers"]),
                infoHash: cleanString(item["infoHash"]),
                headers: headers
            )
        }
    }

    private static func streamURL(from value: Any?) -> String? {
        if let value = value as? String { return cleanString(value) }
        if let value = value as? [String: Any] { return cleanString(value["url"]) }
        return nil
    }

    private static func cleanHeaders(_ value: Any?) -> [String: String]? {
        guard let dictionary = value as? [String: Any] else { return nil }
        let pairs = dictionary.compactMap { key, value -> (String, String)? in
            let headerName = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !headerName.isEmpty,
                  !headerName.caseInsensitiveCompare("Range").isSame,
                  let headerValue = cleanString(value),
                  !headerValue.isEmpty else {
                return nil
            }
            return (headerName, String(headerValue.prefix(maxHeaderValueCharacters)))
        }
        return pairs.isEmpty ? nil : Dictionary(uniqueKeysWithValues: pairs)
    }

    private static func cleanString(_ value: Any?) -> String? {
        let raw: String?
        if let value = value as? String {
            raw = value
        } else if let value = value as? NSNumber {
            raw = value.stringValue
        } else {
            raw = nil
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != "[object Object]" else {
            return nil
        }
        return trimmed
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func headers(from value: JSValue?) -> [String: String] {
        guard let raw = value,
              !raw.isNull,
              !raw.isUndefined,
              let dictionary = raw.toDictionary() as? [String: Any] else {
            return [:]
        }
        return dictionary.compactMapValues { value in
            if let value = value as? String { return value }
            if let value = value as? NSNumber { return value.stringValue }
            return nil
        }
    }

    private static func moduleWrapped(_ code: String) -> String {
        """
        (function() {
            var module = { exports: {} };
            var exports = module.exports;
            globalThis.module = module;
            globalThis.exports = exports;
            \(code)
            globalThis.__nuvio_module = module;
        })();
        """
    }

    private static func invocationCode(tmdbId: String, mediaType: String, season: Int?, episode: Int?) -> String {
        let tmdbLiteral = jsonLiteral(tmdbId) ?? "\"\(tmdbId)\""
        let mediaTypeLiteral = jsonLiteral(mediaType) ?? "\"\(mediaType)\""
        // Pass `undefined` (not `null`) for movies so plugins that rely on default
        // parameter values — `getStreams(id, type, season = 1, ...)` — behave like they
        // do under the reference runtime; defaults only apply for `undefined`.
        let seasonLiteral = season.map(String.init) ?? "undefined"
        let episodeLiteral = episode.map(String.init) ?? "undefined"
        return """
        (function() {
            var getStreams = (globalThis.__nuvio_module && globalThis.__nuvio_module.exports && globalThis.__nuvio_module.exports.getStreams) || globalThis.getStreams;
            if (typeof getStreams !== "function") {
                __capture_error("getStreams not found");
                return;
            }
            Promise.resolve(getStreams(\(tmdbLiteral), \(mediaTypeLiteral), \(seasonLiteral), \(episodeLiteral)))
                .then(function(result) {
                    __capture_result(JSON.stringify(result || []));
                })
                .catch(function(error) {
                    __capture_error(String((error && (error.stack || error.message)) || error || "Plugin failed"));
                });
        })();
        """
    }

    private static func polyfillCode(scraperId: String, settingsJSON: String) -> String {
        let scraperLiteral = jsonLiteral(scraperId) ?? "\"\(scraperId)\""
        return """
        globalThis.global = globalThis;
        globalThis.window = globalThis;
        globalThis.self = globalThis;
        globalThis.SCRAPER_ID = \(scraperLiteral);
        globalThis.SCRAPER_SETTINGS = \(settingsJSON);

        globalThis.atob = function(value) { return __base64_decode(String(value)); };
        globalThis.btoa = function(value) { return __base64_encode(String(value)); };

        if (!Array.prototype.flat) {
            Array.prototype.flat = function() { return [].concat.apply([], this); };
        }
        if (!Array.prototype.flatMap) {
            Array.prototype.flatMap = function(fn, thisArg) { return this.map(fn, thisArg).flat(); };
        }
        if (!Object.entries) {
            Object.entries = function(obj) { var out = []; for (var k in obj) if (Object.prototype.hasOwnProperty.call(obj, k)) out.push([k, obj[k]]); return out; };
        }
        if (!Object.fromEntries) {
            Object.fromEntries = function(entries) { var out = {}; entries.forEach(function(pair) { out[pair[0]] = pair[1]; }); return out; };
        }
        if (!String.prototype.replaceAll) {
            String.prototype.replaceAll = function(search, replacement) { return this.split(search).join(replacement); };
        }

        function HeadersShim(headers) {
            this._headers = headers || {};
        }
        HeadersShim.prototype.get = function(name) {
            var needle = String(name).toLowerCase();
            for (var key in this._headers) {
                if (String(key).toLowerCase() === needle) return this._headers[key];
            }
            return null;
        };

        globalThis.fetch = function(url, options) {
            options = options || {};
            var method = options.method || "GET";
            var headers = options.headers || {};
            var body = options.body == null ? null : String(options.body);
            var redirect = options.redirect === "manual" ? false : true;
            return new Promise(function(resolve, reject) {
                __native_fetch(String(url), String(method), headers, body, redirect, function(raw) {
                    var response = {
                        ok: !!raw.ok,
                        status: raw.status || 0,
                        statusText: raw.statusText || "",
                        url: raw.url || String(url),
                        headers: new HeadersShim(raw.headers || {}),
                        text: function() { return Promise.resolve(raw.body || ""); },
                        json: function() {
                            try { return Promise.resolve(JSON.parse(raw.body || "null")); }
                            catch (_) { return Promise.resolve(null); }
                        }
                    };
                    resolve(response);
                }, reject);
            });
        };

        globalThis.AbortController = function() { this.signal = { aborted: false }; };
        globalThis.AbortController.prototype.abort = function() { this.signal.aborted = true; };
        globalThis.AbortSignal = function() {};

        (function() {
            var __nuvioTimers = {};
            var __nuvioTimerSeq = 1;
            globalThis.setTimeout = function(handler, timeout) {
                if (typeof handler !== "function") return 0;
                var id = __nuvioTimerSeq++;
                __nuvioTimers[id] = true;
                var extraArgs = Array.prototype.slice.call(arguments, 2);
                __schedule_timeout(function() {
                    if (!__nuvioTimers[id]) return;
                    delete __nuvioTimers[id];
                    try { handler.apply(undefined, extraArgs); }
                    catch (e) { if (typeof console !== "undefined" && console.error) console.error("setTimeout callback error:", e); }
                }, Number(timeout) || 0);
                return id;
            };
            globalThis.clearTimeout = function(id) { if (id != null) delete __nuvioTimers[id]; };
            // No real interval timer (avoids runaway loops keeping the JS context alive);
            // scrapers only rely on setTimeout for fetch timeouts in practice.
            globalThis.setInterval = function() { return 0; };
            globalThis.clearInterval = function(id) { if (id != null) delete __nuvioTimers[id]; };
            globalThis.setImmediate = function(handler) {
                return globalThis.setTimeout.apply(null, [handler, 0].concat(Array.prototype.slice.call(arguments, 1)));
            };
            globalThis.clearImmediate = function(id) { globalThis.clearTimeout(id); };
            if (typeof globalThis.queueMicrotask !== "function") {
                globalThis.queueMicrotask = function(cb) { if (typeof cb === "function") Promise.resolve().then(cb); };
            }
        })();

        globalThis.URL = function(value, base) {
            var parsed = __parse_url(String(value), base == null ? null : String(base));
            this.href = parsed.href || String(value);
            this.protocol = parsed.protocol || "";
            this.host = parsed.host || "";
            this.hostname = parsed.hostname || "";
            this.pathname = parsed.pathname || "";
            this.search = parsed.search || "";
            this.hash = parsed.hash || "";
            this.origin = parsed.origin || "";
        };
        globalThis.URL.prototype.toString = function() { return this.href; };

        globalThis.URLSearchParams = function(value) {
            this._pairs = [];
            var text = value == null ? "" : String(value);
            if (text.charAt(0) === "?") text = text.slice(1);
            if (text.length > 0) {
                var parts = text.split("&");
                for (var i = 0; i < parts.length; i++) {
                    var pair = parts[i].split("=");
                    this._pairs.push([decodeURIComponent(pair[0] || ""), decodeURIComponent(pair.slice(1).join("=") || "")]);
                }
            }
        };
        globalThis.URLSearchParams.prototype.get = function(name) {
            for (var i = 0; i < this._pairs.length; i++) if (this._pairs[i][0] === name) return this._pairs[i][1];
            return null;
        };
        globalThis.URLSearchParams.prototype.set = function(name, value) {
            for (var i = 0; i < this._pairs.length; i++) {
                if (this._pairs[i][0] === name) {
                    this._pairs[i][1] = String(value);
                    return;
                }
            }
            this._pairs.push([String(name), String(value)]);
        };
        globalThis.URLSearchParams.prototype.append = function(name, value) {
            this._pairs.push([String(name), String(value)]);
        };
        globalThis.URLSearchParams.prototype.has = function(name) {
            for (var i = 0; i < this._pairs.length; i++) if (this._pairs[i][0] === name) return true;
            return false;
        };
        globalThis.URLSearchParams.prototype.delete = function(name) {
            this._pairs = this._pairs.filter(function(pair) { return pair[0] !== name; });
        };
        globalThis.URLSearchParams.prototype.getAll = function(name) {
            return this._pairs.filter(function(pair) { return pair[0] === name; }).map(function(pair) { return pair[1]; });
        };
        globalThis.URLSearchParams.prototype.entries = function() { return this._pairs.slice(); };
        globalThis.URLSearchParams.prototype.keys = function() { return this._pairs.map(function(pair) { return pair[0]; }); };
        globalThis.URLSearchParams.prototype.values = function() { return this._pairs.map(function(pair) { return pair[1]; }); };
        globalThis.URLSearchParams.prototype.forEach = function(callback) {
            for (var i = 0; i < this._pairs.length; i++) callback(this._pairs[i][1], this._pairs[i][0], this);
        };
        globalThis.URLSearchParams.prototype.toString = function() {
            return this._pairs.map(function(pair) { return encodeURIComponent(pair[0]) + "=" + encodeURIComponent(pair[1]); }).join("&");
        };

        function __hexToWords(hex) {
            var words = [];
            for (var i = 0; i < hex.length; i += 8) {
                var chunk = hex.substring(i, i + 8);
                while (chunk.length < 8) chunk += "0";
                words.push(parseInt(chunk, 16) | 0);
            }
            return words;
        }

        function __wordsToHex(words, sigBytes) {
            var hex = "";
            for (var i = 0; i < sigBytes; i++) {
                var word = words[i >>> 2] || 0;
                var byte = (word >>> (24 - (i % 4) * 8)) & 0xff;
                var part = byte.toString(16);
                if (part.length < 2) part = "0" + part;
                hex += part;
            }
            return hex;
        }

        function __wordArrayToHex(value) {
            if (!value) return "";
            if (typeof value.__hex === "string") return value.__hex.toLowerCase();
            if (Array.isArray(value.words) && typeof value.sigBytes === "number") return __wordsToHex(value.words, value.sigBytes);
            return __utf8_to_hex(String(value));
        }

        function cryptoWord(hex, utf8Override) {
            var normalizedHex = String(hex || "").toLowerCase();
            if (normalizedHex.length % 2 !== 0) normalizedHex = "0" + normalizedHex;
            return {
                __hex: normalizedHex,
                __utf8: utf8Override !== undefined ? utf8Override : __hex_to_utf8(normalizedHex),
                sigBytes: normalizedHex.length / 2,
                words: __hexToWords(normalizedHex),
                toString: function(encoder) {
                    if (!encoder || encoder === globalThis.CryptoJS.enc.Hex) return this.__hex;
                    if (encoder === globalThis.CryptoJS.enc.Utf8) return this.__utf8;
                    if (encoder === globalThis.CryptoJS.enc.Base64) return __base64_encode(this.__utf8);
                    return this.__hex;
                },
                clamp: function() { return this; },
                concat: function(other) {
                    this.__hex += __wordArrayToHex(other);
                    this.__utf8 = __hex_to_utf8(this.__hex);
                    this.sigBytes = this.__hex.length / 2;
                    this.words = __hexToWords(this.__hex);
                    return this;
                }
            };
        }
        function cryptoUtf8Word(value) {
            var text = String(value == null ? "" : value);
            return cryptoWord(__utf8_to_hex(text), text);
        }
        function cryptoBase64Word(value) {
            return cryptoUtf8Word(__base64_decode(String(value || "")));
        }
        function cryptoInput(value) {
            if (value && typeof value === "object" && typeof value.__utf8 === "string") return value.__utf8;
            if (value && typeof value === "object" && typeof value.__hex === "string") return __hex_to_utf8(value.__hex);
            if (value && typeof value === "object" && Array.isArray(value.words) && typeof value.sigBytes === "number") return __hex_to_utf8(__wordsToHex(value.words, value.sigBytes));
            return String(value == null ? "" : value);
        }
        globalThis.CryptoJS = {
            MD5: function(value) { return cryptoWord(__crypto_hash("MD5", cryptoInput(value))); },
            SHA1: function(value) { return cryptoWord(__crypto_hash("SHA1", cryptoInput(value))); },
            SHA256: function(value) { return cryptoWord(__crypto_hash("SHA256", cryptoInput(value))); },
            SHA512: function(value) { return cryptoWord(__crypto_hash("SHA512", cryptoInput(value))); },
            HmacMD5: function(value, key) { return cryptoWord(__crypto_hmac("MD5", cryptoInput(value), cryptoInput(key))); },
            HmacSHA1: function(value, key) { return cryptoWord(__crypto_hmac("SHA1", cryptoInput(value), cryptoInput(key))); },
            HmacSHA256: function(value, key) { return cryptoWord(__crypto_hmac("SHA256", cryptoInput(value), cryptoInput(key))); },
            HmacSHA512: function(value, key) { return cryptoWord(__crypto_hmac("SHA512", cryptoInput(value), cryptoInput(key))); },
            enc: {
                Utf8: { parse: function(value) { return cryptoUtf8Word(value); }, stringify: function(value) { return cryptoInput(value); } },
                Base64: { stringify: function(value) { return __base64_encode(cryptoInput(value)); }, parse: function(value) { return cryptoBase64Word(value); } },
                Hex: { stringify: function(value) { return __wordArrayToHex(value); }, parse: function(value) { return cryptoWord(String(value || "")); } }
            }
        };

        function createCheerioCollection(ids) {
            ids = ids || [];
            function api(selector) { return api.find(selector); }
            api.length = ids.length;
            api.get = function(index) {
                if (index === undefined) return ids.map(function(id) { return createCheerioCollection([id]); });
                return ids[index] == null ? undefined : createCheerioCollection([ids[index]]);
            };
            api.eq = function(index) { return ids[index] == null ? createCheerioCollection([]) : createCheerioCollection([ids[index]]); };
            api.first = function() { return api.eq(0); };
            api.last = function() { return api.eq(ids.length - 1); };
            api.text = function() { return ids.map(function(id) { return __cheerio_text(id); }).join(""); };
            api.html = function() { return ids.length ? __cheerio_inner_html(ids[0]) : null; };
            api.outerHtml = function() { return ids.length ? __cheerio_html(ids[0]) : null; };
            api.attr = function(name) {
                if (!ids.length) return undefined;
                var value = __cheerio_attr(ids[0], String(name));
                return value == null ? undefined : value;
            };
            api.find = function(selector) {
                var out = [];
                ids.forEach(function(id) { out = out.concat(__cheerio_select(id, String(selector))); });
                return createCheerioCollection(out);
            };
            api.next = function() {
                var out = [];
                ids.forEach(function(id) {
                    var next = __cheerio_next(id);
                    if (next) out.push(next);
                });
                return createCheerioCollection(out);
            };
            api.prev = function() {
                var out = [];
                ids.forEach(function(id) {
                    var previous = __cheerio_prev(id);
                    if (previous) out.push(previous);
                });
                return createCheerioCollection(out);
            };
            api.each = function(fn) {
                ids.forEach(function(id, index) { fn.call(createCheerioCollection([id]), index, createCheerioCollection([id])); });
                return api;
            };
            api.map = function(fn) {
                var out = [];
                ids.forEach(function(id, index) {
                    var value = fn.call(createCheerioCollection([id]), index, createCheerioCollection([id]));
                    if (value !== undefined && value !== null) out.push(value);
                });
                return {
                    length: out.length,
                    get: function(index) { return typeof index === "number" ? out[index] : out; },
                    toArray: function() { return out; }
                };
            };
            api.filter = function(selectorOrCallback) {
                if (typeof selectorOrCallback === "function") {
                    var filtered = [];
                    ids.forEach(function(id, index) {
                        var item = createCheerioCollection([id]);
                        if (selectorOrCallback.call(item, index, item)) filtered.push(id);
                    });
                    return createCheerioCollection(filtered);
                }
                return api;
            };
            api.children = function(selector) { return api.find(selector || "*"); };
            api.parent = function() { return createCheerioCollection([]); };
            api.toArray = function() { return ids.map(function(id) { return createCheerioCollection([id]); }); };
            return api;
        }
        function cheerioLoad(html) {
            var root = __cheerio_load(String(html || ""));
            function cheerioFn(selector, context) {
                if (selector == null) return createCheerioCollection([root]);
                // `$(existingCollection)` — return it untouched, matching cheerio.
                if (selector && typeof selector === "object" && typeof selector.toArray === "function") {
                    return selector;
                }
                // `$(selector, context)` — scope the search to the context collection.
                if (context && typeof context === "object" && typeof context.find === "function") {
                    return context.find(String(selector));
                }
                return createCheerioCollection(__cheerio_select(root, String(selector)));
            }
            // Static `$.html()` — serialize the whole document; `$.html(el)` serializes the
            // outer HTML of a node/collection. Common scraper idiom; matches the reference runtime.
            cheerioFn.html = function(node) {
                if (node && typeof node === "object" && typeof node.outerHtml === "function") {
                    return node.outerHtml();
                }
                return __cheerio_html(root);
            };
            return cheerioFn;
        }
        var cheerioModule = { load: cheerioLoad };

        globalThis.require = function(name) {
            if (name === "cheerio" || name === "cheerio-without-node-native" || name === "react-native-cheerio") return cheerioModule;
            if (name === "crypto-js") return globalThis.CryptoJS;
            throw new Error("Module not available: " + name);
        };
        """
    }

    private static func jsonLiteral(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else {
            if let string = value as? String,
               let data = try? JSONSerialization.data(withJSONObject: [string]),
               let text = String(data: data, encoding: .utf8) {
                return String(text.dropFirst().dropLast())
            }
            return nil
        }
        return text
    }

    private static func parseURL(_ value: String, base: String?) -> [String: Any] {
        let url: URL?
        if let base, let baseURL = URL(string: base) {
            url = URL(string: value, relativeTo: baseURL)?.absoluteURL
        } else {
            url = URL(string: value)
        }
        guard let url else { return ["href": value] }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return [
            "href": url.absoluteString,
            "protocol": (url.scheme ?? "").isEmpty ? "" : "\(url.scheme!):",
            "host": url.host ?? "",
            "hostname": url.host ?? "",
            "pathname": url.path,
            "search": components?.percentEncodedQuery.map { "?\($0)" } ?? "",
            "hash": components?.percentEncodedFragment.map { "#\($0)" } ?? "",
            "origin": "\(url.scheme ?? "")://\(url.host ?? "")"
        ]
    }

    private static func digestHex(algorithm: String, value: String) -> String {
        let data = Data(value.utf8)
        switch algorithm.uppercased() {
        case "MD5":
            return md5Hex(data)
        case "SHA1":
            return sha1Hex(data)
        case "SHA512":
            return SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "HEX":
            return data.map { String(format: "%02x", $0) }.joined()
        default:
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    private static func md5Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha1Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA1(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func hmacHex(algorithm: String, value: String, key: String) -> String {
        let data = Data(value.utf8)
        let keyData = Data(key.utf8)
        let algorithmValue: CCHmacAlgorithm
        let length: Int
        switch algorithm.uppercased() {
        case "MD5":
            algorithmValue = CCHmacAlgorithm(kCCHmacAlgMD5)
            length = Int(CC_MD5_DIGEST_LENGTH)
        case "SHA1":
            algorithmValue = CCHmacAlgorithm(kCCHmacAlgSHA1)
            length = Int(CC_SHA1_DIGEST_LENGTH)
        case "SHA512":
            algorithmValue = CCHmacAlgorithm(kCCHmacAlgSHA512)
            length = Int(CC_SHA512_DIGEST_LENGTH)
        default:
            algorithmValue = CCHmacAlgorithm(kCCHmacAlgSHA256)
            length = Int(CC_SHA256_DIGEST_LENGTH)
        }

        var mac = [UInt8](repeating: 0, count: length)
        keyData.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                CCHmac(algorithmValue, keyBytes.baseAddress, keyData.count, dataBytes.baseAddress, data.count, &mac)
            }
        }
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}

private final class NuvioPluginRuntimeCompletion {
    var context: JSContext?
    var timeout: DispatchWorkItem?
    private let continuation: CheckedContinuation<[NuvioPluginStream], Error>
    private let lock = NSLock()
    private var completed = false

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    init(continuation: CheckedContinuation<[NuvioPluginStream], Error>) {
        self.continuation = continuation
    }

    func succeed(_ streams: [NuvioPluginStream]) {
        finish {
            continuation.resume(returning: streams)
        }
    }

    func fail(_ error: Error) {
        finish {
            continuation.resume(throwing: error)
        }
    }

    private func finish(_ resume: () -> Void) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let timeout = timeout
        self.timeout = nil
        context = nil
        lock.unlock()
        timeout?.cancel()
        resume()
    }
}

private final class NuvioCheerioBridge {
    private var nextHandle = 1
    private var documents: [Int: Document] = [:]
    private var elements: [Int: Element] = [:]

    func load(_ html: String) -> Int {
        let document = (try? SwiftSoup.parse(html)) ?? (try! SwiftSoup.parse(""))
        let handle = allocate()
        documents[handle] = document
        return handle
    }

    func select(handle: Int, selector: String) -> [Int] {
        let normalized = NuvioCheerioBridge.normalizeSelector(selector)
        do {
            if let document = documents[handle] {
                return try document.select(normalized).array().map(register)
            }
            if let element = elements[handle] {
                return try element.select(normalized).array().map(register)
            }
        } catch {
            Logger.shared.log("Nuvio cheerio selector failed selector=\(selector) error=\(error.localizedDescription)", type: "Plugin")
        }
        return []
    }

    // jQuery/cheerio plugins commonly write `:contains("text")` / `:contains('text')`,
    // but SwiftSoup (like jsoup) expects the argument unquoted: `:contains(text)`.
    // Strip the quotes so those selectors match instead of throwing. Mirrors the
    // reference runtime's `containsRegex` normalization.
    private static let containsRegex = try? NSRegularExpression(pattern: ":contains\\((\"|')(.*?)\\1\\)")

    private static func normalizeSelector(_ selector: String) -> String {
        guard let regex = containsRegex, selector.contains(":contains(") else { return selector }
        let range = NSRange(selector.startIndex..., in: selector)
        return regex.stringByReplacingMatches(in: selector, options: [], range: range, withTemplate: ":contains($2)")
    }

    func text(handle: Int) -> String {
        if let document = documents[handle] { return (try? document.text()) ?? "" }
        if let element = elements[handle] { return (try? element.text()) ?? "" }
        return ""
    }

    func html(handle: Int) -> String {
        if let document = documents[handle] { return (try? document.outerHtml()) ?? "" }
        if let element = elements[handle] { return (try? element.outerHtml()) ?? "" }
        return ""
    }

    func innerHTML(handle: Int) -> String {
        if let document = documents[handle] { return (try? document.html()) ?? "" }
        if let element = elements[handle] { return (try? element.html()) ?? "" }
        return ""
    }

    func attr(handle: Int, name: String) -> String? {
        guard let element = elements[handle] else { return nil }
        return try? element.attr(name)
    }

    func next(handle: Int) -> Int? {
        guard let element = elements[handle],
              let sibling = try? element.nextElementSibling() else {
            return nil
        }
        return register(sibling)
    }

    func previous(handle: Int) -> Int? {
        guard let element = elements[handle],
              let sibling = try? element.previousElementSibling() else {
            return nil
        }
        return register(sibling)
    }

    private func register(_ element: Element) -> Int {
        let handle = allocate()
        elements[handle] = element
        return handle
    }

    private func allocate() -> Int {
        defer { nextHandle += 1 }
        return nextHandle
    }
}

private extension ComparisonResult {
    var isSame: Bool { self == .orderedSame }
}
