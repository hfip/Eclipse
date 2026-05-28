package dev.soupy.eclipse.android.data

import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import dev.soupy.eclipse.android.core.model.AniListMedia
import dev.soupy.eclipse.android.core.model.BackupCatalog
import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.ExploreMediaCard
import dev.soupy.eclipse.android.core.model.HeroBannerBehavior
import dev.soupy.eclipse.android.core.model.MediaCarouselSection
import dev.soupy.eclipse.android.core.model.TMDBSearchResult
import dev.soupy.eclipse.android.core.model.bestLogoUrl
import dev.soupy.eclipse.android.core.model.displayTitle
import dev.soupy.eclipse.android.core.model.fullBackdropUrl
import dev.soupy.eclipse.android.core.model.fullPosterUrl
import dev.soupy.eclipse.android.core.model.isMovie
import dev.soupy.eclipse.android.core.model.isTVShow
import dev.soupy.eclipse.android.core.network.AniListService
import dev.soupy.eclipse.android.core.network.TmdbService
import dev.soupy.eclipse.android.core.storage.SettingsStore
import kotlinx.coroutines.flow.first

private const val HorrorGenreId = 27

data class HomeContent(
    val hero: ExploreMediaCard? = null,
    val heroCandidates: List<ExploreMediaCard> = emptyList(),
    val heroCarouselEnabled: Boolean = false,
    val sections: List<MediaCarouselSection> = emptyList(),
)

