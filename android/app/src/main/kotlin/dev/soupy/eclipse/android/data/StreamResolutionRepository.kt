package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.EpisodePlaybackContext
import dev.soupy.eclipse.android.core.model.InAppPlayer
import dev.soupy.eclipse.android.core.model.PlayerSource
import dev.soupy.eclipse.android.core.model.ServicesAutoModeQualityPreference
import dev.soupy.eclipse.android.core.model.SimilarityAlgorithm
import dev.soupy.eclipse.android.core.model.SourceHealthSnapshot
import dev.soupy.eclipse.android.core.js.ServiceStreamResult
import dev.soupy.eclipse.android.core.js.ServiceEpisodeLink
import dev.soupy.eclipse.android.core.js.ServiceSearchResult
import dev.soupy.eclipse.android.core.model.StremioCatalog
import dev.soupy.eclipse.android.core.model.StremioContentIdRequest
import dev.soupy.eclipse.android.core.model.StremioManifest
import dev.soupy.eclipse.android.core.model.StremioMetaPreview
import dev.soupy.eclipse.android.core.model.StremioSubtitle
import dev.soupy.eclipse.android.core.model.StremioStream
import dev.soupy.eclipse.android.core.model.StremioVideo
import dev.soupy.eclipse.android.core.model.SubtitleTrack
import dev.soupy.eclipse.android.core.model.buildContentIds
import dev.soupy.eclipse.android.core.model.displayLabel
import dev.soupy.eclipse.android.core.model.displayTitle
import dev.soupy.eclipse.android.core.model.isDirectHttp
import dev.soupy.eclipse.android.core.model.isTorrentLike
import dev.soupy.eclipse.android.core.model.qualityScore
import dev.soupy.eclipse.android.core.model.searchableCatalogs
import dev.soupy.eclipse.android.core.model.supportsResource
import dev.soupy.eclipse.android.core.model.warningTextFor
import dev.soupy.eclipse.android.core.network.AniListService
import dev.soupy.eclipse.android.core.network.EclipseJson
import dev.soupy.eclipse.android.core.network.StremioService
import dev.soupy.eclipse.android.core.network.TmdbService
import dev.soupy.eclipse.android.core.storage.AppSettings
import dev.soupy.eclipse.android.core.storage.SettingsStore
import dev.soupy.eclipse.android.core.storage.StremioAddonDao
import dev.soupy.eclipse.android.core.storage.StremioAddonEntity
import kotlinx.coroutines.flow.first
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

private const val ExactStremioContentMatchFloor = 0.90
private const val ServiceSearchMatchFloor = 0.55

data class ResolvedStreamCandidate(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val supportingText: String? = null,
    val addonName: String,
    val isPlayable: Boolean,
    val qualityScore: Double = 0.0,
    val matchScore: Double = 0.0,
    val playerSource: PlayerSource? = null,
)

data class StreamResolutionResult(
    val statusMessage: String,
    val candidates: List<ResolvedStreamCandidate> = emptyList(),
    val selectedSource: PlayerSource? = null,
)

data class StreamEpisodeSelection(
    val seasonNumber: Int?,
    val episodeNumber: Int?,
    val label: String,
    val localSeasonNumber: Int = seasonNumber ?: 0,
    val localEpisodeNumber: Int = episodeNumber ?: 1,
    val anilistMediaId: Int? = null,
    val tmdbEpisodeOffset: Int? = null,
    val animeAbsoluteEpisodeNumber: Int? = null,
    val animeSeasonEpisodeCount: Int? = null,
    val searchTitle: String? = null,
    val isSpecial: Boolean = false,
    val titleOnlySearch: Boolean = false,
    val serviceHref: String? = null,
)

