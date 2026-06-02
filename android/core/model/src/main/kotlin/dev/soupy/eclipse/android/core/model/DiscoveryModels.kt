package dev.soupy.eclipse.android.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

enum class ScheduleMode(
    val rawValue: String,
    val title: String,
    val description: String,
) {
    ANIME("anime", "Anime", "Anime episodes from AniList."),
    WESTERN("western", "Western", "Regional Western TV and streaming episodes."),
    COMBINED("combined", "Combined", "Anime and Western episodes together."),
    LIBRARY("library", "Library", "Upcoming episodes from your saved library and bookmarks."),
    ;

    companion object {
        val Default: ScheduleMode = ANIME

        fun fromRawValue(value: String?): ScheduleMode =
            entries.firstOrNull { it.rawValue.equals(value?.trim(), ignoreCase = true) } ?: Default

        fun sanitizedRawValue(value: String?): String = fromRawValue(value).rawValue
    }
}

enum class ScheduleSource {
    ANIME,
    WESTERN,
    LIBRARY,
}

@Serializable
sealed interface DetailTarget {
    @Serializable
    @SerialName("tmdb_movie")
    data class TmdbMovie(val id: Int) : DetailTarget

    @Serializable
    @SerialName("tmdb_show")
    data class TmdbShow(val id: Int) : DetailTarget

    @Serializable
    @SerialName("anilist_media")
    data class AniListMediaTarget(val id: Int) : DetailTarget

    @Serializable
    @SerialName("service_media")
    data class ServiceMedia(
        val serviceId: String,
        val href: String,
        val title: String,
        val imageUrl: String? = null,
    ) : DetailTarget
}

data class ExploreMediaCard(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val overview: String? = null,
    val imageUrl: String? = null,
    val backdropUrl: String? = null,
    val logoUrl: String? = null,
    val badge: String? = null,
    val detailTarget: DetailTarget,
    val children: List<ExploreMediaCard> = emptyList(),
)

data class MediaCarouselSection(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val items: List<ExploreMediaCard> = emptyList(),
)

data class ScheduleEntryCard(
    val id: String,
    val title: String,
    val subtitle: String,
    val timeLabel: String? = null,
    val imageUrl: String? = null,
    val detailTarget: DetailTarget,
    val mediaId: Int = 0,
    val format: String? = null,
    val titleCandidates: List<String> = emptyList(),
    val source: ScheduleSource = ScheduleSource.ANIME,
)

data class ScheduleDaySection(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val chipTitle: String? = null,
    val dayNumber: String? = null,
    val items: List<ScheduleEntryCard> = emptyList(),
)

