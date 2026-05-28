package dev.soupy.eclipse.android.feature.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.soupy.eclipse.android.core.design.ErrorPanel
import dev.soupy.eclipse.android.core.design.GlassPanel
import dev.soupy.eclipse.android.core.design.LoadingPanel
import dev.soupy.eclipse.android.core.design.PosterImage
import dev.soupy.eclipse.android.core.design.SectionHeading
import dev.soupy.eclipse.android.core.model.ScheduleDaySection
import dev.soupy.eclipse.android.core.model.ScheduleEntryCard

data class ScheduleScreenState(
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val showLocalScheduleTime: Boolean = true,
    val useClassicScheduleUI: Boolean = false,
    val days: List<ScheduleDaySection> = emptyList(),
    val loadingItemId: String? = null,
    val noTmdbEntryTitle: String? = null,
)

@Composable
fun ScheduleRoute(
    state: ScheduleScreenState,
    onRefresh: () -> Unit,
    onShowLocalScheduleTimeChanged: (Boolean) -> Unit,
    onSelect: (ScheduleEntryCard) -> Unit,
    onDismissNoTmdbEntry: () -> Unit,
) {
    var selectedDayIndex by rememberSaveable { mutableIntStateOf(0) }
    val selectedDay = state.days.getOrNull(selectedDayIndex) ?: state.days.firstOrNull()

    state.noTmdbEntryTitle?.let { title ->
        AlertDialog(
            onDismissRequest = onDismissNoTmdbEntry,
            title = { Text("No TMDB Entry") },
            text = { Text("\"$title\" does not have a TMDB entry and cannot be opened.") },
            confirmButton = {
                TextButton(onClick = onDismissNoTmdbEntry) {
                    Text("OK")
                }
            },
        )
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(18.dp),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
    ) {
        if (state.isLoading && state.days.isEmpty()) {
            item {
                LoadingPanel(
                    title = "Loading schedule",
                    message = "Pulling upcoming anime airings into grouped day buckets.",
                )
            }
        }

        if (!state.isLoading && state.errorMessage == null && state.days.isNotEmpty()) {
            item {
                TimeZoneToggleRow(
                    showLocalScheduleTime = state.showLocalScheduleTime,
                    classic = state.useClassicScheduleUI,
                    onShowLocalScheduleTimeChanged = onShowLocalScheduleTimeChanged,
                )
            }
        }

        state.errorMessage?.let { error ->
            item {
                ErrorPanel(
                    title = "Schedule couldn't finish loading",
                    message = error,
                    actionLabel = "Try Again",
                    onAction = onRefresh,
                )
            }
        }

        if (state.useClassicScheduleUI) {
            items(state.days, key = { it.id }) { day ->
                ScheduleDayColumn(
                    day = day,
                    classic = true,
                    loadingItemId = state.loadingItemId,
                    onSelect = onSelect,
                )
            }
        } else if (state.days.isNotEmpty()) {
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(state.days.size) { index ->
                        val day = state.days[index]
                        DayChip(
                            day = day,
                            selected = day.id == selectedDay?.id,
                            onClick = { selectedDayIndex = index },
                        )
                    }
                }
            }
            item {
                selectedDay?.let { day ->
                    ScheduleDayColumn(
                        day = day,
                        classic = false,
                        loadingItemId = state.loadingItemId,
                        onSelect = onSelect,
                    )
                }
            }
        }

        if (!state.isLoading && state.errorMessage == null && state.days.isEmpty()) {
            item {
                ErrorPanel(
                    title = "No airings landed",
                    message = "AniList did not return any upcoming items for this window.",
                    actionLabel = "Refresh",
                    onAction = onRefresh,
                )
            }
        }
    }
}

