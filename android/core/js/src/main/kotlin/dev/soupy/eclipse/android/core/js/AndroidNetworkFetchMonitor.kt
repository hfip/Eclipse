package dev.soupy.eclipse.android.core.js

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import java.util.LinkedHashSet
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlin.coroutines.resume

private val NetworkFetchJson = Json {
    ignoreUnknownKeys = true
    isLenient = true
    explicitNulls = false
}

internal object AndroidNetworkFetchMonitor {
    suspend fun perform(
        context: Context,
        url: String,
        optionsJson: String?,
        simple: Boolean,
    ): String {
        val options = AndroidNetworkFetchOptions.from(optionsJson, simple)
        val result = withContext(Dispatchers.Main.immediate) {
            AndroidNetworkFetchSession(
                context = context.applicationContext,
                originalUrl = url,
                options = options,
            ).start()
        }
        return NetworkFetchJson.encodeToString(JsonObject.serializer(), result)
    }
}

private data class AndroidNetworkFetchOptions(
    val timeoutSeconds: Int,
    val headers: Map<String, String>,
    val cutoffs: List<String>,
    val returnHtml: Boolean,
    val returnCookies: Boolean,
    val clickSelectors: List<String>,
    val waitForSelectors: List<String>,
    val maxWaitTimeSeconds: Int,
    val htmlContent: String?,
) {
    companion object {
        fun from(raw: String?, simple: Boolean): AndroidNetworkFetchOptions {
            val root = runCatching {
                NetworkFetchJson.parseToJsonElement(raw.orEmpty()).jsonObject
            }.getOrDefault(JsonObject(emptyMap()))
            return AndroidNetworkFetchOptions(
                timeoutSeconds = root["timeoutSeconds"]?.jsonPrimitive?.intOrNull?.coerceIn(1, 60) ?: 10,
                headers = root["headers"]?.jsonObjectOrNull()?.mapValues { (_, value) ->
                    value.jsonPrimitive.contentOrNull.orEmpty()
                }.orEmpty().filterValues(String::isNotBlank),
                cutoffs = root["cutoff"].asStringList(),
                returnHtml = root["returnHTML"]?.jsonPrimitive?.booleanOrNull == true,
                returnCookies = if (simple) {
                    root["returnCookies"]?.jsonPrimitive?.booleanOrNull == true
                } else {
                    root["returnCookies"]?.jsonPrimitive?.booleanOrNull ?: true
                },
                clickSelectors = root["clickSelectors"].asStringList(),
                waitForSelectors = root["waitForSelectors"].asStringList(),
                maxWaitTimeSeconds = root["maxWaitTime"]?.jsonPrimitive?.intOrNull?.coerceIn(0, 30) ?: 5,
                htmlContent = root["htmlContent"]?.jsonPrimitive?.contentOrNull?.takeIf(String::isNotBlank),
            )
        }
    }
}

