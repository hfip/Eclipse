package dev.soupy.eclipse.android.ui.detail

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.soupy.eclipse.android.core.storage.SettingsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import dev.soupy.eclipse.android.data.ContinueWatchingDraft
import dev.soupy.eclipse.android.data.DetailContent
import dev.soupy.eclipse.android.data.DetailRepository
import dev.soupy.eclipse.android.data.DownloadDraft
import dev.soupy.eclipse.android.data.DownloadsRepository
import dev.soupy.eclipse.android.data.EpisodeProgressDraft
import dev.soupy.eclipse.android.data.LibraryItemDraft
import dev.soupy.eclipse.android.data.MovieProgressDraft
import dev.soupy.eclipse.android.data.orNull
import dev.soupy.eclipse.android.data.ProgressRepository
import dev.soupy.eclipse.android.data.RatingsRepository
import dev.soupy.eclipse.android.data.StreamResolutionRepository
import dev.soupy.eclipse.android.data.StreamEpisodeSelection
import dev.soupy.eclipse.android.data.TrackerPlaybackProgressDraft
import dev.soupy.eclipse.android.data.TrackerRepository
import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.EpisodePlaybackContext
import dev.soupy.eclipse.android.core.model.EpisodeProgressBackup
import dev.soupy.eclipse.android.core.model.MovieProgressBackup
import dev.soupy.eclipse.android.core.model.PlayerSource
import dev.soupy.eclipse.android.core.model.SkipSegment
import dev.soupy.eclipse.android.core.model.TrackerStateSnapshot
import dev.soupy.eclipse.android.core.model.formattedUserRatingOutOf10
import dev.soupy.eclipse.android.core.model.normalizedUserRatingOutOf10
import dev.soupy.eclipse.android.core.model.progressPercent
import dev.soupy.eclipse.android.feature.detail.DetailCastRow
import dev.soupy.eclipse.android.feature.detail.DetailEpisodeRow
import dev.soupy.eclipse.android.feature.detail.DetailFactRow
import dev.soupy.eclipse.android.feature.detail.DetailScreenState
import dev.soupy.eclipse.android.feature.detail.DetailStreamRow
import dev.soupy.eclipse.android.core.network.AniSkipService
import dev.soupy.eclipse.android.core.network.IntroDbService
import dev.soupy.eclipse.android.core.network.TmdbService
import kotlin.math.roundToInt

