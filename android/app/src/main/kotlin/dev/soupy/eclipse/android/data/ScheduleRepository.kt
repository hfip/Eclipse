package dev.soupy.eclipse.android.data

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import dev.soupy.eclipse.android.core.model.ScheduleDaySection
import dev.soupy.eclipse.android.core.network.AniListService

class ScheduleRepository(
    private val aniListService: AniListService,
) {
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
}