class StreamResolutionRepository(
    private val tmdbService: TmdbService,
    private val aniListService: AniListService,
    private val animeTmdbMapper: AnimeTmdbMapper,
    private val stremioService: StremioService,
    private val stremioAddonDao: StremioAddonDao,
    private val settingsStore: SettingsStore,
    private val servicesRepository: ServicesRepository,
    private val sourceHealthRepository: SourceHealthRepository,
) {
    suspend fun resolve(
        target: DetailTarget,
        episode: StreamEpisodeSelection? = null,
    ): Result<StreamResolutionResult> = runCatching {
        sourceHealthRepository.load()
        val healthSnapshot = sourceHealthRepository.snapshot.value
        val settings = settingsStore.settings.first()
        if (target is DetailTarget.ServiceMedia) {
            return@runCatching resolveServiceMedia(
                target = target,
                episode = episode,
                sourceWarning = healthSnapshot.warningTextFor("service:${target.serviceId}"),
                settings = settings,
            )
        }
        tmdbService.setLanguage(settings.tmdbLanguage)
        val request = buildRequest(
            target = target,
            episode = episode,
            allowEpisodeAutoResolution = settings.autoModeEnabled,
        )
        val addons = stremioAddonDao.observeAll().first()
            .filter(StremioAddonEntity::enabled)
            .let { enabled ->
                val enabledByAutoModeId = enabled.associateBy { addon -> "stremio:${addon.transportUrl}" }
                val selectedAddonIds = settings.autoModeSourceOrderIds
                    .filter { it in settings.autoModeSourceIds && it in enabledByAutoModeId } +
                    enabledByAutoModeId.keys
                        .filter { it in settings.autoModeSourceIds && it !in settings.autoModeSourceOrderIds }
                if (settings.autoModeEnabled && selectedAddonIds.isNotEmpty()) {
                    selectedAddonIds.mapNotNull(enabledByAutoModeId::get)
                } else {
                    enabled
                }
            }
            .filter { addon ->
                val manifest = addon.manifest()
                manifest == null || manifest.types.isEmpty() || request.type in manifest.types
            }
        val services = servicesRepository.activeSearchSources()
            .let { enabled ->
                val enabledByAutoModeId = enabled.associateBy { service -> service.autoModeId }
                val selectedServiceIds = settings.autoModeSourceOrderIds
                    .filter { it in settings.autoModeSourceIds && it in enabledByAutoModeId } +
                    enabledByAutoModeId.keys
                        .filter { it in settings.autoModeSourceIds && it !in settings.autoModeSourceOrderIds }
                if (settings.autoModeEnabled && selectedServiceIds.isNotEmpty()) {
                    selectedServiceIds.mapNotNull(enabledByAutoModeId::get)
                } else {
                    enabled
                }
            }

        if (addons.isEmpty() && services.isEmpty()) {
            return@runCatching StreamResolutionResult(
                statusMessage = "No enabled Stremio addons or custom services are ready for ${request.type}. Import a source in Services first, or include it in Auto Mode.",
            )
        }

        var rejectedTorrentCount = 0
        val rawCandidates = buildList {
            addons.forEach { addon ->
                val addonLabel = addon.name.ifBlank { addon.transportUrl }
                val sourceWarning = healthSnapshot.warningTextFor("stremio:${addon.transportUrl}")
                val manifest = addon.manifest() ?: StremioManifest()
                val resolution = resolveAddonStreams(
                    addon = addon,
                    manifest = manifest,
                    request = request,
                )
                rejectedTorrentCount += resolution.rejectedTorrentCount
                resolution.streams
                    .mapIndexed { index, resolvedStream ->
                        val stream = resolvedStream.stream
                        stream.toResolvedCandidate(
                            addon = addon,
                            addonLabel = addonLabel,
                            requestSummary = request.summary,
                            requestTitles = request.matchTitles,
                            contentId = resolvedStream.contentId,
                            playbackContext = request.playbackContext,
                            similarityAlgorithm = settings.selectedSimilarityAlgorithm,
                            sourceWarning = sourceWarning,
                            index = index,
                        )
                    }
                    .let(::addAll)
            }
            addAll(
                resolveCustomServiceCandidates(
                    services = services,
                    request = request,
                    episode = episode,
                    settings = settings,
                    healthSnapshot = healthSnapshot,
                ),
            )
        }.sortedWith(streamCandidateComparator(settings.qualityPreference()))
        val openSubtitles = fetchOpenSubtitlesFallbackTracks(settings, request, rawCandidates)
        val candidates = rawCandidates.withAdditionalSubtitles(openSubtitles)

        if (candidates.isEmpty()) {
            return@runCatching StreamResolutionResult(
                statusMessage = if (rejectedTorrentCount > 0) {
                    "Rejected $rejectedTorrentCount torrent or magnet result${if (rejectedTorrentCount == 1) "" else "s"} for ${request.summary}. No safe direct HTTP(S) streams were returned."
                } else {
                    "The enabled addons didn't return any safe direct HTTP(S) streams for ${request.summary} yet."
                },
            )
        }

        val threshold = settings.highQualityThreshold.coerceIn(0.0, 1.0)
        val autoSelectedCandidate = candidates.firstOrNull { candidate ->
            settings.autoModeEnabled &&
                settings.qualityPreference().usesAutomaticSelection &&
                candidate.isPlayable &&
                candidate.matchScore >= threshold
        }
        val playable = autoSelectedCandidate?.playerSource
        val playableCount = candidates.count(ResolvedStreamCandidate::isPlayable)
        val pendingCount = candidates.size - playableCount

        StreamResolutionResult(
            statusMessage = when {
                playable == null && !settings.autoModeEnabled && playableCount > 0 ->
                    "Resolved $playableCount direct HTTP(S) stream${if (playableCount == 1) "" else "s"} for ${request.summary}. Auto Mode is off, so pick one manually.${rejectedTorrentCount.rejectionSuffix()}"
                playable == null && settings.autoModeEnabled && playableCount > 0 ->
                    "Resolved $playableCount direct HTTP(S) stream${if (playableCount == 1) "" else "s"} for ${request.summary}, but none met the Auto Mode match threshold (${(threshold * 100).toInt()}%). Pick one manually or lower the threshold.${rejectedTorrentCount.rejectionSuffix()}"
                playable != null && pendingCount > 0 ->
                    "Resolved $playableCount direct HTTP(S) stream${if (playableCount == 1) "" else "s"} plus $pendingCount unsupported non-torrent result${if (pendingCount == 1) "" else "s"} for ${request.summary}.${rejectedTorrentCount.rejectionSuffix()}"
                playable != null ->
                    "Resolved $playableCount direct HTTP(S) stream${if (playableCount == 1) "" else "s"} for ${request.summary}.${rejectedTorrentCount.rejectionSuffix()}"
                else ->
                    "Found ${candidates.size} non-torrent stream result${if (candidates.size == 1) "" else "s"} for ${request.summary}, but Eclipse only accepts direct HTTP(S) playback URLs.${rejectedTorrentCount.rejectionSuffix()}"
            },
            candidates = candidates,
            selectedSource = playable,
        )
    }

    private suspend fun resolveServiceMedia(
        target: DetailTarget.ServiceMedia,
        episode: StreamEpisodeSelection?,
        sourceWarning: String?,
        settings: AppSettings,
    ): StreamResolutionResult {
        val href = episode?.serviceHref ?: target.href
        val streamResult = servicesRepository.resolveServiceStream(
            id = target.serviceId,
            href = href,
        ).getOrThrow()
        val candidates = streamResult.toServiceCandidates(
            target = target,
            href = href,
            episode = episode,
            sourceWarning = sourceWarning,
        ).sortedWith(streamCandidateComparator(settings.qualityPreference()))
        val selectedSource = candidates.firstOrNull { candidate ->
            settings.autoModeEnabled &&
                settings.qualityPreference().usesAutomaticSelection &&
                candidate.isPlayable
        }?.playerSource
        return StreamResolutionResult(
            statusMessage = if (candidates.isEmpty()) {
                "The selected service did not return a safe direct HTTP(S) stream."
            } else if (!settings.qualityPreference().usesAutomaticSelection && candidates.count(ResolvedStreamCandidate::isPlayable) > 1) {
                "Resolved ${candidates.size} service streams. Auto Mode quality is set to Ask, so pick one manually."
            } else {
                "Resolved ${candidates.size} service stream${if (candidates.size == 1) "" else "s"}."
            },
            candidates = candidates,
            selectedSource = selectedSource,
        )
    }

    private suspend fun buildRequest(
        target: DetailTarget,
        episode: StreamEpisodeSelection?,
        allowEpisodeAutoResolution: Boolean,
    ): StremioRequest = when (target) {
        is DetailTarget.TmdbMovie -> {
            val movie = tmdbService.movieDetail(target.id).orThrow()
            val imdbId = movie.externalIds?.imdbId?.takeIf { it.isNotBlank() }
            StremioRequest(
                type = "movie",
                tmdbId = target.id,
                imdbId = imdbId,
                season = null,
                episode = null,
                summary = movie.title.ifBlank { imdbId ?: "tmdb:${target.id}" },
                matchTitles = listOfNotNull(movie.title, imdbId),
                expectedYear = movie.releaseDate.releaseYear(),
                allowEpisodeAutoResolution = allowEpisodeAutoResolution,
            )
        }

        is DetailTarget.TmdbShow -> {
            val show = tmdbService.tvShowDetail(target.id).orThrow()
            val imdbId = show.externalIds?.imdbId?.takeIf { it.isNotBlank() }
            val selectedEpisode = episode ?: firstPlayableEpisode(target.id)
            StremioRequest(
                type = "series",
                tmdbId = target.id,
                imdbId = imdbId,
                season = selectedEpisode.seasonNumber.takeUnless { selectedEpisode.titleOnlySearch },
                episode = selectedEpisode.episodeNumber.takeUnless { selectedEpisode.titleOnlySearch },
                summary = listOfNotNull(selectedEpisode.searchTitle ?: show.name, selectedEpisode.label).joinToString(" "),
                matchTitles = listOfNotNull(selectedEpisode.searchTitle, show.name),
                expectedYear = show.firstAirDate.releaseYear(),
                anilistMediaId = selectedEpisode.anilistMediaId,
                playbackContext = selectedEpisode.toPlaybackContext(),
                allowEpisodeAutoResolution = allowEpisodeAutoResolution,
            )
        }

        is DetailTarget.AniListMediaTarget -> {
            val media = aniListService.mediaById(target.id).orThrow()
            val match = animeTmdbMapper.findBestMatch(media)
                ?: error("Eclipse couldn't match this AniList anime to TMDB yet, so Stremio episode IDs could not be built.")

            when (val tmdbTarget = match.target) {
                is DetailTarget.TmdbMovie -> {
                    val movie = tmdbService.movieDetail(tmdbTarget.id).orThrow()
                    StremioRequest(
                        type = "movie",
                        tmdbId = tmdbTarget.id,
                        imdbId = movie.externalIds?.imdbId?.takeIf { it.isNotBlank() },
                        season = null,
                        episode = null,
                        summary = "${media.displayTitle} via ${match.title}",
                        matchTitles = listOf(media.displayTitle, match.title, movie.title),
                        expectedYear = media.seasonYear ?: movie.releaseDate.releaseYear(),
                        anilistMediaId = media.id,
                        allowEpisodeAutoResolution = allowEpisodeAutoResolution,
                    )
                }

                is DetailTarget.TmdbShow -> {
                    val show = tmdbService.tvShowDetail(tmdbTarget.id).orThrow()
                    val selectedEpisode = episode
                        ?: match.firstMappedEpisodeSelection(media.id)
                        ?: firstPlayableEpisode(tmdbTarget.id, match.tmdbSeasonNumber)
                    StremioRequest(
                        type = "series",
                        tmdbId = tmdbTarget.id,
                        imdbId = show.externalIds?.imdbId?.takeIf { it.isNotBlank() },
                        season = selectedEpisode.seasonNumber.takeUnless { selectedEpisode.titleOnlySearch },
                        episode = selectedEpisode.episodeNumber.takeUnless { selectedEpisode.titleOnlySearch },
                        summary = "${selectedEpisode.searchTitle ?: media.displayTitle} ${selectedEpisode.label} via ${match.title}",
                        matchTitles = listOfNotNull(selectedEpisode.searchTitle, media.displayTitle, match.title, show.name),
                        expectedYear = media.seasonYear ?: show.firstAirDate.releaseYear(),
                        anilistMediaId = media.id,
                        playbackContext = selectedEpisode
                            .copy(anilistMediaId = selectedEpisode.anilistMediaId ?: media.id)
                            .toPlaybackContext(),
                        allowEpisodeAutoResolution = allowEpisodeAutoResolution,
                    )
                }

                is DetailTarget.AniListMediaTarget -> error("AniList-to-AniList stream mapping is not supported.")
                is DetailTarget.ServiceMedia -> error("Service-backed anime stream mapping is not supported.")
            }
        }

        is DetailTarget.ServiceMedia -> error("Service-backed media streams use the service runtime.")
    }

    private suspend fun resolveAddonStreams(
        addon: StremioAddonEntity,
        manifest: StremioManifest,
        request: StremioRequest,
    ): StremioAddonResolution {
        val contentIds = manifest.buildContentIds(request.toContentIdRequest())
        var rejectedTorrentCount = 0
        val pendingDirectResults = mutableListOf<ResolvedStremioStream>()

        for (contentId in contentIds) {
            val directResult = stremioService.fetchStreams(
                transportUrl = addon.transportUrl,
                type = request.type,
                id = contentId,
            ).orNull()
                ?.streams
                .orEmpty()
                .toResolvedStremioStreams(contentId)
            rejectedTorrentCount += directResult.rejectedTorrentCount
            if (directResult.streams.any { resolvedStream -> resolvedStream.stream.isDirectHttp }) {
                return directResult.copy(rejectedTorrentCount = rejectedTorrentCount)
            }
            pendingDirectResults += directResult.streams
        }

        val fallbackResult = fetchStreamsByCatalogSearch(
            addon = addon,
            manifest = manifest,
            request = request,
        )
        rejectedTorrentCount += fallbackResult.rejectedTorrentCount
        if (fallbackResult.streams.isNotEmpty()) {
            return fallbackResult.copy(rejectedTorrentCount = rejectedTorrentCount)
        }

        return StremioAddonResolution(
            streams = pendingDirectResults,
            rejectedTorrentCount = rejectedTorrentCount,
        )
    }

    private suspend fun resolveCustomServiceCandidates(
        services: List<ServiceSourceRecord>,
        request: StremioRequest,
        episode: StreamEpisodeSelection?,
        settings: AppSettings,
        healthSnapshot: SourceHealthSnapshot,
    ): List<ResolvedStreamCandidate> {
        if (services.isEmpty()) return emptyList()
        val queries = normalizedSearchQueries(request.catalogSearchTitles()).take(3)
        if (queries.isEmpty()) return emptyList()
        val candidates = mutableListOf<ResolvedStreamCandidate>()
        services.forEach { service ->
            val sourceWarning = healthSnapshot.warningTextFor(service.autoModeId)
            val searchResults = queries
                .flatMap { query ->
                    servicesRepository.searchService(service.id, query)
                        .getOrNull()
                        .orEmpty()
                        .take(8)
                }
            val match = searchResults
                .distinctBy(ServiceSearchResult::href)
                .map { result ->
                    result to titleMatchScore(
                        expectedTitles = request.catalogSearchTitles(),
                        candidateText = listOf(result.title, result.subtitle.orEmpty()).joinToString(" "),
                        algorithm = settings.selectedSimilarityAlgorithm,
                    )
                }
                .filter { (_, score) -> score >= ServiceSearchMatchFloor }
                .maxByOrNull { (_, score) -> score }
                ?: return@forEach
            val (result, matchScore) = match
            val detail = servicesRepository.loadServiceDetail(
                id = service.id,
                href = result.href,
                fallbackTitle = result.title,
                fallbackImageUrl = result.image,
            ).getOrNull()
            val serviceTarget = DetailTarget.ServiceMedia(
                serviceId = service.id,
                href = result.href,
                title = detail?.title ?: result.title,
                imageUrl = detail?.imageUrl ?: result.image,
            )
            val serviceEpisodes = detail
                ?.episodes
                ?.episodeCandidatesForRequest(
                    request = request,
                    fallback = episode,
                    allowEpisodeAutoResolution = settings.autoModeEnabled,
                )
                .orEmpty()
            val resolutionTargets = serviceEpisodes
                .takeIf { it.isNotEmpty() }
                ?.map { serviceEpisode ->
                    val serviceSelection = serviceEpisode.toStreamEpisodeSelection(
                        fallback = episode,
                        request = request,
                        preferServiceLabel = !settings.autoModeEnabled,
                    )
                    serviceEpisode.href to serviceSelection
                }
                ?: listOf((detail?.href ?: result.href) to episode?.copy(serviceHref = detail?.href ?: result.href))
            resolutionTargets.forEach { (href, serviceSelection) ->
                val streamResult = servicesRepository.resolveServiceStream(
                    id = service.id,
                    href = href,
                ).getOrNull() ?: return@forEach
                candidates += streamResult.toServiceCandidates(
                    target = serviceTarget,
                    href = href,
                    episode = serviceSelection,
                    sourceWarning = sourceWarning,
                ).map { candidate ->
                    candidate.copy(
                        id = "service:${service.id}:${href.hashCode()}:${candidate.id.substringAfterLast(':')}",
                        subtitle = service.name,
                        addonName = service.name,
                        matchScore = matchScore.coerceAtLeast(candidate.matchScore),
                    )
                }
            }
        }
        return candidates
    }

    private suspend fun fetchStreamsByCatalogSearch(
        addon: StremioAddonEntity,
        manifest: StremioManifest,
        request: StremioRequest,
    ): StremioAddonResolution {
        val searchQueries = normalizedSearchQueries(request.catalogSearchTitles())
        if (searchQueries.isEmpty()) return StremioAddonResolution()

        val catalogs = manifest.searchableCatalogs
            .filter { catalog -> catalog.supportsType(request.type) }
            .take(3)
        if (catalogs.isEmpty()) return StremioAddonResolution()

        val ranked = mutableListOf<RankedCatalogMeta>()
        for (catalog in catalogs) {
            for (query in searchQueries.take(4)) {
                val metas = stremioService.fetchCatalogMetas(
                    transportUrl = addon.transportUrl,
                    catalog = catalog,
                    searchQuery = query,
                ).orNull()
                    ?.metas
                    .orEmpty()
                ranked += metas
                    .asSequence()
                    .take(12)
                    .filter { meta -> metaMatchesRequestedType(meta, catalog, request.type) }
                    .map { meta ->
                        RankedCatalogMeta(
                            catalog = catalog,
                            meta = meta,
                            score = catalogMetaScore(meta, request.catalogSearchTitles(), request.expectedYear),
                            query = query,
                        )
                    }
                    .filter { candidate -> candidate.score >= 0.78 && candidate.meta.id.isNotBlank() }
                    .toList()
            }
        }

        val candidates = ranked
            .sortedWith(
                compareByDescending<RankedCatalogMeta> { candidate -> candidate.score }
                    .thenBy { candidate -> candidate.meta.name.length },
            )
            .take(5)

        var rejectedTorrentCount = 0
        val pendingResults = mutableListOf<ResolvedStremioStream>()
        for (candidate in candidates) {
            val result = fetchStreamsForCatalogMeta(
                preview = candidate.meta,
                catalog = candidate.catalog,
                addon = addon,
                manifest = manifest,
                request = request,
            )
            rejectedTorrentCount += result.rejectedTorrentCount
            if (result.streams.any { resolvedStream -> resolvedStream.stream.isDirectHttp }) {
                return result.copy(rejectedTorrentCount = rejectedTorrentCount)
            }
            pendingResults += result.streams
        }

        return StremioAddonResolution(
            streams = pendingResults,
            rejectedTorrentCount = rejectedTorrentCount,
        )
    }

    private suspend fun fetchStreamsForCatalogMeta(
        preview: StremioMetaPreview,
        catalog: StremioCatalog,
        addon: StremioAddonEntity,
        manifest: StremioManifest,
        request: StremioRequest,
    ): StremioAddonResolution {
        val streamType = preview.type ?: catalog.type
        val directPreviewStreams = streamsFromMeta(preview, request)
        if (directPreviewStreams.streams.any { resolvedStream -> resolvedStream.stream.isDirectHttp }) {
            return directPreviewStreams
        }

        var meta = preview
        var rejectedTorrentCount = directPreviewStreams.rejectedTorrentCount
        if (manifest.supportsResource("meta")) {
            val fetched = stremioService.fetchMeta(
                transportUrl = addon.transportUrl,
                type = streamType,
                id = preview.id,
            ).orNull()
                ?.meta
            if (fetched != null) {
                meta = fetched
                val metaStreams = streamsFromMeta(fetched, request)
                rejectedTorrentCount += metaStreams.rejectedTorrentCount
                if (metaStreams.streams.any { resolvedStream -> resolvedStream.stream.isDirectHttp }) {
                    return metaStreams.copy(rejectedTorrentCount = rejectedTorrentCount)
                }
            }
        }

        val pendingResults = mutableListOf<ResolvedStremioStream>()
        pendingResults += directPreviewStreams.streams
        for (contentId in streamIdsFromMeta(meta, request)) {
            val result = stremioService.fetchStreams(
                transportUrl = addon.transportUrl,
                type = streamType,
                id = contentId,
            ).orNull()
                ?.streams
                .orEmpty()
                .toResolvedStremioStreams(contentId)
            rejectedTorrentCount += result.rejectedTorrentCount
            if (result.streams.any { resolvedStream -> resolvedStream.stream.isDirectHttp }) {
                return result.copy(rejectedTorrentCount = rejectedTorrentCount)
            }
            pendingResults += result.streams
        }

        return StremioAddonResolution(
            streams = pendingResults,
            rejectedTorrentCount = rejectedTorrentCount,
        )
    }

    private suspend fun fetchOpenSubtitlesFallbackTracks(
        settings: AppSettings,
        request: StremioRequest,
        candidates: List<ResolvedStreamCandidate>,
    ): List<SubtitleTrack> {
        if (settings.inAppPlayer != InAppPlayer.VLC ||
            !settings.vlcOpenSubtitlesEnabled ||
            !settings.vlcOpenSubtitlesAutoFallbackEnabled ||
            !settings.enableSubtitlesByDefault
        ) {
            return emptyList()
        }

        val preferredLanguage = settings.defaultSubtitleLanguage
        val needsFallback = candidates.any { candidate ->
            val source = candidate.playerSource ?: return@any false
            !source.hasPreferredSubtitle(preferredLanguage)
        }
        if (!needsFallback) return emptyList()

        return stremioService.fetchOpenSubtitlesV3(
            tmdbId = request.tmdbId,
            imdbId = request.imdbId,
            type = request.type,
            season = request.season,
            episode = request.episode,
        ).orNull()
            .orEmpty()
            .toOpenSubtitleTracks(preferredLanguage)
    }

    private suspend fun firstPlayableEpisode(
        showId: Int,
        preferredSeasonNumber: Int? = null,
    ): StreamEpisodeSelection {
        val show = tmdbService.tvShowDetail(showId).orThrow()
        val firstSeason = preferredSeasonNumber
            ?.let { preferred -> show.seasons.firstOrNull { it.seasonNumber == preferred && it.episodeCount > 0 } }
            ?: show.seasons.firstOrNull { it.seasonNumber > 0 && it.episodeCount > 0 }
            ?: show.seasons.firstOrNull { it.episodeCount > 0 }
            ?: error("This series doesn't expose any seasons yet, so Eclipse can't resolve Stremio episode streams.")
        val seasonDetail = tmdbService.seasonDetail(showId, firstSeason.seasonNumber).orThrow()
        val firstEpisode = seasonDetail.episodes.firstOrNull { it.episodeNumber > 0 }
            ?: error("This series doesn't expose a playable episode yet for stream resolution.")

        return StreamEpisodeSelection(
            seasonNumber = firstSeason.seasonNumber,
            episodeNumber = firstEpisode.episodeNumber,
            label = "S${firstSeason.seasonNumber}E${firstEpisode.episodeNumber}",
        )
    }
}

