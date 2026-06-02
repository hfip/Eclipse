package dev.soupy.eclipse.android.core.network

import kotlin.test.Test
import kotlin.test.assertEquals

class AniSkipServiceTest {
    @Test
    fun requestUsesMalIdAndZeroLengthFallbackBeforePlaybackDurationIsKnown() {
        val url = aniSkipTimesUrl(
            baseUrl = "https://api.aniskip.com/v2",
            malId = 16_498,
            episodeNumber = 1,
            episodeDurationSeconds = 0.0,
        )

        assertEquals(
            "https://api.aniskip.com/v2/skip-times/16498/1" +
                "?types%5B%5D=op&types%5B%5D=ed&types%5B%5D=recap" +
                "&types%5B%5D=mixed-op&types%5B%5D=mixed-ed&episodeLength=0",
            url,
        )
    }

    @Test
    fun requestUsesReportedPlaybackDurationWhenAvailable() {
        val url = aniSkipTimesUrl(
            baseUrl = "https://api.aniskip.com/v2",
            malId = 16_498,
            episodeNumber = 2,
            episodeDurationSeconds = 1_420.9,
        )

        assertEquals(true, url.endsWith("&episodeLength=1420"))
    }
}
