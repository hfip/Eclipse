package dev.soupy.eclipse.android.data

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.ScheduleDaySection
import dev.soupy.eclipse.android.core.model.ScheduleEntryCard
import dev.soupy.eclipse.android.core.model.TMDBSearchResult
import dev.soupy.eclipse.android.core.model.displayTitle
import dev.soupy.eclipse.android.core.model.isMovie
import dev.soupy.eclipse.android.core.model.isTVShow
import dev.soupy.eclipse.android.core.network.AniListService
import dev.soupy.eclipse.android.core.network.TmdbService

class ScheduleRepository(
    private val aniListService: AniListService,
    private val tmdbService: TmdbService,
    private val tmdbEnabled: Boolean,
) {
    private val tmdbTargetCacheByAniListId = mutableMapOf<Int, DetailTarget?>()

    suspend fun loadSchedule(
        daysAhead: Int = 7,
        localTimeZone: Boolean = true,
    ): Result<List<ScheduleDaySection>> = runCatching {
        val schedule = aniListService.fetchAiringSchedule(daysAhead = daysAhead).orThrow()
        val zoneId = if (localTimeZone) ZoneId.systemDefault() else ZoneId.of("UTC")
        val today = LocalDate.now(zoneId)
        val fullDateFormatter = DateTimeFormatter.ofPattern("EEEE, MMM d", Locale.US)
        val chipDateFormatter = DateTimeFormatter.ofPattern("EEE", Locale.US)
        val dayNumberFormatter = DateTimeFormatter.ofPattern("d", Locale.US)
        val entriesByDate = schedule
            .groupBy { Instant.ofEpochSecond(it.airingAtEpochSeconds).atZone(zoneId).toLocalDate() }

        (0..daysAhead)
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
                    items = entries.sortedBy { it.airingAtEpochSeconds }.map { it.toScheduleEntryCard(zoneId) },
                )
            }
    }

    suspend fun lookupTmdbTarget(card: ScheduleEntryCard): Result<DetailTarget?> = runCatching {
        if (!tmdbEnabled) return@runCatching null
        if (card.mediaId > 0 && tmdbTargetCacheByAniListId.containsKey(card.mediaId)) {
            return@runCatching tmdbTargetCacheByAniListId[card.mediaId]
        }

        val target = performTmdbLookup(card)
        if (card.mediaId > 0) {
            tmdbTargetCacheByAniListId[card.mediaId] = target
        }
        target
    }

    private suspend fun performTmdbLookup(card: ScheduleEntryCard): DetailTarget? {
        val titleCandidates = card.titleCandidates
            .ifEmpty { listOf(card.title) }
            .distinctBy(String::normalizedScheduleTitle)
            .filter { it.normalizedScheduleTitle().isNotBlank() }
        val isMovie = card.format?.equals("MOVIE", ignoreCase = true) == true

        titleCandidates.forEach { candidate ->
            val response = if (isMovie) {
                tmdbService.searchMovies(candidate).orNull()
            } else {
                tmdbService.searchTvShows(candidate).orNull()
            }
            val match = response
                ?.results
                ?.bestScheduleMatch(candidate)
                ?.toScheduleDetailTarget()
            if (match != null) return match
        }

        titleCandidates.forEach { candidate ->
            val response = tmdbService.searchMulti(candidate, page = 1).orNull()
            val typedPool = response
                ?.results
                .orEmpty()
                .filter { result ->
                    if (isMovie) result.isMovie else result.isTVShow
                }
            val pool = typedPool.ifEmpty {
                response?.results.orEmpty().filter { it.isMovie || it.isTVShow }
            }
            val match = pool
                .bestScheduleMatch(candidate)
                ?.toScheduleDetailTarget()
            if (match != null) return match
        }

        return null
    }
}

private fun List<TMDBSearchResult>.bestScheduleMatch(candidate: String): TMDBSearchResult? {
    val candidateKey = candidate.normalizedScheduleTitle()
    if (isEmpty() || candidateKey.isBlank()) return null

    val exactMatches = filter { result -> result.displayTitle.normalizedScheduleTitle() == candidateKey }
    if (exactMatches.isNotEmpty()) return exactMatches.bestScheduleResult()

    val partialMatches = filter { result ->
        val resultKey = result.displayTitle.normalizedScheduleTitle()
        resultKey.contains(candidateKey) || candidateKey.contains(resultKey)
    }
    if (partialMatches.isNotEmpty()) return partialMatches.bestScheduleResult()

    return bestScheduleResult()
}

private fun List<TMDBSearchResult>.bestScheduleResult(): TMDBSearchResult? =
    maxWithOrNull(
        compareBy<TMDBSearchResult> { result -> result.genreIds.contains(AnimationGenreId) }
            .thenBy { result -> result.popularity },
    )

private fun TMDBSearchResult.toScheduleDetailTarget(): DetailTarget? = when {
    isMovie -> DetailTarget.TmdbMovie(id)
    isTVShow -> DetailTarget.TmdbShow(id)
    else -> null
}

private fun String.normalizedScheduleTitle(): String =
    lowercase(Locale.US).replace(NonAlphanumericRegex, "")

private val NonAlphanumericRegex = Regex("[^a-z0-9]")
private const val AnimationGenreId = 16


