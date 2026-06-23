import CommonCrypto
import CryptoKit
import Foundation
import JavaScriptCore
import SwiftSoup

enum NuvioPluginRuntime {
    private static let runtimeQueue = DispatchQueue(label: "app.eclipse.soupy.nuvio-plugin-runtime", qos: .userInitiated)
    private static let timeoutSeconds: TimeInterval = 60
    // Truncate by character count on an already-decoded string (matching the Nuvio reference runtime) instead of
    // slicing raw bytes,.
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
            runtimeQueue.async {
                let box = NuvioPluginRuntimeCompletion(continuation: continuation)
                box.timeout = DispatchWorkItem {
                    box.fail(NuvioPluginError.runtimeTimeout)
                }
                if let timeout = box.timeout {
                    runtimeQueue.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
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
                    runtimeQueue.async {
                        guard !box.isFinished else { return }
                        resolve.call(withArguments: [response])
                    }
                } catch {
                    runtimeQueue.async {
                        guard !box.isFinished else { return }
                        reject.call(withArguments: [error.localizedDescription])
                    }
                }
            }
        }
        context.setObject(nativeFetch, forKeyedSubscript: "__native_fetch" as NSString)

        // Back the setTimeout polyfill: JavaScriptCore has no timers, and several scrapers wrap fetch in a
        // setTimeout-based timeout.
        let scheduleTimeout: @convention(block) (JSValue?, Double) -> Void = { callback, milliseconds in
            guard let callback, !callback.isUndefined, !callback.isNull else { return }
            let clamped = min(max(0, milliseconds), timeoutSeconds * 1000)
            runtimeQueue.asyncAfter(deadline: .now() + clamped / 1000.0) {
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

        // Byte-accurate crypto bridges backing the CryptoJS / WebCrypto / TextEncoder polyfills.
        // Everything is hex-in / hex-out so binary data survives the JS<->Swift boundary intact.
        let utf8ToHexCrypto: @convention(block) (String) -> String = { value in
            hexFromData(Data(value.utf8))
        }
        context.setObject(utf8ToHexCrypto, forKeyedSubscript: "__crypto_utf8_to_hex" as NSString)

        let hexToUTF8Crypto: @convention(block) (String) -> String = { value in
            // Lenient UTF-8 decode (inserts U+FFFD for invalid bytes) instead of collapsing to "".
            String(decoding: dataFromHex(value), as: UTF8.self)
        }
        context.setObject(hexToUTF8Crypto, forKeyedSubscript: "__crypto_hex_to_utf8" as NSString)

        let digestRaw: @convention(block) (String, String) -> String = { name, dataHex in
            digestHexRaw(hashName: name, dataHex: dataHex)
        }
        context.setObject(digestRaw, forKeyedSubscript: "__crypto_digest_hex_raw" as NSString)

        let hmacRaw: @convention(block) (String, String, String) -> String = { name, keyHex, dataHex in
            hmacHexRaw(hashName: name, keyHex: keyHex, dataHex: dataHex)
        }
        context.setObject(hmacRaw, forKeyedSubscript: "__crypto_hmac_hex_raw" as NSString)

        let pbkdf2: @convention(block) (String, String, Int32, Int32, String) -> String = { passHex, saltHex, iterations, keyBits, name in
            pbkdf2Hex(passHex: passHex, saltHex: saltHex, iterations: Int(iterations), keyBits: Int(keyBits), hashName: name)
        }
        context.setObject(pbkdf2, forKeyedSubscript: "__crypto_pbkdf2_hex" as NSString)

        let aesEncrypt: @convention(block) (String, String, String, String) -> String = { mode, keyHex, ivHex, dataHex in
            cipherHex(encrypt: true, algorithmMode: mode, keyHex: keyHex, ivHex: ivHex, dataHex: dataHex)
        }
        context.setObject(aesEncrypt, forKeyedSubscript: "__crypto_aes_encrypt_hex" as NSString)

        let aesDecrypt: @convention(block) (String, String, String, String) -> String = { mode, keyHex, ivHex, dataHex in
            cipherHex(encrypt: false, algorithmMode: mode, keyHex: keyHex, ivHex: ivHex, dataHex: dataHex)
        }
        context.setObject(aesDecrypt, forKeyedSubscript: "__crypto_aes_decrypt_hex" as NSString)

        let des3Encrypt: @convention(block) (String, String, String, String) -> String = { mode, keyHex, ivHex, dataHex in
            cipherHex(encrypt: true, algorithmMode: mode, keyHex: keyHex, ivHex: ivHex, dataHex: dataHex)
        }
        context.setObject(des3Encrypt, forKeyedSubscript: "__crypto_des3_encrypt_hex" as NSString)

        let des3Decrypt: @convention(block) (String, String, String, String) -> String = { mode, keyHex, ivHex, dataHex in
            cipherHex(encrypt: false, algorithmMode: mode, keyHex: keyHex, ivHex: ivHex, dataHex: dataHex)
        }
        context.setObject(des3Decrypt, forKeyedSubscript: "__crypto_des3_decrypt_hex" as NSString)

        let randomValues: @convention(block) (Int32) -> String = { byteLength in
            randomHex(byteLength: Int(byteLength))
        }
        context.setObject(randomValues, forKeyedSubscript: "__crypto_get_random_values_hex" as NSString)

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
        // and don't force DNT/Sec-GPC - some hosts vary or block responses based on them.
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

    /// Decode a response body for plugin consumption.
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
            let subtitles = parseSubtitles(from: item)
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
                headers: headers,
                subtitles: subtitles
            )
        }
    }

    private static func streamURL(from value: Any?) -> String? {
        if let value = value as? String { return cleanString(value) }
        if let value = value as? [String: Any] { return cleanString(value["url"]) }
        return nil
    }

    private static func parseSubtitles(from item: [String: Any]) -> [NuvioPluginSubtitle]? {
        let topLevelHeaders = cleanHeaders(item["subtitleHeaders"])
            ?? cleanHeaders(item["subtitlesHeaders"])
            ?? cleanHeaders(item["subtitle_headers"])
        var subtitles: [NuvioPluginSubtitle] = []

        if let subtitle = cleanString(item["subtitle"] ?? item["subtitleURL"] ?? item["subtitleUrl"]),
           NuvioPluginSupport.isDirectHTTPURL(subtitle) {
            subtitles.append(NuvioPluginSubtitle(
                url: subtitle,
                language: cleanString(item["subtitleLanguage"] ?? item["subtitleLang"] ?? item["lang"]) ?? "Unknown",
                name: cleanString(item["subtitleName"] ?? item["subtitleTitle"]),
                headers: topLevelHeaders
            ))
        }

        for key in ["subtitles", "subtitleTracks", "allSubtitles"] {
            guard let value = item[key] else { continue }
            subtitles.append(contentsOf: parseSubtitleValue(value, inheritedHeaders: topLevelHeaders))
        }

        var seen = Set<String>()
        let deduped = subtitles.filter { subtitle in
            let normalized = subtitle.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return false }
            return true
        }
        return deduped.isEmpty ? nil : deduped
    }

    private static func parseSubtitleValue(_ value: Any, inheritedHeaders: [String: String]?) -> [NuvioPluginSubtitle] {
        if let dictionary = value as? [String: Any],
           let subtitle = parseSubtitleObject(dictionary, inheritedHeaders: inheritedHeaders) {
            return [subtitle]
        }

        if let dictionaries = value as? [[String: Any]] {
            return dictionaries.compactMap { parseSubtitleObject($0, inheritedHeaders: inheritedHeaders) }
        }

        if let strings = value as? [String] {
            return parseSubtitleStrings(strings, inheritedHeaders: inheritedHeaders)
        }

        if let urlString = cleanString(value),
           NuvioPluginSupport.isDirectHTTPURL(urlString) {
            return [NuvioPluginSubtitle(url: urlString, language: "Unknown", name: nil, headers: inheritedHeaders)]
        }

        return []
    }

    private static func parseSubtitleObject(_ object: [String: Any], inheritedHeaders: [String: String]?) -> NuvioPluginSubtitle? {
        guard let url = cleanString(object["url"] ?? object["href"] ?? object["link"] ?? object["file"] ?? object["src"]),
              NuvioPluginSupport.isDirectHTTPURL(url) else {
            return nil
        }

        let language = cleanString(object["language"] ?? object["lang"] ?? object["locale"]) ?? "Unknown"
        let name = cleanString(object["name"] ?? object["title"] ?? object["label"])
        let headers = cleanHeaders(object["headers"] ?? object["requestHeaders"] ?? object["subtitleHeaders"]) ?? inheritedHeaders

        return NuvioPluginSubtitle(url: url, language: language, name: name, headers: headers)
    }

    private static func parseSubtitleStrings(_ values: [String], inheritedHeaders: [String: String]?) -> [NuvioPluginSubtitle] {
        var subtitles: [NuvioPluginSubtitle] = []
        var pendingLabel: String?

        for rawValue in values {
            guard let value = cleanString(rawValue) else { continue }
            if NuvioPluginSupport.isDirectHTTPURL(value) {
                subtitles.append(NuvioPluginSubtitle(
                    url: value,
                    language: pendingLabel ?? "Unknown",
                    name: pendingLabel,
                    headers: inheritedHeaders
                ))
                pendingLabel = nil
            } else {
                pendingLabel = value
            }
        }

        return subtitles
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
              !raw.isUndefined else {
            return [:]
        }

        if let dictionary = raw.toDictionary() {
            let direct = cleanHeaderDictionary(dictionary)
            if !direct.isEmpty { return direct }

            if let nested = dictionary["_headers"] as? [AnyHashable: Any] {
                let nestedHeaders = cleanHeaderDictionary(nested)
                if !nestedHeaders.isEmpty { return nestedHeaders }
            } else if let nested = dictionary["_headers"] as? [String: Any] {
                let nestedHeaders = cleanHeaderDictionary(Dictionary(uniqueKeysWithValues: nested.map { (AnyHashable($0.key), $0.value) }))
                if !nestedHeaders.isEmpty { return nestedHeaders }
            }
        }

        let nested = raw.forProperty("_headers")
        if let nested,
           !nested.isNull,
           !nested.isUndefined,
           let dictionary = nested.toDictionary() {
            let nestedHeaders = cleanHeaderDictionary(dictionary)
            if !nestedHeaders.isEmpty { return nestedHeaders }
        }

        if let entries = raw.invokeMethod("entries", withArguments: [])?.toArray() {
            let entryHeaders = cleanHeaderEntries(entries)
            if !entryHeaders.isEmpty { return entryHeaders }
        }

        return [:]
    }

    private static func cleanHeaderDictionary(_ dictionary: [AnyHashable: Any]) -> [String: String] {
        let pairs = dictionary.compactMap { key, value -> (String, String)? in
            let headerName = String(describing: key).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !headerName.isEmpty,
                  !headerName.caseInsensitiveCompare("Range").isSame,
                  let headerValue = cleanString(value),
                  !headerValue.isEmpty else {
                return nil
            }
            return (headerName, String(headerValue.prefix(maxHeaderValueCharacters)))
        }
        var headers: [String: String] = [:]
        for (key, value) in pairs {
            headers[key] = value
        }
        return headers
    }

    private static func cleanHeaderEntries(_ entries: [Any]) -> [String: String] {
        let pairs = entries.compactMap { entry -> (String, String)? in
            guard let pair = entry as? [Any],
                  pair.count >= 2,
                  let key = cleanString(pair[0]),
                  let value = cleanString(pair[1]) else {
                return nil
            }
            let headerName = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let headerValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !headerName.isEmpty,
                  !headerName.caseInsensitiveCompare("Range").isSame,
                  !headerValue.isEmpty else {
                return nil
            }
            return (headerName, String(headerValue.prefix(maxHeaderValueCharacters)))
        }
        var headers: [String: String] = [:]
        for (key, value) in pairs {
            headers[key] = value
        }
        return headers
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
        // parameter values - `getStreams(id, type, season = 1, ...)` - behave like they
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

        // atob/btoa must operate on binary ("Latin1") strings - one character per byte (0-255) -
        // NOT UTF-8. Decoding the base64 bytes as UTF-8 (the previous behaviour) returned "" for any
        // payload that wasn't valid UTF-8, breaking every scraper that base64-decodes ciphertext,
        // obfuscated config, or otherwise feeds the result through `charCodeAt`. Pure-JS,
        // binary-correct implementations matching the reference runtime and browsers:
        globalThis.atob = function(value) {
            var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
            var str = String(value).replace(/=+$/, "");
            if (str.length % 4 === 1) throw new Error("InvalidCharacterError");
            var output = "";
            var bc = 0, bs, buffer, idx = 0;
            while ((buffer = str.charAt(idx++))) {
                buffer = chars.indexOf(buffer);
                if (buffer === -1) continue;
                bs = bc % 4 ? bs * 64 + buffer : buffer;
                if (bc++ % 4) output += String.fromCharCode(255 & (bs >> ((-2 * bc) & 6)));
            }
            return output;
        };
        globalThis.btoa = function(value) {
            var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
            var str = String(value);
            var output = "";
            for (var block, charCode, idx = 0, map = chars;
                 str.charAt(idx | 0) || (map = "=", idx % 1);
                 output += map.charAt(63 & (block >> (8 - (idx % 1) * 8)))) {
                charCode = str.charCodeAt(idx += 3 / 4);
                if (charCode > 0xFF) throw new Error("InvalidCharacterError");
                block = (block << 8) | charCode;
            }
            return output;
        };

        if (!Array.prototype.flat) {
            Array.prototype.flat = function(depth) {
                depth = depth === undefined ? 1 : Math.floor(depth);
                if (depth < 1) return Array.prototype.slice.call(this);
                function flatten(items, level) {
                    return items.reduce(function(output, item) {
                        return output.concat(Array.isArray(item) && level > 0 ? flatten(item, level - 1) : item);
                    }, []);
                }
                return flatten(this, depth);
            };
        }
        if (!Array.prototype.flatMap) {
            Array.prototype.flatMap = function(fn, thisArg) { return this.map(fn, thisArg).flat(1); };
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
            this._headers = {};
            var self = this;
            function add(name, value) {
                if (name == null || value == null) return;
                self._headers[String(name)] = String(value);
            }
            if (headers instanceof HeadersShim) {
                headers.forEach(function(value, name) { add(name, value); });
            } else if (Array.isArray(headers)) {
                headers.forEach(function(pair) {
                    if (pair && pair.length >= 2) add(pair[0], pair[1]);
                });
            } else if (headers && typeof headers.entries === "function" && !headers._pairs) {
                var entries = headers.entries();
                if (Array.isArray(entries)) {
                    entries.forEach(function(pair) {
                        if (pair && pair.length >= 2) add(pair[0], pair[1]);
                    });
                }
            } else if (headers && typeof headers === "object") {
                Object.keys(headers).forEach(function(name) { add(name, headers[name]); });
            }
        }
        HeadersShim.prototype.get = function(name) {
            var needle = String(name).toLowerCase();
            for (var key in this._headers) {
                if (String(key).toLowerCase() === needle) return this._headers[key];
            }
            return null;
        };
        HeadersShim.prototype.set = function(name, value) { this._headers[String(name)] = String(value); };
        HeadersShim.prototype.append = function(name, value) { this.set(name, value); };
        HeadersShim.prototype.has = function(name) { return this.get(name) !== null; };
        HeadersShim.prototype.delete = function(name) {
            var needle = String(name).toLowerCase();
            for (var key in this._headers) {
                if (String(key).toLowerCase() === needle) delete this._headers[key];
            }
        };
        HeadersShim.prototype.entries = function() {
            var self = this;
            return Object.keys(this._headers).map(function(key) { return [key, self._headers[key]]; });
        };
        HeadersShim.prototype.keys = function() { return Object.keys(this._headers); };
        HeadersShim.prototype.values = function() {
            var self = this;
            return Object.keys(this._headers).map(function(key) { return self._headers[key]; });
        };
        HeadersShim.prototype.forEach = function(callback) {
            var self = this;
            Object.keys(this._headers).forEach(function(key) { callback(self._headers[key], key, self); });
        };
        if (typeof Symbol !== "undefined" && Symbol.iterator) {
            HeadersShim.prototype[Symbol.iterator] = function() { return this.entries()[Symbol.iterator](); };
        }
        globalThis.Headers = HeadersShim;

        function headersToObject(headers) {
            var out = {};
            var shim = new HeadersShim(headers || {});
            shim.forEach(function(value, name) { out[name] = value; });
            return out;
        }

        globalThis.fetch = function(url, options) {
            options = options || {};
            var method = options.method || "GET";
            var headers = headersToObject(options.headers || {});
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

        globalThis.AbortSignal = function() {
            this.aborted = false;
            this.reason = undefined;
            this._listeners = [];
        };
        globalThis.AbortSignal.prototype.addEventListener = function(type, listener) {
            if (type === "abort" && typeof listener === "function") this._listeners.push(listener);
        };
        globalThis.AbortSignal.prototype.removeEventListener = function(type, listener) {
            if (type !== "abort") return;
            this._listeners = this._listeners.filter(function(value) { return value !== listener; });
        };
        globalThis.AbortSignal.prototype.dispatchEvent = function(event) {
            if (!event || event.type !== "abort") return true;
            this._listeners.forEach(function(listener) {
                try { listener.call(this, event); } catch (_) {}
            }, this);
            return true;
        };
        globalThis.AbortController = function() { this.signal = new globalThis.AbortSignal(); };
        globalThis.AbortController.prototype.abort = function(reason) {
            if (this.signal.aborted) return;
            this.signal.aborted = true;
            this.signal.reason = reason;
            this.signal.dispatchEvent({ type: "abort" });
        };

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
            this.port = parsed.port || "";
            this.pathname = parsed.pathname || "";
            this.search = parsed.search || "";
            this.hash = parsed.hash || "";
            this.origin = parsed.origin || "";
            this.searchParams = new globalThis.URLSearchParams(this.search || "");
        };
        globalThis.URL.prototype.toString = function() { return this.href; };

        globalThis.URLSearchParams = function(value) {
            this._pairs = [];
            if (value && value._pairs && Array.isArray(value._pairs)) {
                this._pairs = value._pairs.map(function(pair) { return [String(pair[0]), String(pair[1])]; });
                return;
            }
            if (Array.isArray(value)) {
                for (var pairIndex = 0; pairIndex < value.length; pairIndex++) {
                    var item = value[pairIndex];
                    if (item && item.length >= 2) this._pairs.push([String(item[0]), String(item[1])]);
                }
                return;
            }
            if (value && typeof value === "object") {
                var self = this;
                Object.keys(value).forEach(function(key) { self._pairs.push([String(key), String(value[key])]); });
                return;
            }
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
        globalThis.URLSearchParams.prototype.sort = function() {
            this._pairs.sort(function(lhs, rhs) { return lhs[0] < rhs[0] ? -1 : (lhs[0] > rhs[0] ? 1 : 0); });
        };
        globalThis.URLSearchParams.prototype.toString = function() {
            return this._pairs.map(function(pair) { return encodeURIComponent(pair[0]) + "=" + encodeURIComponent(pair[1]); }).join("&");
        };
        if (typeof Symbol !== "undefined" && Symbol.iterator) {
            globalThis.URLSearchParams.prototype[Symbol.iterator] = function() { return this.entries()[Symbol.iterator](); };
        }

        // ===== TextEncoder / TextDecoder =====
        if (typeof TextEncoder === "undefined") {
            globalThis.TextEncoder = function() {};
            TextEncoder.prototype.encode = function(str) {
                var hex = __crypto_utf8_to_hex(String(str == null ? "" : str));
                var bytes = new Uint8Array(hex.length / 2);
                for (var i = 0; i < hex.length; i += 2) bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
                return bytes;
            };
        }
        if (typeof TextDecoder === "undefined") {
            globalThis.TextDecoder = function() {};
            TextDecoder.prototype.decode = function(data) {
                var bytes = data;
                if (data instanceof ArrayBuffer) bytes = new Uint8Array(data);
                else if (data && data.buffer instanceof ArrayBuffer && !(data instanceof Uint8Array)) bytes = new Uint8Array(data.buffer, data.byteOffset || 0, data.byteLength);
                var hex = "";
                for (var i = 0; i < bytes.length; i++) hex += bytes[i].toString(16).padStart(2, "0");
                return __crypto_hex_to_utf8(hex);
            };
        }

        // ===== CryptoJS (byte-accurate, native-backed) + TripleDES =====
        var WordArray = {
            init: function(words, sigBytes) {
                this.words = words || [];
                this.sigBytes = sigBytes != undefined ? sigBytes : this.words.length * 4;
            },
            toString: function(encoder) { return (encoder || CryptoJS.enc.Hex).stringify(this); },
            concat: function(wordArray) {
                var thisWords = this.words, thatWords = wordArray.words;
                var thisSigBytes = this.sigBytes, thatSigBytes = wordArray.sigBytes;
                this.clamp();
                for (var i = 0; i < thatSigBytes; i++) {
                    var thatByte = (thatWords[i >>> 2] >>> (24 - (i % 4) * 8)) & 0xff;
                    thisWords[(thisSigBytes + i) >>> 2] |= thatByte << (24 - ((thisSigBytes + i) % 4) * 8);
                }
                this.sigBytes += thatSigBytes;
                return this;
            },
            clamp: function() {
                var words = this.words, sigBytes = this.sigBytes;
                if (sigBytes % 4) words[sigBytes >>> 2] &= 0xffffffff << (32 - (sigBytes % 4) * 8);
                words.length = Math.ceil(sigBytes / 4);
                return this;
            },
            clone: function() { return __wordArrayCreate(this.words.slice(0), this.sigBytes); }
        };
        function __wordArrayCreate(words, sigBytes) { var wa = Object.create(WordArray); wa.init(words, sigBytes); return wa; }
        function __isWordArray(value) { return value && typeof value === "object" && Array.isArray(value.words) && typeof value.sigBytes === "number"; }
        function __copyUint8Array(bytes) { bytes = __toUint8Array(bytes); var copy = new Uint8Array(bytes.length); copy.set(bytes); return copy; }
        function __toUint8Array(data) {
            if (!data) return new Uint8Array(0);
            if (data instanceof Uint8Array) return data;
            if (data instanceof ArrayBuffer) return new Uint8Array(data);
            if (typeof ArrayBuffer !== "undefined" && ArrayBuffer.isView && ArrayBuffer.isView(data)) return new Uint8Array(data.buffer, data.byteOffset || 0, data.byteLength);
            if (Array.isArray(data)) return new Uint8Array(data);
            if (typeof data.length === "number") return new Uint8Array(Array.prototype.slice.call(data));
            return new Uint8Array(0);
        }
        function __bytesToArrayBuffer(bytes) { return __copyUint8Array(bytes).buffer; }
        function __wordArrayToBytes(wordArray) {
            if (!__isWordArray(wordArray)) return typeof wordArray === "string" ? new TextEncoder().encode(wordArray) : __toUint8Array(wordArray);
            var bytes = new Uint8Array(wordArray.sigBytes);
            for (var i = 0; i < wordArray.sigBytes; i++) bytes[i] = (wordArray.words[i >>> 2] >>> (24 - (i % 4) * 8)) & 0xff;
            return bytes;
        }
        function __bytesToWordArray(bytes) {
            bytes = __toUint8Array(bytes);
            var words = [];
            for (var i = 0; i < bytes.length; i++) words[i >>> 2] |= (bytes[i] & 0xff) << (24 - (i % 4) * 8);
            return __wordArrayCreate(words, bytes.length);
        }
        function __normalizeWordArrayInput(value) {
            if (__isWordArray(value)) return __wordArrayToBytes(value);
            if (typeof value === "string") return new TextEncoder().encode(value);
            return __toUint8Array(value);
        }
        function __bytesToHex(bytes) { bytes = __toUint8Array(bytes); var out = []; for (var i = 0; i < bytes.length; i++) { var hex = bytes[i].toString(16); out.push(hex.length < 2 ? "0" + hex : hex); } return out.join(""); }
        function __hexToBytes(hex) {
            hex = String(hex || "").replace(/[^0-9a-fA-F]/g, "");
            if (hex.length % 2) hex = "0" + hex;
            var bytes = new Uint8Array(hex.length / 2);
            for (var i = 0; i < hex.length; i += 2) bytes[i / 2] = parseInt(hex.substr(i, 2), 16) & 0xff;
            return bytes;
        }
        function __concatBytes() {
            var total = 0, parts = [];
            for (var i = 0; i < arguments.length; i++) { var part = __toUint8Array(arguments[i]); parts.push(part); total += part.length; }
            var out = new Uint8Array(total), offset = 0;
            for (var j = 0; j < parts.length; j++) { out.set(parts[j], offset); offset += parts[j].length; }
            return out;
        }
        function __normalizeHashName(hash) {
            var name = hash && hash.name ? hash.name : hash;
            name = String(name || "SHA-256").toUpperCase().replace(/[^A-Z0-9]/g, "");
            if (name === "SHA1" || name === "SHA256" || name === "SHA384" || name === "SHA512" || name === "MD5") return name;
            throw new Error("Unsupported hash algorithm: " + name);
        }
        function __normalizeAlgorithmName(algo) {
            var name = algo && algo.name ? algo.name : algo;
            name = String(name || "").toUpperCase();
            if (name.indexOf("AES-GCM") >= 0) return "AES-GCM";
            if (name.indexOf("AES-CBC") >= 0) return "AES-CBC";
            if (name.indexOf("AES-ECB") >= 0 || name === "ECB") return "AES-ECB";
            if (name.indexOf("PBKDF2") >= 0) return "PBKDF2";
            if (name.indexOf("HMAC") >= 0) return "HMAC";
            return name;
        }
        function __aesModeName(mode, padding) {
            var normalized = __normalizeAlgorithmName(mode || "AES-CBC");
            if (padding === CryptoJS.pad.NoPadding || padding === "NoPadding") normalized += "-NoPadding";
            return normalized;
        }
        function __des3ModeName(mode, padding) {
            var m = String((mode && mode.name) || mode || "CBC").toUpperCase();
            var normalized = m.indexOf("ECB") >= 0 ? "DES3-ECB" : "DES3-CBC";
            if (padding === CryptoJS.pad.NoPadding || padding === "NoPadding") normalized += "-NoPadding";
            return normalized;
        }
        function __nativeDigestBytes(hash, dataBytes) {
            if (typeof __crypto_digest_hex_raw === "undefined") throw new Error("Native digest bridge is unavailable");
            return __hexToBytes(__crypto_digest_hex_raw(__normalizeHashName(hash), __bytesToHex(dataBytes)));
        }
        function __nativeHmacBytes(hash, keyBytes, dataBytes) {
            if (typeof __crypto_hmac_hex_raw === "undefined") throw new Error("Native HMAC bridge is unavailable");
            return __hexToBytes(__crypto_hmac_hex_raw(__normalizeHashName(hash), __bytesToHex(keyBytes), __bytesToHex(dataBytes)));
        }
        function __nativePbkdf2Bytes(passwordBytes, saltBytes, iterations, keySizeBits, hash) {
            if (typeof __crypto_pbkdf2_hex === "undefined") throw new Error("Native PBKDF2 bridge is unavailable");
            return __hexToBytes(__crypto_pbkdf2_hex(__bytesToHex(passwordBytes), __bytesToHex(saltBytes), iterations, keySizeBits, __normalizeHashName(hash)));
        }
        function __nativeAesBytes(encrypt, mode, keyBytes, ivBytes, dataBytes) {
            var fn = encrypt ? __crypto_aes_encrypt_hex : __crypto_aes_decrypt_hex;
            if (typeof fn === "undefined") throw new Error("Native AES bridge is unavailable");
            return __hexToBytes(fn(mode, __bytesToHex(keyBytes), __bytesToHex(ivBytes), __bytesToHex(dataBytes)));
        }
        function __nativeDes3Bytes(encrypt, mode, keyBytes, ivBytes, dataBytes) {
            var fn = encrypt ? __crypto_des3_encrypt_hex : __crypto_des3_decrypt_hex;
            if (typeof fn === "undefined") throw new Error("Native TripleDES bridge is unavailable");
            return __hexToBytes(fn(mode, __bytesToHex(keyBytes), __bytesToHex(ivBytes), __bytesToHex(dataBytes)));
        }
        function __evpKdf(passwordBytes, saltBytes, keySizeBytes, ivSizeBytes) {
            var targetSize = keySizeBytes + ivSizeBytes;
            var derived = new Uint8Array(targetSize);
            var block = new Uint8Array(0), offset = 0;
            while (offset < targetSize) {
                block = __nativeDigestBytes("MD5", __concatBytes(block, passwordBytes, saltBytes || new Uint8Array(0)));
                var take = Math.min(block.length, targetSize - offset);
                derived.set(block.subarray(0, take), offset);
                offset += take;
            }
            return { key: derived.subarray(0, keySizeBytes), iv: derived.subarray(keySizeBytes, keySizeBytes + ivSizeBytes) };
        }
        function __opensslSaltHeader() { return new Uint8Array([83, 97, 108, 116, 101, 100, 95, 95]); }
        function __hasOpenSslSaltHeader(bytes) {
            var header = __opensslSaltHeader();
            if (!bytes || bytes.length < 16) return false;
            for (var i = 0; i < header.length; i++) if (bytes[i] !== header[i]) return false;
            return true;
        }
        function __makeCipherParams(ciphertext, key, iv, salt, mode) {
            return {
                ciphertext: __bytesToWordArray(ciphertext),
                key: key ? __bytesToWordArray(key) : undefined,
                iv: iv ? __bytesToWordArray(iv) : undefined,
                salt: salt ? __bytesToWordArray(salt) : undefined,
                mode: mode,
                toString: function(formatter) { return (formatter || CryptoJS.format.OpenSSL).stringify(this); }
            };
        }
        function __makeCipherApi(nativeFn, modeNameFn, keySizeBytes, ivSizeBytes) {
            return {
                encrypt: function(message, key, options) {
                    options = options || {};
                    var data = __normalizeWordArrayInput(message);
                    var kBytes, ivBytes, saltBytes;
                    if (typeof key === "string") {
                        saltBytes = options.salt ? __wordArrayToBytes(options.salt) : __wordArrayToBytes(CryptoJS.lib.WordArray.random(8));
                        var derived = __evpKdf(new TextEncoder().encode(key), saltBytes, keySizeBytes, ivSizeBytes);
                        kBytes = derived.key;
                        ivBytes = options.iv ? __wordArrayToBytes(options.iv) : derived.iv;
                    } else {
                        kBytes = __wordArrayToBytes(key);
                        ivBytes = options.iv ? __wordArrayToBytes(options.iv) : new Uint8Array(0);
                    }
                    var mode = modeNameFn(options.mode, options.padding);
                    var resBytes = nativeFn(true, mode, kBytes, ivBytes, data);
                    return __makeCipherParams(resBytes, kBytes, ivBytes, saltBytes, mode);
                },
                decrypt: function(cipher, key, options) {
                    options = options || {};
                    var cipherParams = typeof cipher === "string" ? CryptoJS.format.OpenSSL.parse(cipher) : cipher;
                    var data = cipherParams.ciphertext ? __wordArrayToBytes(cipherParams.ciphertext) : __toUint8Array(cipherParams);
                    var kBytes, ivBytes;
                    if (typeof key === "string") {
                        var saltBytes = options.salt ? __wordArrayToBytes(options.salt) : (cipherParams.salt ? __wordArrayToBytes(cipherParams.salt) : new Uint8Array(0));
                        var derived = __evpKdf(new TextEncoder().encode(key), saltBytes, keySizeBytes, ivSizeBytes);
                        kBytes = derived.key;
                        ivBytes = options.iv ? __wordArrayToBytes(options.iv) : derived.iv;
                    } else {
                        kBytes = __wordArrayToBytes(key);
                        ivBytes = options.iv ? __wordArrayToBytes(options.iv) : new Uint8Array(0);
                    }
                    var mode = modeNameFn(options.mode, options.padding);
                    return __bytesToWordArray(nativeFn(false, mode, kBytes, ivBytes, data));
                }
            };
        }
        var CryptoJS = {
            enc: {
                Hex: {
                    stringify: function(wordArray) { return __bytesToHex(__wordArrayToBytes(wordArray)); },
                    parse: function(hexStr) { return __bytesToWordArray(__hexToBytes(hexStr)); }
                },
                Utf8: {
                    stringify: function(wordArray) { return new TextDecoder("utf-8").decode(__wordArrayToBytes(wordArray)); },
                    parse: function(utf8Str) { return __bytesToWordArray(new TextEncoder().encode(String(utf8Str))); }
                },
                Latin1: {
                    stringify: function(wordArray) { var bytes = __wordArrayToBytes(wordArray); var out = ""; for (var i = 0; i < bytes.length; i++) out += String.fromCharCode(bytes[i]); return out; },
                    parse: function(str) { str = String(str || ""); var bytes = new Uint8Array(str.length); for (var i = 0; i < str.length; i++) bytes[i] = str.charCodeAt(i) & 0xff; return __bytesToWordArray(bytes); }
                },
                Base64: {
                    stringify: function(wordArray) { var bytes = __wordArrayToBytes(wordArray); var binaryStr = ""; for (var j = 0; j < bytes.length; j++) binaryStr += String.fromCharCode(bytes[j]); return btoa(binaryStr); },
                    parse: function(base64Str) { var binaryStr = atob(String(base64Str || "")); var bytes = new Uint8Array(binaryStr.length); for (var i = 0; i < binaryStr.length; i++) bytes[i] = binaryStr.charCodeAt(i) & 0xff; return __bytesToWordArray(bytes); }
                }
            },
            lib: {
                WordArray: {
                    create: function(words, sigBytes) {
                        if (words == null) return __wordArrayCreate([], sigBytes || 0);
                        if (__isWordArray(words)) return words.clone();
                        if (typeof words === "string") return CryptoJS.enc.Utf8.parse(words);
                        if (words instanceof ArrayBuffer || (typeof ArrayBuffer !== "undefined" && ArrayBuffer.isView && ArrayBuffer.isView(words))) {
                            var bytes = __toUint8Array(words);
                            return __bytesToWordArray(sigBytes != undefined ? bytes.subarray(0, sigBytes) : bytes);
                        }
                        return __wordArrayCreate(words, sigBytes);
                    },
                    random: function(nBytes) {
                        var bytes = new Uint8Array(nBytes || 0);
                        globalThis.crypto.getRandomValues(bytes);
                        return __bytesToWordArray(bytes);
                    }
                },
                CipherParams: {
                    create: function(params) {
                        params = params || {};
                        params.toString = params.toString || function(formatter) { return (formatter || CryptoJS.format.OpenSSL).stringify(this); };
                        return params;
                    }
                }
            },
            format: {
                OpenSSL: {
                    stringify: function(cipherParams) {
                        var cipherBytes = __wordArrayToBytes(cipherParams.ciphertext);
                        var out = cipherParams.salt ? __concatBytes(__opensslSaltHeader(), __wordArrayToBytes(cipherParams.salt), cipherBytes) : cipherBytes;
                        return CryptoJS.enc.Base64.stringify(__bytesToWordArray(out));
                    },
                    parse: function(str) {
                        var bytes = __wordArrayToBytes(CryptoJS.enc.Base64.parse(str));
                        if (__hasOpenSslSaltHeader(bytes)) return CryptoJS.lib.CipherParams.create({ salt: __bytesToWordArray(bytes.subarray(8, 16)), ciphertext: __bytesToWordArray(bytes.subarray(16)) });
                        return CryptoJS.lib.CipherParams.create({ ciphertext: __bytesToWordArray(bytes) });
                    }
                }
            },
            mode: { CBC: "AES-CBC", GCM: "AES-GCM", ECB: "AES-ECB" },
            pad: { Pkcs7: "Pkcs7", NoPadding: "NoPadding" },
            algo: { MD5: "MD5", SHA1: "SHA1", SHA256: "SHA256", SHA384: "SHA384", SHA512: "SHA512", AES: "AES" },
            MD5: function(m) { return __bytesToWordArray(__nativeDigestBytes("MD5", __normalizeWordArrayInput(m))); },
            SHA1: function(m) { return __bytesToWordArray(__nativeDigestBytes("SHA1", __normalizeWordArrayInput(m))); },
            SHA256: function(m) { return __bytesToWordArray(__nativeDigestBytes("SHA256", __normalizeWordArrayInput(m))); },
            SHA384: function(m) { return __bytesToWordArray(__nativeDigestBytes("SHA384", __normalizeWordArrayInput(m))); },
            SHA512: function(m) { return __bytesToWordArray(__nativeDigestBytes("SHA512", __normalizeWordArrayInput(m))); },
            HmacMD5: function(m, k) { return __bytesToWordArray(__nativeHmacBytes("MD5", __normalizeWordArrayInput(k), __normalizeWordArrayInput(m))); },
            HmacSHA1: function(m, k) { return __bytesToWordArray(__nativeHmacBytes("SHA1", __normalizeWordArrayInput(k), __normalizeWordArrayInput(m))); },
            HmacSHA256: function(m, k) { return __bytesToWordArray(__nativeHmacBytes("SHA256", __normalizeWordArrayInput(k), __normalizeWordArrayInput(m))); },
            HmacSHA384: function(m, k) { return __bytesToWordArray(__nativeHmacBytes("SHA384", __normalizeWordArrayInput(k), __normalizeWordArrayInput(m))); },
            HmacSHA512: function(m, k) { return __bytesToWordArray(__nativeHmacBytes("SHA512", __normalizeWordArrayInput(k), __normalizeWordArrayInput(m))); },
            PBKDF2: function(pass, salt, options) {
                options = options || {};
                var pBytes = __normalizeWordArrayInput(pass);
                var sBytes = __normalizeWordArrayInput(salt);
                var iter = options.iterations || 1000;
                var kSize = options.keySize || 8;
                var algo = options.hasher || "SHA1";
                return __bytesToWordArray(__nativePbkdf2Bytes(pBytes, sBytes, iter, kSize * 32, algo));
            }
        };
        CryptoJS.AES = __makeCipherApi(__nativeAesBytes, __aesModeName, 32, 16);
        CryptoJS.TripleDES = __makeCipherApi(__nativeDes3Bytes, __des3ModeName, 24, 8);
        CryptoJS.DES3 = CryptoJS.TripleDES;
        globalThis.CryptoJS = CryptoJS;

        // ===== Web Crypto (subtle digest/hmac/aes + getRandomValues) =====
        function __makeCryptoKey(type, algorithm, extractable, usages, rawBytes) {
            return { type: type, extractable: !!extractable, algorithm: algorithm, usages: usages || [], _raw: __copyUint8Array(rawBytes) };
        }
        function __webCryptoAlgorithm(algo) {
            var name = __normalizeAlgorithmName(algo);
            var out = { name: name };
            if (algo && typeof algo === "object" && algo.length) out.length = algo.length;
            if (algo && typeof algo === "object" && algo.hash) out.hash = { name: __normalizeHashName(algo.hash) };
            return out;
        }
        globalThis.crypto = {
            subtle: {
                digest: async function(algo, data) { return __bytesToArrayBuffer(__nativeDigestBytes(algo, __toUint8Array(data))); },
                importKey: async function(fmt, data, algo, extractable, usages) {
                    fmt = String(fmt || "raw").toLowerCase();
                    if (fmt !== "raw") throw new Error("Unsupported key format: " + fmt);
                    return __makeCryptoKey("secret", __webCryptoAlgorithm(algo || {}), extractable, usages || [], __toUint8Array(data));
                },
                exportKey: async function(fmt, key) { return __bytesToArrayBuffer(key._raw); },
                deriveBits: async function(params, key, len) {
                    if (__normalizeAlgorithmName(params) !== "PBKDF2") throw new Error("Only PBKDF2 deriveBits is supported");
                    return __bytesToArrayBuffer(__nativePbkdf2Bytes(__toUint8Array(key._raw), __toUint8Array(params.salt), params.iterations || 1000, len, params.hash || "SHA-256"));
                },
                encrypt: async function(params, key, data) {
                    var mode = __normalizeAlgorithmName(params);
                    if (mode !== "AES-CBC" && mode !== "AES-GCM") throw new Error("Unsupported encrypt algorithm: " + mode);
                    return __bytesToArrayBuffer(__nativeAesBytes(true, mode, __toUint8Array(key._raw), __toUint8Array(params.iv || new Uint8Array(0)), __toUint8Array(data)));
                },
                decrypt: async function(params, key, data) {
                    var mode = __normalizeAlgorithmName(params);
                    if (mode !== "AES-CBC" && mode !== "AES-GCM") throw new Error("Unsupported decrypt algorithm: " + mode);
                    return __bytesToArrayBuffer(__nativeAesBytes(false, mode, __toUint8Array(key._raw), __toUint8Array(params.iv || new Uint8Array(0)), __toUint8Array(data)));
                },
                sign: async function(algo, key, data) {
                    if (__normalizeAlgorithmName(algo || key.algorithm) === "HMAC" || (key.algorithm && key.algorithm.name === "HMAC")) {
                        var hash = (algo && algo.hash) || (key.algorithm && key.algorithm.hash) || "SHA-256";
                        return __bytesToArrayBuffer(__nativeHmacBytes(hash, __toUint8Array(key._raw), __toUint8Array(data)));
                    }
                    throw new Error("Unsupported sign algorithm");
                },
                verify: async function(algo, key, sig, data) {
                    if (__normalizeAlgorithmName(algo || key.algorithm) === "HMAC" || (key.algorithm && key.algorithm.name === "HMAC")) {
                        var expected = __nativeHmacBytes((algo && algo.hash) || (key.algorithm && key.algorithm.hash) || "SHA-256", __toUint8Array(key._raw), __toUint8Array(data));
                        var actual = __toUint8Array(sig);
                        if (expected.length !== actual.length) return false;
                        var diff = 0;
                        for (var i = 0; i < expected.length; i++) diff |= expected[i] ^ actual[i];
                        return diff === 0;
                    }
                    throw new Error("Unsupported verify algorithm");
                }
            },
            getRandomValues: function(arr) {
                if (!arr) return arr;
                var byteLength = arr.byteLength != undefined ? arr.byteLength : arr.length;
                if (!byteLength) return arr;
                if (typeof __crypto_get_random_values_hex === "undefined") throw new Error("Native random bridge is unavailable");
                var random = __hexToBytes(__crypto_get_random_values_hex(byteLength));
                if (arr.buffer && arr.byteLength != undefined) new Uint8Array(arr.buffer, arr.byteOffset || 0, arr.byteLength).set(random);
                else for (var i = 0; i < arr.length; i++) arr[i] = random[i] || 0;
                return arr;
            },
            randomUUID: function() {
                var b = new Uint8Array(16);
                globalThis.crypto.getRandomValues(b);
                b[6] = (b[6] & 0x0f) | 0x40;
                b[8] = (b[8] & 0x3f) | 0x80;
                var h = __bytesToHex(b);
                return h.substr(0, 8) + "-" + h.substr(8, 4) + "-" + h.substr(12, 4) + "-" + h.substr(16, 4) + "-" + h.substr(20);
            }
        };

        globalThis.WebAssembly = globalThis.WebAssembly || {
            instantiate: async function() { return { instance: { exports: {} }, module: {} }; }
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
                // `$(existingNode)` / `$(existingCollection)` - return it untouched, matching cheerio.
                // Collections are FUNCTIONS (so they can be invoked as `$(...)`), so `typeof` is
                // "function", not "object". Accept both, otherwise the extremely common
                // `.map((i, el) => $(el)...)` / `.each((i, el) => $(el)...)` idiom falls through to
                // `String(selector)` (the function's source code) and produces a garbage selector.
                if (selector && (typeof selector === "object" || typeof selector === "function") && typeof selector.toArray === "function") {
                    return selector;
                }
                // `$(selector, context)` - scope the search to the context collection (also a function).
                if (context && (typeof context === "object" || typeof context === "function") && typeof context.find === "function") {
                    return context.find(String(selector));
                }
                return createCheerioCollection(__cheerio_select(root, String(selector)));
            }
            // Static `$.html()` - serialize the whole document; `$.html(el)` serializes the
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
        let hostname = url.host ?? ""
        let port = url.port.map(String.init) ?? ""
        let host = port.isEmpty ? hostname : "\(hostname):\(port)"
        let pathname = url.path.isEmpty ? "/" : url.path
        return [
            "href": url.absoluteString,
            "protocol": (url.scheme ?? "").isEmpty ? "" : "\(url.scheme!):",
            "host": host,
            "hostname": hostname,
            "port": port,
            "pathname": pathname,
            "search": components?.percentEncodedQuery.map { "?\($0)" } ?? "",
            "hash": components?.percentEncodedFragment.map { "#\($0)" } ?? "",
            "origin": "\(url.scheme ?? "")://\(host)"
        ]
    }

    // MARK: - Byte-accurate crypto bridges (hex in / hex out)

    private static func hexFromData(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func dataFromHex(_ hex: String) -> Data {
        let filtered = hex.lowercased().filter { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
        let normalized = filtered.count.isMultiple(of: 2) ? filtered : "0" + filtered
        var data = Data(capacity: normalized.count / 2)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let next = normalized.index(index, offsetBy: 2)
            if let byte = UInt8(normalized[index..<next], radix: 16) {
                data.append(byte)
            }
            index = next
        }
        return data
    }

    private static func digestHexRaw(hashName: String, dataHex: String) -> String {
        let data = dataFromHex(dataHex)
        switch hashName.uppercased() {
        case "MD5": return hexFromData(Data(Insecure.MD5.hash(data: data)))
        case "SHA1": return hexFromData(Data(Insecure.SHA1.hash(data: data)))
        case "SHA384": return hexFromData(Data(SHA384.hash(data: data)))
        case "SHA512": return hexFromData(Data(SHA512.hash(data: data)))
        default: return hexFromData(Data(SHA256.hash(data: data)))
        }
    }

    private static func hmacHexRaw(hashName: String, keyHex: String, dataHex: String) -> String {
        let key = SymmetricKey(data: dataFromHex(keyHex))
        let data = dataFromHex(dataHex)
        switch hashName.uppercased() {
        case "MD5": return hexFromData(Data(HMAC<Insecure.MD5>.authenticationCode(for: data, using: key)))
        case "SHA1": return hexFromData(Data(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: key)))
        case "SHA384": return hexFromData(Data(HMAC<SHA384>.authenticationCode(for: data, using: key)))
        case "SHA512": return hexFromData(Data(HMAC<SHA512>.authenticationCode(for: data, using: key)))
        default: return hexFromData(Data(HMAC<SHA256>.authenticationCode(for: data, using: key)))
        }
    }

    private static func pbkdf2Hex(passHex: String, saltHex: String, iterations: Int, keyBits: Int, hashName: String) -> String {
        let password = dataFromHex(passHex)
        let salt = dataFromHex(saltHex)
        let keyLength = max(1, keyBits / 8)
        let prf: CCPseudoRandomAlgorithm
        switch hashName.uppercased() {
        case "SHA1": prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
        case "SHA384": prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA384)
        case "SHA512": prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512)
        case "MD5": prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1) // CommonCrypto PBKDF2 has no MD5 PRF; SHA1 fallback
        default: prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
        }
        var derived = [UInt8](repeating: 0, count: keyLength)
        let status = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.bindMemory(to: Int8.self).baseAddress, password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    prf, UInt32(max(1, iterations)),
                    &derived, keyLength
                )
            }
        }
        guard Int(status) == kCCSuccess else { return "" }
        return hexFromData(Data(derived))
    }

    private static func randomHex(byteLength: Int) -> String {
        let count = max(0, byteLength)
        guard count > 0 else { return "" }
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return hexFromData(Data(bytes))
    }

    /// Symmetric block cipher (AES or 3DES) for the CryptoJS / WebCrypto polyfills.
    /// `algorithmMode` looks like "AES-CBC", "AES-ECB", "AES-GCM", "DES3-CBC", optionally
    /// suffixed "-NoPadding" (default is PKCS7).
    private static func cipherHex(encrypt: Bool, algorithmMode: String, keyHex: String, ivHex: String, dataHex: String) -> String {
        let noPadding = algorithmMode.hasSuffix("-NoPadding")
        let base = noPadding ? String(algorithmMode.dropLast("-NoPadding".count)) : algorithmMode
        let parts = base.uppercased().split(separator: "-").map(String.init)
        let algo = parts.first ?? "AES"
        let mode = parts.count > 1 ? parts[parts.count - 1] : "CBC"

        let key = dataFromHex(keyHex)
        let iv = dataFromHex(ivHex)
        let input = dataFromHex(dataHex)

        if algo == "AES" && mode == "GCM" {
            return aesGCMHex(encrypt: encrypt, key: key, iv: iv, input: input)
        }

        let algorithm = CCAlgorithm(algo == "DES3" || algo == "3DES" ? kCCAlgorithm3DES : kCCAlgorithmAES)
        let blockSize = (algo == "DES3" || algo == "3DES") ? kCCBlockSize3DES : kCCBlockSizeAES128
        var options: CCOptions = 0
        if !noPadding { options |= CCOptions(kCCOptionPKCS7Padding) }
        if mode == "ECB" { options |= CCOptions(kCCOptionECBMode) }

        guard let output = ccCrypt(
            operation: CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
            algorithm: algorithm,
            options: options,
            key: key,
            iv: mode == "ECB" ? Data() : iv,
            input: input,
            blockSize: blockSize
        ) else {
            return ""
        }
        return hexFromData(output)
    }

    private static func ccCrypt(operation: CCOperation, algorithm: CCAlgorithm, options: CCOptions, key: Data, iv: Data, input: Data, blockSize: Int) -> Data? {
        // Capture lengths up front: reading these inside the `withUnsafe*Bytes` borrows
        // (especially `output` under the mutable borrow) would be overlapping access.
        let keyCount = key.count
        let inputCount = input.count
        let ivIsEmpty = iv.isEmpty
        let outputCapacity = inputCount + blockSize
        var outMoved = 0
        var output = Data(count: outputCapacity)
        let status = output.withUnsafeMutableBytes { outBytes -> CCCryptorStatus in
            input.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation, algorithm, options,
                            keyBytes.baseAddress, keyCount,
                            ivIsEmpty ? nil : ivBytes.baseAddress,
                            inBytes.baseAddress, inputCount,
                            outBytes.baseAddress, outputCapacity,
                            &outMoved
                        )
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess) else { return nil }
        return output.prefix(outMoved)
    }

    private static func aesGCMHex(encrypt: Bool, key: Data, iv: Data, input: Data) -> String {
        do {
            let symmetricKey = SymmetricKey(data: key)
            let nonce = try AES.GCM.Nonce(data: iv)
            if encrypt {
                let sealed = try AES.GCM.seal(input, using: symmetricKey, nonce: nonce)
                return hexFromData(sealed.ciphertext + sealed.tag)
            } else {
                guard input.count >= 16 else { return "" }
                let tag = input.suffix(16)
                let ciphertext = input.prefix(input.count - 16)
                let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
                return hexFromData(try AES.GCM.open(box, using: symmetricKey))
            }
        } catch {
            return ""
        }
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