class AndroidDetailViewModel(
    private val repository: DetailRepository,
    private val streamResolutionRepository: StreamResolutionRepository,
    private val progressRepository: ProgressRepository,
    private val downloadsRepository: DownloadsRepository,
    private val ratingsRepository: RatingsRepository,
    private val trackerRepository: TrackerRepository,
    private val aniSkipService: AniSkipService,
    private val introDbService: IntroDbService,
    private val tmdbService: TmdbService,
    private val settingsStore: SettingsStore,
) : ViewModel() {
    private val _state = MutableStateFlow(DetailScreenState())
    val state: StateFlow<DetailScreenState> = _state.asStateFlow()

    private var currentTarget: DetailTarget? = null
    private var currentProgressTarget: DetailTarget? = null
    private var currentRatingTmdbId: Int? = null
    private var currentRatingAniListId: Int? = null
    private var skipProviderSettings = SkipProviderSettings()
    private var preferDownloadedMedia = false
    private var detailUiSettings = DetailUiSettings()
    private val syncedTrackerProgressKeys = mutableSetOf<String>()

    init {
        viewModelScope.launch {
            settingsStore.settings.collect { settings ->
                preferDownloadedMedia = settings.preferDownloadedMedia
                skipProviderSettings = SkipProviderSettings(
                    aniSkipEnabled = settings.aniSkipEnabled,
                    introDbEnabled = settings.introDbEnabled,
                    introDbAppEnabled = settings.introDbAppEnabled,
                )
                detailUiSettings = DetailUiSettings(
                    seasonMenu = settings.seasonMenu,
                    horizontalEpisodeList = settings.horizontalEpisodeList,
                    mediaDetailElementOrder = settings.mediaDetailElementOrder,
                    mediaDetailHiddenElements = settings.mediaDetailHiddenElements,
                )
                _state.update { state -> detailUiSettings.applyTo(state) }
            }
        }
    }

    fun load(target: DetailTarget?) {
        if (target == null) {
            currentTarget = null
            currentProgressTarget = null
            currentRatingTmdbId = null
            currentRatingAniListId = null
            _state.value = DetailScreenState()
            return
        }

        if (target == currentTarget && (_state.value.title.isNotBlank() || _state.value.isLoading)) {
            return
        }

        currentTarget = target
        viewModelScope.launch {
            _state.value = DetailScreenState(hasSelection = true, isLoading = true)
            val result = repository.load(target)
            result
                .onSuccess { content ->
                    currentProgressTarget = content.progressTarget ?: target
                    currentRatingTmdbId = (currentProgressTarget ?: target).tmdbRatingId()
                    currentRatingAniListId = content.primaryAniListId.takeIf { content.isAnime }
                    val ratingsSnapshot = ratingsRepository.loadSnapshot().getOrNull()
                    val ratingKey = currentRatingTmdbId?.toString()
                    val rating = ratingKey?.let { key ->
                        ratingsSnapshot?.ratings?.get(key)
                    }
                    val note = ratingKey?.let { key ->
                        ratingsSnapshot?.notes?.get(key)
                    }.orEmpty()
                    val trackerSnapshot = trackerRepository.loadSnapshot().getOrNull()
                    _state.value = detailUiSettings.applyTo(
                        content.toUiState(userRating = rating, userRatingNote = note).copy(
                            canSyncRatingToAniList = content.canSyncRatingTo("anilist", trackerSnapshot),
                            canSyncRatingToMyAnimeList = content.canSyncRatingTo("myanimelist", trackerSnapshot),
                        ),
                    )
                }
                .onFailure { error ->
                    currentProgressTarget = null
                    currentRatingTmdbId = null
                    currentRatingAniListId = null
                    _state.update {
                        it.copy(
                            hasSelection = true,
                            isLoading = false,
                            errorMessage = error.message ?: "Unknown detail error.",
                        )
                    }
                }
        }
    }

    fun setUserRating(rating: Double) {
        val tmdbId = currentRatingTmdbId ?: return markUnsupportedRating()
        val anilistId = currentRatingAniListId
        val clampedRating = normalizedUserRatingOutOf10(rating)
        val ratingText = formattedUserRatingOutOf10(clampedRating)
        viewModelScope.launch {
            ratingsRepository.setRating(tmdbId, clampedRating)
                .onSuccess {
                    _state.update {
                        it.copy(
                            userRating = clampedRating,
                            streamStatusMessage = "Saved rating $ratingText/10.",
                        )
                    }
                    syncRatingIfNeeded(anilistId, clampedRating)
                }
                .onFailure { error ->
                    _state.update {
                        it.copy(streamStatusMessage = error.message ?: "Could not save rating.")
                    }
                }
        }
    }

    private suspend fun syncRatingIfNeeded(
        anilistId: Int?,
        rating: Double,
    ) {
        if (anilistId == null) return
        val ratingText = formattedUserRatingOutOf10(rating)
        trackerRepository.syncUserRating(anilistId, rating)
            .onSuccess { summary ->
                val message = when {
                    summary.failures.isNotEmpty() && summary.syncedItems == 0 ->
                        "Saved rating $ratingText/10 locally. Remote rating sync failed: ${summary.failures.first()}"
                    summary.failures.isNotEmpty() ->
                        "Saved rating $ratingText/10 and synced ${summary.syncedItems} tracker rating${summary.syncedItems.pluralSuffix()} with ${summary.failures.size} issue${summary.failures.size.pluralSuffix()}."
                    summary.syncedItems > 0 ->
                        "Saved rating $ratingText/10 and synced ${summary.syncedItems} tracker rating${summary.syncedItems.pluralSuffix()}."
                    else -> null
                }
                message?.let { status ->
                    _state.update { it.copy(streamStatusMessage = status) }
                }
            }
            .onFailure { error ->
                _state.update {
                    it.copy(streamStatusMessage = "Saved rating $ratingText/10 locally. Remote rating sync failed: ${error.message ?: "unknown error"}.")
                }
            }
    }

    fun setUserRatingNote(note: String) {
        val tmdbId = currentRatingTmdbId ?: return markUnsupportedRating()
        viewModelScope.launch {
            ratingsRepository.setNote(tmdbId, note)
                .onSuccess {
                    _state.update {
                        it.copy(userRatingNote = note, streamStatusMessage = "Saved private note.")
                    }
                }
                .onFailure { error ->
                    _state.update {
                        it.copy(streamStatusMessage = error.message ?: "Could not save note.")
                    }
                }
        }
    }

    fun clearUserRating() {
        val tmdbId = currentRatingTmdbId ?: return markUnsupportedRating()
        viewModelScope.launch {
            ratingsRepository.removeRating(tmdbId)
                .onSuccess {
                    _state.update {
                        it.copy(userRating = null, streamStatusMessage = "Removed your rating.")
                    }
                }
                .onFailure { error ->
                    _state.update {
                        it.copy(streamStatusMessage = error.message ?: "Could not remove rating.")
                    }
                }
        }
    }

    fun syncRatingNoteToAniList() {
        syncRatingNoteTo("AniList")
    }

    fun syncRatingNoteToMyAnimeList() {
        syncRatingNoteTo("MyAnimeList")
    }

    private fun syncRatingNoteTo(service: String) {
        val anilistId = currentRatingAniListId ?: return markUnsupportedRating()
        val rating = _state.value.userRating ?: return
        val note = _state.value.userRatingNote
        viewModelScope.launch {
            _state.update {
                it.copy(streamStatusMessage = "Syncing rating and note to $service...")
            }
            trackerRepository.syncUserRatingAndNote(
                service = service,
                anilistMediaId = anilistId,
                ratingOutOf10 = rating,
                note = note,
            ).onSuccess { summary ->
                val message = when {
                    summary.failures.isNotEmpty() -> "Could not sync $service rating: ${summary.failures.first()}"
                    summary.syncedItems > 0 -> "Synced rating and note to $service."
                    else -> "No $service rating sync was needed."
                }
                _state.update { it.copy(streamStatusMessage = message) }
            }.onFailure { error ->
                _state.update {
                    it.copy(streamStatusMessage = error.message ?: "Could not sync rating to $service.")
                }
            }
        }
    }

    fun markCurrentWatched() {
        markCurrent(watched = true)
    }

    fun markCurrentUnwatched() {
        markCurrent(watched = false)
    }

    fun markEpisodeWatched(episodeId: String) {
        markEpisode(episodeId = episodeId, watched = true)
    }

    fun markEpisodeUnwatched(episodeId: String) {
        markEpisode(episodeId = episodeId, watched = false)
    }

    fun markPreviousEpisodesWatched(episodeId: String) {
        val target = currentProgressTarget as? DetailTarget.TmdbShow ?: return markUnsupportedProgress()
        val episodes = state.value.episodes
        val episodeIndex = episodes.indexOfFirst { it.id == episodeId }
        if (episodeIndex < 0) return
        val episode = episodes[episodeIndex]
        val localSeasonNumber = episode.seasonNumber ?: return
        val localEpisodeNumber = episode.episodeNumber ?: return
        val previousEpisodes = episodes
            .take(episodeIndex)
            .filter { previous ->
                previous.seasonNumber == localSeasonNumber &&
                    previous.sourceSeasonNumber != null &&
                    previous.sourceEpisodeNumber != null
            }
        if (localEpisodeNumber <= 1 || previousEpisodes.isEmpty()) {
            _state.update { it.copy(streamStatusMessage = "There are no previous episodes in this season.") }
            return
        }
        viewModelScope.launch {
            var failureMessage: String? = null
            previousEpisodes.forEach { previous ->
                progressRepository.markEpisodeWatched(
                    showId = target.id,
                    seasonNumber = previous.sourceSeasonNumber ?: return@forEach,
                    episodeNumber = previous.sourceEpisodeNumber ?: return@forEach,
                    watched = true,
                    anilistMediaId = previous.anilistMediaId,
                    isAnime = state.value.hasAnimePlaybackEvidence(previous),
                ).onFailure { error ->
                    failureMessage = error.message ?: "Could not mark previous episodes watched."
                }
            }
            if (failureMessage == null) {
                _state.update {
                    it.copy(streamStatusMessage = "Marked ${previousEpisodes.size} previous episode${if (previousEpisodes.size == 1) "" else "s"} watched.")
                }
            } else {
                _state.update { it.copy(streamStatusMessage = failureMessage) }
            }
        }
    }

    fun retry() {
        load(currentTarget)
    }

    fun resolveStreams() {
        val snapshot = state.value
        val selectedEpisode = snapshot.selectedEpisodeId
            ?.let { id -> snapshot.episodes.firstOrNull { it.id == id } }
        viewModelScope.launch {
            val showTarget = (currentProgressTarget ?: currentTarget) as? DetailTarget.TmdbShow
            val progressEntries = showTarget
                ?.let { progressRepository.loadSnapshot().getOrNull()?.episodeProgress }
                .orEmpty()
            val mainPlayEpisode = selectedEpisode ?: if (snapshot.isMovie) {
                null
            } else {
                chooseMainPlayEpisode(
                    episodes = snapshot.episodes,
                    progressEntries = progressEntries,
                    showId = showTarget?.id,
                )
            }
            if (playDownloadedIfPreferred(snapshot, mainPlayEpisode)) return@launch
            resolveStreamsForEpisode(mainPlayEpisode?.toStreamEpisodeSelection())
        }
    }

    fun resolveEpisodeStreams(episodeId: String) {
        val episode = state.value.episodes.firstOrNull { it.id == episodeId } ?: return
        val selection = episode.toStreamEpisodeSelection() ?: return
        resolveStreamsForEpisode(selection)
    }

    private fun resolveStreamsForEpisode(episode: StreamEpisodeSelection?) {
        val target = currentTarget ?: return
        if (_state.value.isResolvingStreams) return

        viewModelScope.launch {
            _state.update {
                it.copy(
                    isResolvingStreams = true,
                    streamStatusMessage = episode?.let { selected ->
                        "Resolving addon streams for ${selected.label}..."
                    } ?: "Resolving addon streams...",
                    selectedEpisodeId = episode?.let { selected ->
                        _state.value.episodes.firstOrNull { it.matchesSelection(selected) }?.id
                    } ?: it.selectedEpisodeId,
                    selectedEpisodeLabel = episode?.label ?: it.selectedEpisodeLabel,
                )
            }
            streamResolutionRepository.resolve(target, episode)
                .onSuccess { result ->
                    val current = _state.value
                    val selectedEpisodeId = episode?.let { selected ->
                        current.episodes.firstOrNull { it.matchesSelection(selected) }?.id
                    } ?: current.selectedEpisodeId
                    val selectedEpisodeLabel = episode?.label ?: current.selectedEpisodeLabel
                    val resumeState = current.copy(
                        selectedEpisodeId = selectedEpisodeId,
                        selectedEpisodeLabel = selectedEpisodeLabel,
                    )
                    val candidates = result.candidates.map { candidate ->
                        candidate.copy(
                            playerSource = candidate.playerSource?.withResumePosition(resumeState),
                        )
                    }
                    val selectedSource = result.selectedSource?.withResumePosition(resumeState)
                    _state.update { state ->
                        state.copy(
                            isResolvingStreams = false,
                            streamStatusMessage = result.statusMessage,
                            streamCandidates = candidates.map { candidate ->
                                DetailStreamRow(
                                    id = candidate.id,
                                    title = candidate.title,
                                    subtitle = candidate.subtitle,
                                    supportingText = candidate.supportingText,
                                    playable = candidate.isPlayable,
                                    playerSource = candidate.playerSource,
                                )
                            },
                            playerSource = selectedSource ?: state.playerSource,
                            skipSegments = if (selectedSource != null) emptyList() else state.skipSegments,
                            skipStatusMessage = if (selectedSource != null) {
                                "Loading skip segments..."
                            } else {
                                state.skipStatusMessage
                            },
                        )
                    }
                    selectedSource?.let(::loadSkipSegmentsFor)
                }
                .onFailure { error ->
                    _state.update {
                        it.copy(
                            isResolvingStreams = false,
                            streamStatusMessage = error.message ?: "Stream resolution failed.",
                            streamCandidates = emptyList(),
                        )
                    }
                }
        }
    }

    private suspend fun playDownloadedIfPreferred(
        snapshot: DetailScreenState,
        episode: DetailEpisodeRow?,
    ): Boolean {
        if (!preferDownloadedMedia) return false
        val target = currentTarget ?: return false
        val exactSource = downloadsRepository.completedPlayerSource(
            target = target,
            downloadKeySuffix = episode?.downloadKeySuffix(),
        ).getOrNull()
        val fallbackPlayback = if (exactSource == null && target is DetailTarget.TmdbShow) {
            downloadsRepository.latestCompletedPlayerSource(target).getOrNull()
        } else {
            null
        }
        val fallbackEpisode = fallbackPlayback
            ?.downloadKeySuffix
            ?.let { suffix -> snapshot.episodes.firstOrNull { it.downloadKeySuffix() == suffix } }
        val source = exactSource ?: fallbackPlayback?.source ?: return false
        val playbackEpisode = episode ?: fallbackEpisode
        val selection = playbackEpisode?.toStreamEpisodeSelection()
        val sourceWithContext = source.copy(
            context = source.context ?: selection?.toPlaybackContext(),
            isDownloaded = true,
        )
        val resumeState = snapshot.copy(
            selectedEpisodeId = playbackEpisode?.id ?: snapshot.selectedEpisodeId,
            selectedEpisodeLabel = selection?.label ?: snapshot.selectedEpisodeLabel,
        )
        val resumedSource = sourceWithContext.withResumePosition(resumeState)
        _state.update { state ->
            state.copy(
                selectedEpisodeId = resumeState.selectedEpisodeId,
                selectedEpisodeLabel = resumeState.selectedEpisodeLabel,
                isResolvingStreams = false,
                streamStatusMessage = "Playing downloaded media from app storage.",
                streamCandidates = emptyList(),
                playerSource = resumedSource,
                skipSegments = emptyList(),
                skipStatusMessage = "Loading skip segments...",
            )
        }
        loadSkipSegmentsFor(resumedSource)
        return true
    }

    fun playResolvedStream(streamId: String) {
        viewModelScope.launch {
            val current = state.value
            val selectedSource = current.streamCandidates.firstOrNull { it.id == streamId }?.playerSource
                ?.withResumePosition(current)
            _state.update { state ->
                state.copy(
                    playerSource = selectedSource ?: state.playerSource,
                    skipSegments = if (selectedSource != null) emptyList() else state.skipSegments,
                    skipStatusMessage = if (selectedSource != null) "Loading skip segments..." else state.skipStatusMessage,
                )
            }
            selectedSource?.let(::loadSkipSegmentsFor)
        }
    }

    fun playNextEpisode() {
        val nextEpisode = nextEpisodeAfterCurrent()
        if (nextEpisode == null) {
            _state.update { it.copy(streamStatusMessage = "No next episode is loaded yet.") }
            return
        }
        val selection = nextEpisode.toStreamEpisodeSelection()
        if (selection == null) {
            _state.update { it.copy(streamStatusMessage = "Next episode metadata is not playable yet.") }
            return
        }
        resolveStreamsForEpisode(selection)
    }

    fun currentPlaybackProgressDraft(
        positionMs: Long,
        durationMs: Long,
        isFinished: Boolean,
    ): ContinueWatchingDraft? {
        val target = currentProgressTarget ?: currentTarget ?: return null
        val snapshot = state.value
        if (snapshot.title.isBlank() || durationMs <= 0L) return null

        val progressPercent = if (isFinished) {
            1f
        } else {
            (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)
        }
        if (!isFinished && positionMs < 15_000L && progressPercent < 0.05f) {
            return null
        }

        val selectedEpisode = snapshot.selectedEpisodeId
            ?.let { id -> snapshot.episodes.firstOrNull { it.id == id } }
            ?: snapshot.episodes.firstOrNull()
        recordTypedProgress(
            target = target,
            snapshot = snapshot,
            selectedEpisode = selectedEpisode,
            positionMs = positionMs,
            durationMs = durationMs,
            isFinished = isFinished,
        )
        syncTrackersIfNeeded(
            target = target,
            snapshot = snapshot,
            selectedEpisode = selectedEpisode,
            progressPercent = progressPercent.toDouble(),
            isFinished = isFinished,
        )

        val subtitle = selectedEpisode?.title ?: snapshot.subtitle ?: snapshot.playerSource?.title
        val progressLabel = listOfNotNull(
            selectedEpisode?.subtitle,
            "${(progressPercent * 100f).roundToInt()}% watched",
        ).joinToString(" | ").ifBlank {
            "${(progressPercent * 100f).roundToInt()}% watched"
        }

        return ContinueWatchingDraft(
            detailTarget = target,
            title = snapshot.title,
            subtitle = subtitle,
            imageUrl = snapshot.posterUrl,
            backdropUrl = snapshot.backdropUrl,
            progressPercent = progressPercent,
            progressLabel = progressLabel,
        )
    }

    fun currentLibraryItemDraft(): LibraryItemDraft? {
        val target = currentTarget ?: return null
        val snapshot = state.value
        if (snapshot.title.isBlank()) return null

        return LibraryItemDraft(
            detailTarget = target,
            title = snapshot.title,
            subtitle = snapshot.subtitle,
            overview = snapshot.overview,
            imageUrl = snapshot.posterUrl,
            backdropUrl = snapshot.backdropUrl,
            mediaLabel = snapshot.metadataChips.firstOrNull(),
        )
    }

    fun currentContinueWatchingDraft(): ContinueWatchingDraft? {
        val target = currentTarget ?: return null
        val snapshot = state.value
        if (snapshot.title.isBlank()) return null

        val firstEpisode = snapshot.episodes.firstOrNull()
        return ContinueWatchingDraft(
            detailTarget = target,
            title = snapshot.title,
            subtitle = firstEpisode?.title ?: snapshot.subtitle,
            imageUrl = snapshot.posterUrl,
            backdropUrl = snapshot.backdropUrl,
            progressPercent = if (firstEpisode == null) 0.42f else 0.08f,
            progressLabel = firstEpisode?.let { episode ->
                episode.subtitle?.let { "Resume near $it" } ?: "Resume from ${episode.title}"
            } ?: "Resume from the last saved movie position.",
        )
    }

    fun currentDownloadDraft(
        episodeId: String? = null,
        playerSourceOverride: PlayerSource? = null,
    ): DownloadDraft? {
        val target = currentTarget ?: return null
        val snapshot = state.value
        if (snapshot.title.isBlank()) return null

        val selectedEpisode = episodeId
            ?.let { id -> snapshot.episodes.firstOrNull { it.id == id } }
            ?: snapshot.selectedEpisodeId
            ?.let { id -> snapshot.episodes.firstOrNull { it.id == id } }
            ?: snapshot.episodes.firstOrNull()
        val attachedPlayerSource = playerSourceOverride ?: snapshot.playerSource.takeIf {
            episodeId == null || selectedEpisode?.id == snapshot.selectedEpisodeId
        }
        val playbackContext = attachedPlayerSource?.context
        val isEpisodeDraft = selectedEpisode != null || playbackContext != null
        return DownloadDraft(
            detailTarget = target,
            title = snapshot.title,
            subtitle = selectedEpisode?.title ?: snapshot.subtitle,
            imageUrl = snapshot.posterUrl,
            backdropUrl = snapshot.backdropUrl,
            mediaLabel = snapshot.metadataChips.firstOrNull(),
            progressLabel = selectedEpisode?.subtitle?.let { "Preparing offline draft near $it" }
                ?: "Preparing an offline draft from the current source.",
            sourceLabel = attachedPlayerSource?.title ?: if (isEpisodeDraft) {
                "Episode download draft"
            } else {
                "Movie download draft"
            },
            downloadKeySuffix = selectedEpisode?.downloadKeySuffix()
                ?: playbackContext?.downloadKeySuffix(),
            playerSource = attachedPlayerSource,
        )
    }

    fun currentDownloadDraftForStream(streamId: String): DownloadDraft? {
        val source = state.value.streamCandidates.firstOrNull { stream -> stream.id == streamId }?.playerSource
            ?: return null
        return currentDownloadDraft(playerSourceOverride = source)
    }

    fun currentDownloadDrafts(episodeIds: List<String>): List<DownloadDraft> =
        episodeIds
            .distinct()
            .mapNotNull { episodeId -> currentDownloadDraft(episodeId) }

    private fun recordTypedProgress(
        target: DetailTarget,
        snapshot: DetailScreenState,
        selectedEpisode: DetailEpisodeRow?,
        positionMs: Long,
        durationMs: Long,
        isFinished: Boolean,
    ) {
        val currentSeconds = positionMs.toDouble() / 1000.0
        val durationSeconds = durationMs.toDouble() / 1000.0
        when (target) {
            is DetailTarget.TmdbMovie -> {
                viewModelScope.launch {
                    progressRepository.recordMovieProgress(
                        MovieProgressDraft(
                            movieId = target.id,
                            title = snapshot.title,
                            posterUrl = snapshot.posterUrl,
                            currentTimeSeconds = currentSeconds,
                            totalDurationSeconds = durationSeconds,
                            isFinished = isFinished,
                            lastServiceId = snapshot.playerSource?.serviceId,
                            lastHref = snapshot.playerSource?.serviceHref,
                        ),
                    )
                }
            }
            is DetailTarget.TmdbShow -> {
                val episode = selectedEpisode ?: return
                val seasonNumber = episode.sourceSeasonNumber ?: return
                val episodeNumber = episode.sourceEpisodeNumber ?: return
                viewModelScope.launch {
                    progressRepository.recordEpisodeProgress(
                        EpisodeProgressDraft(
                            showId = target.id,
                            seasonNumber = seasonNumber,
                            episodeNumber = episodeNumber,
                            showTitle = snapshot.title,
                            showPosterUrl = snapshot.posterUrl,
                            anilistMediaId = snapshot.playerSource?.context?.anilistMediaId,
                            isAnime = snapshot.hasAnimePlaybackEvidence(selectedEpisode),
                            currentTimeSeconds = currentSeconds,
                            totalDurationSeconds = durationSeconds,
                            isFinished = isFinished,
                            lastServiceId = snapshot.playerSource?.serviceId,
                            lastHref = snapshot.playerSource?.serviceHref,
                        ),
                    )
                }
            }
            is DetailTarget.AniListMediaTarget,
            is DetailTarget.ServiceMedia -> Unit
        }
    }

    private fun syncTrackersIfNeeded(
        target: DetailTarget,
        snapshot: DetailScreenState,
        selectedEpisode: DetailEpisodeRow?,
        progressPercent: Double,
        isFinished: Boolean,
    ) {
        if (!isFinished && progressPercent < TrackerSyncProgressThreshold) return

        val syncKey = when (target) {
            is DetailTarget.TmdbMovie -> "movie:${target.id}"
            is DetailTarget.TmdbShow -> {
                val episode = selectedEpisode ?: return
                val seasonNumber = episode.sourceSeasonNumber ?: return
                val episodeNumber = episode.sourceEpisodeNumber ?: return
                "show:${target.id}:$seasonNumber:$episodeNumber"
            }
            is DetailTarget.AniListMediaTarget,
            is DetailTarget.ServiceMedia -> return
        }
        if (!syncedTrackerProgressKeys.add(syncKey)) return

        viewModelScope.launch {
            trackerRepository.syncPlaybackProgress(
                TrackerPlaybackProgressDraft(
                    target = target,
                    title = snapshot.title,
                    seasonNumber = selectedEpisode?.sourceSeasonNumber,
                    episodeNumber = selectedEpisode?.sourceEpisodeNumber,
                    anilistMediaId = snapshot.playerSource?.context?.anilistMediaId,
                    isAnime = snapshot.hasAnimePlaybackEvidence(selectedEpisode),
                    progressPercent = progressPercent,
                    isFinished = isFinished,
                    playbackContext = snapshot.playerSource?.context,
                ),
            )
        }
    }

    private fun markCurrent(watched: Boolean) {
        when (val target = currentProgressTarget ?: currentTarget) {
            is DetailTarget.TmdbMovie -> {
                viewModelScope.launch {
                    progressRepository.markMovieWatched(target.id, watched)
                        .onSuccess {
                            _state.update {
                                it.copy(streamStatusMessage = if (watched) "Marked movie watched." else "Marked movie unwatched.")
                            }
                        }
                        .onFailure { error ->
                            _state.update {
                                it.copy(streamStatusMessage = error.message ?: "Could not update movie progress.")
                            }
                        }
                }
            }
            is DetailTarget.TmdbShow -> markLoadedShowEpisodes(target.id, watched)
            is DetailTarget.AniListMediaTarget,
            is DetailTarget.ServiceMedia,
            null -> markUnsupportedProgress()
        }
    }

    private fun markLoadedShowEpisodes(showId: Int, watched: Boolean) {
        val episodes = state.value.episodes.filter {
            it.sourceSeasonNumber != null && it.sourceEpisodeNumber != null
        }
        if (episodes.isEmpty()) {
            markUnsupportedProgress()
            return
        }
        viewModelScope.launch {
            episodes.forEach { episode ->
                progressRepository.markEpisodeWatched(
                    showId = showId,
                    seasonNumber = episode.sourceSeasonNumber ?: return@forEach,
                    episodeNumber = episode.sourceEpisodeNumber ?: return@forEach,
                    watched = watched,
                    anilistMediaId = episode.anilistMediaId,
                    isAnime = state.value.hasAnimePlaybackEvidence(episode),
                )
            }
            _state.update {
                it.copy(
                    streamStatusMessage = if (watched) {
                        "Marked ${episodes.size} loaded episodes watched."
                    } else {
                        "Marked ${episodes.size} loaded episodes unwatched."
                    },
                )
            }
        }
    }

    private fun markEpisode(episodeId: String, watched: Boolean) {
        val target = currentProgressTarget as? DetailTarget.TmdbShow ?: return markUnsupportedProgress()
        val episode = state.value.episodes.firstOrNull { it.id == episodeId } ?: return
        val seasonNumber = episode.sourceSeasonNumber ?: return
        val episodeNumber = episode.sourceEpisodeNumber ?: return
        viewModelScope.launch {
            progressRepository.markEpisodeWatched(
                showId = target.id,
                seasonNumber = seasonNumber,
                episodeNumber = episodeNumber,
                watched = watched,
                anilistMediaId = episode.anilistMediaId,
                isAnime = state.value.hasAnimePlaybackEvidence(episode),
            ).onSuccess {
                _state.update {
                    it.copy(
                        streamStatusMessage = if (watched) {
                            "Marked S${seasonNumber}E${episodeNumber} watched."
                        } else {
                            "Marked S${seasonNumber}E${episodeNumber} unwatched."
                        },
                    )
                }
            }.onFailure { error ->
                _state.update {
                    it.copy(streamStatusMessage = error.message ?: "Could not update episode progress.")
                }
            }
        }
    }

    private fun markUnsupportedProgress() {
        _state.update {
            it.copy(streamStatusMessage = "Progress actions need a TMDB movie or mapped TMDB series.")
        }
    }

    private fun markUnsupportedRating() {
        _state.update {
            it.copy(streamStatusMessage = "Ratings need a TMDB movie or mapped TMDB series.")
        }
    }

    private fun nextEpisodeAfterCurrent(): DetailEpisodeRow? {
        val playableEpisodes = state.value.episodes.filter {
            it.sourceSeasonNumber != null && it.sourceEpisodeNumber != null
        }
        if (playableEpisodes.size < 2) return null
        val currentIndex = state.value.selectedEpisodeId
            ?.let { id -> playableEpisodes.indexOfFirst { it.id == id } }
            ?.takeIf { it >= 0 }
            ?: 0
        return playableEpisodes.getOrNull(currentIndex + 1)
    }

    private suspend fun PlayerSource.withResumePosition(snapshot: DetailScreenState): PlayerSource {
        val resumePosition = resumePositionMsFor(snapshot, this)
        return if (resumePosition > 0L) {
            copy(resumePositionMs = resumePosition)
        } else {
            this
        }
    }

    private suspend fun resumePositionMsFor(
        snapshot: DetailScreenState,
        source: PlayerSource,
    ): Long {
        val target = currentProgressTarget ?: currentTarget ?: return 0L
        val progress = progressRepository.loadSnapshot().getOrNull() ?: return 0L
        return when (target) {
            is DetailTarget.TmdbMovie -> progress.movieProgress
                .firstOrNull { movie -> movie.id == target.id }
                ?.resumePositionMs()
                ?: 0L
            is DetailTarget.TmdbShow -> {
                val episode = snapshot.selectedPlaybackEpisode(source)
                val seasonNumber = episode?.sourceSeasonNumber
                    ?: source.context?.resolvedTMDBSeasonNumber
                    ?: return 0L
                val episodeNumber = episode?.sourceEpisodeNumber
                    ?: source.context?.resolvedTMDBEpisodeNumber
                    ?: return 0L
                progress.episodeProgress
                    .firstOrNull { entry ->
                        entry.showId == target.id &&
                            entry.seasonNumber == seasonNumber &&
                            entry.episodeNumber == episodeNumber
                    }
                    ?.resumePositionMs()
                    ?: 0L
            }
            is DetailTarget.AniListMediaTarget,
            is DetailTarget.ServiceMedia -> 0L
        }
    }

    private fun loadSkipSegmentsFor(source: PlayerSource) {
        val target = currentProgressTarget ?: currentTarget ?: return
        val context = source.context
        viewModelScope.launch {
            val providerSettings = skipProviderSettings
            if (!providerSettings.aniSkipEnabled && !providerSettings.introDbEnabled && !providerSettings.introDbAppEnabled) {
                _state.update {
                    it.copy(
                        skipSegments = emptyList(),
                        skipStatusMessage = "Skip segment providers are disabled in Settings.",
                    )
                }
                return@launch
            }

            val aniSkipSegments = if (providerSettings.aniSkipEnabled) context?.anilistMediaId?.let { anilistId ->
                aniSkipService.fetchSkipTimes(
                    anilistId = anilistId,
                    episodeNumber = context.localEpisodeNumber,
                    episodeDurationSeconds = 0.0,
                ).orNull().orEmpty()
            }.orEmpty() else emptyList()

            val introSegments = if (providerSettings.introDbEnabled && aniSkipSegments.isEmpty()) {
                when (target) {
                    is DetailTarget.TmdbMovie -> introDbService.fetchSkipTimes(
                        tmdbId = target.id,
                    ).orNull().orEmpty()
                    is DetailTarget.TmdbShow -> introDbService.fetchSkipTimes(
                        tmdbId = target.id,
                        seasonNumber = context?.resolvedTMDBSeasonNumber,
                        episodeNumber = context?.resolvedTMDBEpisodeNumber,
                    ).orNull().orEmpty()
                    is DetailTarget.AniListMediaTarget,
                    is DetailTarget.ServiceMedia -> emptyList()
                }
            } else {
                emptyList()
            }
            val introDbAppSegments = if (
                providerSettings.introDbAppEnabled &&
                aniSkipSegments.isEmpty() &&
                introSegments.isEmpty()
            ) {
                resolveIntroDbAppImdbId(target, source)?.let { imdbId ->
                    introDbService.fetchIntroDbAppSkipTimes(
                        imdbId = imdbId,
                        seasonNumber = context?.resolvedTMDBSeasonNumber,
                        episodeNumber = context?.resolvedTMDBEpisodeNumber,
                    ).orNull().orEmpty()
                }.orEmpty()
            } else {
                emptyList()
            }

            val merged = (aniSkipSegments + introSegments + introDbAppSegments).mergeSkipSegments()
            _state.update {
                it.copy(
                    skipSegments = merged,
                    skipStatusMessage = when {
                        merged.isEmpty() -> "No skip segments found yet for this source."
                        else -> "Loaded ${merged.size} skip segment${if (merged.size == 1) "" else "s"} for manual${if (merged.isNotEmpty()) "/auto" else ""} skipping."
                    },
                )
            }
        }
    }

    private suspend fun resolveIntroDbAppImdbId(
        target: DetailTarget,
        source: PlayerSource,
    ): String? =
        source.serviceHref.extractImdbId()
            ?: source.uri.extractImdbId()
            ?: when (target) {
                is DetailTarget.TmdbMovie -> tmdbService.movieDetail(target.id).orNull()?.externalIds?.imdbId
                is DetailTarget.TmdbShow -> tmdbService.tvShowDetail(target.id).orNull()?.externalIds?.imdbId
                is DetailTarget.AniListMediaTarget,
                is DetailTarget.ServiceMedia -> null
            }?.takeIf { it.isNotBlank() }
}