class HomeRepository(
    private val tmdbService: TmdbService,
    private val aniListService: AniListService,
    private val animeTmdbMapper: AnimeTmdbMapper,
    private val catalogRepository: CatalogRepository,
    private val recommendationRepository: RecommendationRepository,
    private val progressRepository: ProgressRepository,
    private val settingsStore: SettingsStore,
    private val tmdbEnabled: Boolean,
) {
    suspend fun loadHome(): Result<HomeContent> = runCatching {
        coroutineScope {
            val settings = settingsStore.settings.first()
            tmdbService.setLanguage(settings.tmdbLanguage)
            val enabledCatalogsDeferred = async { catalogRepository.enabledCatalogs() }
            val continueWatchingDeferred = async { progressRepository.continueWatching(limit = 12) }
            val trendingDeferred = async {
                if (tmdbEnabled) tmdbService.trendingAll()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val popularMoviesDeferred = async {
                if (tmdbEnabled) tmdbService.popularMovies()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val nowPlayingMoviesDeferred = async {
                if (tmdbEnabled) tmdbService.nowPlayingMovies()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val upcomingMoviesDeferred = async {
                if (tmdbEnabled) tmdbService.upcomingMovies()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val popularTvDeferred = async {
                if (tmdbEnabled) tmdbService.popularTv()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val airingTodayDeferred = async {
                if (tmdbEnabled) tmdbService.airingTodayTv()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val onTheAirDeferred = async {
                if (tmdbEnabled) tmdbService.onTheAirTv()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val topRatedTvDeferred = async {
                if (tmdbEnabled) tmdbService.topRatedTv()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val topRatedMoviesDeferred = async {
                if (tmdbEnabled) tmdbService.topRatedMovies()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val animeCatalogsDeferred = async { aniListService.fetchHomeCatalogs() }

            val enabledCatalogs = enabledCatalogsDeferred.await()
            if (!tmdbEnabled && enabledCatalogs.any { catalog -> catalog.resolvedSource.equals("TMDB", ignoreCase = true) }) {
                error("TMDB home catalogs are not configured. Add TMDB_API_KEY to android/local.properties or Build.xcconfig and rebuild the app.")
            }
            val sections = run {
                val trending = trendingDeferred.await().orEmptyList()
                    .withoutFilteredHorror(settings.filterHorrorContent)
                    .filter { it.isMovie || it.isTVShow }
                    .take(12)
                    .map { it.toExploreMediaCard("Trending") }
                val popularMovies = popularMoviesDeferred.await().orEmptyList()
                    .withoutFilteredHorror(settings.filterHorrorContent)
                    .take(12)
                    .map { it.toExploreMediaCard("Movie") }
                val nowPlayingMovies = nowPlayingMoviesDeferred.await().orEmptyList()
                    .withoutFilteredHorror(settings.filterHorrorContent)
                    .take(12)
                    .map { it.toExploreMediaCard("Now playing") }
                val upcomingMovies = upcomingMoviesDeferred.await().orEmptyList()
                    .withoutFilteredHorror(settings.filterHorrorContent)
                    .take(12)
                    .map { it.toExploreMediaCard("Upcoming") }
                val popularTv = popularTvDeferred.await().orEmptyList()
                    .withoutFilteredHorror(settings.filterHorrorContent)
                    .take(12)
                    .map { it.toExploreMediaCard("Series") }
                val airingToday = airingTodayDeferred.await().orEmptyList()
                    .withoutFilteredHorror(settings.filterHorrorContent)
                    .take(12)
                    .map { it.toExploreMediaCard("Airing today") }
                val onTheAir = onTheAirDeferred.await().orEmptyList()
                    .withoutFilteredHorror(settings.filterHorrorContent)
                    .take(12)
                    .map { it.toExploreMediaCard("On the air") }
                val topRatedTv = topRatedTvDeferred.await().orEmptyList()
                    .withoutFilteredHorror(settings.filterHorrorContent)
                    .take(12)
                    .map { it.toExploreMediaCard("Top rated") }
                val topRatedMovies = topRatedMoviesDeferred.await().orEmptyList()
                    .withoutFilteredHorror(settings.filterHorrorContent)
                    .take(12)
                    .map { it.toExploreMediaCard("Top rated") }
                val animeCatalogs = animeCatalogsDeferred.await().orThrow()
                val animeTrending = animeCatalogs.trending.toMappedAnimeCards("Anime")
                val animePopular = animeCatalogs.popular.toMappedAnimeCards("Anime")
                val animeAiring = animeCatalogs.airing.toMappedAnimeCards("Airing")
                val animeUpcoming = animeCatalogs.upcoming.toMappedAnimeCards("Upcoming")
                val animeTop = animeCatalogs.topRated.toMappedAnimeCards("Top rated")
                val tmdbPool = (trending + popularMovies + nowPlayingMovies + upcomingMovies + popularTv + airingToday + onTheAir + topRatedTv + topRatedMovies)
                    .distinctBy { it.id }
                val justForYou = recommendationRepository.justForYou(tmdbPool)
                val becauseYouWatched = recommendationRepository.becauseYouWatched(tmdbPool)
                val enabledCatalogIds = enabledCatalogs.map(BackupCatalog::id).toSet()
                val networkGroups = if (tmdbEnabled && "networks" in enabledCatalogIds) {
                    discoverNetworkGroups(settings.filterHorrorContent)
                } else {
                    emptyList()
                }
                val genreGroups = if (tmdbEnabled && "genres" in enabledCatalogIds) {
                    discoverGenreGroups(settings.filterHorrorContent)
                } else {
                    emptyList()
                }
                val companyGroups = if (tmdbEnabled && "companies" in enabledCatalogIds) {
                    discoverCompanyGroups(settings.filterHorrorContent)
                } else {
                    emptyList()
                }
                val featuredGroup = if (tmdbEnabled && "featured" in enabledCatalogIds) {
                    discoverFeaturedGroup(settings.filterHorrorContent)
                } else {
                    null
                }
                val continueWatching = continueWatchingDeferred.await().map { record ->
                    ExploreMediaCard(
                        id = record.id,
                        title = record.title,
                        subtitle = record.progressLabel ?: record.subtitle,
                        imageUrl = record.imageUrl,
                        backdropUrl = record.backdropUrl ?: record.imageUrl,
                        badge = "Continue",
                        detailTarget = record.detailTarget,
                    )
                }

                val sectionByCatalogId = buildMap {
                    put("continueWatching", MediaCarouselSection("local-continue-watching", "Continue Watching", "Resume from playback progress", continueWatching))
                    put("forYou", MediaCarouselSection("local-for-you", "Just For You", "Picked from your progress, ratings, and recommendations", justForYou))
                    put("becauseYouWatched", MediaCarouselSection("local-because-you-watched", "Because You Watched", "More picks shaped by your watched and resume history", becauseYouWatched))
                    put("trending", MediaCarouselSection("tmdb-trending", "Trending This Week", "Popular right now", trending))
                    put("popularMovies", MediaCarouselSection("tmdb-movies", "Popular Movies", "What people are queueing right now", popularMovies))
                    put("networks", MediaCarouselSection("tmdb-networks", "Network", "Series from familiar networks", networkGroups))
                    put("nowPlayingMovies", MediaCarouselSection("tmdb-now-playing", "Now Playing Movies", "Fresh theatrical and streaming movie picks", nowPlayingMovies))
                    put("upcomingMovies", MediaCarouselSection("tmdb-upcoming-movies", "Upcoming Movies", "Movies arriving soon", upcomingMovies))
                    put("popularTVShows", MediaCarouselSection("tmdb-tv", "Popular TV Shows", "Popular series people are watching", popularTv))
                    put("genres", MediaCarouselSection("tmdb-genres", "Category", "Browse by mood and category", genreGroups))
                    put("onTheAirTV", MediaCarouselSection("tmdb-on-the-air", "On The Air TV Shows", "Series airing now", onTheAir))
                    put("airingTodayTV", MediaCarouselSection("tmdb-airing", "Airing Today TV Shows", "Shows with fresh TV episodes today", airingToday))
                    put("topRatedTVShows", MediaCarouselSection("tmdb-top-tv", "Top Rated TV Shows", "Highly rated series", topRatedTv))
                    put("topRatedMovies", MediaCarouselSection("tmdb-top-movies", "Top Rated Movies", "Highly rated movies", topRatedMovies))
                    put("companies", MediaCarouselSection("tmdb-companies", "Company", "Studio and company picks", companyGroups))
                    put("trendingAnime", MediaCarouselSection("anime-trending", "Trending Anime", "Anime people are watching now", animeTrending))
                    put("popularAnime", MediaCarouselSection("anime-popular", "Popular Anime", "Frequently watched anime picks", animePopular))
                    put("featured", MediaCarouselSection("tmdb-featured", "Featured", "A broader featured mix", listOfNotNull(featuredGroup)))
                    put("topRatedAnime", MediaCarouselSection("anime-top", "Top Rated Anime", "Highly rated anime", animeTop))
                    put("airingAnime", MediaCarouselSection("anime-airing", "Currently Airing Anime", "What's actively rolling out now", animeAiring))
                    put("upcomingAnime", MediaCarouselSection("anime-upcoming", "Upcoming Anime", "Not-yet-released anime with strong interest", animeUpcoming))
                    put("bestTVShows", MediaCarouselSection("tmdb-best-tv", "Best TV Shows", "Ranked series", topRatedTv))
                    put("bestMovies", MediaCarouselSection("tmdb-best-movies", "Best Movies", "Ranked movies", topRatedMovies))
                    put("bestAnime", MediaCarouselSection("anime-best", "Best Anime", "Ranked anime", animeTop))
                }

                (listOfNotNull(sectionByCatalogId["continueWatching"]?.takeIf { it.items.isNotEmpty() }) +
                    enabledCatalogs
                    .mapNotNull { catalog -> sectionByCatalogId[catalog.id]?.forCatalog(catalog) }
                    .filter { it.items.isNotEmpty() })
            }

            if (sections.isEmpty()) {
                error("No TMDB or AniList browse sections were available.")
            }

            val heroBehavior = HeroBannerBehavior.fromRawValue(settings.heroBannerBehavior)
            val heroCandidates = sections
                .heroCandidatesFor(settings.heroBannerCatalogId)
                .ifEmpty { sections.flatMap { it.items }.take(12) }
            val selectedHero = when (heroBehavior) {
                HeroBannerBehavior.LAUNCH -> heroCandidates.randomOrNull()
                HeroBannerBehavior.STATIC,
                HeroBannerBehavior.CAROUSEL -> heroCandidates.firstOrNull()
            }?.withLogo(settings.tmdbLanguage)
            val carouselCandidates = if (heroBehavior == HeroBannerBehavior.CAROUSEL) {
                heroCandidates
                    .take(8)
                    .map { candidate -> candidate.withLogo(settings.tmdbLanguage) }
            } else {
                emptyList()
            }

            HomeContent(
                hero = selectedHero,
                heroCandidates = carouselCandidates,
                heroCarouselEnabled = carouselCandidates.size > 1,
                sections = sections,
            )
        }
    }

    private suspend fun ExploreMediaCard.withLogo(preferredLanguage: String): ExploreMediaCard {
        val logoUrl = when (val target = detailTarget) {
            is DetailTarget.TmdbMovie -> tmdbService.movieImages(target.id).orNull()?.bestLogoUrl(preferredLanguage)
            is DetailTarget.TmdbShow -> tmdbService.tvImages(target.id).orNull()?.bestLogoUrl(preferredLanguage)
            else -> null
        }
        return logoUrl?.let { copy(logoUrl = it) } ?: this
    }

    private suspend fun List<AniListMedia>.toMappedAnimeCards(
        badge: String,
    ): List<ExploreMediaCard> = coroutineScope {
        take(12)
            .map { anime ->
                async { anime.toMappedAnimeCard(badge) }
            }
            .awaitAll()
            .filterNotNull()
    }

    private suspend fun AniListMedia.toMappedAnimeCard(badge: String): ExploreMediaCard? {
        if (!tmdbEnabled) return toExploreMediaCard(badge)
        val match = runCatching { animeTmdbMapper.findBestMatch(this) }.getOrNull()
        return when (val target = match?.target) {
            is DetailTarget.TmdbMovie -> {
                val movie = tmdbService.movieDetail(target.id).orNull()
                movie?.let {
                    ExploreMediaCard(
                        id = "anilist-$id-tmdb-movie-${it.id}",
                        title = displayTitle,
                        subtitle = it.releaseDate?.take(4),
                        overview = it.overview,
                        imageUrl = it.fullPosterUrl,
                        backdropUrl = it.fullBackdropUrl,
                        badge = badge,
                        detailTarget = DetailTarget.AniListMediaTarget(id),
                    )
                } ?: toExploreMediaCard(badge)
            }

            is DetailTarget.TmdbShow -> {
                val show = tmdbService.tvShowDetail(target.id).orNull()
                show?.let {
                    ExploreMediaCard(
                        id = "anilist-$id-tmdb-tv-${it.id}",
                        title = displayTitle,
                        subtitle = it.firstAirDate?.take(4),
                        overview = it.overview,
                        imageUrl = it.fullPosterUrl,
                        backdropUrl = it.fullBackdropUrl,
                        badge = badge,
                        detailTarget = DetailTarget.AniListMediaTarget(id),
                    )
                } ?: toExploreMediaCard(badge)
            }

            else -> toExploreMediaCard(badge)
        }
    }

    private suspend fun discoverNetworkGroups(filterHorrorContent: Boolean): List<ExploreMediaCard> =
        discoverGroups(
            groups = CuratedNetworks,
            badge = "Network",
            maxGroups = CuratedNetworks.size,
            filterHorrorContent = filterHorrorContent,
        ) { group ->
            tmdbService.discoverByNetwork(group.id).orEmptyList()
        }

    private suspend fun discoverGenreGroups(filterHorrorContent: Boolean): List<ExploreMediaCard> =
        discoverGroups(
            groups = CuratedGenres.filterNot { filterHorrorContent && it.id == HorrorGenreId },
            badge = "Category",
            maxGroups = 6,
            filterHorrorContent = filterHorrorContent,
        ) { group ->
            tmdbService.discoverByGenre(group.id).orEmptyList()
        }

    private suspend fun discoverCompanyGroups(filterHorrorContent: Boolean): List<ExploreMediaCard> =
        discoverGroups(
            groups = CuratedCompanies,
            badge = "Company",
            maxGroups = 4,
            filterHorrorContent = filterHorrorContent,
        ) { group ->
            tmdbService.discoverByCompany(group.id).orEmptyList()
        }

    private suspend fun discoverFeaturedGroup(filterHorrorContent: Boolean): ExploreMediaCard? {
        val genre = CuratedGenres
            .filterNot { filterHorrorContent && it.id == HorrorGenreId }
            .randomOrNull()
            ?: return null
        val children = tmdbService.discoverByGenre(genre.id, mediaType = "tv")
            .orEmptyList()
            .toDiscoverChildren(
                badge = "Featured",
                filterHorrorContent = filterHorrorContent,
            )
        return genre.toDiscoverGroupCard(
            badge = "Featured",
            children = children,
            title = "Popular ${genre.name}",
        )
    }

    private suspend fun discoverGroups(
        groups: List<CuratedDiscoveryGroup>,
        badge: String,
        maxGroups: Int,
        filterHorrorContent: Boolean,
        load: suspend (CuratedDiscoveryGroup) -> List<TMDBSearchResult>,
    ): List<ExploreMediaCard> = coroutineScope {
        groups
            .map { group ->
                async {
                    val children = load(group).toDiscoverChildren(
                        badge = badge,
                        filterHorrorContent = filterHorrorContent,
                    )
                    group.toDiscoverGroupCard(badge = badge, children = children)
                }
            }
            .awaitAll()
            .filterNotNull()
            .take(maxGroups)
    }

    private fun List<TMDBSearchResult>.toDiscoverChildren(
        badge: String,
        filterHorrorContent: Boolean,
    ): List<ExploreMediaCard> =
        withoutFilteredHorror(filterHorrorContent)
            .filter { it.isMovie || it.isTVShow }
            .take(12)
            .map { it.toExploreMediaCard(badge) }
}

private fun MediaCarouselSection.forCatalog(catalog: BackupCatalog): MediaCarouselSection = copy(
    id = "catalog-${catalog.id}",
    title = catalog.displayName,
    subtitle = when (catalog.displayStyle) {
        "network" -> subtitle ?: "Network browse"
        "genre" -> subtitle ?: "Genre browse"
        "company" -> subtitle ?: "Company browse"
        "ranked" -> subtitle ?: "Ranked list"
        "featured" -> subtitle ?: "Featured picks"
        else -> subtitle
    },
)

private fun List<MediaCarouselSection>.heroCandidatesFor(catalogId: String): List<ExploreMediaCard> {
    val normalized = catalogId.trim().ifBlank { "trending" }
    val sectionIds = when (normalized) {
        "continueWatching" -> listOf("local-continue-watching")
        "forYou" -> listOf("local-for-you")
        "becauseYouWatched" -> listOf("local-because-you-watched")
        else -> listOf("catalog-$normalized", normalized)
    }
    return firstOrNull { section -> section.id in sectionIds }
        ?.items
        .orEmpty()
}

private fun List<TMDBSearchResult>.withoutFilteredHorror(enabled: Boolean): List<TMDBSearchResult> =
    if (enabled) {
        filterNot { result -> HorrorGenreId in result.genreIds }
    } else {
        this
    }

private data class CuratedDiscoveryGroup(
    val id: Int,
    val name: String,
)

private fun CuratedDiscoveryGroup.toDiscoverGroupCard(
    badge: String,
    children: List<ExploreMediaCard>,
    title: String = name,
): ExploreMediaCard? {
    val first = children.firstOrNull() ?: return null
    return ExploreMediaCard(
        id = "${badge.lowercase()}-$id",
        title = title,
        subtitle = "${children.size} ${badge.lowercase()} pick${if (children.size == 1) "" else "s"}",
        overview = first.overview,
        imageUrl = first.imageUrl,
        backdropUrl = first.backdropUrl ?: first.imageUrl,
        badge = badge,
        detailTarget = first.detailTarget,
        children = children,
    )
}

private val CuratedNetworks = listOf(
    CuratedDiscoveryGroup(213, "Netflix"),
    CuratedDiscoveryGroup(2739, "Disney+"),
    CuratedDiscoveryGroup(49, "HBO"),
    CuratedDiscoveryGroup(1024, "Amazon"),
    CuratedDiscoveryGroup(2552, "Apple TV+"),
    CuratedDiscoveryGroup(453, "Hulu"),
    CuratedDiscoveryGroup(4330, "Paramount+"),
    CuratedDiscoveryGroup(1112, "Crunchyroll"),
)

private val CuratedCompanies = listOf(
    CuratedDiscoveryGroup(33, "Universal"),
    CuratedDiscoveryGroup(4, "Paramount"),
    CuratedDiscoveryGroup(174, "Warner Bros."),
    CuratedDiscoveryGroup(25, "20th Century"),
    CuratedDiscoveryGroup(2, "Walt Disney"),
    CuratedDiscoveryGroup(41077, "A24"),
    CuratedDiscoveryGroup(1632, "Lionsgate"),
    CuratedDiscoveryGroup(5, "Columbia"),
)

private val CuratedGenres = listOf(
    CuratedDiscoveryGroup(28, "Action"),
    CuratedDiscoveryGroup(35, "Comedy"),
    CuratedDiscoveryGroup(18, "Drama"),
    CuratedDiscoveryGroup(878, "Sci-Fi"),
    CuratedDiscoveryGroup(10749, "Romance"),
    CuratedDiscoveryGroup(16, "Animation"),
    CuratedDiscoveryGroup(10751, "Family"),
    CuratedDiscoveryGroup(53, "Thriller"),
    CuratedDiscoveryGroup(27, "Horror"),
    CuratedDiscoveryGroup(99, "Documentary"),
)

