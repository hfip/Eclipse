package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.js.ServiceEpisodeLink
import dev.soupy.eclipse.android.core.model.EpisodePlaybackContext
import dev.soupy.eclipse.android.core.model.StremioMetaPreview
import dev.soupy.eclipse.android.core.model.StremioVideo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class StreamResolutionRepositoryEpisodeMatchingTest {
    @Test
    fun autoModeUsesAbsoluteEpisodeForBundledAnimeMeta() {
        val request = animeRequest(
            season = 2,
            episode = 1,
            localSeason = 2,
            localEpisode = 1,
            absoluteEpisode = 13,
            seasonEpisodeCount = 13,
            autoMode = true,
        )
        val meta = StremioMetaPreview(
            id = "series",
            videos = (1..25).map { episode ->
                StremioVideo(id = "series:1:$episode", season = 1, episode = episode)
            },
        )

        val matches = matchingMetaVideosForRequest(meta, request)

        assertEquals(listOf("series:1:13"), matches.map(StremioVideo::id))
    }

    @Test
    fun manualModeDoesNotInferBundledAnimeEpisode() {
        val request = animeRequest(
            season = 2,
            episode = 1,
            localSeason = 2,
            localEpisode = 1,
            absoluteEpisode = 13,
            seasonEpisodeCount = 13,
            autoMode = false,
        )
        val meta = StremioMetaPreview(
            id = "series",
            videos = (1..25).map { episode ->
                StremioVideo(id = "series:1:$episode", season = 1, episode = episode)
            },
        )

        assertTrue(matchingMetaVideosForRequest(meta, request).isEmpty())
    }

    @Test
    fun autoModeUsesLocalEpisodeForSeasonOnlyAnimeMeta() {
        val request = animeRequest(
            season = 2,
            episode = 1,
            localSeason = 2,
            localEpisode = 1,
            absoluteEpisode = 13,
            seasonEpisodeCount = 13,
            autoMode = true,
        )
        val meta = StremioMetaPreview(
            id = "series-season",
            videos = (1..13).map { episode ->
                StremioVideo(id = "series-season:1:$episode", season = 1, episode = episode)
            },
        )

        val matches = matchingMetaVideosForRequest(meta, request)

        assertEquals(listOf("series-season:1:1"), matches.map(StremioVideo::id))
    }

    @Test
    fun exactSeasonEpisodeMatchWinsBeforeAnimeInference() {
        val request = animeRequest(
            season = 2,
            episode = 1,
            localSeason = 2,
            localEpisode = 1,
            absoluteEpisode = 13,
            seasonEpisodeCount = 13,
            autoMode = true,
        )
        val meta = StremioMetaPreview(
            id = "series",
            videos = listOf(
                StremioVideo(id = "series:1:13", season = 1, episode = 13),
                StremioVideo(id = "series:2:1", season = 2, episode = 1),
            ),
        )

        val matches = matchingMetaVideosForRequest(meta, request)

        assertEquals(listOf("series:2:1"), matches.map(StremioVideo::id))
    }

    @Test
    fun streamIdsForKitsuMetaUseEpisodeOnlySuffix() {
        val request = animeRequest(
            season = 2,
            episode = 1,
            localSeason = 2,
            localEpisode = 1,
            absoluteEpisode = 13,
            seasonEpisodeCount = 13,
            autoMode = true,
        ).let { base ->
            base.copy(playbackContext = base.playbackContext?.copy(kitsuMediaId = 555))
        }
        val meta = StremioMetaPreview(id = "kitsu:555")

        val ids = streamIdsFromMeta(meta, request)

        assertEquals(listOf("kitsu:555:1"), ids)
    }

    @Test
    fun streamIdsForAnimeMetaIncludeSeasonScopedLocalEpisodeFallback() {
        val request = animeRequest(
            season = 2,
            episode = 1,
            localSeason = 2,
            localEpisode = 1,
            absoluteEpisode = 13,
            seasonEpisodeCount = 13,
            autoMode = true,
        )
        val meta = StremioMetaPreview(id = "anime-addon-id")

        val ids = streamIdsFromMeta(meta, request)

        assertEquals(
            listOf("anime-addon-id:2:1", "anime-addon-id:1:1"),
            ids,
        )
    }

    @Test
    fun streamIdsForTmdbIdMetaIncludeSeasonScopedAnimeFallback() {
        val request = animeRequest(
            season = 2,
            episode = 1,
            localSeason = 2,
            localEpisode = 1,
            absoluteEpisode = 13,
            seasonEpisodeCount = 13,
            autoMode = true,
        )
        val meta = StremioMetaPreview(id = "tmdb_id:100")

        val ids = streamIdsFromMeta(meta, request)

        assertEquals(
            listOf("tmdb_id:100:2:1", "tmdb_id:100:1:1"),
            ids,
        )
    }

    @Test
    fun autoModeUsesAbsoluteEpisodeForBundledCustomServiceEpisodes() {
        val selection = animeSelection(
            season = 2,
            episode = 1,
            localSeason = 2,
            localEpisode = 1,
            absoluteEpisode = 13,
            seasonEpisodeCount = 13,
        )
        val request = animeRequest(
            season = 2,
            episode = 1,
            localSeason = 2,
            localEpisode = 1,
            absoluteEpisode = 13,
            seasonEpisodeCount = 13,
            autoMode = true,
        )
        val episodes = serviceEpisodes(1..25)

        val match = episodes.bestEpisodeForRequest(
            request = request,
            fallback = selection,
            allowEpisodeAutoResolution = true,
        )

        assertEquals(13, match?.episodeNumber)
    }

    @Test
    fun manualModeExposesLocalAndAbsoluteCustomServiceEpisodeChoices() {
        val selection = animeSelection(
            season = 2,
            episode = 1,
            localSeason = 2,
            localEpisode = 1,
            absoluteEpisode = 13,
            seasonEpisodeCount = 13,
        )
        val request = animeRequest(
            season = 2,
            episode = 1,
            localSeason = 2,
            localEpisode = 1,
            absoluteEpisode = 13,
            seasonEpisodeCount = 13,
            autoMode = false,
        )
        val episodes = serviceEpisodes(1..25)

        val choices = episodes.episodeCandidatesForRequest(
            request = request,
            fallback = selection,
            allowEpisodeAutoResolution = false,
        )

        assertEquals(listOf(1, 13), choices.map(ServiceEpisodeLink::episodeNumber))
    }

    @Test
    fun autoModeUsesLocalEpisodeForSeasonScopedCustomServiceEpisodes() {
        val selection = animeSelection(
            season = 2,
            episode = 1,
            localSeason = 2,
            localEpisode = 1,
            absoluteEpisode = 13,
            seasonEpisodeCount = 13,
        )
        val request = animeRequest(
            season = 2,
            episode = 1,
            localSeason = 2,
            localEpisode = 1,
            absoluteEpisode = 13,
            seasonEpisodeCount = 13,
            autoMode = true,
        )
        val episodes = serviceEpisodes(1..13)

        val match = episodes.bestEpisodeForRequest(
            request = request,
            fallback = selection,
            allowEpisodeAutoResolution = true,
        )

        assertEquals(1, match?.episodeNumber)
    }

    private fun animeRequest(
        season: Int,
        episode: Int,
        localSeason: Int,
        localEpisode: Int,
        absoluteEpisode: Int,
        seasonEpisodeCount: Int,
        autoMode: Boolean,
    ): StremioRequest = StremioRequest(
        type = "series",
        tmdbId = 1,
        imdbId = "tt1",
        season = season,
        episode = episode,
        summary = "Anime S${localSeason}E$localEpisode",
        playbackContext = EpisodePlaybackContext(
            localSeasonNumber = localSeason,
            localEpisodeNumber = localEpisode,
            anilistMediaId = 100,
            tmdbSeasonNumber = season,
            tmdbEpisodeNumber = episode,
            animeAbsoluteEpisodeNumber = absoluteEpisode,
            animeSeasonEpisodeCount = seasonEpisodeCount,
        ),
        allowEpisodeAutoResolution = autoMode,
    )

    private fun animeSelection(
        season: Int,
        episode: Int,
        localSeason: Int,
        localEpisode: Int,
        absoluteEpisode: Int,
        seasonEpisodeCount: Int,
    ): StreamEpisodeSelection = StreamEpisodeSelection(
        seasonNumber = season,
        episodeNumber = episode,
        localSeasonNumber = localSeason,
        localEpisodeNumber = localEpisode,
        animeAbsoluteEpisodeNumber = absoluteEpisode,
        animeSeasonEpisodeCount = seasonEpisodeCount,
        label = "S${localSeason}E$localEpisode",
    )

    private fun serviceEpisodes(range: IntRange): List<ServiceEpisodeLink> =
        range.map { episode ->
            ServiceEpisodeLink(
                title = "Episode $episode",
                href = "/episode/$episode",
                episodeNumber = episode,
            )
        }
}