private fun List<ResolvedStreamCandidate>.withAdditionalSubtitles(
    subtitles: List<SubtitleTrack>,
): List<ResolvedStreamCandidate> {
    if (subtitles.isEmpty()) return this
    return map { candidate ->
        val source = candidate.playerSource ?: return@map candidate
        candidate.copy(playerSource = source.withAdditionalSubtitles(subtitles))
    }
}

private fun PlayerSource.withAdditionalSubtitles(
    subtitles: List<SubtitleTrack>,
): PlayerSource {
    val seenUris = this.subtitles.mapNotNull(SubtitleTrack::uri).toMutableSet()
    val deduped = subtitles.filter { subtitle ->
        val uri = subtitle.uri ?: return@filter false
        seenUris.add(uri)
    }
    return if (deduped.isEmpty()) this else copy(subtitles = this.subtitles + deduped)
}

private fun PlayerSource.hasPreferredSubtitle(preferredLanguage: String): Boolean =
    subtitles.any { subtitle -> subtitle.matchesPreferredLanguage(preferredLanguage) }

private fun SubtitleTrack.matchesPreferredLanguage(preferredLanguage: String): Boolean {
    val tokens = languageTokens(preferredLanguage)
    if (tokens.isEmpty()) return true
    val fields = listOfNotNull(language, label, id).joinToString(" ").lowercase()
    return tokens.any(fields::contains)
}

