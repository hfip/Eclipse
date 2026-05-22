package dev.soupy.eclipse.android.core.player

import java.io.BufferedInputStream
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.ServerSocket
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class AndroidVlcHeaderProxyTest {
    @Test
    fun proxyForwardsIncomingAndSessionHeaders() {
        FakeUpstreamServer(
            body = "ok",
            headers = mapOf("Content-Type" to "text/plain"),
        ).use { upstream ->
            val proxied = AndroidVlcHeaderProxy.proxiedUrl(
                targetUrl = upstream.url("/video.ts"),
                headers = mapOf(
                    "Referer" to "https://example.test/player",
                    "Cookie" to "session=abc",
                    "Connection" to "drop-me",
                ),
            )

            assertNotNull(proxied)
            val connection = URL(proxied).openConnection() as HttpURLConnection
            connection.setRequestProperty("Range", "bytes=100-")
            connection.setRequestProperty("User-Agent", "VLC-test")
            assertEquals("ok", connection.inputStream.readBytes().toString(StandardCharsets.UTF_8))

            val request = upstream.awaitRequest().lowercase()
            assertTrue("range: bytes=100-" in request)
            assertTrue("user-agent: vlc-test" in request)
            assertTrue("referer: https://example.test/player" in request)
            assertTrue("cookie: session=abc" in request)
            assertTrue("drop-me" !in request)
        }
    }

    @Test
    fun proxyRejectsRequestsWithoutSessionToken() {
        FakeUpstreamServer(body = "ok").use { upstream ->
            val proxied = AndroidVlcHeaderProxy.proxiedUrl(
                targetUrl = upstream.url("/video.ts"),
                headers = mapOf("Referer" to "https://example.test/player"),
            )

            assertNotNull(proxied)
            val withoutToken = proxied.substringBefore("&token=")
            val connection = URL(withoutToken).openConnection() as HttpURLConnection

            assertEquals(403, connection.responseCode)
        }
    }

    @Test
    fun proxyRewritesPlaylistMediaAndUriAttributes() {
        val playlist = """
            #EXTM3U
            #EXT-X-KEY:METHOD=AES-128,uri=keys/main.key
            #EXT-X-MAP:URI="init.mp4"
            segment-1.ts
        """.trimIndent()

        FakeUpstreamServer(
            body = playlist,
            headers = mapOf("Content-Type" to "application/vnd.apple.mpegurl"),
        ).use { upstream ->
            val proxied = AndroidVlcHeaderProxy.proxiedUrl(
                targetUrl = upstream.url("/hls/master.m3u8"),
                headers = mapOf("Referer" to "https://example.test/player"),
            )

            assertNotNull(proxied)
            val body = URL(proxied).readText()

            assertTrue("uri=http://127.0.0.1:" in body)
            assertTrue("URI=\"http://127.0.0.1:" in body)
            assertTrue("http://127.0.0.1:" in body.substringAfter("#EXT-X-MAP"))
            assertEquals(3, Regex("""http://127\.0\.0\.1:\d+/proxy/""").findAll(body).count())
        }
    }

    private class FakeUpstreamServer(
        private val body: String,
        private val headers: Map<String, String> = emptyMap(),
    ) : AutoCloseable {
        private val socket = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
        private val requests = ArrayBlockingQueue<String>(4)
        private val worker = thread(name = "fake-vlc-upstream", isDaemon = true) {
            while (!socket.isClosed) {
                val client = runCatching { socket.accept() }.getOrNull() ?: continue
                client.use {
                    val input = BufferedInputStream(it.getInputStream())
                    val request = input.readHeaders()
                    requests.offer(request)
                    val bytes = body.toByteArray(StandardCharsets.UTF_8)
                    val responseHeaders = headers + ("Content-Length" to bytes.size.toString())
                    val response = buildString {
                        append("HTTP/1.1 200 OK\r\n")
                        responseHeaders.forEach { (name, value) ->
                            append(name).append(": ").append(value).append("\r\n")
                        }
                        append("Connection: close\r\n\r\n")
                    }.toByteArray(StandardCharsets.ISO_8859_1)
                    it.getOutputStream().write(response)
                    it.getOutputStream().write(bytes)
                    it.getOutputStream().flush()
                }
            }
        }

        fun url(path: String): String = "http://127.0.0.1:${socket.localPort}$path"

        fun awaitRequest(): String =
            requests.poll(3, TimeUnit.SECONDS) ?: error("Upstream request was not received.")

        override fun close() {
            socket.close()
            worker.join(500)
        }

        private fun BufferedInputStream.readHeaders(): String {
            val bytes = mutableListOf<Byte>()
            while (true) {
                val next = read()
                if (next < 0) break
                bytes += next.toByte()
                if (bytes.size >= 4 &&
                    bytes[bytes.lastIndex - 3] == '\r'.code.toByte() &&
                    bytes[bytes.lastIndex - 2] == '\n'.code.toByte() &&
                    bytes[bytes.lastIndex - 1] == '\r'.code.toByte() &&
                    bytes[bytes.lastIndex] == '\n'.code.toByte()
                ) {
                    break
                }
            }
            return bytes.toByteArray().toString(StandardCharsets.ISO_8859_1)
        }
    }
}
