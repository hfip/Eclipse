package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.AniListAiringScheduleEntry
import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.LibraryItemRecord
import dev.soupy.eclipse.android.core.model.ScheduleDaySection
import dev.soupy.eclipse.android.core.model.ScheduleEntryCard
import dev.soupy.eclipse.android.core.model.ScheduleMode
import dev.soupy.eclipse.android.core.model.ScheduleSource
import dev.soupy.eclipse.android.core.model.TMDBSearchResult
import dev.soupy.eclipse.android.core.model.bestAvailableUrl
import dev.soupy.eclipse.android.core.model.displayTitle
import dev.soupy.eclipse.android.core.model.fullPosterUrl
import dev.soupy.eclipse.android.core.model.isMovie
import dev.soupy.eclipse.android.core.model.isTVShow
import dev.soupy.eclipse.android.core.network.AniListService
import dev.soupy.eclipse.android.core.network.EclipseHttpClient
import dev.soupy.eclipse.android.core.network.EclipseJson
import dev.soupy.eclipse.android.core.network.TmdbService
import java.net.URLEncoder
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString

class ScheduleRepository(
    private val aniListService: AniListService,
    private val tmdbService: TmdbService,
    private val libraryRepository: LibraryRepository,
    private val tmdbEnabled: Boolean,
    private val httpClient: EclipseHttpClient = EclipseHttpClient(),
) {
    private val tmdbTargetCacheByScheduleKey = mutableMapOf<String, DetailTarget?>()

    suspend fun loadSchedule(
        mode: ScheduleMode = ScheduleMode.Default,
        daysAhead: Int = 7,
        localTimeZone: Boolean = true,
    ): Result<List<ScheduleDaySection>> = runCatching {
        val dayCount = maxOf(daysAhead, 1)
        entriesFor(mode, dayCount).toDaySections(dayCount, localTimeZone)
    }

    suspend fun lookupTmdbTarget(card: ScheduleEntryCard): Result<DetailTarget?> = runCatching {
        if (card.source == ScheduleSource.LIBRARY) return@runCatching card.detailTarget
        if (!tmdbEnabled) return@runCatching null
        val cacheKey = "${card.source}:${card.mediaId}"
        if (card.mediaId > 0 && tmdbTargetCacheByScheduleKey.containsKey(cacheKey)) {
            return@runCatching tmdbTargetCacheByScheduleKey[cacheKey]
        }

        val target = performTmdbLookup(card)
        if (card.mediaId > 0) {
            tmdbTargetCacheByScheduleKey[cacheKey] = target
        }
        target
    }

    private suspend fun entriesFor(mode: ScheduleMode, dayCount: Int): List<ScheduledEntry> = when (mode) {
        ScheduleMode.ANIME -> animeEntries(dayCount)
        ScheduleMode.WESTERN -> westernEntries(dayCount)
        ScheduleMode.LIBRARY -> libraryEntries(dayCount)
        ScheduleMode.COMBINED -> {
            val anime = runCatching { animeEntries(dayCount) }
            val western = runCatching { westernEntries(dayCount) }
            if (anime.isFailure && western.isFailure) {
                throw (anime.exceptionOrNull() ?: western.exceptionOrNull() ?: error("Schedule feeds failed."))
            }
            anime.getOrDefault(emptyList()) + western.getOrDefault(emptyList())
        }
    }

    private suspend fun animeEntries(dayCount: Int): List<ScheduledEntry> =
        aniListService.fetchAiringSchedule(daysAhead = dayCount)
            .orThrow()
            .map(AniListAiringScheduleEntry::toScheduledEntry)

    private suspend fun westernEntries(dayCount: Int): List<ScheduledEntry> {
        val today = LocalDate.now()
        val country = Locale.getDefault().country.uppercase(Locale.US).ifBlank { "US" }
        val episodesById = mutableMapOf<Int, TVMazeScheduleEpisode>()
        repeat(dayCount) { offset ->
            val date = today.plusDays(offset.toLong())
            fetchTVMazeEpisodes(country, date).forEach { episode ->
                if (!episode.show.isLikelyAnime) {
                    episodesById[episode.id] = episode
                }
            }
        }
        return episodesById.values.mapNotNull(TVMazeScheduleEpisode::toScheduledEntry)
    }

    private suspend fun libraryEntries(dayCount: Int): List<ScheduledEntry> {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val end = today.plusDays(dayCount.toLong())
        return libraryRepository.loadSnapshot()
            .getOrThrow()
            .savedItems
            .mapNotNull { record -> (record.detailTarget as? DetailTarget.TmdbShow)?.let { record to it.id } }
            .distinctBy { (_, showId) -> showId }
            .mapNotNull { (record, showId) ->
                val show = tmdbService.tvShowDetail(showId).orNull() ?: return@mapNotNull null
                val nextEpisode = show.nextEpisodeToAir ?: return@mapNotNull null
                val airDate = nextEpisode.airDate?.let { value -> runCatching { LocalDate.parse(value) }.getOrNull() }
                    ?: return@mapNotNull null
                if (airDate < today || airDate >= end) return@mapNotNull null
                ScheduledEntry(
                    id = "library-$showId-${nextEpisode.id}",
                    source = ScheduleSource.LIBRARY,
                    sourceMediaId = showId,
                    title = record.title,
                    airingAt = airDate.atStartOfDay(zone).toInstant(),
                    episode = nextEpisode.episodeNumber,
                    season = nextEpisode.seasonNumber,
                    imageUrl = record.imageUrl ?: show.fullPosterUrl,
                    titleCandidates = listOf(record.title),
                    hasKnownAiringTime = false,
                    detailTarget = DetailTarget.TmdbShow(showId),
                )
            }
    }

    private suspend fun fetchTVMazeEpisodes(
        country: String,
        date: LocalDate,
    ): List<TVMazeScheduleEpisode> {
        val url = "https://api.tvmaze.com/schedule?country=${country.urlEncode()}&date=${date.toString().urlEncode()}"
        return EclipseJson.decodeFromString(httpClient.get(url).orThrow())
    }

    private suspend fun performTmdbLookup(card: ScheduleEntryCard): DetailTarget? {
        val titleCandidates = card.titleCandidates
            .ifEmpty { listOf(card.title) }
            .distinctBy(String::normalizedScheduleTitle)
            .filter { it.normalizedScheduleTitle().isNotBlank() }
        val preferAnimation = card.source == ScheduleSource.ANIME
        val isMovie = preferAnimation && card.format?.equals("MOVIE", ignoreCase = true) == true

        titleCandidates.forEach { candidate ->
            val response = if (isMovie) {
                tmdbService.searchMovies(candidate).orNull()
            } else {
                tmdbService.searchTvShows(candidate).orNull()
            }
            val match = response
                ?.results
                ?.bestScheduleMatch(candidate, preferAnimation)
                ?.toScheduleDetailTarget()
            if (match != null) return match
        }

        titleCandidates.forEach { candidate ->
            val response = tmdbService.searchMulti(candidate, page = 1).orNull()
            val typedPool = response
                ?.results
                .orEmpty()
                .filter { result -> if (isMovie) result.isMovie else result.isTVShow }
            val pool = typedPool.ifEmpty {
                response?.results.orEmpty().filter { it.isMovie || it.isTVShow }
            }
            val match = pool
                .bestScheduleMatch(candidate, preferAnimation)
                ?.toScheduleDetailTarget()
            if (match != null) return match
        }

        return null
    }
}