private data class SkipProviderSettings(
    val aniSkipEnabled: Boolean = true,
    val introDbEnabled: Boolean = true,
    val introDbAppEnabled: Boolean = true,
)

private data class DetailUiSettings(
    val seasonMenu: Boolean = false,
    val horizontalEpisodeList: Boolean = false,
    val mediaDetailElementOrder: String = dev.soupy.eclipse.android.core.model.MediaDetailElement.DefaultOrderRawValue,
    val mediaDetailHiddenElements: String = "",
) {
    fun applyTo(state: DetailScreenState): DetailScreenState = state.copy(
        seasonMenu = seasonMenu,
        horizontalEpisodeList = horizontalEpisodeList,
        mediaDetailElementOrder = mediaDetailElementOrder,
        mediaDetailHiddenElements = mediaDetailHiddenElements,
    )
}

private fun DetailContent.toUiState(
    userRating: Double?,
    userRatingNote: String,
): DetailScreenState = DetailScreenState(
    hasSelection = true,
    isLoading = false,
    title = title,
    subtitle = subtitle,
    overview = overview,
    posterUrl = posterUrl,
    backdropUrl = backdropUrl,
    logoUrl = logoUrl,
    metadataChips = metadataChips,
    detailFacts = detailFacts.map {
        DetailFactRow(
            label = it.label,
            value = it.value,
        )
    },
    contentRating = contentRating,
    userRating = userRating,
    userRatingNote = userRatingNote,
    cast = cast.map {
        DetailCastRow(
            id = it.id,
            name = it.name,
            role = it.role,
            imageUrl = it.imageUrl,
        )
    },
    episodesTitle = episodesTitle,
    episodes = episodes.map {
        DetailEpisodeRow(
            id = it.id,
            title = it.title,
            subtitle = it.subtitle,
            imageUrl = it.imageUrl,
            overview = it.overview,
            seasonNumber = it.seasonNumber,
            episodeNumber = it.episodeNumber,
            runtimeMinutes = it.runtimeMinutes,
            anilistMediaId = it.anilistMediaId,
            tmdbSeasonNumber = it.tmdbSeasonNumber,
            tmdbEpisodeNumber = it.tmdbEpisodeNumber,
            tmdbEpisodeOffset = it.tmdbEpisodeOffset,
            animeAbsoluteEpisodeNumber = it.animeAbsoluteEpisodeNumber,
            animeSeasonEpisodeCount = it.animeSeasonEpisodeCount,
            isSpecial = it.isSpecial,
            titleOnlySearch = it.titleOnlySearch,
            searchTitle = it.searchTitle,
            serviceHref = it.serviceHref,
        )
    },
    isMovie = isMovie,
    isAnime = isAnime,
)