private class AndroidNetworkFetchSession(
    private val context: Context,
    private val originalUrl: String,
    private val options: AndroidNetworkFetchOptions,
) {
    private val handler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val requests = LinkedHashSet<String>()
    private val result = CompletableDeferred<JsonObject>()
    private var webView: WebView? = null
    private var completed = false
    private var cutoffTriggered = false
    private var cutoffUrl: String? = null
    private var lastError: String? = null
    private var lastStatus: Int = 200

    @SuppressLint("SetJavaScriptEnabled")
    suspend fun start(): JsonObject {
        val view = WebView(context)
        webView = view
        view.settings.javaScriptEnabled = true
        view.settings.domStorageEnabled = true
        view.settings.mediaPlaybackRequiresUserGesture = false
        view.settings.userAgentString = options.headers.userAgent() ?: view.settings.userAgentString
        view.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                recordRequest(url)
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                recordRequest(url)
                scheduleCapture()
            }

            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                recordRequest(request?.url?.toString())
                return false
            }

            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): android.webkit.WebResourceResponse? {
                request?.url?.toString()?.let { url -> handler.post { recordRequest(url) } }
                return null
            }

            override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                if (request?.isForMainFrame == true) {
                    lastError = error?.description?.toString()
                    lastStatus = 0
                }
            }

            override fun onReceivedHttpError(
                view: WebView?,
                request: WebResourceRequest?,
                errorResponse: android.webkit.WebResourceResponse?,
            ) {
                if (request?.isForMainFrame == true) {
                    lastStatus = errorResponse?.statusCode ?: 0
                    lastError = if (lastStatus >= 400) "HTTP $lastStatus" else lastError
                }
            }

            override fun onReceivedSslError(view: WebView?, handler: SslErrorHandler?, error: SslError?) {
                lastError = error?.toString() ?: "SSL error"
                handler?.cancel()
            }
        }

        val timeoutMs = options.timeoutSeconds * 1_000L
        handler.postDelayed({ completeFromCurrentPage(timedOut = true) }, timeoutMs)

        if (options.htmlContent != null) {
            recordRequest("data:text/html;charset=utf-8,<html_content>")
            view.loadDataWithBaseURL(
                originalUrl.takeIf { it.startsWith("http", ignoreCase = true) } ?: "https://eclipse.local/",
                options.htmlContent,
                "text/html",
                "UTF-8",
                null,
            )
        } else {
            recordRequest(originalUrl)
            view.loadUrl(originalUrl, options.headers.withBrowserDefaults())
        }

        return try {
            withTimeout(timeoutMs + 1_000L) {
                result.await()
            }
        } finally {
            handler.removeCallbacksAndMessages(null)
            scope.cancel()
            runCatching { webView?.destroy() }
            webView = null
        }
    }

    private fun scheduleCapture() {
        if (completed) return
        scope.launch {
            delay(500L + options.maxWaitTimeSeconds.coerceAtLeast(0) * 100L)
            completeFromCurrentPage(timedOut = false)
        }
    }

    private fun completeFromCurrentPage(timedOut: Boolean) {
        if (completed) return
        completed = true
        scope.launch {
            val view = webView
            val html = if (options.returnHtml && view != null) {
                view.evaluateString("document.documentElement ? document.documentElement.outerHTML : ''")
            } else {
                null
            }
            val discoveredRequests = view?.evaluateString(networkScanningScript())
                ?.decodeJsonStringList()
                .orEmpty()
            discoveredRequests.forEach(::recordRequest)
            val interactions = view?.evaluateString(selectorInteractionScript(options.waitForSelectors, options.clickSelectors))
                ?.let { raw -> runCatching { NetworkFetchJson.parseToJsonElement(raw).jsonObject }.getOrNull() }
                ?: JsonObject(emptyMap())
            val cookies = if (options.returnCookies) {
                CookieManager.getInstance().getCookie(view?.url ?: originalUrl).toCookieMap()
            } else {
                emptyMap()
            }
            result.complete(
                buildJsonObject {
                    put("originalUrl", view?.url ?: originalUrl)
                    put(
                        "requests",
                        buildJsonArray {
                            requests.forEach { request -> add(JsonPrimitive(request)) }
                        },
                    )
                    put("html", html?.let(::JsonPrimitive) ?: JsonNull)
                    put(
                        "cookies",
                        if (cookies.isEmpty()) {
                            JsonNull
                        } else {
                            JsonObject(cookies.mapValues { (_, value) -> JsonPrimitive(value) })
                        },
                    )
                    val success = lastError == null && (lastStatus in 200..399 || lastStatus == 0 && !timedOut)
                    put("success", success)
                    put("status", lastStatus)
                    put("error", lastError?.let(::JsonPrimitive) ?: JsonNull)
                    put("cutoffTriggered", cutoffTriggered)
                    put("cutoffUrl", cutoffUrl?.let(::JsonPrimitive) ?: JsonNull)
                    put("htmlCaptured", html != null)
                    put("cookiesCaptured", cookies.isNotEmpty())
                    put("elementsClicked", interactions["elementsClicked"] ?: JsonArray(emptyList()))
                    put("waitResults", interactions["waitResults"] ?: JsonObject(emptyMap()))
                },
            )
        }
    }

    private fun recordRequest(url: String?) {
        val value = url?.takeIf { it.isNotBlank() } ?: return
        if (requests.add(value)) {
            val cutoff = options.cutoffs.firstOrNull { candidate ->
                candidate.isNotBlank() && value.contains(candidate, ignoreCase = true)
            }
            if (cutoff != null) {
                cutoffTriggered = true
                cutoffUrl = value
            }
        }
    }
}

