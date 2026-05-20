//
//  HomeViewModel.swift
//  Luna
//
//  Created by Soupy-dev
//

import Foundation
import SwiftUI

final class HomeViewModel: ObservableObject {
    @Published var catalogResults: [String: [TMDBSearchResult]] = [:]
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var heroContent: TMDBSearchResult?
    @Published var ambientColor: Color = Color.black
    @Published var hasLoadedContent = false
    @Published var widgetData: [String: [TMDBSearchResult]] = [:]
    @Published var becauseYouWatchedTitle: String = ""
    private var heroCarouselItems: [TMDBSearchResult] = []
    private var heroCarouselIndex = 0
    private var heroLaunchSelectionCatalogId: String?
    
    init() {
        // Init body can be simplified if needed
    }
    
    func loadContent(
        tmdbService: TMDBService,
        catalogManager: CatalogManager,
        contentFilter: TMDBContentFilter
    ) {
        // Don't reload if we already have content
        guard !hasLoadedContent else {
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            async let trending: [TMDBSearchResult] = self.loadHomeCatalog("trending") {
                try await tmdbService.getTrending()
            }
            async let popularM: [TMDBMovie] = self.loadHomeCatalog("popularMovies") {
                try await tmdbService.getPopularMovies()
            }
            async let nowPlayingM: [TMDBMovie] = self.loadHomeCatalog("nowPlayingMovies") {
                try await tmdbService.getNowPlayingMovies()
            }
            async let upcomingM: [TMDBMovie] = self.loadHomeCatalog("upcomingMovies") {
                try await tmdbService.getUpcomingMovies()
            }
            async let popularTV: [TMDBTVShow] = self.loadHomeCatalog("popularTVShows") {
                try await tmdbService.getPopularTVShows()
            }
            async let onTheAirTV: [TMDBTVShow] = self.loadHomeCatalog("onTheAirTV") {
                try await tmdbService.getOnTheAirTVShows()
            }
            async let airingTodayTV: [TMDBTVShow] = self.loadHomeCatalog("airingTodayTV") {
                try await tmdbService.getAiringTodayTVShows()
            }
            async let topRatedTV: [TMDBTVShow] = self.loadHomeCatalog("topRatedTVShows") {
                try await tmdbService.getTopRatedTVShows()
            }
            async let topRatedM: [TMDBMovie] = self.loadHomeCatalog("topRatedMovies") {
                try await tmdbService.getTopRatedMovies()
            }

            let tmdbResults = await (
                trending, popularM, nowPlayingM, upcomingM, popularTV, onTheAirTV,
                airingTodayTV, topRatedTV, topRatedM
            )

            // Fetch all anime catalogs in a single AniList query (1 API call instead of 5)
            let animeCatalogs = await self.loadAnimeCatalogs(tmdbService: tmdbService)
            let trendingAnime = animeCatalogs[.trending] ?? []
            let popularAnime = animeCatalogs[.popular] ?? []
            let topRatedAnime = animeCatalogs[.topRated] ?? []
            let airingAnime = animeCatalogs[.airing] ?? []
            let upcomingAnime = animeCatalogs[.upcoming] ?? []

            let loadedCatalogs: [String: [TMDBSearchResult]] = [
                "trending": tmdbResults.0,
                "popularMovies": tmdbResults.1.map { self.movieSearchResult($0) },
                "nowPlayingMovies": tmdbResults.2.map { self.movieSearchResult($0) },
                "upcomingMovies": tmdbResults.3.map { self.movieSearchResult($0) },
                "popularTVShows": tmdbResults.4.map { self.tvSearchResult($0) },
                "onTheAirTV": tmdbResults.5.map { self.tvSearchResult($0) },
                "airingTodayTV": tmdbResults.6.map { self.tvSearchResult($0) },
                "topRatedTVShows": tmdbResults.7.map { self.tvSearchResult($0) },
                "topRatedMovies": tmdbResults.8.map { self.movieSearchResult($0) },
                "trendingAnime": trendingAnime,
                "popularAnime": popularAnime,
                "topRatedAnime": topRatedAnime,
                "airingAnime": airingAnime,
                "upcomingAnime": upcomingAnime
            ]
            let loadedCatalogCount = loadedCatalogs.values.filter { !$0.isEmpty }.count

            await MainActor.run {
                self.catalogResults = loadedCatalogs
                self.applyHeroBannerSelection()
                self.isLoading = false
                self.hasLoadedContent = loadedCatalogCount > 0
                self.errorMessage = loadedCatalogCount == 0
                    ? "Unable to load home catalogs. Check your internet connection and API configuration, then try again."
                    : nil
            }

            guard loadedCatalogCount > 0 else { return }

            // Generate "Just For You" recommendations after catalogs are populated
            let currentResults = await MainActor.run { self.catalogResults }
            let forYou = await RecommendationEngine.shared.generateRecommendations(
                catalogResults: currentResults,
                tmdbService: tmdbService
            )
            if !forYou.isEmpty {
                await MainActor.run {
                    self.catalogResults["forYou"] = forYou
                    self.applyHeroBannerSelection()
                }
            }

            // Generate "Because you watched X" catalog
            let (bywTitle, bywResults) = await RecommendationEngine.shared.generateBecauseYouWatched(
                tmdbService: tmdbService
            )
            if !bywResults.isEmpty {
                await MainActor.run {
                    self.catalogResults["becauseYouWatched"] = bywResults
                    self.becauseYouWatchedTitle = bywTitle
                    self.applyHeroBannerSelection()
                }
            }

            // Load widget data in secondary pass (non-blocking, progressive)
            self.loadWidgetData(tmdbService: tmdbService, catalogManager: catalogManager)
        }
    }