private fun DetailScreenState.hasAnimePlaybackEvidence(episode: DetailEpisodeRow?): Boolean =
    isAnime || episode?.anilistMediaId != null || playerSource?.context?.anilistMediaId != null

internal fun chooseMainPlayEpisode(
    episodes: List<DetailEpisodeRow>,
    progressEntries: List<EpisodeProgressBackup>,
    showId: Int?,
): DetailEpisodeRow? {
    val candidates = episodes
        .filter { episode -> episode.sourceSeasonNumber != null && episode.sourceEpisodeNumber != null }
        .distinctBy { episode -> DetailEpisodeKey(episode.sourceSeasonNumber ?: 0, episode.sourceEpisodeNumber ?: 0) }
    if (candidates.isEmpty()) return null
    if (showId == null) return candidates.first()

    val progressByEpisode = progressEntries
        .asSequence()
        .filter { entry -> entry.showId == showId }
        .groupBy { entry -> DetailEpisodeKey(entry.seasonNumber, entry.episodeNumber) }
        .mapValues { (_, entries) ->
            entries.maxByOrNull { entry -> entry.lastUpdated.toEpochMillisOrZero() }
        }

    val latestWatchedIndex = candidates.indices.lastOrNull { index ->
        progressByEpisode[candidates[index].episodeKey]?.let(::isWatchedForMainPlay) == true
    }
    val inProgressIndices = candidates.indices.filter { index ->
        progressByEpisode[candidates[index].episodeKey]?.let(::hasResumeProgressForMainPlay) == true
    }
    val eligibleInProgressIndices = latestWatchedIndex
        ?.let { watchedIndex -> inProgressIndices.filter { index -> index > watchedIndex } }
        ?: inProgressIndices

    eligibleInProgressIndices.lastOrNull()?.let { return candidates[it] }
    latestWatchedIndex?.plus(1)?.takeIf { it < candidates.size }?.let { return candidates[it] }
    inProgressIndices.lastOrNull()?.let { return candidates[it] }
    return candidates.first()
}

