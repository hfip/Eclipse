package dev.soupy.eclipse.android.ui.detail

import dev.soupy.eclipse.android.core.model.EpisodeProgressBackup
import dev.soupy.eclipse.android.core.model.EpisodePlaybackContext
import dev.soupy.eclipse.android.core.model.PlayerSource
import dev.soupy.eclipse.android.feature.detail.DetailEpisodeRow
import dev.soupy.eclipse.android.feature.detail.DetailScreenState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AndroidDetailMainPlayEpisodeTest {
    @Test
    fun choosesLatestInProgressEpisodeAfterWatchedRun() {
        val episodes = episodes(1, 4)
        val selected = chooseMainPlayEpisode(
            episodes = episodes,
            progressEntries = listOf(
                progress(episode = 1, current = 1800.0, total = 1800.0, watched = true),
                progress(episode = 2, current = 600.0, total = 1800.0, updated = "2026-01-01T00:00:00Z"),
                progress(episode = 3, current = 300.0, total = 1800.0, updated = "2026-01-02T00:00:00Z"),
            ),
            showId = ShowId,
        )

        assertEquals("s1e3", selected?.id)
    }

    @Test
    fun choosesNextEpisodeAfterLatestWatchedEpisode() {
        val selected = chooseMainPlayEpisode(
            episodes = episodes(1, 4),
            progressEntries = listOf(
                progress(episode = 1, current = 1800.0, total = 1800.0, watched = true),
                progress(episode = 2, current = 1800.0, total = 1800.0, watched = true),
            ),
            showId = ShowId,
        )

        assertEquals("s1e3", selected?.id)
    }

    @Test
    fun choosesInProgressEpisodeWhenNothingIsWatched() {
        val selected = chooseMainPlayEpisode(
            episodes = episodes(1, 3),
            progressEntries = listOf(
                progress(episode = 2, current = 500.0, total = 1800.0),
            ),
            showId = ShowId,
        )

        assertEquals("s1e2", selected?.id)
    }

    @Test
    fun fallsBackToFirstEpisodeWithoutTmdbShowProgressTarget() {
        val selected = chooseMainPlayEpisode(
            episodes = episodes(1, 3),
            progressEntries = listOf(
                progress(episode = 2, current = 500.0, total = 1800.0),
            ),
            showId = null,
        )

        assertEquals("s1e1", selected?.id)
    }

    @Test
    fun progressSnapshotUsesOutgoingSourceContextAfterNextEpisodeSelection() {
        val selected = DetailScreenState(
            episodes = episodes(1, 3),
            selectedEpisodeId = "s1e2",
        ).progressEpisodeFor(
            PlayerSource(
                uri = "https://example.com/episode-1.m3u8",
                context = EpisodePlaybackContext(
                    localSeasonNumber = 1,
                    localEpisodeNumber = 1,
                    tmdbSeasonNumber = 1,
                    tmdbEpisodeNumber = 1,
                ),
            ),
        )

        assertEquals("s1e1", selected?.id)
    }

    @Test
    fun progressSnapshotDoesNotFallBackWhenSourceContextIsUnknown() {
        val selected = DetailScreenState(
            episodes = episodes(1, 3),
            selectedEpisodeId = "s1e2",
        ).progressEpisodeFor(
            PlayerSource(
                uri = "https://example.com/unknown.m3u8",
                context = EpisodePlaybackContext(
                    localSeasonNumber = 4,
                    localEpisodeNumber = 7,
                ),
            ),
        )

        assertNull(selected)
    }

    @Test
    fun progressSnapshotsRejectTransientTinyDurations() {
        assertFalse(isReliablePlaybackProgressDuration(1_500L))
        assertTrue(isReliablePlaybackProgressDuration(5_000L))
    }

    private fun episodes(
        season: Int,
        count: Int,
    ): List<DetailEpisodeRow> = (1..count).map { episode ->
        DetailEpisodeRow(
            id = "s${season}e$episode",
            title = "Episode $episode",
            seasonNumber = season,
            episodeNumber = episode,
        )
    }

    private fun progress(
        episode: Int,
        current: Double,
        total: Double,
        watched: Boolean = false,
        updated: String = "2026-01-01T00:00:00Z",
    ): EpisodeProgressBackup = EpisodeProgressBackup(
        id = "ep_${ShowId}_s1_e$episode",
        showId = ShowId,
        seasonNumber = 1,
        episodeNumber = episode,
        currentTime = current,
        totalDuration = total,
        isWatched = watched,
        lastUpdated = updated,
    )

    private companion object {
        const val ShowId = 123
    }
}