    private func loadHomeCatalog<T>(_ id: String, fetch: () async throws -> [T]) async -> [T] {
        do {
            let items = try await fetch()
            Logger.shared.log("HomeViewModel: catalog \(id) loaded count=\(items.count)", type: "TMDB")
            return items
        } catch {
            Logger.shared.log("HomeViewModel: catalog \(id) failed: \(error.localizedDescription)", type: "Error")
            return []
        }
    }

    private func loadAnimeCatalogs(tmdbService: TMDBService) async -> [AniListService.AniListCatalogKind: [TMDBSearchResult]] {
        do {
            let catalogs = try await AniListService.shared.fetchAllAnimeCatalogs(tmdbService: tmdbService)
            let loadedSummary = catalogs
                .map { "\(String(describing: $0.key))=\($0.value.count)" }
                .sorted()
                .joined(separator: ",")
            Logger.shared.log("HomeViewModel: anime catalogs loaded \(loadedSummary)", type: "AniList")
            return catalogs
        } catch {
            Logger.shared.log("HomeViewModel: anime catalogs failed: \(error.localizedDescription)", type: "Error")
            return [:]
        }
    }

    private func movieSearchResult(_ movie: TMDBMovie) -> TMDBSearchResult {
        TMDBSearchResult(
            id: movie.id,
            mediaType: "movie",
            title: movie.title,
            name: nil,
            overview: movie.overview,
            posterPath: movie.posterPath,
            backdropPath: movie.backdropPath,
            releaseDate: movie.releaseDate,
            firstAirDate: nil,
            voteAverage: movie.voteAverage,
            popularity: movie.popularity,
            adult: movie.adult,
            genreIds: movie.genreIds
        )
    }

    private func tvSearchResult(_ show: TMDBTVShow) -> TMDBSearchResult {
        TMDBSearchResult(
            id: show.id,
            mediaType: "tv",
            title: nil,
            name: show.name,
            overview: show.overview,
            posterPath: show.posterPath,
            backdropPath: show.backdropPath,
            releaseDate: nil,
            firstAirDate: show.firstAirDate,
            voteAverage: show.voteAverage,
            popularity: show.popularity,
            adult: nil,
            genreIds: show.genreIds
        )
    }

    
    func loadWidgetData(
        tmdbService: TMDBService,
        catalogManager: CatalogManager
    ) {
        let enabledCatalogs = catalogManager.getEnabledCatalogs()
        
        Task {
            // Ranked lists reuse existing catalog data — zero extra API calls
            let rankedMappings: [(catalogId: String, sourceKey: String)] = [
                ("bestTVShows", "topRatedTVShows"),
                ("bestMovies", "topRatedMovies"),
                ("bestAnime", "topRatedAnime")
            ]
            let currentResults = await MainActor.run { self.catalogResults }
            for mapping in rankedMappings {
                if enabledCatalogs.contains(where: { $0.id == mapping.catalogId }),
                   let items = currentResults[mapping.sourceKey], !items.isEmpty {
                    await MainActor.run {
                        self.widgetData[mapping.catalogId] = items
                        self.applyHeroBannerSelection()
                    }
                }
            }
            
            // Networks — parallel discover calls
            if enabledCatalogs.contains(where: { $0.id == "networks" }) {
                await withTaskGroup(of: (Int, [TMDBSearchResult]).self) { group in
                    for network in WidgetNetwork.curated {
                        group.addTask {
                            let results = (try? await tmdbService.discoverByNetwork(networkId: network.id)) ?? []
                            return (network.id, results)
                        }
                    }
                    for await (networkId, results) in group {
                        if !results.isEmpty {
                            await MainActor.run {
                                self.widgetData["network_\(networkId)"] = results
                                self.applyHeroBannerSelection()
                            }
                        }
                    }
                }
            }
            
            // Genres — parallel discover calls
            if enabledCatalogs.contains(where: { $0.id == "genres" }) {
                await withTaskGroup(of: (Int, [TMDBSearchResult]).self) { group in
                    for genre in WidgetGenre.curated {
                        group.addTask {
                            let results = (try? await tmdbService.discoverByGenre(genreId: genre.id)) ?? []
                            return (genre.id, results)
                        }
                    }
                    for await (genreId, results) in group {
                        if !results.isEmpty {
                            await MainActor.run {
                                self.widgetData["genre_\(genreId)"] = results
                                self.applyHeroBannerSelection()
                            }
                        }
                    }
                }
            }
            
            // Companies — parallel discover calls
            if enabledCatalogs.contains(where: { $0.id == "companies" }) {
                await withTaskGroup(of: (Int, [TMDBSearchResult]).self) { group in
                    for company in WidgetCompany.curated {
                        group.addTask {
                            let results = (try? await tmdbService.discoverByCompany(companyId: company.id)) ?? []
                            return (company.id, results)
                        }
                    }
                    for await (companyId, results) in group {
                        if !results.isEmpty {
                            await MainActor.run {
                                self.widgetData["company_\(companyId)"] = results
                                self.applyHeroBannerSelection()
                            }
                        }
                    }
                }
            }
            
            // Featured — pick a random popular genre
            if enabledCatalogs.contains(where: { $0.id == "featured" }) {
                let randomGenre = WidgetGenre.curated.randomElement() ?? WidgetGenre.curated[0]
                let results = (try? await tmdbService.discoverByGenre(genreId: randomGenre.id, mediaType: "tv")) ?? []
                if !results.isEmpty {
                    await MainActor.run {
                        self.widgetData["featured"] = results
                        self.widgetData["featured_genreName"] = [] // Store genre name via key convention
                        self.applyHeroBannerSelection()
                    }
                    // Store the genre name for display
                    await MainActor.run {
                        self.featuredGenreName = randomGenre.name
                    }
                }
            }
        }
    }
    
