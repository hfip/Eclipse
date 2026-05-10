package dev.soupy.eclipse.android.core.js

internal fun browserCompatibilityScript(): String = """
      if (typeof window.globalThis === "undefined") window.globalThis = window;
      const __eclipseNativeBtoa = typeof window.btoa === "function" ? window.btoa.bind(window) : null;
      const __eclipseNativeAtob = typeof window.atob === "function" ? window.atob.bind(window) : null;
      const __eclipseBase64Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
      function __eclipseBinaryToBase64(binary) {
        let output = "";
        let index = 0;
        while (index < binary.length) {
          const chr1 = binary.charCodeAt(index++) & 255;
          const chr2 = binary.charCodeAt(index++);
          const chr3 = binary.charCodeAt(index++);
          const enc1 = chr1 >> 2;
          const enc2 = ((chr1 & 3) << 4) | ((chr2 || 0) >> 4);
          let enc3 = ((chr2 || 0) & 15) << 2 | ((chr3 || 0) >> 6);
          let enc4 = (chr3 || 0) & 63;
          if (Number.isNaN(chr2)) {
            enc3 = 64;
            enc4 = 64;
          } else if (Number.isNaN(chr3)) {
            enc4 = 64;
          }
          output += __eclipseBase64Alphabet.charAt(enc1) +
            __eclipseBase64Alphabet.charAt(enc2) +
            __eclipseBase64Alphabet.charAt(enc3) +
            __eclipseBase64Alphabet.charAt(enc4);
        }
        return output;
      }
      function __eclipseBase64ToBinary(base64) {
        const input = String(base64 || "").replace(/[^A-Za-z0-9+/=]/g, "");
        let output = "";
        let index = 0;
        while (index < input.length) {
          const enc1 = __eclipseBase64Alphabet.indexOf(input.charAt(index++));
          const enc2 = __eclipseBase64Alphabet.indexOf(input.charAt(index++));
          const enc3 = __eclipseBase64Alphabet.indexOf(input.charAt(index++));
          const enc4 = __eclipseBase64Alphabet.indexOf(input.charAt(index++));
          const chr1 = (enc1 << 2) | (enc2 >> 4);
          const chr2 = ((enc2 & 15) << 4) | (enc3 >> 2);
          const chr3 = ((enc3 & 3) << 6) | enc4;
          output += String.fromCharCode(chr1);
          if (enc3 !== 64 && enc3 >= 0) output += String.fromCharCode(chr2);
          if (enc4 !== 64 && enc4 >= 0) output += String.fromCharCode(chr3);
        }
        return output;
      }
      if (typeof globalThis.btoa !== "function") {
        globalThis.btoa = function(data) {
          const input = String(data == null ? "" : data);
          if (typeof TextEncoder === "function") {
            const bytes = new TextEncoder().encode(input);
            let binary = "";
            for (let index = 0; index < bytes.length; index += 1) {
              binary += String.fromCharCode(bytes[index]);
            }
            return (__eclipseNativeBtoa || __eclipseBinaryToBase64)(binary);
          }
          return (__eclipseNativeBtoa || __eclipseBinaryToBase64)(unescape(encodeURIComponent(input)));
        };
      }
      if (typeof globalThis.atob !== "function") {
        globalThis.atob = function(base64) {
          const binary = (__eclipseNativeAtob || __eclipseBase64ToBinary)(String(base64 == null ? "" : base64));
          if (typeof TextDecoder === "function") {
            const bytes = new Uint8Array(binary.length);
            for (let index = 0; index < binary.length; index += 1) {
              bytes[index] = binary.charCodeAt(index);
            }
            return new TextDecoder("utf-8").decode(bytes);
          }
          return decodeURIComponent(escape(binary));
        };
      }
""".trimIndent()

