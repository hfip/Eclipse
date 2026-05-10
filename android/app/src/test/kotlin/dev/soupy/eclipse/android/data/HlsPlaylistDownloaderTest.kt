package dev.soupy.eclipse.android.data

import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull

class HlsPlaylistDownloaderTest {
    private fun downloader(): HlsPlaylistDownloader =
        HlsPlaylistDownloader(
            headers = emptyMap(),
            outputFile = File.createTempFile("eclipse-hls-test", ".ts").apply { deleteOnExit() },
        )

    @Test
    fun masterPlaylistHandlesQuotedCommaAttributes() {
        val variants = downloader().parseMasterPlaylist(
            content = """
                #EXTM3U
                #EXT-X-STREAM-INF:BANDWIDTH=800000,CODECS="avc1.4d401e,mp4a.40.2"
                low/index.m3u8
                #EXT-X-STREAM-INF:CODECS="avc1.640028,mp4a.40.2",BANDWIDTH=2500000
                high/index.m3u8
            """.trimIndent(),
            baseUrl = URL("https://cdn.example/anime/master.m3u8"),
        )

        assertEquals(2, variants.size)
        assertEquals(800000, variants[0].bandwidth)
        assertEquals("https://cdn.example/anime/low/index.m3u8", variants[0].url.toExternalForm())
        assertEquals(2500000, variants[1].bandwidth)
        assertEquals("https://cdn.example/anime/high/index.m3u8", variants[1].url.toExternalForm())
    }

    @Test
    fun mediaPlaylistTracksMapByteRangesAndPerSegmentKeys() {
        val parsed = downloader().parseMediaPlaylist(
            content = """
                #EXTM3U
                #EXT-X-MEDIA-SEQUENCE:42
                #EXT-X-KEY:METHOD=AES-128,URI="https://keys.example/key.bin?token=1,2",IV=0x0000000000000000000000000000002A
                #EXT-X-MAP:URI="init.mp4",BYTERANGE="720@0"
                #EXTINF:4.0,
                #EXT-X-BYTERANGE:100@720
                segments/video.ts
                #EXTINF:4.0,
                #EXT-X-BYTERANGE:100
                segments/video.ts
                #EXT-X-KEY:METHOD=NONE
                #EXTINF:4.0,
                clear.ts
                #EXT-X-KEY:METHOD=AES-128,URI="key2.bin"
                #EXTINF:4.0,
                encrypted2.ts
            """.trimIndent(),
            baseUrl = URL("https://cdn.example/anime/episode/index.m3u8"),
        )

        assertEquals("https://cdn.example/anime/episode/init.mp4", parsed.initSegment?.url?.toExternalForm())
        assertEquals(HlsByteRange(offset = 0, length = 720), parsed.initSegment?.byteRange)
        assertEquals("https://keys.example/key.bin?token=1,2", parsed.initSegmentEncryptionKey?.keyUrl?.toExternalForm())
        assertContentEquals(
            ByteArray(16).also { it[15] = 0x2A },
            parsed.initSegmentEncryptionKey?.iv,
        )

        assertEquals(4, parsed.segments.size)
        assertEquals(42, parsed.segments[0].sequenceNumber)
        assertEquals(HlsByteRange(offset = 720, length = 100), parsed.segments[0].resource.byteRange)
        assertEquals("https://keys.example/key.bin?token=1,2", parsed.segments[0].encryptionKey?.keyUrl?.toExternalForm())
        assertEquals(HlsByteRange(offset = 820, length = 100), parsed.segments[1].resource.byteRange)
        assertEquals("https://keys.example/key.bin?token=1,2", parsed.segments[1].encryptionKey?.keyUrl?.toExternalForm())
        assertNull(parsed.segments[2].encryptionKey)
        assertEquals("https://cdn.example/anime/episode/key2.bin", parsed.segments[3].encryptionKey?.keyUrl?.toExternalForm())
        assertEquals("https://cdn.example/anime/episode/key2.bin", parsed.encryptionKey?.keyUrl?.toExternalForm())
    }

    @Test
    fun directResumeTotalBytesUsesContentRangeWhenAvailable() {
        assertEquals(
            1_000,
            resolveTotalBytesForResume(
                existingBytes = 400,
                responseCode = HttpURLConnection.HTTP_PARTIAL,
                contentLength = 600,
                contentRange = "bytes 400-999/1000",
            ),
        )
        assertEquals(
            1_000,
            resolveTotalBytesForResume(
                existingBytes = 400,
                responseCode = HttpURLConnection.HTTP_PARTIAL,
                contentLength = 600,
                contentRange = null,
            ),
        )
        assertEquals(
            600,
            resolveTotalBytesForResume(
                existingBytes = 400,
                responseCode = HttpURLConnection.HTTP_OK,
                contentLength = 600,
                contentRange = null,
            ),
        )
    }
}
