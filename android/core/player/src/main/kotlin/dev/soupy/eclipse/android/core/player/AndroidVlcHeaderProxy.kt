package dev.soupy.eclipse.android.core.player

import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.Charset
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

internal object AndroidVlcHeaderProxy {
    private val sessions = ConcurrentHashMap<String, ProxySession>()
    @Volatile
    private var server: ServerSocket? = null
    @Volatile
    private var port: Int = 0

    fun proxiedUrl(
        targetUrl: String,
        headers: Map<String, String>,
    ): String? {
        if (headers.isEmpty() || !targetUrl.isHttpUrl()) return null
        val sessionId = UUID.randomUUID().toString()
        sessions[sessionId] = ProxySession(headers.sanitizedProxyHeaders())
        val activePort = ensureStarted() ?: return null
        return proxyUrl(
            port = activePort,
            sessionId = sessionId,
            targetUrl = targetUrl,
        )
    }

    private fun ensureStarted(): Int? {
        server?.takeIf { !it.isClosed }?.let { return port }
        synchronized(this) {
            server?.takeIf { !it.isClosed }?.let { return port }
            val socket = runCatching {
                ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
            }.getOrNull() ?: return null
            server = socket
            port = socket.localPort
            thread(name = "eclipse-vlc-header-proxy", isDaemon = true) {
                acceptLoop(socket)
            }
            return port
        }
    }

    private fun acceptLoop(socket: ServerSocket) {
        while (!socket.isClosed) {
            val client = runCatching { socket.accept() }.getOrNull() ?: continue
            thread(name = "eclipse-vlc-header-proxy-client", isDaemon = true) {
                handle(client)
            }
        }
    }

    private fun handle(client: Socket) {
        client.use { socket ->
            val input = BufferedInputStream(socket.getInputStream())
            val output = BufferedOutputStream(socket.getOutputStream())
            val request = input.readHttpRequest() ?: run {
                output.sendSimpleResponse(400, "Bad request")
                return
            }
            val session = sessions[request.sessionId] ?: run {
                output.sendSimpleResponse(404, "Unknown VLC proxy session")
                return
            }
            val targetUrl = request.targetUrl ?: run {
                output.sendSimpleResponse(400, "Missing target URL")
                return
            }
            val target = runCatching { URL(targetUrl) }.getOrNull() ?: run {
                output.sendSimpleResponse(400, "Invalid target URL")
                return
            }
            runCatching {
                forward(
                    request = request,
                    session = session,
                    target = target,
                    output = output,
                )
            }.onFailure {
                output.sendSimpleResponse(502, "Upstream error")
            }
        }
    }

    private fun forward(
        request: ProxyRequest,
        session: ProxySession,
        target: URL,
        output: BufferedOutputStream,
    ) {
        val connection = (target.openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            requestMethod = if (request.method.equals("HEAD", ignoreCase = true)) "HEAD" else "GET"
            connectTimeout = 15_000
            readTimeout = 30_000
            session.headers.forEach { (name, value) -> setRequestProperty(name, value) }
            request.headers["range"]?.let { range -> setRequestProperty("Range", range) }
        }
        val statusCode = connection.responseCode
        val responseHeaders = connection.filteredResponseHeaders()
        val stream = if (statusCode >= 400) {
            connection.errorStream
        } else {
            connection.inputStream
        }
        if (request.method.equals("HEAD", ignoreCase = true) || stream == null) {
            output.sendResponseHeaders(statusCode, responseHeaders)
            return
        }

        stream.use { body ->
            val contentType = responseHeaders.firstHeader("content-type")
            if (target.toString().looksLikePlaylistUrl() || contentType.looksLikePlaylistContentType()) {
                val bytes = body.readBytes()
                if (bytes.isPlaylistData()) {
                    val charset = contentType.charsetFromContentType() ?: StandardCharsets.UTF_8
                    val rewritten = bytes.toString(charset)
                        .rewritePlaylist(
                            baseUrl = target,
                            port = port,
                            sessionId = request.sessionId,
                        )
                        .toByteArray(charset)
                    val headers = responseHeaders
                        .withoutHeader("content-length")
                        .withHeader("content-length", rewritten.size.toString())
                    output.sendResponse(statusCode, headers, rewritten)
                } else {
                    output.sendResponse(statusCode, responseHeaders, bytes)
                }
            } else {
                output.sendResponseHeaders(statusCode, responseHeaders)
                body.copyTo(output)
                output.flush()
            }
        }
    }

    private fun proxyUrl(
        port: Int,
        sessionId: String,
        targetUrl: String,
    ): String {
        val encoded = URLEncoder.encode(targetUrl, StandardCharsets.UTF_8.name())
        return "http://127.0.0.1:$port/proxy/$sessionId?url=$encoded"
    }

    private data class ProxySession(
        val headers: Map<String, String>,
    )

    private data class ProxyRequest(
        val method: String,
        val sessionId: String,
        val targetUrl: String?,
        val headers: Map<String, String>,
    )