private fun List<StremioSubtitle>.toOpenSubtitleTracks(preferredLanguage: String): List<SubtitleTrack> {
    val seenUris = mutableSetOf<String>()
    return asSequence()
        .filter { subtitle -> subtitle.url.isDirectHttpUrl() }
        .filter { subtitle -> subtitle.url?.let(seenUris::add) == true }
        .sortedWith(
            compareByDescending<StremioSubtitle> { subtitle -> subtitle.matchesPreferredLanguage(preferredLanguage) }
                .thenBy { subtitle -> subtitle.openSubtitleDisplayName().lowercase() },
        )
        .take(20)
        .mapIndexed { index, subtitle ->
            val displayName = subtitle.openSubtitleDisplayName()
            SubtitleTrack(
                id = "opensubtitles-${subtitle.id ?: index + 1}",
                label = "OpenSubtitles - $displayName",
                language = subtitle.lang,
                uri = subtitle.url,
                format = subtitle.url.subtitleFormatFromUrl(),
                isDefault = index == 0 && subtitle.matchesPreferredLanguage(preferredLanguage),
            )
        }
        .toList()
}

private fun StremioSubtitle.matchesPreferredLanguage(preferredLanguage: String): Boolean {
    val tokens = languageTokens(preferredLanguage)
    if (tokens.isEmpty()) return true
    val fields = listOfNotNull(lang, label, name, title, id).joinToString(" ").lowercase()
    return tokens.any(fields::contains)
}