private data class ScheduledEntry(
    val id: String,
    val source: ScheduleSource,
    val sourceMediaId: Int,
    val title: String,
    val airingAt: Instant,
    val episode: Int,
    val season: Int? = null,
    val imageUrl: String? = null,
    val titleCandidates: List<String> = emptyList(),
    val format: String? = null,
    val hasKnownAiringTime: Boolean = true,
    val detailTarget: DetailTarget,
)

private fun AniListAiringScheduleEntry.toScheduledEntry(): ScheduledEntry = ScheduledEntry(
    id = "anime-$id",
    source = ScheduleSource.ANIME,
    sourceMediaId = media.id,
    title = media.displayTitle,
    airingAt = Instant.ofEpochSecond(airingAtEpochSeconds),
    episode = episode,
    imageUrl = media.coverImage.bestAvailableUrl,
    titleCandidates = listOfNotNull(media.title.english, media.title.romaji, media.title.native),
    format = media.format,
    detailTarget = DetailTarget.AniListMediaTarget(media.id),
)

private fun TVMazeScheduleEpisode.toScheduledEntry(): ScheduledEntry? = ScheduledEntry(
    id = "western-$id",
    source = ScheduleSource.WESTERN,
    sourceMediaId = show.id,
    title = show.name,
    airingAt = airingInstant ?: return null,
    episode = number ?: 0,
    season = season,
    imageUrl = show.image?.medium ?: show.image?.original,
    titleCandidates = listOf(show.name),
    detailTarget = DetailTarget.TmdbShow(0),
)

private fun List<ScheduledEntry>.toDaySections(
    dayCount: Int,
    localTimeZone: Boolean,
): List<ScheduleDaySection> {
    val zoneId = if (localTimeZone) ZoneId.systemDefault() else ZoneId.of("UTC")
    val today = LocalDate.now(zoneId)
    val fullDateFormatter = DateTimeFormatter.ofPattern("EEEE, MMM d", Locale.US)
    val chipDateFormatter = DateTimeFormatter.ofPattern("EEE", Locale.US)
    val dayNumberFormatter = DateTimeFormatter.ofPattern("d", Locale.US)
    val entriesByDate = groupBy { entry -> entry.airingAt.atZone(zoneId).toLocalDate() }

    return (0 until dayCount)
        .map { offset -> today.plusDays(offset.toLong()) }
        .map { date ->
            val entries = entriesByDate[date].orEmpty()
            val title = when (date) {
                today -> "Today"
                today.plusDays(1) -> "Tomorrow"
                else -> date.format(DateTimeFormatter.ofPattern("EEEE", Locale.US))
            }
            val chipTitle = when (date) {
                today -> "Today"
                today.plusDays(1) -> "Tmrw"
                else -> date.format(chipDateFormatter)
            }
            ScheduleDaySection(
                id = date.toString(),
                title = title,
                subtitle = date.format(fullDateFormatter),
                chipTitle = chipTitle,
                dayNumber = date.format(dayNumberFormatter),
                items = entries.sortedBy(ScheduledEntry::airingAt).map { entry -> entry.toScheduleEntryCard(zoneId) },
            )
        }
}