internal fun networkFetchCompatibilityScript(): String = """
      function __eclipseArrayOption(value) {
        if (Array.isArray(value)) return value.map(function(item) { return String(item); });
        if (value == null || value === false) return [];
        return [String(value)];
      }

      function __eclipseNormalizeHeaders(headers) {
        const normalized = {};
        if (!headers) return normalized;
        if (Array.isArray(headers)) {
          headers.forEach(function(pair) {
            if (pair && pair.length >= 2) normalized[String(pair[0])] = String(pair[1]);
          });
          return normalized;
        }
        if (typeof headers.forEach === "function") {
          headers.forEach(function(value, key) { normalized[String(key)] = String(value); });
          return normalized;
        }
        Object.keys(headers).forEach(function(key) { normalized[String(key)] = String(headers[key]); });
        return normalized;
      }

      function __eclipseBrowserHeaders(overrides) {
        const headers = {
          "User-Agent": navigator.userAgent || "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome Mobile Safari/537.36",
          "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
          "Accept-Language": "en-US,en;q=0.5",
          "Cache-Control": "no-cache",
          "Upgrade-Insecure-Requests": "1"
        };
        const provided = __eclipseNormalizeHeaders(overrides);
        Object.keys(provided).forEach(function(key) { headers[key] = provided[key]; });
        return headers;
      }

      function __eclipseAbsoluteUrl(candidate, baseUrl) {
        try { return new URL(String(candidate), baseUrl || window.location.href).href; } catch (error) { return null; }
      }

      function __eclipseAddUniqueUrl(requests, candidate, baseUrl) {
        if (!candidate) return;
        let value = String(candidate)
          .replace(/&amp;/g, "&")
          .replace(/\\u0026/g, "&")
          .replace(/\\\//g, "/")
          .trim();
        if (!value || value === "#" || value.toLowerCase().startsWith("javascript:")) return;
        const absolute = __eclipseAbsoluteUrl(value, baseUrl);
        if (!absolute) return;
        if (requests.indexOf(absolute) === -1) requests.push(absolute);
      }

      function __eclipseExtractRequests(html, baseUrl) {
        const requests = [];
        __eclipseAddUniqueUrl(requests, baseUrl, baseUrl);
        const text = String(html || "");
        const absoluteUrlRegex = /https?:\/\/[^\s"'<>\\)]+/gi;
        let match;
        while ((match = absoluteUrlRegex.exec(text)) !== null) {
          __eclipseAddUniqueUrl(requests, match[0], baseUrl);
        }
        const attributeRegex = /\b(?:src|href|data-src|data-href|poster|file)\s*=\s*["']([^"']+)["']/gi;
        while ((match = attributeRegex.exec(text)) !== null) {
          __eclipseAddUniqueUrl(requests, match[1], baseUrl);
        }
        const mediaRegex = /["']([^"']+\.(?:m3u8|mpd|mp4|m4v|m4s|webm|ts|vtt|srt|ass)(?:\?[^"']*)?)["']/gi;
        while ((match = mediaRegex.exec(text)) !== null) {
          __eclipseAddUniqueUrl(requests, match[1], baseUrl);
        }
        return requests;
      }

      function __eclipseCookieMap(headers) {
        const cookies = {};
        Object.keys(headers || {}).forEach(function(key) {
          if (String(key).toLowerCase() !== "set-cookie") return;
          String(headers[key] || "").split(/,(?=\s*[^;,\s]+=)/).forEach(function(cookie) {
            const pair = cookie.split(";")[0];
            const separator = pair.indexOf("=");
            if (separator > 0) {
              cookies[pair.slice(0, separator).trim()] = pair.slice(separator + 1).trim();
            }
          });
        });
        return cookies;
      }

      function __eclipseSelectorResults(html, waitForSelectors, clickSelectors) {
        const waitResults = {};
        const clicked = [];
        const parserAvailable = typeof DOMParser === "function";
        let documentNode = null;
        if (parserAvailable) {
          try { documentNode = new DOMParser().parseFromString(String(html || ""), "text/html"); } catch (error) { documentNode = null; }
        }
        waitForSelectors.forEach(function(selector) {
          let exists = false;
          if (documentNode) {
            try { exists = !!documentNode.querySelector(selector); } catch (error) { exists = false; }
          }
          waitResults[selector] = exists;
        });
        clickSelectors.forEach(function(selector) {
          let exists = false;
          if (documentNode) {
            try { exists = !!documentNode.querySelector(selector); } catch (error) { exists = false; }
          }
          if (exists) clicked.push(selector);
        });
        return { waitResults: waitResults, elementsClicked: clicked };
      }

      function __eclipseNetworkFetchResult(url, options, simple) {
        options = options || {};
        if (typeof window.__eclipseNativeNetworkFetch === "function") {
          return window.__eclipseNativeNetworkFetch(url, options, simple);
        }
        const originalUrl = String(url);
        const absoluteUrl = __eclipseAbsoluteUrl(originalUrl) || originalUrl;
        const htmlFromOptions = options.htmlContent == null ? null : String(options.htmlContent);
        const returnHTML = options.returnHTML === true;
        const returnCookies = simple ? options.returnCookies === true : options.returnCookies !== false;
        const cutoffs = __eclipseArrayOption(options.cutoff);
        const waitForSelectors = __eclipseArrayOption(options.waitForSelectors);
        const clickSelectors = __eclipseArrayOption(options.clickSelectors);
        const responsePromise = htmlFromOptions != null
          ? Promise.resolve({ status: 200, headers: {}, text: function() { return Promise.resolve(htmlFromOptions); } })
          : window.fetchv2(absoluteUrl, __eclipseBrowserHeaders(options.headers || {}), "GET", null, options.redirect !== false, options.encoding || "utf-8");

        return responsePromise.then(function(response) {
          return response.text().then(function(body) {
            const headers = response.headers || response.rawHeaders || {};
            const requests = __eclipseExtractRequests(body, absoluteUrl);
            const cookies = __eclipseCookieMap(headers);
            let cutoffTriggered = false;
            let cutoffUrl = null;
            if (cutoffs.length > 0) {
              requests.some(function(requestUrl) {
                const lowerUrl = String(requestUrl).toLowerCase();
                return cutoffs.some(function(cutoff) {
                  const hit = lowerUrl.indexOf(String(cutoff).toLowerCase()) !== -1;
                  if (hit) {
                    cutoffTriggered = true;
                    cutoffUrl = requestUrl;
                  }
                  return hit;
                });
              });
            }
            const selectorResults = __eclipseSelectorResults(body, waitForSelectors, clickSelectors);
            const status = response.status || 0;
            return {
              originalUrl: originalUrl,
              requests: requests,
              html: returnHTML ? body : null,
              cookies: returnCookies && Object.keys(cookies).length > 0 ? cookies : null,
              success: status >= 200 && status < 400,
              status: status,
              error: status >= 400 ? ("HTTP " + status) : null,
              cutoffTriggered: cutoffTriggered,
              cutoffUrl: cutoffUrl,
              htmlCaptured: returnHTML,
              cookiesCaptured: returnCookies && Object.keys(cookies).length > 0,
              elementsClicked: selectorResults.elementsClicked,
              waitResults: selectorResults.waitResults
            };
          });
        });
      }

      window.networkFetchSimple = function(url, options) {
        return __eclipseNetworkFetchResult(url, options || {}, true);
      };

      window.networkFetch = function(url, options) {
        return __eclipseNetworkFetchResult(url, options || {}, false);
      };
""".trimIndent()