private fun StremioSubtitle.openSubtitleDisplayName(): String {
    val base = displayLabel
    val language = lang?.uppercase()?.takeIf { it.isNotBlank() }
    return if (language != null && !base.contains(language, ignoreCase = true)) {
        "$language - $base"
    } else {
        base
    }
}

private fun AnimeTmdbMatch.firstMappedEpisodeSelection(anilistMediaId: Int): StreamEpisodeSelection? {
    val mapping = episodeMappings
        .firstOrNull { episode -> episode.anilistMediaId == anilistMediaId && episode.localEpisodeNumber > 0 }
        ?: return null
    return StreamEpisodeSelection(
        seasonNumber = mapping.tmdbSeasonNumber,
        episodeNumber = mapping.tmdbEpisodeNumber,
        label = "S${mapping.localSeasonNumber}E${mapping.localEpisodeNumber}",
        localSeasonNumber = mapping.localSeasonNumber,
        localEpisodeNumber = mapping.localEpisodeNumber,
        anilistMediaId = mapping.anilistMediaId,
        tmdbEpisodeOffset = mapping.tmdbEpisodeOffset,
    )
}

internal data class StremioRequest(
    val type: String,
    val tmdbId: Int,
    val imdbId: String?,
    val season: Int?,
    val episode: Int?,
    val summary: String,
    val matchTitles: List<String> = emptyList(),
    val playbackContext: EpisodePlaybackContext? = null,
    val expectedYear: Int? = null,
    val anilistMediaId: Int? = playbackContext?.anilistMediaId,
    val allowEpisodeAutoResolution: Boolean = false,
) {
    fun toContentIdRequest(): StremioContentIdRequest = StremioContentIdRequest(
        tmdbId = tmdbId,
        imdbId = imdbId,
        type = type,
        season = season,
        episode = episode,
        anilistId = anilistMediaId,
    )
}

private data class StremioAddonResolution(
    val streams: List<ResolvedStremioStream> = emptyList(),
    val rejectedTorrentCount: Int = 0,
)

private data class ResolvedStremioStream(
    val stream: StremioStream,
    val contentId: String,
)

private data class RankedCatalogMeta(
    val catalog: StremioCatalog,
    val meta: StremioMetaPreview,
    val score: Double,
    val query: String,
)

private fun List<StremioStream>.toResolvedStremioStreams(contentId: String): StremioAddonResolution {
    var rejectedTorrentCount = 0
    val streams = mapNotNull { stream ->
        if (stream.isTorrentLike) {
            rejectedTorrentCount += 1
            null
        } else {
            ResolvedStremioStream(stream = stream, contentId = contentId)
        }
    }
    return StremioAddonResolution(
        streams = streams,
        rejectedTorrentCount = rejectedTorrentCount,
    )
}

private fun streamsFromMeta(
    meta: StremioMetaPreview,
    request: StremioRequest,
): StremioAddonResolution {
    val matchingVideos = matchingMetaVideosForRequest(meta, request)

    var rejectedTorrentCount = 0
    val streams = matchingVideos.flatMap { video ->
        val contentId = video.id.ifBlank { meta.id }
        video.streams.mapNotNull { stream ->
            if (stream.isTorrentLike) {
                rejectedTorrentCount += 1
                null
            } else {
                ResolvedStremioStream(stream = stream, contentId = contentId)
            }
        }
    }.distinctBy { resolvedStream ->
        resolvedStream.stream.url ?: resolvedStream.stream.infoHash ?: resolvedStream.contentId
    }

    return StremioAddonResolution(
        streams = streams,
        rejectedTorrentCount = rejectedTorrentCount,
    )
}

private fun streamIdsFromMeta(
    meta: StremioMetaPreview,
    request: StremioRequest,
): List<String> {
    val candidates = mutableListOf<String>()

    if (request.season != null && request.episode != null) {
        val matchingVideos = matchingMetaVideosForRequest(meta, request)
        matchingVideos.forEach { video ->
            video.id.takeIf(String::isNotBlank)?.let(candidates::add)
            val videoSeason = video.season ?: request.season
            val videoEpisode = video.episode ?: request.episode
            candidates += "${meta.id}:$videoSeason:$videoEpisode"
        }
        candidates += "${meta.id}:${request.season}:${request.episode}"
    } else if (request.type == "movie") {
        candidates += meta.id
    } else {
        meta.behaviorHints?.defaultVideoId?.let(candidates::add)
    }

    if (candidates.isEmpty()) {
        candidates += meta.id
    }

    return candidates.filter(String::isNotBlank).distinct()
}

internal fun matchingMetaVideosForRequest(
    meta: StremioMetaPreview,
    request: StremioRequest,
): List<StremioVideo> {
    val defaultVideoId = meta.behaviorHints?.defaultVideoId
    val season = request.season
    val episode = request.episode
    return when {
        season != null && episode != null -> {
            meta.videos.filter { video ->
                video.season == season && video.episode == episode
            }.ifEmpty {
                request.autoEpisodeMatches(meta.videos)
            }
        }
        defaultVideoId != null -> meta.videos.filter { video ->
            video.id == defaultVideoId
        }.ifEmpty { meta.videos }
        else -> meta.videos
    }
}

private fun StremioRequest.autoEpisodeMatches(videos: List<StremioVideo>): List<StremioVideo> {
    val context = playbackContext ?: return emptyList()
    if (!allowEpisodeAutoResolution || context.isSpecial || context.titleOnlySearch) return emptyList()
    val seasonEpisodeCount = context.animeSeasonEpisodeCount?.takeIf { it > 0 } ?: return emptyList()
    val localEpisode = context.localEpisodeNumber.takeIf { it > 0 } ?: return emptyList()
    val absoluteEpisode = context.animeAbsoluteEpisodeNumber?.takeIf { it > 0 }
    val episodeNumbers = videos.mapNotNull(StremioVideo::episode)
    val maxEpisode = episodeNumbers.maxOrNull() ?: return emptyList()

    return when {
        absoluteEpisode != null && maxEpisode > seasonEpisodeCount -> videos.filter { video ->
            video.episode == absoluteEpisode
        }
        maxEpisode <= seasonEpisodeCount -> videos.filter { video ->
            video.episode == localEpisode
        }
        else -> emptyList()
    }
}

private fun metaMatchesRequestedType(
    meta: StremioMetaPreview,
    catalog: StremioCatalog,
    requestedType: String,
): Boolean {
    val metaType = meta.type ?: catalog.type
    return metaType == requestedType || (requestedType == "series" && metaType == "tv")
}

private fun catalogMetaScore(
    meta: StremioMetaPreview,
    titleCandidates: List<String>,
    expectedYear: Int?,
): Double {
    val score = titleCandidates
        .map { title -> catalogTitleSimilarity(title, meta.name) }
        .maxOrNull()
        ?: 0.0
    val yearAdjusted = when {
        expectedYear == null -> score
        meta.releaseYear() == null -> score
        kotlin.math.abs(expectedYear - meta.releaseYear()!!) == 0 -> score + 0.08
        kotlin.math.abs(expectedYear - meta.releaseYear()!!) == 1 -> score + 0.03
        kotlin.math.abs(expectedYear - meta.releaseYear()!!) > 3 -> score - 0.12
        else -> score
    }
    return yearAdjusted.coerceIn(0.0, 1.0)
}

private fun catalogTitleSimilarity(expected: String, result: String): Double {
    val expectedCanonical = expected.normalizedCatalogTitle()
    val resultCanonical = result.normalizedCatalogTitle()
    if (expectedCanonical.isBlank() || resultCanonical.isBlank()) return 0.0

    val raw = titleMatchScore(listOf(expected), result, SimilarityAlgorithm.HYBRID)
    val canonical = titleMatchScore(listOf(expectedCanonical), resultCanonical, SimilarityAlgorithm.HYBRID)
    val token = tokenOverlapScore(expectedCanonical, resultCanonical)
    val base = maxOf(raw, canonical) * 0.68 + token * 0.32
    val adjusted = when {
        expectedCanonical == resultCanonical -> base + 0.12
        expectedCanonical.contains(resultCanonical) || resultCanonical.contains(expectedCanonical) -> base + 0.05
        else -> base
    }
    return adjusted.coerceIn(0.0, 1.0)
}

