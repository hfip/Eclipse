package dev.soupy.eclipse.android.core.network

import dev.soupy.eclipse.android.core.model.SkipType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class IntroDbServiceTest {
    @Test
    fun introDbAppParserAcceptsNestedClockAndMillisecondSegments() {
        val body = """
            {
              "intro": {
                "segments": [
                  { "start_sec": "00:01:30", "end_sec": "00:02:00" },
                  { "start_ms": 90000, "end_ms": 120000 }
                ]
              },
              "recap": { "start_sec": 4, "end_sec": 12.5 },
              "credits": { "segments": { "start_sec": "23:00", "end_sec": "25:00" } }
            }
        """.trimIndent()

        val result = decodeIntroDbAppSkipSegments(body, episodeDurationSeconds = 1_450.0)

        val segments = assertIs<NetworkResult.Success<List<dev.soupy.eclipse.android.core.model.SkipSegment>>>(result).value
        assertEquals(3, segments.size)
        assertEquals(SkipType.RECAP, segments[0].type)
        assertEquals(4.0, segments[0].startTime)
        assertEquals(12.5, segments[0].endTime)
        assertEquals(SkipType.INTRO, segments[1].type)
        assertEquals(90.0, segments[1].startTime)
        assertEquals(120.0, segments[1].endTime)
        assertEquals(SkipType.OUTRO, segments[2].type)
        assertEquals(1_380.0, segments[2].startTime)
        assertEquals(1_450.0, segments[2].endTime)
    }

    @Test
    fun introDbAppParserDedupesEquivalentSegments() {
        val body = """
            {
              "intro": [
                { "start_sec": 10, "end_sec": 70 },
                { "start_ms": 10000, "end_ms": 70000 }
              ],
              "preview": [
                { "start_sec": 10, "end_sec": 70 }
              ]
            }
        """.trimIndent()

        val result = decodeIntroDbAppSkipSegments(body, episodeDurationSeconds = 600.0)

        val segments = assertIs<NetworkResult.Success<List<dev.soupy.eclipse.android.core.model.SkipSegment>>>(result).value
        assertEquals(2, segments.size)
        assertEquals(listOf(SkipType.INTRO, SkipType.PREVIEW), segments.map { it.type })
    }
}
