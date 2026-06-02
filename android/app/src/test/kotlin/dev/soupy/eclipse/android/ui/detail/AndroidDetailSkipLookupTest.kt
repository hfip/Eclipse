package dev.soupy.eclipse.android.ui.detail

import dev.soupy.eclipse.android.core.model.EpisodePlaybackContext
import kotlin.test.Test
import kotlin.test.assertEquals

class AndroidDetailSkipLookupTest {
    @Test
    fun regularAnimeUsesLocalEpisodeForAniSkipAndIntroDbAppButTmdbEpisodeForTheIntroDb() {
        val lookup = EpisodePlaybackContext(
            localSeasonNumber = 2,
            localEpisodeNumber = 1,
            anilistMediaId = 123,
            tmdbSeasonNumber = 1,
            tmdbEpisodeNumber = 13,
        ).skipEpisodeLookup()

        assertEquals(1, lookup.aniSkipEpisodeNumber)
        assertEquals(1, lookup.theIntroDbSeasonNumber)
        assertEquals(13, lookup.theIntroDbEpisodeNumber)
        assertEquals(2, lookup.introDbAppSeasonNumber)
        assertEquals(1, lookup.introDbAppEpisodeNumber)
    }

    @Test
    fun animeSpecialUsesMappedTmdbEpisodeForBothIntroDatabases() {
        val lookup = EpisodePlaybackContext(
            localSeasonNumber = 3,
            localEpisodeNumber = 1,
            anilistMediaId = 456,
            tmdbSeasonNumber = 0,
            tmdbEpisodeNumber = 7,
            isSpecial = true,
        ).skipEpisodeLookup()

        assertEquals(1, lookup.aniSkipEpisodeNumber)
        assertEquals(0, lookup.theIntroDbSeasonNumber)
        assertEquals(7, lookup.theIntroDbEpisodeNumber)
        assertEquals(0, lookup.introDbAppSeasonNumber)
        assertEquals(7, lookup.introDbAppEpisodeNumber)
    }

    @Test
    fun standardShowUsesItsPlayedEpisodeForBothIntroDatabases() {
        val lookup = EpisodePlaybackContext(
            localSeasonNumber = 4,
            localEpisodeNumber = 3,
        ).skipEpisodeLookup()

        assertEquals(3, lookup.aniSkipEpisodeNumber)
        assertEquals(4, lookup.theIntroDbSeasonNumber)
        assertEquals(3, lookup.theIntroDbEpisodeNumber)
        assertEquals(4, lookup.introDbAppSeasonNumber)
        assertEquals(3, lookup.introDbAppEpisodeNumber)
    }
}