@Composable
private fun TimeZoneToggleRow(
    showLocalScheduleTime: Boolean,
    classic: Boolean,
    onShowLocalScheduleTimeChanged: (Boolean) -> Unit,
) {
    GlassPanel(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = if (classic) 14.dp else 10.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = if (classic) "Timezone" else if (showLocalScheduleTime) "Local time" else "UTC",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                if (classic) {
                    Text(
                        text = "Times are shown in ${if (showLocalScheduleTime) "your local time" else "UTC"}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f),
                    )
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (showLocalScheduleTime) {
                    Button(onClick = { onShowLocalScheduleTimeChanged(true) }) {
                        Text("Local")
                    }
                } else {
                    OutlinedButton(onClick = { onShowLocalScheduleTimeChanged(true) }) {
                        Text("Local")
                    }
                }
                if (!showLocalScheduleTime) {
                    Button(onClick = { onShowLocalScheduleTimeChanged(false) }) {
                        Text("UTC")
                    }
                } else {
                    OutlinedButton(onClick = { onShowLocalScheduleTimeChanged(false) }) {
                        Text("UTC")
                    }
                }
            }
        }
    }
}

@Composable
private fun DayChip(
    day: ScheduleDaySection,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val container = if (selected) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.surface.copy(alpha = 0.36f)
    }
    val content = if (selected) {
        MaterialTheme.colorScheme.onPrimary
    } else {
        MaterialTheme.colorScheme.onSurface
    }
    Box(
        modifier = Modifier
            .width(62.dp)
            .height(72.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(container)
            .clickable(onClick = onClick)
            .padding(horizontal = 6.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(
                text = day.chipTitle ?: day.title.takeIf { it.length <= 5 } ?: day.title.take(3),
                style = MaterialTheme.typography.labelLarge,
                color = content,
                maxLines = 1,
            )
            Text(
                text = day.dayNumber ?: day.subtitle?.substringAfterLast(" ").orEmpty(),
                style = MaterialTheme.typography.titleLarge,
                color = content,
                maxLines = 1,
            )
            Text(
                text = day.items.size.toString(),
                style = MaterialTheme.typography.labelLarge,
                color = content.copy(alpha = 0.72f),
            )
        }
    }
}

@Composable
private fun ScheduleDayColumn(
    day: ScheduleDaySection,
    classic: Boolean,
    loadingItemId: String?,
    onSelect: (ScheduleEntryCard) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeading(
            title = day.title,
            subtitle = if (classic) day.subtitle else "${day.items.size} airing${if (day.items.size == 1) "" else "s"}",
        )
        if (day.items.isEmpty()) {
            GlassPanel(modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = "No episodes scheduled",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.70f),
                )
            }
        } else {
            day.items.forEach { item ->
                ScheduleItemCard(
                    item = item,
                    classic = classic,
                    loading = loadingItemId == item.id,
                    onSelect = onSelect,
                )
            }
        }
    }
}

@Composable
private fun ScheduleItemCard(
    item: ScheduleEntryCard,
    classic: Boolean,
    loading: Boolean,
    onSelect: (ScheduleEntryCard) -> Unit,
) {
    GlassPanel(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = !loading) { onSelect(item) },
        contentPadding = if (classic) PaddingValues(16.dp) else PaddingValues(10.dp),
    ) {
        Box(modifier = Modifier.fillMaxWidth()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                PosterImage(
                    imageUrl = item.imageUrl,
                    contentDescription = item.title,
                    modifier = Modifier
                        .width(if (classic) 54.dp else 54.dp)
                        .height(if (classic) 76.dp else 76.dp),
                )
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        text = item.title,
                        style = if (classic) MaterialTheme.typography.titleLarge else MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = item.subtitle,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.68f),
                    )
                }
                item.timeLabel?.let { time ->
                    Text(
                        text = time,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f))
                            .padding(horizontal = 8.dp, vertical = 5.dp),
                        maxLines = 1,
                    )
                }
            }
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.CenterEnd),
                    color = MaterialTheme.colorScheme.tertiary,
                    strokeWidth = 2.dp,
                )
            }
        }
    }
}