private fun DetailContent.canSyncRatingTo(
    service: String,
    trackerSnapshot: TrackerStateSnapshot?,
): Boolean {
    if (!isAnime || primaryAniListId == null || trackerSnapshot?.syncEnabled != true) return false
    return trackerSnapshot.accounts.any { account ->
        account.isConnected &&
            account.accessToken.isNotBlank() &&
            account.service.isSameTrackerService(service)
    }
}

private fun DetailTarget.tmdbRatingId(): Int? = when (this) {
    is DetailTarget.TmdbMovie -> id
    is DetailTarget.TmdbShow -> id
    is DetailTarget.AniListMediaTarget -> null
    is DetailTarget.ServiceMedia -> null
}

private fun Int.pluralSuffix(): String = if (this == 1) "" else "s"

private fun String.normalizedTrackerService(): String =
    trim()
        .lowercase()
        .replace(" ", "")
        .replace("-", "")

private fun String.isSameTrackerService(other: String): Boolean {
    val left = normalizedTrackerService()
    val right = other.normalizedTrackerService()
    return left == right || left in setOf("myanimelist", "mal") && right in setOf("myanimelist", "mal")
}

private fun DetailEpisodeRow.toStreamEpisodeSelection(): StreamEpisodeSelection? {
    val localSeason = seasonNumber ?: tmdbSeasonNumber ?: return null
    val localEpisode = episodeNumber ?: tmdbEpisodeNumber ?: return null
    val useTitleOnly = titleOnlySearch || (isSpecial && (tmdbSeasonNumber == null || tmdbEpisodeNumber == null))
    val season = if (useTitleOnly) null else tmdbSeasonNumber ?: localSeason
    val episode = if (useTitleOnly) null else tmdbEpisodeNumber ?: localEpisode
    return StreamEpisodeSelection(
        seasonNumber = season,
        episodeNumber = episode,
        label = if (isSpecial) "Special E$localEpisode" else "S${localSeason}E${localEpisode}",
        localSeasonNumber = localSeason,
        localEpisodeNumber = localEpisode,
        anilistMediaId = anilistMediaId,
        tmdbEpisodeOffset = tmdbEpisodeOffset,
        animeAbsoluteEpisodeNumber = animeAbsoluteEpisodeNumber,
        animeSeasonEpisodeCount = animeSeasonEpisodeCount,
        searchTitle = searchTitle ?: title,
        isSpecial = isSpecial,
        titleOnlySearch = useTitleOnly,
        serviceHref = serviceHref,
    )
}