private fun StremioRequest.catalogSearchTitles(): List<String> {
    val values = matchTitles + summary
    val filtered = values
        .map { title -> title.trim() }
        .filter { title -> title.isNotBlank() }
        .filterNot { title -> title.startsWith("tt") || title.startsWith("tmdb:") || title.startsWith("imdb:") }
    return filtered.ifEmpty { listOf(summary) }
}

private fun normalizedSearchQueries(values: List<String>): List<String> {
    val seen = mutableSetOf<String>()
    return values
        .map { value -> value.stripEpisodeSuffix().trim() }
        .filter(String::isNotBlank)
        .filter { value -> seen.add(value.normalizedCatalogTitle()) }
}

private fun String.normalizedCatalogTitle(): String =
    lowercase()
        .replace(Regex("[^a-z0-9]+"), " ")
        .trim()

private fun String.stripEpisodeSuffix(): String {
    val patterns = listOf(
        Regex("\\s*-\\s*S\\d{1,3}E\\d{1,4}$", RegexOption.IGNORE_CASE),
        Regex("\\s*S\\d{1,3}E\\d{1,4}$", RegexOption.IGNORE_CASE),
        Regex("\\s*-\\s*E\\d{1,4}$", RegexOption.IGNORE_CASE),
        Regex("\\s*E\\d{1,4}$", RegexOption.IGNORE_CASE),
        Regex("\\s*episode\\s+\\d{1,4}$", RegexOption.IGNORE_CASE),
    )
    return patterns.firstOrNull { pattern -> pattern.containsMatchIn(this) }?.replace(this, "") ?: this
}

private fun tokenOverlapScore(left: String, right: String): Double {
    val ignored = setOf("a", "an", "and", "the", "of", "to", "in", "on", "tv", "series", "episode")
    val leftTokens = left.split(" ").filter { token -> token.length > 1 && token !in ignored }.toSet()
    val rightTokens = right.split(" ").filter { token -> token.length > 1 && token !in ignored }.toSet()
    if (leftTokens.isEmpty() || rightTokens.isEmpty()) return 0.0
    return leftTokens.intersect(rightTokens).size.toDouble() / maxOf(leftTokens.size, rightTokens.size).toDouble()
}

private fun StremioMetaPreview.releaseYear(): Int? =
    (releaseInfo ?: released).releaseYear()

private fun String?.releaseYear(): Int? =
    this?.let { value -> Regex("\\b(19|20)\\d{2}\\b").find(value)?.value?.toIntOrNull() }

private fun AppSettings.qualityPreference(): ServicesAutoModeQualityPreference =
    ServicesAutoModeQualityPreference.fromRawValue(servicesAutoModeQualityPreference)

private fun streamCandidateComparator(
    preference: ServicesAutoModeQualityPreference,
): Comparator<ResolvedStreamCandidate> =
    compareByDescending<ResolvedStreamCandidate> { it.isPlayable }
        .thenByDescending { it.matchScore }
        .thenByDescending { it.qualityPreferenceScore(preference) }
        .thenByDescending { it.qualityScore }
        .thenBy { it.addonName.lowercase() }
        .thenBy { it.title.lowercase() }

private fun ResolvedStreamCandidate.qualityPreferenceScore(
    preference: ServicesAutoModeQualityPreference,
): Double {
    if (!preference.usesAutomaticSelection) return 0.0
    val height = qualityHeight()
    return when (preference) {
        ServicesAutoModeQualityPreference.MANUAL -> 0.0
        ServicesAutoModeQualityPreference.AUTO,
        ServicesAutoModeQualityPreference.HIGHEST -> qualityScore
        ServicesAutoModeQualityPreference.LOWEST -> 1.0 - qualityScore
        ServicesAutoModeQualityPreference.QUALITY_2160,
        ServicesAutoModeQualityPreference.QUALITY_1080,
        ServicesAutoModeQualityPreference.QUALITY_720,
        ServicesAutoModeQualityPreference.QUALITY_480 -> {
            val target = preference.targetResolutionHeight ?: return qualityScore
            when {
                height == null -> qualityScore * 0.25
                height == target -> 2.0
                height < target -> 1.0 + height.toDouble() / target.toDouble()
                else -> 0.5 + target.toDouble() / height.toDouble()
            }
        }
    }
}

private fun ResolvedStreamCandidate.qualityHeight(): Int? {
    val haystack = listOfNotNull(title, subtitle, supportingText, addonName)
        .joinToString(" ")
        .lowercase()
    if (Regex("""\b(4k|uhd)\b""").containsMatchIn(haystack)) return 2160
    return Regex("""\b(2160|1080|720|480)p?\b""")
        .find(haystack)
        ?.groupValues
        ?.getOrNull(1)
        ?.toIntOrNull()
}

private fun qualityScoreFromText(text: String): Double {
    val lower = text.lowercase()
    val height = when {
        Regex("""\b(4k|uhd|2160p?)\b""").containsMatchIn(lower) -> 2160
        Regex("""\b1080p?\b""").containsMatchIn(lower) -> 1080
        Regex("""\b720p?\b""").containsMatchIn(lower) -> 720
        Regex("""\b480p?\b""").containsMatchIn(lower) -> 480
        else -> null
    }
    return when (height) {
        2160 -> 1.0
        1080 -> 0.86
        720 -> 0.70
        480 -> 0.52
        else -> 0.50
    }
}

private fun StremioStream.toResolvedCandidate(
    addon: StremioAddonEntity,
    addonLabel: String,
    requestSummary: String,
    requestTitles: List<String>,
    contentId: String,
    playbackContext: EpisodePlaybackContext?,
    similarityAlgorithm: SimilarityAlgorithm,
    sourceWarning: String?,
    index: Int,
): ResolvedStreamCandidate {
    val directUrl = url?.takeIf { isDirectHttp }
    val sourceQualityScore = qualityScore()
    val rawMatchScore = titleMatchScore(
        expectedTitles = requestTitles,
        candidateText = listOfNotNull(title, name, description, behaviorHints?.filename).joinToString(" "),
        algorithm = similarityAlgorithm,
    )
    val matchScore = if (directUrl != null) {
        maxOf(rawMatchScore, ExactStremioContentMatchFloor)
    } else {
        rawMatchScore
    }
    val playerSource = directUrl?.let {
        PlayerSource(
            uri = it,
            title = title ?: name ?: addonLabel,
            headers = behaviorHints?.proxyHeaders?.request.orEmpty(),
            subtitles = subtitles.mapNotNull { subtitle ->
                subtitle.url?.let { subtitleUrl ->
                    SubtitleTrack(
                        id = subtitle.id ?: "$addonLabel-$index-${subtitle.lang ?: "sub"}",
                        label = subtitle.label ?: subtitle.lang ?: "Subtitle",
                        language = subtitle.lang,
                        uri = subtitleUrl,
                    )
                }
            },
            serviceId = "stremio:${addon.transportUrl}",
            serviceName = addonLabel,
            serviceHref = contentId,
            context = playbackContext,
        )
    }

    val stateText = when {
        directUrl != null -> "Direct stream"
        ytId != null -> "YouTube handoff pending"
        else -> "Unsupported non-HTTP stream format"
    }

    return ResolvedStreamCandidate(
        id = "${addon.transportUrl}#$index",
        title = title ?: name ?: addonLabel,
        subtitle = addonLabel,
        supportingText = listOfNotNull(
            sourceWarning?.let { "Source warning: $it" },
            description?.takeIf { it.isNotBlank() },
            stateText,
            "Match ${(matchScore * 100).toInt()}",
            "Quality ${(sourceQualityScore * 100).toInt()}",
            behaviorHints?.filename,
            "$requestSummary via $contentId".takeIf { playerSource != null && description.isNullOrBlank() },
        ).joinToString(" | ").ifBlank { null },
        addonName = addonLabel,
        isPlayable = playerSource != null,
        qualityScore = sourceQualityScore,
        matchScore = matchScore,
        playerSource = playerSource,
    )
}