private suspend fun WebView.evaluateString(expression: String): String =
    suspendCancellableCoroutine { continuation ->
        evaluateJavascript(
            "(function() { try { return $expression; } catch (error) { return ''; } })();",
        ) { raw ->
            if (continuation.isActive) {
                continuation.resume(raw.decodeJsString())
            }
        }
    }

private fun networkScanningScript(): String = """
    JSON.stringify((function() {
      const urls = [];
      const add = function(value) {
        if (!value) return;
        try {
          const absolute = new URL(String(value), document.location.href).href;
          if (urls.indexOf(absolute) === -1) urls.push(absolute);
        } catch (error) {}
      };
      add(document.location.href);
      if (window.performance && performance.getEntriesByType) {
        performance.getEntriesByType('resource').forEach(function(entry) { add(entry.name); });
      }
      document.querySelectorAll('[src], [href], source, video, audio, track').forEach(function(element) {
        add(element.getAttribute('src'));
        add(element.getAttribute('href'));
        add(element.currentSrc);
      });
      if (typeof window.jwplayer === 'function') {
        try {
          const player = window.jwplayer();
          const playlist = player && typeof player.getPlaylist === 'function' ? player.getPlaylist() : [];
          (playlist || []).forEach(function(item) {
            add(item.file);
            (item.sources || []).forEach(function(source) { add(source.file); });
            (item.tracks || []).forEach(function(track) { add(track.file); });
          });
        } catch (error) {}
      }
      const html = document.documentElement ? document.documentElement.outerHTML : '';
      const absoluteUrlRegex = /https?:\/\/[^\s"'<>\\)]+/gi;
      let match;
      while ((match = absoluteUrlRegex.exec(html)) !== null) add(match[0]);
      return urls;
    })())
""".trimIndent()

private fun selectorInteractionScript(
    waitForSelectors: List<String>,
    clickSelectors: List<String>,
): String = """
    JSON.stringify((function() {
      const waitSelectors = ${NetworkFetchJson.encodeToString(ListSerializer(String.serializer()), waitForSelectors)};
      const clickSelectors = ${NetworkFetchJson.encodeToString(ListSerializer(String.serializer()), clickSelectors)};
      const waitResults = {};
      const clicked = [];
      waitSelectors.forEach(function(selector) {
        try { waitResults[selector] = !!document.querySelector(selector); } catch (error) { waitResults[selector] = false; }
      });
      clickSelectors.forEach(function(selector) {
        try {
          const elements = document.querySelectorAll(selector);
          if (elements.length > 0) {
            elements[0].click();
            clicked.push(selector);
          }
        } catch (error) {}
      });
      return { waitResults: waitResults, elementsClicked: clicked };
    })())
""".trimIndent()

private fun String?.toCookieMap(): Map<String, String> =
    this
        ?.split(';')
        ?.mapNotNull { raw ->
            val pair = raw.trim()
            val separator = pair.indexOf('=')
            if (separator > 0) pair.substring(0, separator) to pair.substring(separator + 1) else null
        }
        ?.toMap()
        .orEmpty()

private fun String?.decodeJsString(): String =
    this?.let { raw ->
        runCatching { NetworkFetchJson.decodeFromString(String.serializer(), raw) }.getOrDefault(raw)
    }.orEmpty()

private fun String.decodeJsonStringList(): List<String> =
    runCatching {
        NetworkFetchJson.parseToJsonElement(this).jsonArray.mapNotNull { element ->
            element.jsonPrimitive.contentOrNull
        }
    }.getOrDefault(emptyList())

private fun Map<String, String>.withBrowserDefaults(): Map<String, String> =
    mutableMapOf(
        "Accept" to "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language" to "en-US,en;q=0.5",
        "Cache-Control" to "no-cache",
        "Upgrade-Insecure-Requests" to "1",
    ).also { headers ->
        forEach { (key, value) -> headers[key] = value }
    }

private fun Map<String, String>.userAgent(): String? =
    entries.firstOrNull { (key, _) -> key.equals("User-Agent", ignoreCase = true) }?.value

private fun JsonElement?.jsonObjectOrNull(): JsonObject? =
    this as? JsonObject

private fun JsonElement?.asStringList(): List<String> = when (this) {
    is JsonArray -> mapNotNull { element -> element.jsonPrimitive.contentOrNull }
    is JsonPrimitive -> contentOrNull?.takeIf(String::isNotBlank)?.let(::listOf).orEmpty()
    else -> emptyList()
}
