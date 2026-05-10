package dev.soupy.eclipse.android.core.model

import kotlin.test.Test
import kotlin.test.assertEquals

class EpisodePlaybackContextTest {
    @Test
    fun resolvedTmdbEpisodePrefersExplicitEpisodeBeforeOffset() {
        val context = EpisodePlaybackContext(
            localSeasonNumber = 1,
            localEpisodeNumber = 4,
            tmdbSeasonNumber = 2,
            tmdbEpisodeNumber = 7,
            tmdbEpisodeOffset = 1,
        )

        assertEquals(2, context.resolvedTMDBSeasonNumber)
        assertEquals(7, context.resolvedTMDBEpisodeNumber)
    }

    @Test
    fun resolvedTmdbEpisodeUsesOffsetWhenExplicitEpisodeIsMissing() {
        val context = EpisodePlaybackContext(
            localSeasonNumber = 0,
            localEpisodeNumber = 4,
            tmdbSeasonNumber = 0,
            tmdbEpisodeOffset = 10,
        )

        assertEquals(14, context.resolvedTMDBEpisodeNumber)
    }

    @Test
    fun forEpisodeNumberAdvancesMappedEpisode() {
        val context = EpisodePlaybackContext(
            localSeasonNumber = 1,
            localEpisodeNumber = 3,
            tmdbEpisodeNumber = 10,
        )

        assertEquals(12, context.forEpisodeNumber(5).tmdbEpisodeNumber)
    }
}

