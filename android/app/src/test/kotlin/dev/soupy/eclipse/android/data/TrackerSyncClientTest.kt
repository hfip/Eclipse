package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.EpisodePlaybackContext
import dev.soupy.eclipse.android.core.model.TrackerAccountSnapshot
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class TrackerSyncClientTest {
    @Test
    fun traktHistoryPayloadUsesTmdbShowSeasonAndEpisode() {
        val payload = TrackerSyncItem(
            target = DetailTarget.TmdbShow(42),
            title = "Example Show",
            seasonNumber = 2,
            episodeNumber = 5,
            progressPercent = 0.9,
        ).toTraktHistoryPayload("2026-04-24T12:00:00Z")!!

        val show = payload["shows"]!!.jsonArray.first().jsonObject
        val season = show["seasons"]!!.jsonArray.first().jsonObject
        val episode = season["episodes"]!!.jsonArray.first().jsonObject

        assertEquals("42", show["ids"]!!.jsonObject["tmdb"]!!.jsonPrimitive.content)
        assertEquals("2", season["number"]!!.jsonPrimitive.content)
        assertEquals("5", episode["number"]!!.jsonPrimitive.content)
        assertEquals("2026-04-24T12:00:00Z", episode["watched_at"]!!.jsonPrimitive.content)
    }

    @Test
    fun playbackDraftKeepsAniListLocalEpisodeAndTraktTmdbEpisodeSeparate() {
        val item = TrackerPlaybackProgressDraft(
            target = DetailTarget.TmdbShow(100),
            title = "Mapped Anime",
            seasonNumber = 1,
            episodeNumber = 3,
            anilistMediaId = 9001,
            progressPercent = 0.86,
            playbackContext = EpisodePlaybackContext(
                localSeasonNumber = 1,
                localEpisodeNumber = 3,
                anilistMediaId = 9001,
                tmdbSeasonNumber = 2,
                tmdbEpisodeNumber = 12,
            ),
        ).toTrackerSyncItem()

        assertEquals(2, item.seasonNumber)
        assertEquals(12, item.episodeNumber)
        assertEquals(9001, item.anilistMediaId)
        assertEquals(3, item.anilistEpisodeNumber)
        assertTrue(item.isAnime)
    }

    @Test
    fun playbackDraftDoesNotGuessTmdbEpisodeForUnmappedAnimeSeason() {
        val item = TrackerPlaybackProgressDraft(
            target = DetailTarget.TmdbShow(100),
            title = "Anime Sequel",
            seasonNumber = 1,
            episodeNumber = 2,
            progressPercent = 0.4,
            playbackContext = EpisodePlaybackContext(
                localSeasonNumber = 2,
                localEpisodeNumber = 2,
                anilistMediaId = 9002,
            ),
        ).toTrackerSyncItem()

        assertEquals(null, item.seasonNumber)
        assertEquals(null, item.episodeNumber)
        assertEquals(2, item.anilistEpisodeNumber)
    }

    @Test
    fun playbackDraftUsesLocalEpisodeForOrdinaryUnmappedShow() {
        val item = TrackerPlaybackProgressDraft(
            target = DetailTarget.TmdbShow(101),
            title = "Ordinary Show",
            seasonNumber = 3,
            episodeNumber = 4,
            progressPercent = 0.4,
            playbackContext = EpisodePlaybackContext(
                localSeasonNumber = 3,
                localEpisodeNumber = 4,
            ),
        ).toTrackerSyncItem()

        assertEquals(3, item.seasonNumber)
        assertEquals(4, item.episodeNumber)
    }

    @Test
    fun aniListSyncSkipsTmdbShowsWithoutAnimeEvidenceEvenIfAniListIdIsPresent() = runBlocking {
        val result = TrackerSyncClient().sync(
            account = TrackerAccountSnapshot(
                service = "AniList",
                accessToken = "token",
                isConnected = true,
            ),
            item = TrackerSyncItem(
                target = DetailTarget.TmdbShow(100),
                title = "Ordinary Show",
                seasonNumber = 1,
                episodeNumber = 1,
                anilistMediaId = 9001,
                anilistEpisodeNumber = 1,
                progressPercent = 0.95,
                isAnime = false,
            ),
        )

        assertTrue(result.skipped)
        assertEquals("AniList anime sync needs anime playback evidence.", result.message)
    }

    @Test
    fun aniListMutationTargetsCurrentProgress() {
        val mutation = aniListSaveMediaListMutation(mediaId = 123, progress = 7)

        assertTrue("mediaId: 123" in mutation)
        assertTrue("progress: 7" in mutation)
        assertTrue("status: CURRENT" in mutation)
    }

    @Test
    fun aniListRatingMutationUsesScoreAndHalfStarNormalization() {
        val mutation = aniListRatingMutation(
            anilistMediaId = 321,
            ratingOutOf10 = 7.3,
            note = "solid episode",
        )

        assertTrue("mediaId: 321" in mutation)
        assertTrue("score: 7.5" in mutation)
        assertTrue("notes: \"solid episode\"" in mutation)
        assertTrue("scoreRaw" !in mutation)
    }
}
