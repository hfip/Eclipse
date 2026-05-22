package dev.soupy.eclipse.android.core.model

import kotlinx.serialization.Serializable

@Serializable
enum class ServicesAutoModeQualityPreference(
    val rawValue: String,
    val title: String,
    val targetResolutionHeight: Int? = null,
    val usesAutomaticSelection: Boolean = true,
) {
    MANUAL("manual", "Ask", usesAutomaticSelection = false),
    AUTO("auto", "Auto"),
    HIGHEST("highest", "Highest"),
    QUALITY_2160("2160p", "2160p", targetResolutionHeight = 2160),
    QUALITY_1080("1080p", "1080p", targetResolutionHeight = 1080),
    QUALITY_720("720p", "720p", targetResolutionHeight = 720),
    QUALITY_480("480p", "480p", targetResolutionHeight = 480),
    LOWEST("lowest", "Lowest"),
    ;

    companion object {
        val Default: ServicesAutoModeQualityPreference = AUTO

        fun fromRawValue(value: String?): ServicesAutoModeQualityPreference =
            entries.firstOrNull { it.rawValue.equals(value?.trim(), ignoreCase = true) } ?: Default

        fun sanitizedRawValue(value: String?): String = fromRawValue(value).rawValue
    }
}

@Serializable
enum class MediaDetailElement(
    val rawValue: String,
    val displayName: String,
    val appliesToMovies: Boolean = true,
) {
    OVERVIEW("overview", "Overview"),
    ACTIONS("actions", "Actions"),
    DETAILS("details", "Details"),
    CAST("cast", "Cast"),
    RATING_NOTES("ratingNotes", "Rating & Notes"),
    EPISODES("episodes", "Episodes", appliesToMovies = false),
    ;

    companion object {
        val DefaultOrder: List<MediaDetailElement> = listOf(
            OVERVIEW,
            ACTIONS,
            DETAILS,
            CAST,
            RATING_NOTES,
            EPISODES,
        )

        val DefaultOrderRawValue: String = rawValueFor(DefaultOrder)

        fun rawValueFor(elements: Iterable<MediaDetailElement>): String =
            elements.joinToString(",") { it.rawValue }

        fun fromRawValue(value: String?): MediaDetailElement? =
            entries.firstOrNull { it.rawValue == value?.trim() }

        fun orderedElements(rawValue: String?): List<MediaDetailElement> {
            val selected = rawValue
                .orEmpty()
                .split(',')
                .mapNotNull(::fromRawValue)
                .distinct()
            return selected + DefaultOrder.filterNot { it in selected }
        }

        fun sanitizedOrderRawValue(value: String?): String =
            rawValueFor(orderedElements(value))

        fun hiddenElements(rawValue: String?): Set<MediaDetailElement> =
            rawValue
                .orEmpty()
                .split(',')
                .mapNotNull(::fromRawValue)
                .toSet()

        fun sanitizedHiddenRawValue(value: String?): String =
            rawValueFor(DefaultOrder.filter { it in hiddenElements(value) })
    }
}

@Serializable
enum class HeroBannerBehavior(val rawValue: String, val title: String) {
    STATIC("static", "Static"),
    CAROUSEL("carousel", "Carousel"),
    LAUNCH("launch", "Change on App Launch"),
    ;

    companion object {
        val Default: HeroBannerBehavior = STATIC

        fun fromRawValue(value: String?): HeroBannerBehavior =
            entries.firstOrNull { it.rawValue.equals(value?.trim(), ignoreCase = true) } ?: Default

        fun sanitizedRawValue(value: String?): String = fromRawValue(value).rawValue
    }
}

@Serializable
enum class AtmosphereStyle(val rawValue: String, val title: String) {
    GRADIENT("gradient", "Gradient"),
    SOLID("solid", "Solid Color"),
    ;

    companion object {
        val Default: AtmosphereStyle = GRADIENT

        fun fromRawValue(value: String?): AtmosphereStyle =
            entries.firstOrNull { it.rawValue.equals(value?.trim(), ignoreCase = true) } ?: Default

        fun sanitizedRawValue(value: String?): String = fromRawValue(value).rawValue
    }
}

@Serializable
enum class AtmosphereSolidColorSource(val rawValue: String, val title: String) {
    DOMINANT("dominant", "Poster Dominant"),
    CUSTOM("custom", "Custom Color"),
    ;

    companion object {
        val Default: AtmosphereSolidColorSource = DOMINANT

        fun fromRawValue(value: String?): AtmosphereSolidColorSource =
            entries.firstOrNull { it.rawValue.equals(value?.trim(), ignoreCase = true) } ?: Default

        fun sanitizedRawValue(value: String?): String = fromRawValue(value).rawValue
    }
}
