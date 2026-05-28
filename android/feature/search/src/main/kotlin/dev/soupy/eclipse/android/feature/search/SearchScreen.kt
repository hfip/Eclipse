package dev.soupy.eclipse.android.feature.search

import android.content.res.Configuration
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import dev.soupy.eclipse.android.core.design.ErrorPanel
import dev.soupy.eclipse.android.core.design.LoadingPanel
import dev.soupy.eclipse.android.core.design.MediaPosterCard
import dev.soupy.eclipse.android.core.design.SectionHeading
import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.MediaCarouselSection

data class SearchSourceRow(
    val id: String,
    val label: String,
    val subtitle: String? = null,
    val isTmdb: Boolean = false,
)

private enum class SearchFilter(val label: String) {
    ALL("All"),
    MOVIES("Movies"),
    TV("TV Shows"),
}

data class SearchScreenState(
    val query: String = "",
    val isSearching: Boolean = false,
    val errorMessage: String? = null,
    val recentQueries: List<String> = emptyList(),
    val sections: List<MediaCarouselSection> = emptyList(),
    val sourceOptions: List<SearchSourceRow> = listOf(SearchSourceRow("tmdb", "TMDB", "Movies and TV shows", isTmdb = true)),
    val selectedSourceId: String = "tmdb",
    val mediaColumnsPortrait: Int = 3,
    val mediaColumnsLandscape: Int = 5,
)

@Composable
fun SearchRoute(
    state: SearchScreenState,
    onQueryChange: (String) -> Unit,
    onSearch: () -> Unit,
    onRecentQuery: (String) -> Unit,
    onClearRecentQueries: () -> Unit,
    onRemoveRecentQuery: (String) -> Unit,
    onSourceSelected: (String) -> Unit,
    onSelect: (DetailTarget) -> Unit,
) {
    val configuration = LocalConfiguration.current
    val columnCount = if (configuration.orientation == Configuration.ORIENTATION_LANDSCAPE) {
        state.mediaColumnsLandscape
    } else {
        state.mediaColumnsPortrait
    }.coerceIn(2, 8)
    var selectedFilter by rememberSaveable { mutableStateOf(SearchFilter.ALL) }
    var filterMenuExpanded by rememberSaveable { mutableStateOf(false) }
    val results = state.sections.flatMap { it.items }
    val filteredResults = when (selectedFilter) {
        SearchFilter.ALL -> results
        SearchFilter.MOVIES -> results.filter { it.detailTarget is DetailTarget.TmdbMovie }
        SearchFilter.TV -> results.filter { it.detailTarget is DetailTarget.TmdbShow }
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
    ) {
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = state.query,
                    onValueChange = onQueryChange,
                    label = { Text("Search...") },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSearch = { onSearch() }),
                )
                Button(
                    onClick = onSearch,
                    enabled = state.query.isNotBlank() && !state.isSearching,
                ) {
                    Text("Search")
                }
                if (results.isNotEmpty()) {
                    Box {
                        androidx.compose.material3.OutlinedButton(
                            onClick = { filterMenuExpanded = true },
                        ) {
                            Text(selectedFilter.label)
                        }
                        DropdownMenu(
                            expanded = filterMenuExpanded,
                            onDismissRequest = { filterMenuExpanded = false },
                        ) {
                            SearchFilter.entries.forEach { filter ->
                                DropdownMenuItem(
                                    text = { Text(filter.label) },
                                    onClick = {
                                        selectedFilter = filter
                                        filterMenuExpanded = false
                                    },
                                )
                            }
                        }
                    }
                }
            }
        }

        if (state.query.isBlank() && state.recentQueries.isNotEmpty()) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        SectionHeading(
                            title = "Recent Searches",
                            modifier = Modifier.weight(1f),
                        )
                        androidx.compose.material3.OutlinedButton(onClick = onClearRecentQueries) {
                            Text("Clear")
                        }
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        state.recentQueries.forEach { query ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Button(
                                    onClick = { onRecentQuery(query) },
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Text(query)
                                }
                                androidx.compose.material3.OutlinedButton(
                                    onClick = { onRemoveRecentQuery(query) },
                                ) {
                                    Text("Remove")
                                }
                            }
                        }
                    }
                }
            }
        }

        if (state.isSearching) {
            item {
                LoadingPanel(
                    title = "Searching",
                    message = "Looking across movies and TV shows.",
                )
            }
        }

        state.errorMessage?.let { error ->
            item {
                ErrorPanel(
                    title = "Search hit a snag",
                    message = error,
                    actionLabel = "Retry",
                    onAction = onSearch,
                )
            }
        }

        if (state.query.isBlank() && state.sections.isEmpty()) {
            item {
                ErrorPanel(
                    title = "Search Movies & TV Shows",
                    message = "Search for a movie or TV show.",
                )
            }
        }

        if (state.query.isNotBlank() && !state.isSearching && state.errorMessage == null && results.isEmpty()) {
            item {
                ErrorPanel(
                    title = "No results found",
                    message = "Try searching for a different movie or TV show.",
                )
            }
        }

        if (results.isNotEmpty() && filteredResults.isEmpty()) {
            item {
                ErrorPanel(
                    title = "No ${selectedFilter.label.lowercase()} found",
                    message = "Try another filter or search for something else.",
                )
            }
        }

        if (filteredResults.isNotEmpty()) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionHeading(
                        title = "Search Results",
                        subtitle = "${filteredResults.size} ${selectedFilter.label.lowercase()} result${if (filteredResults.size == 1) "" else "s"}",
                    )
                    filteredResults.chunked(columnCount).forEach { rowItems ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            rowItems.forEach { item ->
                                MediaPosterCard(
                                    item = item,
                                    onClick = { onSelect(item.detailTarget) },
                                    modifier = Modifier.weight(1f),
                                )
                            }
                            repeat(columnCount - rowItems.size) {
                                Column(modifier = Modifier.weight(1f)) {}
                            }
                        }
                    }
                }
            }
        }
    }
}