private fun ServiceStreamResult.toServiceCandidates(
    target: DetailTarget.ServiceMedia,
    href: String,
    episode: StreamEpisodeSelection?,
    sourceWarning: String?,
): List<ResolvedStreamCandidate> {
    val allStreams = serviceStreamPayloads().distinctBy { stream -> stream.url }
    return allStreams.mapIndexed { index, stream ->
        val title = if (episode != null) {
            "${target.title} ${episode.label}"
        } else {
            target.title
        }
        ResolvedStreamCandidate(
            id = "service:${target.serviceId}:$index",
            title = title,
            subtitle = "Service source",
            supportingText = listOfNotNull(
                sourceWarning?.let { "Source warning: $it" },
                "Direct HTTP(S) stream from ${target.serviceId}",
            ).joinToString(" | "),
            addonName = target.serviceId,
            isPlayable = true,
            qualityScore = qualityScoreFromText("$title ${stream.url}"),
            matchScore = 1.0,
            playerSource = PlayerSource(
                uri = stream.url,
                title = title,
                headers = stream.headers,
                subtitles = stream.subtitles,
                serviceId = "service:${target.serviceId}",
                serviceName = target.serviceId,
                serviceHref = href,
                context = episode?.toPlaybackContext(),
            ),
        )
    }
}

private data class ServiceStreamPayload(
    val url: String,
    val headers: Map<String, String>,
    val subtitles: List<SubtitleTrack>,
)

private fun ServiceStreamResult.serviceStreamPayloads(): List<ServiceStreamPayload> {
    val globalSubtitles = buildServiceSubtitleTracks(
        subtitleStrings = subtitles,
        subtitleObjects = subtitleTracks,
        defaultSubtitle = defaultSubtitle,
    )
    val directStreams = streams.mapNotNull { stream ->
        stream.takeIf(String::isDirectHttpUrl)?.let { url ->
            ServiceStreamPayload(
                url = url,
                headers = headers,
                subtitles = globalSubtitles,
            )
        }
    }

    val sourceStreams = sources.mapNotNull { source ->
        val url = source.firstString("url", "stream", "file", "src", "href")
            ?.takeIf(String::isDirectHttpUrl)
            ?: return@mapNotNull null
        val sourceHeaders = headers + source.headerStrings()
        val sourceSubtitles = buildServiceSubtitleTracks(
            subtitleStrings = source.subtitleStrings(),
            subtitleObjects = source.subtitleObjects(),
            defaultSubtitle = defaultSubtitle,
        ).ifEmpty { globalSubtitles }
        ServiceStreamPayload(
            url = url,
            headers = sourceHeaders,
            subtitles = sourceSubtitles,
        )
    }
    return directStreams + sourceStreams
}

private fun buildServiceSubtitleTracks(
    subtitleStrings: List<String>,
    subtitleObjects: List<JsonObject>,
    defaultSubtitle: String?,
): List<SubtitleTrack> {
    val fromObjects = subtitleObjects.mapIndexedNotNull { index, subtitle ->
        val uri = subtitle.firstString("url", "href", "file", "src")
            ?.takeIf(String::isDirectHttpUrl)
            ?: return@mapIndexedNotNull null
        val language = subtitle.firstString("lang", "language", "locale")
        val label = subtitle.firstString("label", "name", "title")
            ?: language?.uppercase()
            ?: "Subtitle ${index + 1}"
        SubtitleTrack(
            id = subtitle.firstString("id") ?: "service-subtitle-object-${index + 1}",
            label = label,
            language = language,
            uri = uri,
            format = subtitle.firstString("format", "type") ?: uri.subtitleFormatFromUrl(),
            isDefault = subtitle.booleanValue("default") ||
                subtitle.booleanValue("isDefault") ||
                subtitle.matchesDefaultSubtitle(defaultSubtitle, uri, label, language),
        )
    }
    val seenUris = fromObjects.mapNotNull(SubtitleTrack::uri).toMutableSet()
    val fromStrings = subtitleStrings.mapIndexedNotNull { index, uri ->
        uri.takeIf(String::isDirectHttpUrl)
            ?.takeIf(seenUris::add)
            ?.let { subtitleUri ->
                SubtitleTrack(
                    id = "service-subtitle-${index + 1}",
                    label = subtitleUri.subtitleDisplayLabel(index),
                    uri = subtitleUri,
                    format = subtitleUri.subtitleFormatFromUrl(),
                    isDefault = defaultSubtitle?.equals(subtitleUri, ignoreCase = true) == true,
                )
            }
    }
    return (fromObjects + fromStrings)
        .let { tracks ->
            if (tracks.any(SubtitleTrack::isDefault)) tracks else tracks.mapIndexed { index, track ->
                if (index == 0 && defaultSubtitle == null) track.copy(isDefault = true) else track
            }
        }
}

private fun StremioAddonEntity.manifest(): StremioManifest? = manifestJson?.runCatching {
    EclipseJson.decodeFromString<StremioManifest>(this)
}?.getOrNull()

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

internal fun List<ServiceEpisodeLink>.bestEpisodeForRequest(
    request: StremioRequest,
    fallback: StreamEpisodeSelection?,
    allowEpisodeAutoResolution: Boolean,
): ServiceEpisodeLink? {
    if (isEmpty()) return null
    val selected = fallback
    if (selected != null) {
        firstOrNull { episode ->
            episode.seasonNumber == selected.seasonNumber &&
                episode.episodeNumber == selected.episodeNumber
        }?.let { return it }
        if (allowEpisodeAutoResolution && !selected.isSpecial && !selected.titleOnlySearch) {
            bundledAnimeAbsoluteEpisode(selected)?.let { absoluteEpisode ->
                firstOrNull { episode -> episode.episodeNumber == absoluteEpisode }?.let { return it }
            }
        }
        firstOrNull { episode -> episode.episodeNumber == selected.localEpisodeNumber }?.let { return it }
    }
    if (request.type == "movie") return firstOrNull()
    request.episode?.let { requestedEpisode ->
        firstOrNull { episode -> episode.episodeNumber == requestedEpisode }?.let { return it }
    }
    return firstOrNull()
}

internal fun List<ServiceEpisodeLink>.episodeCandidatesForRequest(
    request: StremioRequest,
    fallback: StreamEpisodeSelection?,
    allowEpisodeAutoResolution: Boolean,
): List<ServiceEpisodeLink> {
    if (isEmpty()) return emptyList()
    if (allowEpisodeAutoResolution) {
        return listOfNotNull(bestEpisodeForRequest(request, fallback, allowEpisodeAutoResolution = true))
    }
    val selected = fallback
    if (selected != null) {
        firstOrNull { episode ->
            episode.seasonNumber == selected.seasonNumber &&
                episode.episodeNumber == selected.episodeNumber
        }?.let { return listOf(it) }

        val candidates = buildList {
            this@episodeCandidatesForRequest
                .firstOrNull { episode -> episode.episodeNumber == selected.localEpisodeNumber }
                ?.let(::add)
            this@episodeCandidatesForRequest.bundledAnimeAbsoluteEpisode(selected)?.let { absoluteEpisode ->
                this@episodeCandidatesForRequest
                    .firstOrNull { episode -> episode.episodeNumber == absoluteEpisode }
                    ?.let(::add)
            }
            request.episode?.let { requestedEpisode ->
                this@episodeCandidatesForRequest
                    .firstOrNull { episode -> episode.episodeNumber == requestedEpisode }
                    ?.let(::add)
            }
        }.distinctBy(ServiceEpisodeLink::href)
        if (candidates.isNotEmpty()) return candidates
    }
    if (request.type == "movie") return take(1)
    request.episode?.let { requestedEpisode ->
        firstOrNull { episode -> episode.episodeNumber == requestedEpisode }?.let { return listOf(it) }
    }
    return take(1)
}

