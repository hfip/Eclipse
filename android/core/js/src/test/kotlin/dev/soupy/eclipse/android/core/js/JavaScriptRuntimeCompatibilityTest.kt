package dev.soupy.eclipse.android.core.js

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class JavaScriptRuntimeCompatibilityTest {
    @Test
    fun networkFetchScriptExposesIosResultShape() {
        val script = networkFetchCompatibilityScript()

        listOf(
            "originalUrl",
            "requests",
            "html",
            "cookies",
            "success",
            "cutoffTriggered",
            "cutoffUrl",
            "htmlCaptured",
            "cookiesCaptured",
            "elementsClicked",
            "waitResults",
        ).forEach { key ->
            assertTrue(key in script, "networkFetch result should include $key")
        }
        assertTrue("window.networkFetchSimple" in script)
        assertTrue("window.networkFetch" in script)
        assertTrue("__eclipseBrowserHeaders" in script)
        assertTrue("DOMParser" in script)
    }

    @Test
    fun browserCompatibilityScriptInstallsBase64Helpers() {
        val script = browserCompatibilityScript()

        assertTrue("globalThis.btoa" in script)
        assertTrue("globalThis.atob" in script)
        assertTrue("TextEncoder" in script)
        assertTrue("TextDecoder" in script)
    }

    @Test
    fun serviceStreamParserKeepsHeadersAndStructuredSubtitles() {
        val parsed = parseServiceStreamResult(
            """
            {
              "headers": { "Referer": "https://provider.example/watch/1" },
              "defaultSubtitle": "eng",
              "sources": [
                {
                  "file": "https://cdn.example/video.m3u8",
                  "headers": { "Origin": "https://provider.example" },
                  "subtitles": [
                    { "url": "https://cdn.example/subs/en.vtt", "language": "eng", "label": "English" }
                  ]
                }
              ],
              "subtitles": ["https://cdn.example/subs/fallback.srt"]
            }
            """.trimIndent(),
        )

        assertEquals("https://provider.example/watch/1", parsed.headers["Referer"])
        assertEquals("https://cdn.example/subs/fallback.srt", parsed.subtitles.single())
        assertEquals("https://cdn.example/video.m3u8", parsed.sources.single()["file"]!!.jsonPrimitive.content)
        assertEquals("eng", parsed.sources.single()["subtitles"]!!.jsonArray.first().jsonObject["language"]!!.jsonPrimitive.content)
    }
}