private fun DetailScreenState.selectedPlaybackEpisode(source: PlayerSource): DetailEpisodeRow? {
    selectedEpisodeId
        ?.let { id -> episodes.firstOrNull { episode -> episode.id == id } }
        ?.let { return it }

    val context = source.context ?: return episodes.firstOrNull()
    return episodes.firstOrNull { episode ->
        val seasonNumber = episode.sourceSeasonNumber
            ?: episode.tmdbSeasonNumber
            ?: episode.seasonNumber
        val episodeNumber = episode.sourceEpisodeNumber
            ?: episode.tmdbEpisodeNumber
            ?: episode.episodeNumber
        seasonNumber == context.resolvedTMDBSeasonNumber &&
            episodeNumber == context.resolvedTMDBEpisodeNumber
    } ?: episodes.firstOrNull()
}

private val DetailEpisodeRow.sourceSeasonNumber: Int?
    get() = tmdbSeasonNumber ?: seasonNumber

private val DetailEpisodeRow.sourceEpisodeNumber: Int?
    get() = tmdbEpisodeNumber ?: episodeNumber

private val DetailEpisodeRow.episodeKey: DetailEpisodeKey
    get() = DetailEpisodeKey(sourceSeasonNumber ?: 0, sourceEpisodeNumber ?: 0)