    @Published var featuredGenreName: String = ""

    func refreshHeroContentForSettingsChange() {
        applyHeroBannerSelection()
    }

    func advanceHeroCarouselIfNeeded() {
        let behaviorRaw = UserDefaults.standard.string(forKey: "heroBannerBehavior") ?? HeroBannerBehavior.static.rawValue
        guard HeroBannerBehavior(rawValue: behaviorRaw) == .carousel else { return }
        guard heroCarouselItems.count > 1 else { return }
        heroCarouselIndex = (heroCarouselIndex + 1) % heroCarouselItems.count
        heroContent = heroCarouselItems[heroCarouselIndex]
    }

    private func applyHeroBannerSelection() {
        let catalogId = UserDefaults.standard.string(forKey: "heroBannerCatalogId") ?? "trending"
        let behaviorRaw = UserDefaults.standard.string(forKey: "heroBannerBehavior") ?? HeroBannerBehavior.static.rawValue
        let behavior = HeroBannerBehavior(rawValue: behaviorRaw) ?? .static
        let candidates = heroCandidates(for: catalogId)

        guard !candidates.isEmpty else { return }

        heroCarouselItems = candidates
        switch behavior {
        case .static:
            heroLaunchSelectionCatalogId = nil
            heroCarouselIndex = 0
            heroContent = candidates.first
        case .carousel:
            heroLaunchSelectionCatalogId = nil
            if let current = heroContent,
               let currentIndex = candidates.firstIndex(where: { $0.stableIdentity == current.stableIdentity }) {
                heroCarouselIndex = currentIndex
            } else {
                heroCarouselIndex = 0
                heroContent = candidates.first
            }
        case .launch:
            if heroLaunchSelectionCatalogId == catalogId,
               let current = heroContent,
               let currentIndex = candidates.firstIndex(where: { $0.stableIdentity == current.stableIdentity }) {
                heroCarouselIndex = currentIndex
                return
            }
            let selectedIndex = candidates.indices.randomElement() ?? candidates.startIndex
            heroLaunchSelectionCatalogId = catalogId
            heroCarouselIndex = selectedIndex
            heroContent = candidates[selectedIndex]
        }
    }

    private func heroCandidates(for catalogId: String) -> [TMDBSearchResult] {
        if let items = catalogResults[catalogId], !items.isEmpty {
            return items
        }

        if let items = widgetData[catalogId], !items.isEmpty {
            return items
        }

        if catalogId == "networks" {
            let items = WidgetNetwork.curated.flatMap { widgetData["network_\($0.id)"] ?? [] }
            if !items.isEmpty { return items }
        }

        if catalogId == "genres" {
            let items = WidgetGenre.curated.flatMap { widgetData["genre_\($0.id)"] ?? [] }
            if !items.isEmpty { return items }
        }

        if catalogId == "companies" {
            let items = WidgetCompany.curated.flatMap { widgetData["company_\($0.id)"] ?? [] }
            if !items.isEmpty { return items }
        }

        return catalogResults["trending"] ?? []
    }
    
    func resetContent() {
        catalogResults = [:]
        widgetData = [:]
        isLoading = true
        errorMessage = nil
        heroContent = nil
        heroLaunchSelectionCatalogId = nil
        hasLoadedContent = false
        featuredGenreName = ""
        becauseYouWatchedTitle = ""
        RecommendationEngine.shared.invalidateCache()
    }
}
