package dev.soupy.eclipse.android.core.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class PlayerSourceTest {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    @Test
    fun serviceMetadataRoundTripsThroughPlayerSource() {
        val source = PlayerSource(
            uri = "https://example.test/video.m3u8",
            serviceId = "stremio:https://addon.example.test/manifest.json",
            serviceHref = "tt1234567:1:2",
            progressTarget = DetailTarget.TmdbShow(42),
        )

        val decoded = json.decodeFromString<PlayerSource>(json.encodeToString(source))

        assertEquals(source.serviceId, decoded.serviceId)
        assertEquals(source.serviceHref, decoded.serviceHref)
        assertEquals(source.progressTarget, decoded.progressTarget)
    }

    @Test
    fun serviceMetadataDefaultsToNullForOlderSources() {
        val decoded = json.decodeFromString<PlayerSource>(
            """{"uri":"https://example.test/video.mp4"}""",
        )

        assertNull(decoded.serviceId)
        assertNull(decoded.serviceHref)
        assertNull(decoded.progressTarget)
    }

    @Test
    fun subtitleHeadersRoundTripThroughPlayerSource() {
        val source = PlayerSource(
            uri = "https://example.test/video.m3u8",
            headers = mapOf("Referer" to "https://example.test/player"),
            subtitles = listOf(
                SubtitleTrack(
                    id = "sub-1",
                    label = "English",
                    language = "eng",
                    uri = "https://example.test/subtitles/en.vtt",
                    format = "vtt",
                    headers = mapOf("Cookie" to "subtitle-session=abc"),
                    isDefault = true,
                ),
            ),
        )

        val decoded = json.decodeFromString<PlayerSource>(json.encodeToString(source))

        assertEquals("subtitle-session=abc", decoded.subtitles.single().headers.getValue("Cookie"))
        assertEquals("https://example.test/player", decoded.headers.getValue("Referer"))
    }
}