private data class DetailEpisodeKey(
    val seasonNumber: Int,
    val episodeNumber: Int,
)

private fun isWatchedForMainPlay(entry: EpisodeProgressBackup): Boolean =
    entry.isWatched || entry.progressPercent >= MainPlayWatchedThreshold

private fun hasResumeProgressForMainPlay(entry: EpisodeProgressBackup): Boolean =
    !isWatchedForMainPlay(entry) && (entry.currentTime > 0.0 || entry.progressPercent > 0.0)

private fun DetailEpisodeRow.downloadKeySuffix(): String? {
    val season = sourceSeasonNumber ?: return null
    val episode = sourceEpisodeNumber ?: return null
    return "s${season}_e${episode}"
}

private fun EpisodePlaybackContext.downloadKeySuffix(): String =
    "s${resolvedTMDBSeasonNumber}_e${resolvedTMDBEpisodeNumber}"

private fun StreamEpisodeSelection.toPlaybackContext(): EpisodePlaybackContext = EpisodePlaybackContext(
    localSeasonNumber = localSeasonNumber,
    localEpisodeNumber = localEpisodeNumber,
    anilistMediaId = anilistMediaId,
    tmdbSeasonNumber = seasonNumber.takeUnless { titleOnlySearch },
    tmdbEpisodeNumber = episodeNumber.takeUnless { titleOnlySearch },
    tmdbEpisodeOffset = tmdbEpisodeOffset,
    animeAbsoluteEpisodeNumber = animeAbsoluteEpisodeNumber,
    animeSeasonEpisodeCount = animeSeasonEpisodeCount,
    isSpecial = isSpecial,
    titleOnlySearch = titleOnlySearch,
)