    private fun BufferedInputStream.readHttpRequest(): ProxyRequest? {
        val headerBytes = ByteArrayOutputStream()
        var current: Int
        while (true) {
            current = read()
            if (current < 0) return null
            headerBytes.write(current)
            val data = headerBytes.toByteArray()
            if (
                data.size >= 4 &&
                data[data.lastIndex - 3] == '\r'.code.toByte() &&
                data[data.lastIndex - 2] == '\n'.code.toByte() &&
                data[data.lastIndex - 1] == '\r'.code.toByte() &&
                data[data.lastIndex] == '\n'.code.toByte()
            ) {
                break
            }
            if (headerBytes.size() > 64 * 1024) return null
        }
        val lines = headerBytes.toString(StandardCharsets.ISO_8859_1.name())
            .split("\r\n")
            .filter { it.isNotBlank() }
        val firstLine = lines.firstOrNull() ?: return null
        val parts = firstLine.split(" ")
        val method = parts.getOrNull(0) ?: return null
        val rawPath = parts.getOrNull(1) ?: return null
        val headers = lines.drop(1)
            .mapNotNull { line ->
                val index = line.indexOf(':').takeIf { it > 0 } ?: return@mapNotNull null
                line.substring(0, index).trim().lowercase() to line.substring(index + 1).trim()
            }
            .toMap()
        val path = rawPath.substringBefore('?')
        val sessionId = path.removePrefix("/proxy/").substringBefore('/').takeIf { it.isNotBlank() } ?: return null
        val targetUrl = rawPath.substringAfter("?", missingDelimiterValue = "")
            .split("&")
            .firstOrNull { it.startsWith("url=") }
            ?.substringAfter("=")
            ?.let { URLDecoder.decode(it, StandardCharsets.UTF_8.name()) }
        return ProxyRequest(
            method = method,
            sessionId = sessionId,
            targetUrl = targetUrl,
            headers = headers,
        )
    }

    private fun HttpURLConnection.filteredResponseHeaders(): Map<String, List<String>> =
        headerFields
            .filterKeys { name -> name != null && !name.isHopByHopHeader() }
            .mapKeys { (name, _) -> name.orEmpty().lowercase() }
            .filterValues { values -> values.isNotEmpty() }

    private fun BufferedOutputStream.sendSimpleResponse(
        statusCode: Int,
        body: String,
    ) {
        val bytes = body.toByteArray(StandardCharsets.UTF_8)
        sendResponse(
            statusCode = statusCode,
            headers = mapOf(
                "content-type" to listOf("text/plain; charset=utf-8"),
                "content-length" to listOf(bytes.size.toString()),
            ),
            body = bytes,
        )
    }

    private fun BufferedOutputStream.sendResponse(
        statusCode: Int,
        headers: Map<String, List<String>>,
        body: ByteArray,
    ) {
        sendResponseHeaders(statusCode, headers)
        write(body)
        flush()
    }

    private fun BufferedOutputStream.sendResponseHeaders(
        statusCode: Int,
        headers: Map<String, List<String>>,
    ) {
        write("HTTP/1.1 $statusCode ${statusText(statusCode)}\r\n".toByteArray(StandardCharsets.ISO_8859_1))
        headers.forEach { (name, values) ->
            values.forEach { value ->
                write("$name: $value\r\n".toByteArray(StandardCharsets.ISO_8859_1))
            }
        }
        write("connection: close\r\n\r\n".toByteArray(StandardCharsets.ISO_8859_1))
        flush()
    }

    private fun statusText(statusCode: Int): String = when (statusCode) {
        200 -> "OK"
        206 -> "Partial Content"
        400 -> "Bad Request"
        404 -> "Not Found"
        502 -> "Bad Gateway"
        else -> "Status"
    }

    private fun Map<String, List<String>>.firstHeader(name: String): String? =
        entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value?.firstOrNull()

    private fun Map<String, List<String>>.withoutHeader(name: String): Map<String, List<String>> =
        filterKeys { !it.equals(name, ignoreCase = true) }

    private fun Map<String, List<String>>.withHeader(name: String, value: String): Map<String, List<String>> =
        this + (name to listOf(value))

    private fun String.rewritePlaylist(
        baseUrl: URL,
        port: Int,
        sessionId: String,
    ): String = lineSequence()
        .map { line ->
            when {
                line.startsWith("#") ->
                    line.replace(Regex("""URI="([^"]+)"""")) { match ->
                        val resolved = runCatching { URL(baseUrl, match.groupValues[1]).toString() }
                            .getOrDefault(match.groupValues[1])
                        "URI=\"${proxyUrl(port, sessionId, resolved)}\""
                    }
                line.isBlank() -> line
                else -> runCatching { proxyUrl(port, sessionId, URL(baseUrl, line.trim()).toString()) }
                    .getOrDefault(line)
            }
        }
        .joinToString("\n")

    private fun ByteArray.isPlaylistData(): Boolean =
        decodeToStringOrEmpty().trimStart().startsWith("#EXTM3U")

    private fun ByteArray.decodeToStringOrEmpty(): String =
        runCatching { toString(StandardCharsets.UTF_8) }.getOrDefault("")

    private fun String?.charsetFromContentType(): Charset? =
        this?.split(";")
            ?.map(String::trim)
            ?.firstOrNull { it.startsWith("charset=", ignoreCase = true) }
            ?.substringAfter("=")
            ?.trim('"')
            ?.let { runCatching { Charset.forName(it) }.getOrNull() }

    private fun String?.looksLikePlaylistContentType(): Boolean =
        this?.contains("mpegurl", ignoreCase = true) == true ||
            this?.contains("application/vnd.apple.mpegurl", ignoreCase = true) == true

    private fun String.looksLikePlaylistUrl(): Boolean =
        substringBefore('?').endsWith(".m3u8", ignoreCase = true)

    private fun String.isHttpUrl(): Boolean =
        startsWith("http://", ignoreCase = true) || startsWith("https://", ignoreCase = true)

    private fun String?.isHopByHopHeader(): Boolean = when (this?.lowercase()) {
        null,
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "proxy-connection",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade" -> true
        else -> false
    }

    private fun Map<String, String>.sanitizedProxyHeaders(): Map<String, String> =
        filterKeys { name -> !name.isHopByHopHeader() && !name.equals("host", ignoreCase = true) }
            .filterValues { it.isNotBlank() }
}