private fun ScheduledEntry.toScheduleEntryCard(zoneId: ZoneId): ScheduleEntryCard = ScheduleEntryCard(
    id = id,
    title = title,
    subtitle = formatLabel(),
    timeLabel = if (hasKnownAiringTime) {
        airingAt.atZone(zoneId).format(DateTimeFormatter.ofPattern("h:mm a", Locale.US))
    } else {
        "Time TBA"
    },
    imageUrl = imageUrl,
    detailTarget = detailTarget,
    mediaId = sourceMediaId,
    format = format,
    titleCandidates = titleCandidates,
    source = source,
)

private fun ScheduledEntry.formatLabel(): String {
    if (source != ScheduleSource.ANIME) {
        return when {
            season != null && episode > 0 -> "S$season Ep. $episode"
            episode > 0 -> "Ep. $episode"
            else -> "New episode"
        }
    }
    return when (format?.uppercase(Locale.US)) {
        "MOVIE" -> "Movie"
        "OVA" -> "OVA"
        "ONA" -> "ONA Ep. $episode"
        "SPECIAL" -> "Special"
        "MUSIC" -> "Music"
        else -> "Ep. $episode"
    }
}

private fun List<TMDBSearchResult>.bestScheduleMatch(
    candidate: String,
    preferAnimation: Boolean,
): TMDBSearchResult? {
    val candidateKey = candidate.normalizedScheduleTitle()
    if (isEmpty() || candidateKey.isBlank()) return null

    val exactMatches = filter { result -> result.displayTitle.normalizedScheduleTitle() == candidateKey }
    if (exactMatches.isNotEmpty()) return exactMatches.bestScheduleResult(preferAnimation)

    val partialMatches = filter { result ->
        val resultKey = result.displayTitle.normalizedScheduleTitle()
        resultKey.contains(candidateKey) || candidateKey.contains(resultKey)
    }
    if (partialMatches.isNotEmpty()) return partialMatches.bestScheduleResult(preferAnimation)

    return bestScheduleResult(preferAnimation)
}

private fun List<TMDBSearchResult>.bestScheduleResult(preferAnimation: Boolean): TMDBSearchResult? =
    maxWithOrNull(
        compareBy<TMDBSearchResult> { result -> preferAnimation && result.genreIds.contains(AnimationGenreId) }
            .thenBy(TMDBSearchResult::popularity),
    )

private fun TMDBSearchResult.toScheduleDetailTarget(): DetailTarget? = when {
    isMovie -> DetailTarget.TmdbMovie(id)
    isTVShow -> DetailTarget.TmdbShow(id)
    else -> null
}

private fun String.normalizedScheduleTitle(): String =
    lowercase(Locale.US).replace(NonAlphanumericRegex, "")

private fun String.urlEncode(): String = URLEncoder.encode(this, Charsets.UTF_8.name())

@Serializable
private data class TVMazeScheduleEpisode(
    val id: Int,
    val season: Int,
    val number: Int? = null,
    val airdate: String,
    val airtime: String? = null,
    val airstamp: String? = null,
    val show: TVMazeShow,
) {
    val airingInstant: Instant?
        get() = airstamp?.let { value -> runCatching { Instant.parse(value) }.getOrNull() }
            ?: runCatching {
                val local = LocalDateTime.parse(
                    "$airdate ${airtime ?: "00:00"}",
                    DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm", Locale.US),
                )
                val zone = (show.network?.country?.timezone ?: show.webChannel?.country?.timezone)
                    ?.let { timezone -> runCatching { ZoneId.of(timezone) }.getOrNull() }
                    ?: ZoneId.systemDefault()
                local.atZone(zone).toInstant()
            }.getOrNull()
}

@Serializable
private data class TVMazeShow(
    val id: Int,
    val name: String,
    val language: String? = null,
    val genres: List<String> = emptyList(),
    val image: TVMazeImage? = null,
    val network: TVMazeChannel? = null,
    @SerialName("webChannel") val webChannel: TVMazeChannel? = null,
) {
    val isLikelyAnime: Boolean
        get() = language.equals("Japanese", ignoreCase = true) &&
            genres.any { genre -> genre.equals("Anime", ignoreCase = true) || genre.equals("Animation", ignoreCase = true) }
}

@Serializable
private data class TVMazeImage(
    val medium: String? = null,
    val original: String? = null,
)

@Serializable
private data class TVMazeChannel(
    val country: TVMazeCountry? = null,
)

@Serializable
private data class TVMazeCountry(
    val timezone: String? = null,
)

private val NonAlphanumericRegex = Regex("[^a-z0-9]")
private const val AnimationGenreId = 16