private fun MovieProgressBackup.resumePositionMs(): Long =
    resumePositionMs(
        currentTimeSeconds = currentTime,
        totalDurationSeconds = totalDuration,
        watched = isWatched,
    )

private fun EpisodeProgressBackup.resumePositionMs(): Long =
    resumePositionMs(
        currentTimeSeconds = currentTime,
        totalDurationSeconds = totalDuration,
        watched = isWatched,
    )

private fun resumePositionMs(
    currentTimeSeconds: Double,
    totalDurationSeconds: Double,
    watched: Boolean,
): Long {
    if (watched || currentTimeSeconds <= 0.0) return 0L
    val progress = if (totalDurationSeconds > 0.0) {
        currentTimeSeconds / totalDurationSeconds
    } else {
        0.0
    }
    if (progress >= 0.95) return 0L
    return (currentTimeSeconds * 1_000.0).toLong().coerceAtLeast(0L)
}

private fun DetailEpisodeRow.matchesSelection(selection: StreamEpisodeSelection): Boolean {
    if (!selection.serviceHref.isNullOrBlank() && serviceHref == selection.serviceHref) {
        return true
    }
    if (selection.titleOnlySearch) {
        val selectedTitle = selection.searchTitle?.trim().orEmpty()
        return selectedTitle.isNotBlank() &&
            listOf(title, searchTitle).any { candidate ->
                candidate?.trim()?.equals(selectedTitle, ignoreCase = true) == true
            }
    }
    return sourceSeasonNumber == selection.seasonNumber &&
        sourceEpisodeNumber == selection.episodeNumber &&
        (seasonNumber ?: sourceSeasonNumber) == selection.localSeasonNumber &&
        (episodeNumber ?: sourceEpisodeNumber) == selection.localEpisodeNumber
}

private fun List<SkipSegment>.mergeSkipSegments(): List<SkipSegment> =
    sortedWith(
        compareBy<SkipSegment> { it.startTime }
            .thenBy { it.endTime }
            .thenBy { it.type.id },
    )
        .distinctBy { segment ->
            "${segment.type.id}:${segment.startTime.toInt()}:${segment.endTime.toInt()}"
        }

private fun String?.toEpochMillisOrZero(): Long =
    this?.let { value -> runCatching { Instant.parse(value).toEpochMilli() }.getOrDefault(0L) } ?: 0L

private fun String?.extractImdbId(): String? =
    this
        ?.let { value -> Regex("""tt\d{6,10}""").find(value)?.value }
        ?.takeIf { it.isNotBlank() }

private const val TrackerSyncProgressThreshold = 0.85
private const val MainPlayWatchedThreshold = 0.85