private fun List<ServiceEpisodeLink>.bundledAnimeAbsoluteEpisode(
    selected: StreamEpisodeSelection,
): Int? {
    if (selected.isSpecial || selected.titleOnlySearch) return null
    val seasonEpisodeCount = selected.animeSeasonEpisodeCount?.takeIf { it > 0 } ?: return null
    val absoluteEpisode = selected.animeAbsoluteEpisodeNumber?.takeIf { it > 0 } ?: return null
    val maxEpisode = mapNotNull(ServiceEpisodeLink::episodeNumber).maxOrNull() ?: return null
    return absoluteEpisode.takeIf { maxEpisode > seasonEpisodeCount }
}

private fun ServiceEpisodeLink.toStreamEpisodeSelection(
    fallback: StreamEpisodeSelection?,
    request: StremioRequest,
    preferServiceLabel: Boolean = false,
): StreamEpisodeSelection {
    val localSeason = seasonNumber ?: fallback?.localSeasonNumber ?: request.season ?: 1
    val localEpisode = episodeNumber ?: fallback?.localEpisodeNumber ?: request.episode ?: 1
    val serviceLabel = title.takeIf { it.isNotBlank() } ?: "Episode $localEpisode"
    return StreamEpisodeSelection(
        seasonNumber = seasonNumber ?: fallback?.seasonNumber ?: request.season,
        episodeNumber = episodeNumber ?: fallback?.episodeNumber ?: request.episode,
        label = if (preferServiceLabel) serviceLabel else fallback?.label ?: "S${localSeason}E${localEpisode}",
        localSeasonNumber = localSeason,
        localEpisodeNumber = localEpisode,
        anilistMediaId = fallback?.anilistMediaId ?: request.anilistMediaId,
        tmdbEpisodeOffset = fallback?.tmdbEpisodeOffset,
        animeAbsoluteEpisodeNumber = fallback?.animeAbsoluteEpisodeNumber,
        animeSeasonEpisodeCount = fallback?.animeSeasonEpisodeCount,
        searchTitle = fallback?.searchTitle ?: request.summary,
        isSpecial = fallback?.isSpecial == true,
        titleOnlySearch = fallback?.titleOnlySearch == true,
        serviceHref = href,
    )
}

private fun Int.rejectionSuffix(): String =
    if (this > 0) {
        " Rejected $this torrent or magnet result${if (this == 1) "" else "s"}."
    } else {
        ""
    }

private fun JsonElement.jsonObjectOrNull(): JsonObject? =
    this as? JsonObject

private fun JsonObject.firstString(vararg keys: String): String? =
    keys.firstNotNullOfOrNull { key ->
        (this[key] as? JsonPrimitive)
            ?.contentOrNull
            ?.takeIf { it.isNotBlank() }
    }

private fun JsonObject.headerStrings(): Map<String, String> =
    listOf("headers", "requestHeaders", "httpHeaders")
        .asSequence()
        .mapNotNull { key -> this[key]?.jsonObjectOrNull() }
        .flatMap { headers -> headers.entries.asSequence() }
        .mapNotNull { (key, value) ->
            (value as? JsonPrimitive)
                ?.contentOrNull
                ?.takeIf { it.isNotBlank() }
                ?.let { key to it }
        }
        .toMap()

private fun JsonObject.subtitleStrings(): List<String> =
    listOf("subtitles", "subtitle", "subtitleUrls")
        .flatMap { key -> this[key].subtitleStrings() }
        .distinct()

private fun JsonObject.subtitleObjects(): List<JsonObject> =
    listOf("subtitles", "subtitleTracks", "tracks", "captions")
        .flatMap { key -> this[key].jsonObjects() }

private fun JsonElement?.subtitleStrings(): List<String> =
    when (this) {
        is JsonArray -> mapNotNull { subtitle ->
            when (subtitle) {
                is JsonObject -> subtitle.firstString("url", "href", "file", "src")
                is JsonPrimitive -> subtitle.contentOrNull?.takeIf { it.isNotBlank() }
                else -> null
            }
        }
        is JsonObject -> listOfNotNull(firstString("url", "href", "file", "src"))
        is JsonPrimitive -> listOfNotNull(contentOrNull?.takeIf { it.isNotBlank() })
        else -> emptyList()
    }

private fun JsonElement?.jsonObjects(): List<JsonObject> =
    when (this) {
        is JsonArray -> mapNotNull { it as? JsonObject }
        is JsonObject -> listOf(this)
        else -> emptyList()
    }

private fun JsonObject.booleanValue(key: String): Boolean =
    firstString(key)?.equals("true", ignoreCase = true) == true

private fun JsonObject.matchesDefaultSubtitle(
    defaultSubtitle: String?,
    uri: String,
    label: String,
    language: String?,
): Boolean {
    val default = defaultSubtitle?.takeIf { it.isNotBlank() } ?: return false
    return default.equals(uri, ignoreCase = true) ||
        default.equals(label, ignoreCase = true) ||
        language?.let { default.equals(it, ignoreCase = true) } == true ||
        firstString("id")?.let { default.equals(it, ignoreCase = true) } == true
}

private fun String?.isDirectHttpUrl(): Boolean =
    this?.startsWith("http://", ignoreCase = true) == true ||
        this?.startsWith("https://", ignoreCase = true) == true

private fun String.subtitleDisplayLabel(index: Int): String {
    val fileName = substringBefore('?')
        .substringBefore('#')
        .substringAfterLast('/')
        .takeIf { it.isNotBlank() }
    return fileName ?: "Subtitle ${index + 1}"
}

private fun String?.subtitleFormatFromUrl(): String? {
    val path = this
        ?.substringBefore('?')
        ?.substringBefore('#')
        ?.lowercase()
        ?: return null
    return when {
        path.endsWith(".srt") -> "srt"
        path.endsWith(".vtt") || path.endsWith(".webvtt") -> "vtt"
        path.endsWith(".ass") -> "ass"
        path.endsWith(".ssa") -> "ssa"
        path.endsWith(".ttml") || path.endsWith(".xml") -> "ttml"
        else -> null
    }
}

private fun languageTokens(preferredLanguage: String): List<String> {
    val lower = preferredLanguage.trim().lowercase()
    if (lower.isBlank()) return emptyList()
    return when (lower) {
        "jpn", "ja", "jp" -> listOf("jpn", "ja", "jp", "japanese")
        "eng", "en" -> listOf("eng", "en", "us", "uk", "english")
        "spa", "es", "esp" -> listOf("spa", "es", "esp", "spanish", "lat")
        "fre", "fra", "fr" -> listOf("fre", "fra", "fr", "french")
        "ger", "deu", "de" -> listOf("ger", "deu", "de", "german")
        "ita", "it" -> listOf("ita", "it", "italian")
        "por", "pt" -> listOf("por", "pt", "br", "portuguese")
        "rus", "ru" -> listOf("rus", "ru", "russian")
        "chi", "zho", "zh" -> listOf("chi", "zho", "zh", "chinese", "mandarin", "cantonese")
        "kor", "ko" -> listOf("kor", "ko", "korean")
        else -> listOf(lower)
    }
}
