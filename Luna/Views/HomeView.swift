//
//  HomeView.swift
//  Sora

import SwiftUI
import Kingfisher
import AVKit

func homeImageDecodeSize(width: CGFloat, height: CGFloat) -> CGSize {
#if os(iOS) || os(tvOS)
    let scale = UIScreen.main.scale
#else
    let scale: CGFloat = 2
#endif
    return CGSize(width: max(width * scale, 1), height: max(height * scale, 1))
}

struct HomeView: View {
    private let onStartupReady: () -> Void
    @State private var showingSettings = false
    @State private var isHoveringWatchNow = false
    @State private var isHoveringWatchlist = false
    @State private var continueWatchingItems: [ContinueWatchingItem] = []
    @State private var continueWatchingRefreshID = UUID()
    @State private var didReportStartupReady = false
    @ObservedObject private var libraryManager = LibraryManager.shared
    @ObservedObject private var trackerManager = TrackerManager.shared
    @State private var scrollOffset: CGFloat = 0
    
    @AppStorage("tmdbLanguage") private var selectedLanguage = "en-US"
    
    @StateObject private var homeViewModel = HomeViewModel()
    @StateObject private var catalogManager = CatalogManager.shared
    @StateObject private var tmdbService = TMDBService.shared
    @StateObject private var contentFilter = TMDBContentFilter.shared
    @ObservedObject private var theme = LunaTheme.shared
    @AppStorage("heroBannerCatalogId") private var heroBannerCatalogId = "trending"
    @AppStorage("heroBannerBehavior") private var heroBannerBehavior = HeroBannerBehavior.static.rawValue

    private let heroCarouselTimer = Timer.publish(every: 12, on: .main, in: .common).autoconnect()

    init(onStartupReady: @escaping () -> Void = {}) {
        self.onStartupReady = onStartupReady
    }
    
    private var enabledCatalogs: [Catalog] {
        return catalogManager.getEnabledCatalogs()
    }
    
    private var heroHeight: CGFloat {
#if os(tvOS)
        UIScreen.main.bounds.height * 0.8
#else
        isIPad ? 720 : 580
#endif
    }

    private var ambientColor: Color { homeViewModel.ambientColor }
    private var atmosphereColor: Color { theme.atmosphereColor(dominant: ambientColor) }

    private var tracksBackgroundScroll: Bool {
#if os(iOS)
        !isIPad
#else
        true
#endif
    }

    private var backgroundScrollOffset: CGFloat {
        tracksBackgroundScroll ? scrollOffset : 0
    }

    private var scrollOffsetUpdateThreshold: CGFloat {
        8
    }
    
    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                homeContent
            }
        } else {
            NavigationView {
                homeContent
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }
    
    private var homeContent: some View {
        ZStack {
            GlobalGradientBackground(scrollOffset: backgroundScrollOffset)
                .ignoresSafeArea(.all)
            
            Group {
                theme.atmosphereStyle == .solid ? atmosphereColor : homeViewModel.ambientColor
            }
            .ignoresSafeArea(.all)
            
            if homeViewModel.isLoading {
                loadingView
            } else if let errorMessage = homeViewModel.errorMessage {
                errorView(errorMessage)
            } else {
                mainScrollView
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            refreshContinueWatchingItems()
            if homeViewModel.hasCompletedInitialLoad {
                reportStartupReadyIfNeeded()
            }
            if !homeViewModel.hasLoadedContent {
                homeViewModel.loadContent(tmdbService: tmdbService, catalogManager: catalogManager, contentFilter: contentFilter)
            }
        }
        .onChange(of: homeViewModel.hasCompletedInitialLoad) { hasCompletedInitialLoad in
            if hasCompletedInitialLoad {
                reportStartupReadyIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshContinueWatchingItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerDidClose)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                refreshContinueWatchingItems()
            }
        }
        .onChangeComp(of: trackerManager.trackerState.mergeTraktContinueWatching) { _, _ in
            refreshContinueWatchingItems()
        }
        .onChangeComp(of: contentFilter.filterHorror) { _, _ in
            if homeViewModel.hasLoadedContent {
                homeViewModel.loadContent(tmdbService: tmdbService, catalogManager: catalogManager, contentFilter: contentFilter)
            }
        }
        .onChangeComp(of: heroBannerCatalogId) { _, _ in
            homeViewModel.refreshHeroContentForSettingsChange()
        }
        .onChangeComp(of: heroBannerBehavior) { _, _ in
            homeViewModel.refreshHeroContentForSettingsChange()
        }
        .onReceive(heroCarouselTimer) { _ in
            homeViewModel.advanceHeroCarouselIfNeeded()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
    
    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading amazing content...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Connection Error")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Retry") {
                loadContent()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var mainScrollView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                heroSection
                continueWatchingSection
                contentSections
            }
            .background(
                Group {
                    if tracksBackgroundScroll {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: -geo.frame(in: .named("homeScroll")).origin.y
                            )
                        }
                    }
                }
            )
        }
        .coordinateSpace(name: "homeScroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { newOffset in
            guard tracksBackgroundScroll else { return }
            guard abs(scrollOffset - newOffset) >= scrollOffsetUpdateThreshold else { return }
            scrollOffset = newOffset
        }
        .ignoresSafeArea(edges: [.top, .leading, .trailing])
    }

    @ViewBuilder
    private var continueWatchingSection: some View {
        if !continueWatchingItems.isEmpty {
            ContinueWatchingSection(
                items: continueWatchingItems,
                tmdbService: tmdbService,
                onDataChanged: refreshContinueWatchingItems
            )
        }
    }

    
    @ViewBuilder
    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            StretchyHeaderView(
                backdropURL: homeViewModel.heroContent?.fullBackdropURL ?? homeViewModel.heroContent?.fullPosterURL,
                isMovie: homeViewModel.heroContent?.mediaType == "movie",
                headerHeight: heroHeight,
                minHeaderHeight: 300,
                onAmbientColorExtracted: { color in
                    homeViewModel.ambientColor = color
                }
            )
            
            heroGradientOverlay
            heroContentInfo
        }
    }
    
    @ViewBuilder
    private var heroGradientOverlay: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: ambientColor.opacity(0.0), location: 0.0),
                .init(color: atmosphereColor.opacity(theme.atmosphereStyle == .solid ? 0.5 : 0.4), location: 0.2),
                .init(color: atmosphereColor.opacity(theme.atmosphereStyle == .solid ? 0.8 : 0.7), location: 0.6),
                .init(color: atmosphereColor.opacity(1), location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }
    
    @ViewBuilder
    private var heroContentInfo: some View {
        if let hero = homeViewModel.heroContent {
            VStack(alignment: .center, spacing: isTvOS ? 30 : 12) {
                HStack {
                    Text(hero.isMovie ? "Movie" : "TV Series")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, isTvOS ? 16 : 8)
                        .padding(.vertical, isTvOS ? 10 : 4)
                        .applyLiquidGlassBackground(cornerRadius: 12)
                    
                    if (hero.voteAverage ?? 0.0) > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            
                            Text(String(format: "%.1f", hero.voteAverage ?? 0.0))
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, isTvOS ? 16 : 8)
                        .padding(.vertical, isTvOS ? 10 : 4)
                        .applyLiquidGlassBackground(cornerRadius: 12)
                    }
                }
                
                heroTitleText(hero)
                
                if let overview = hero.overview, !overview.isEmpty {
                    Text(String(overview.prefix(100)) + (overview.count > 100 ? "..." : ""))
                        .font(.system(size: isTvOS ? 30 : 15))
                        .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                
                HStack(spacing: 16) {
                    NavigationLink(destination: MediaDetailView(searchResult: hero)) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.subheadline)
                            Text("Watch Now")
                                .fontWeight(.semibold)
                                .fixedSize()
                                .lineLimit(1)
                        }
                        .foregroundColor(isHoveringWatchNow ? .black : .white)
                        .tvos({ view in
                            view.frame(width: 200, height: 60)
                                .buttonStyle(PlainButtonStyle())
#if os(tvOS)
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(_): isHoveringWatchNow = true
                                    case .ended: isHoveringWatchNow = false
                                    }
                                }
#endif
                        }, else: { view in
                            view
                                .frame(width: 140, height: 42)
                                .buttonStyle(PlainButtonStyle())
                                .applyLiquidGlassBackground(cornerRadius: 12)
                        })
                    }
                    
                    Button(action: {
                        if let hero = homeViewModel.heroContent {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                libraryManager.toggleBookmark(for: hero)
                            }
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: libraryManager.isBookmarked(hero) ? "checkmark" : "plus")
                                .font(.subheadline)
                            Text(libraryManager.isBookmarked(hero) ? "In Watchlist" : "Watchlist")
                                .fontWeight(.semibold)
                                .fixedSize()
                                .lineLimit(1)
                        }
                        .foregroundColor(isHoveringWatchlist ? .black : .white)
                        .tvos({ view in
                            view.frame(width: 200, height: 60)
                                .buttonStyle(PlainButtonStyle())
#if os(tvOS)
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(_): isHoveringWatchlist = true
                                    case .ended: isHoveringWatchlist = false
                                    }
                                }
#endif
                        }, else: { view in
                            view.frame(width: 140, height: 42)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.black.opacity(0.3))
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(.white.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        })
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private func heroTitleText(_ hero: TMDBSearchResult) -> some View {
        Text(hero.displayTitle)
            .font(.system(size: isTvOS ? 40 : 25))
            .fontWeight(.bold)
            .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
            .foregroundColor(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }
    
    @ViewBuilder
    private var contentSections: some View {
        LazyVStack(spacing: 0) {
            let catalogs = enabledCatalogs.filter { catalog in
                switch catalog.displayStyle {
                case .standard:
                    if let items = homeViewModel.catalogResults[catalog.id], !items.isEmpty {
                        return true
                    }
                    return false
                case .network:
                    return WidgetNetwork.curated.contains { !( homeViewModel.widgetData["network_\($0.id)"] ?? []).isEmpty }
                case .genre:
                    return WidgetGenre.curated.contains { !(homeViewModel.widgetData["genre_\($0.id)"] ?? []).isEmpty }
                case .company:
                    return WidgetCompany.curated.contains { !(homeViewModel.widgetData["company_\($0.id)"] ?? []).isEmpty }
                case .ranked:
                    if let items = homeViewModel.widgetData[catalog.id], !items.isEmpty { return true }
                    if let items = homeViewModel.catalogResults[catalog.id], !items.isEmpty { return true }
                    return false
                case .featured:
                    return !(homeViewModel.widgetData["featured"] ?? []).isEmpty
                }
            }
            
            ForEach(Array(catalogs.enumerated()), id: \.element.id) { index, catalog in
                switch catalog.displayStyle {
                case .standard:
                    if let items = homeViewModel.catalogResults[catalog.id], !items.isEmpty {
                        let limitedItems = Array(items.prefix(15))
                        let displayItems = catalog.id == "trending"
                            ? limitedItems.filter { $0.stableIdentity != homeViewModel.heroContent?.stableIdentity }
                            : limitedItems
                        
                        let displayTitle: String = {
                            if catalog.id == "becauseYouWatched" && !homeViewModel.becauseYouWatchedTitle.isEmpty {
                                return "Because You Watched \(homeViewModel.becauseYouWatchedTitle)"
                            }
                            return catalog.name
                        }()
                        
                        MediaSection(
                            title: displayTitle,
                            items: displayItems
                        )
                    }
                    
                case .network:
                    NetworkSectionWidget(
                        widgetData: homeViewModel.widgetData,
                        tmdbService: tmdbService
                    )
                    
                case .genre:
                    GenreSectionWidget(
                        widgetData: homeViewModel.widgetData,
                        tmdbService: tmdbService
                    )
                    
                case .company:
                    CompanySectionWidget(
                        widgetData: homeViewModel.widgetData,
                        tmdbService: tmdbService
                    )
                    
                case .ranked:
                    let items = homeViewModel.widgetData[catalog.id]
                        ?? homeViewModel.catalogResults[catalog.id]
                        ?? []
                    RankedListWidget(
                        catalogId: catalog.id,
                        title: catalog.name,
                        items: Array(items.prefix(10)),
                        tmdbService: tmdbService
                    )
                    
                case .featured:
                    FeaturedSpotlightWidget(
                        widgetData: homeViewModel.widgetData,
                        genreName: homeViewModel.featuredGenreName,
                        tmdbService: tmdbService
                    )
                }
                
                if index < catalogs.count - 1 {
                    SectionDivider()
                }
            }
            
            Spacer(minLength: 50)
        }
        .background(
            Group {
                if theme.atmosphereStyle == .solid {
                    atmosphereColor
                } else {
                    LinearGradient(
                        colors: [ambientColor, Color.clear, LunaTheme.shared.backgroundBase],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.3)
                    )
                }
            }
        )
    }
    
    private func loadContent() {
        homeViewModel.loadContent(
            tmdbService: tmdbService,
            catalogManager: catalogManager,
            contentFilter: contentFilter
        )
    }

    private func refreshContinueWatchingItems() {
        let refreshID = UUID()
        continueWatchingRefreshID = refreshID
        let localItems = ProgressManager.shared.getContinueWatchingItems()
        continueWatchingItems = localItems

        Task { @MainActor in
            async let traktItems = trackerManager.fetchTraktContinueWatchingItems()
            async let watchNextItems = resolveWatchNextItems()
            let mergedItems = mergeContinueWatchingItems(
                localItems: localItems,
                traktItems: await traktItems,
                watchNextItems: await watchNextItems
            )
            guard continueWatchingRefreshID == refreshID else { return }
            continueWatchingItems = mergedItems
        }
    }

    private func resolveWatchNextItems() async -> [ContinueWatchingItem] {
        var items: [ContinueWatchingItem] = []
        for candidate in ProgressManager.shared.getWatchNextCandidates().prefix(10) {
            if let item = await resolveWatchNextItem(candidate) {
                items.append(item)
            }
        }
        return items
    }

    private func resolveWatchNextItem(_ candidate: WatchNextCandidate) async -> ContinueWatchingItem? {
        if let playbackContext = candidate.playbackContext,
           playbackContext.hasAnimeMediaId {
            guard !playbackContext.isSpecial,
                  let episodeCount = playbackContext.animeSeasonEpisodeCount,
                  candidate.episodeNumber < episodeCount else {
                return nil
            }
            return makeWatchNextItem(
                candidate: candidate,
                seasonNumber: candidate.seasonNumber,
                episodeNumber: candidate.episodeNumber + 1,
                playbackContext: playbackContext.forEpisodeNumber(candidate.episodeNumber + 1)
            )
        }

        do {
            let season = try await tmdbService.getSeasonDetails(
                tvShowId: candidate.tmdbId,
                seasonNumber: candidate.seasonNumber
            )
            if let nextEpisode = season.episodes
                .filter({ $0.episodeNumber > candidate.episodeNumber && episodeHasAired($0) })
                .min(by: { $0.episodeNumber < $1.episodeNumber }) {
                return makeWatchNextItem(
                    candidate: candidate,
                    seasonNumber: nextEpisode.seasonNumber,
                    episodeNumber: nextEpisode.episodeNumber,
                    playbackContext: candidate.playbackContext?.forEpisodeNumber(nextEpisode.episodeNumber)
                )
            }

            let show = try await tmdbService.getTVShowWithSeasons(id: candidate.tmdbId)
            for nextSeason in show.seasons
                .filter({ $0.seasonNumber > candidate.seasonNumber && $0.seasonNumber > 0 && $0.episodeCount > 0 })
                .sorted(by: { $0.seasonNumber < $1.seasonNumber }) {
                let season = try await tmdbService.getSeasonDetails(
                    tvShowId: candidate.tmdbId,
                    seasonNumber: nextSeason.seasonNumber
                )
                if let firstEpisode = season.episodes
                    .filter({ episodeHasAired($0) })
                    .min(by: { $0.episodeNumber < $1.episodeNumber }) {
                    return makeWatchNextItem(
                        candidate: candidate,
                        seasonNumber: firstEpisode.seasonNumber,
                        episodeNumber: firstEpisode.episodeNumber,
                        playbackContext: nil
                    )
                }
            }
        } catch {
            Logger.shared.log("HomeView: Watch Next lookup failed for TMDB \(candidate.tmdbId): \(error.localizedDescription)", type: "TMDB")
        }

        return nil
    }

    private func makeWatchNextItem(
        candidate: WatchNextCandidate,
        seasonNumber: Int,
        episodeNumber: Int,
        playbackContext: EpisodePlaybackContext?
    ) -> ContinueWatchingItem {
        ContinueWatchingItem(
            id: "watch_next_\(candidate.tmdbId)_s\(seasonNumber)_e\(episodeNumber)",
            tmdbId: candidate.tmdbId,
            isMovie: false,
            title: candidate.title,
            posterURL: candidate.posterURL,
            progress: 0,
            lastUpdated: candidate.lastUpdated,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            currentTime: 0,
            totalDuration: 1,
            playbackContext: playbackContext,
            isAnime: candidate.isAnime,
            statusText: "Watch next",
            isWatchNext: true,
            traktPlaybackId: nil
        )
    }

    private func episodeHasAired(_ episode: TMDBEpisode) -> Bool {
        guard let airDate = episode.airDate,
              let parsedDate = Self.tmdbDateFormatter.date(from: airDate) else {
            return true
        }
        return parsedDate <= Date()
    }

    private func mergeContinueWatchingItems(
        localItems: [ContinueWatchingItem],
        traktItems: [ContinueWatchingItem],
        watchNextItems: [ContinueWatchingItem],
        limit: Int = 10
    ) -> [ContinueWatchingItem] {
        var itemByMediaKey: [String: ContinueWatchingItem] = [:]

        for item in watchNextItems + localItems + traktItems {
            let key = "\(item.isMovie ? "movie" : "show")|\(item.tmdbId)"
            guard let existing = itemByMediaKey[key] else {
                itemByMediaKey[key] = item
                continue
            }

            if existing.isWatchNext != item.isWatchNext {
                if existing.isWatchNext {
                    itemByMediaKey[key] = item
                }
            } else if item.lastUpdated > existing.lastUpdated {
                itemByMediaKey[key] = item
            }
        }

        return itemByMediaKey.values
            .sorted { $0.lastUpdated > $1.lastUpdated }
            .prefix(limit)
            .map { $0 }
    }

    private static let tmdbDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func reportStartupReadyIfNeeded() {
        guard !didReportStartupReady else { return }
        didReportStartupReady = true
        onStartupReady()
    }

}

struct MediaSection: View {
    let title: String
    let items: [TMDBSearchResult]
    
    var gap: Double { isTvOS ? 50.0 : (isIPad ? 28.0 : 20.0) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(isTvOS ? .headline : .title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, isTvOS ? 40 : 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: gap) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        MediaCard(
                            result: item,
                            heroID: "home-\(title)-\(index)-\(item.stableIdentity)"
                        )
                    }
                }
                .padding(.horizontal, isTvOS ? 40 : 16)
            }
            .modifier(ScrollClipModifier())
            .buttonStyle(.borderless)
        }
        .padding(.top, isTvOS ? 40 : 24)
        .opacity(items.isEmpty ? 0 : 1)
    }
}

struct ScrollClipModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.scrollClipDisabled()
        } else {
            content
        }
    }
}

struct SectionDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            line
            Image(systemName: "sparkle")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.2))
            line
        }
        .padding(.horizontal, 60)
        .padding(.top, 28)
        .padding(.bottom, 4)
    }
    
    private var line: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.12), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.5)
    }
}

struct MediaCard: View {
    let result: TMDBSearchResult
    let heroID: String
    @State private var isHovering: Bool = false
    @Environment(\.heroNamespace) private var heroNamespace

    private var posterWidth: CGFloat { isTvOS ? 280 : 120 * iPadScale }
    private var posterHeight: CGFloat { isTvOS ? 380 : 180 * iPadScale }
    private var posterShadowRadius: CGFloat { isIPad ? 4 : 8 }
    
    var body: some View {
        NavigationLink(destination: MediaDetailView(searchResult: result)
            .heroDestination(id: heroID, namespace: heroNamespace)
        ) {
            VStack(alignment: .leading, spacing: 6) {
                KFImage(URL(string: result.fullPosterURL ?? ""))
                    .setProcessor(DownsamplingImageProcessor(size: homeImageDecodeSize(width: posterWidth, height: posterHeight)))
                    .placeholder {
                        FallbackImageView(
                            isMovie: result.isMovie,
                            size: CGSize(width: posterWidth, height: posterHeight)
                        )
                    }
                    .resizable()
                    .aspectRatio(2/3, contentMode: .fill)
                    .tvos({ view in
                        view
                            .frame(width: posterWidth, height: posterHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .hoverEffect(.highlight)
                            .modifier(ContinuousHoverModifier(isHovering: $isHovering))
                            .padding(.vertical, 30)
                    }, else: { view in
                        view
                            .frame(width: posterWidth, height: posterHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.25), radius: posterShadowRadius, x: 0, y: 4)
                    })
                    .heroSource(id: heroID, namespace: heroNamespace)
                
                VStack(alignment: .leading, spacing: isTvOS ? 10 : 3) {
                    Text(result.displayTitle)
                        .tvos({ view in
                            view
                                .foregroundColor(isHovering ? .white : .secondary)
                                .fontWeight(.semibold)
                        }, else: { view in
                            view
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                        })
                        .font(.caption)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack(alignment: .center, spacing: isTvOS ? 18 : 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            
                            Text(String(format: "%.1f", result.voteAverage ?? 0.0))
                                .font(.caption2)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .fixedSize()
                        }
                            .padding(.horizontal, isTvOS ? 16 : 8)
                            .padding(.vertical, isTvOS ? 10 : 4)
                            .applyLiquidGlassBackground(cornerRadius: 12)

                        Spacer()

                        Text(result.isMovie ? "Movie" : "TV")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, isTvOS ? 16 : 8)
                            .padding(.vertical, isTvOS ? 10 : 4)
                            .applyLiquidGlassBackground(cornerRadius: 12)
                    }
                }
                .frame(width: posterWidth, alignment: .leading)
            }
        }
        .tvos({ view in
            view.buttonStyle(BorderlessButtonStyle())
        }, else: { view in
            view.buttonStyle(PlainButtonStyle())
        })
    }
}

struct ContinueWatchingSection: View {
    let items: [ContinueWatchingItem]
    let tmdbService: TMDBService
    let onDataChanged: () -> Void

    private var gap: Double { isTvOS ? 50.0 : (isIPad ? 24.0 : 16.0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Continue Watching")
                    .font(isTvOS ? .headline : .title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.horizontal, isTvOS ? 40 : 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: gap) {
                    ForEach(items) { item in
                        ContinueWatchingCard(item: item, tmdbService: tmdbService, onDataChanged: onDataChanged)
                    }
                }
                .padding(.horizontal, isTvOS ? 40 : 16)
            }
            .modifier(ScrollClipModifier())
            .buttonStyle(.borderless)
        }
        .padding(.top, isTvOS ? 40 : 24)
    }
}

struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem
    let tmdbService: TMDBService
    let onDataChanged: () -> Void

    @AppStorage("tmdbLanguage") private var selectedLanguage = "en-US"

    @State private var backdropURL: String?
    @State private var logoURL: String?
    @State private var title: String = ""
    @State private var isHovering = false
    @State private var isLoaded = false
    @State private var showingSearchResults = false
    @State private var showingDetails = false

    // Anime metadata resolved from TMDB + AniList (mirrors MediaDetailView logic)
    @State private var isAnimeContent = false
    @State private var animeSeasonTitle: String? = nil
    @State private var animeSeasonRomajiTitle: String? = nil
    @State private var originalTitle: String? = nil
    @State private var isMetadataReady = false
    @State private var pendingOpenSheet = false
    @State private var imdbId: String? = nil
    @State private var enrichedPlaybackContext: EpisodePlaybackContext? = nil

    private var cardWidth: CGFloat { isTvOS ? 380 : (isIPad ? 360 : 260) }
    private var cardHeight: CGFloat { isTvOS ? 220 : (isIPad ? 200 : 146) }
    private var logoMaxWidth: CGFloat { isTvOS ? 200 : (isIPad ? 180 : 140) }
    private var logoMaxHeight: CGFloat { isTvOS ? 60 : (isIPad ? 52 : 40) }
    private var backdropDecodeSize: CGSize { homeImageDecodeSize(width: cardWidth, height: cardHeight) }
    private var logoDecodeSize: CGSize { homeImageDecodeSize(width: logoMaxWidth, height: logoMaxHeight) }
    private var cardShadowRadius: CGFloat { isIPad ? (isHovering ? 8 : 5) : (isHovering ? 12 : 8) }
    private var cardShadowYOffset: CGFloat { isIPad ? (isHovering ? 5 : 3) : (isHovering ? 8 : 4) }

    private var displayTitle: String {
        title.isEmpty ? item.title : title
    }

    private var searchSheetIsAnime: Bool {
        let playbackContext = enrichedPlaybackContext ?? item.playbackContext
        return isAnimeContent ||
            item.isAnime ||
            playbackContext?.hasAnimeMediaId == true
    }

    /// Title to pass to the search sheet – uses the AniList season title for anime, matching MediaDetailView's logic
    private var searchSheetTitle: String {
        if searchSheetIsAnime, !item.isMovie,
           let seasonTitle = animeSeasonTitle {
            return seasonTitle
        }
        return displayTitle
    }

    private var selectedEpisodeForSearch: TMDBEpisode? {
        guard !item.isMovie,
              let seasonNumber = item.seasonNumber,
              let episodeNumber = item.episodeNumber else {
            return nil
        }

        return TMDBEpisode(
            id: Int("\(item.tmdbId)\(seasonNumber)\(episodeNumber)") ?? item.tmdbId,
            name: "",
            overview: nil,
            stillPath: nil,
            episodeNumber: episodeNumber,
            seasonNumber: seasonNumber,
            airDate: nil,
            runtime: nil,
            voteAverage: 0,
            voteCount: 0
        )
    }

    private var selectedEpisodePlaybackContext: EpisodePlaybackContext? {
        let baseContext = enrichedPlaybackContext ?? item.playbackContext
        guard let episode = selectedEpisodeForSearch else { return baseContext }
        return baseContext?.forEpisodeNumber(episode.episodeNumber)
    }

    private var detailSearchResult: TMDBSearchResult {
        TMDBSearchResult(
            id: item.tmdbId,
            mediaType: item.isMovie ? "movie" : "tv",
            title: item.isMovie ? displayTitle : nil,
            name: item.isMovie ? nil : displayTitle,
            overview: nil,
            posterPath: nil,
            backdropPath: nil,
            releaseDate: nil,
            firstAirDate: nil,
            voteAverage: nil,
            popularity: 0,
            adult: nil,
            genreIds: nil
        )
    }

    var body: some View {
        Button {
            if isMetadataReady {
                showingSearchResults = true
            } else {
                pendingOpenSheet = true
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    if let backdropURL {
                        KFImage(URL(string: backdropURL))
                            .setProcessor(DownsamplingImageProcessor(size: backdropDecodeSize))
                            .placeholder { backdropPlaceholder }
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        backdropPlaceholder
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipped()

                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.3), location: 0.4),
                        .init(color: .black.opacity(0.85), location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: isTvOS ? 10 : 6) {
                    Spacer()

                    HStack(alignment: .bottom, spacing: isTvOS ? 12 : 8) {
                        if let logoURL {
                            KFImage(URL(string: logoURL))
                                .setProcessor(DownsamplingImageProcessor(size: logoDecodeSize))
                                .placeholder { titleText }
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: logoMaxWidth, maxHeight: logoMaxHeight, alignment: .leading)
                        } else {
                            titleText
                        }

                        Spacer()

                        if !item.isMovie, let season = item.seasonNumber, let episode = item.episodeNumber {
                            Text("S\(season) E\(episode)")
                                .font(isTvOS ? .subheadline : .caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }

                    HStack(spacing: isTvOS ? 12 : 8) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.3))
                                    .frame(height: isTvOS ? 6 : 4)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white)
                                    .frame(width: geometry.size.width * item.progress, height: isTvOS ? 6 : 4)
                            }
                        }
                        .frame(height: isTvOS ? 6 : 4)

                        Text(item.displayStatus)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))
                            .fixedSize()
                    }
                }
                .padding(isTvOS ? 16 : 12)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(isHovering ? 0.5 : 0.15), lineWidth: isHovering ? 2 : 0.5)
            )
            .shadow(color: .black.opacity(0.35), radius: cardShadowRadius, x: 0, y: cardShadowYOffset)
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            .modifier(ContinuousHoverModifier(isHovering: $isHovering))
        }
        .tvos({ view in
            view.buttonStyle(BorderlessButtonStyle())
        }, else: { view in
            view.buttonStyle(PlainButtonStyle())
        })
        .task {
            await loadMediaDetails()
        }
        .sheet(isPresented: $showingSearchResults) {
            ModulesSearchResultsSheet(
                mediaTitle: searchSheetTitle,
                seasonTitleOverride: searchSheetIsAnime ? animeSeasonTitle : nil,
                originalTitle: searchSheetIsAnime ? (animeSeasonRomajiTitle ?? originalTitle) : originalTitle,
                isMovie: item.isMovie,
                isAnimeContent: searchSheetIsAnime,
                selectedEpisode: selectedEpisodeForSearch,
                tmdbId: item.tmdbId,
                animeSeasonTitle: searchSheetIsAnime ? "anime" : nil,
                posterPath: item.posterURL,
                imdbId: imdbId,
                originalTMDBSeasonNumber: selectedEpisodePlaybackContext?.resolvedTMDBSeasonNumber,
                originalTMDBEpisodeNumber: selectedEpisodePlaybackContext?.resolvedTMDBEpisodeNumber,
                episodePlaybackContext: selectedEpisodePlaybackContext,
                autoModeOnly: UserDefaults.standard.bool(forKey: "servicesAutoModeEnabled"),
                onResolvedPlaybackRequest: { request in
                    Task { @MainActor in
                        self.presentResolvedPlayback(request)
                    }
                }
            )
        }
        .contextMenu {
            Button {
                showingDetails = true
            } label: {
                Label("Details", systemImage: "info.circle")
            }

            Button {
                markAsWatched()
            } label: {
                Label("Mark as Watched", systemImage: "checkmark.circle")
            }

            if !item.isWatchNext {
                Button(role: .destructive) {
                    removeFromContinueWatching()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
        .background(
            NavigationLink(destination: MediaDetailView(searchResult: detailSearchResult), isActive: $showingDetails) {
                EmptyView()
            }
            .hidden()
        )
    }

    @ViewBuilder
    private var titleText: some View {
        Text(displayTitle)
            .font(isTvOS ? .title3 : .subheadline)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    private var backdropPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: item.isMovie ? "film" : "tv")
                    .font(isTvOS ? .largeTitle : .title)
                    .foregroundColor(.gray.opacity(0.5))
            )
    }

    private func loadMediaDetails() async {
        guard !isLoaded else { return }

        do {
            if item.isMovie {
                async let detailsTask = tmdbService.getMovieDetails(id: item.tmdbId)
                async let imagesTask = tmdbService.getMovieImages(id: item.tmdbId, preferredLanguage: selectedLanguage)
                async let romajiTask = tmdbService.getRomajiTitle(for: "movie", id: item.tmdbId)

                let (details, images, romaji) = try await (detailsTask, imagesTask, romajiTask)

                await MainActor.run {
                    self.title = details.title
                    self.backdropURL = details.fullBackdropURL ?? details.fullPosterURL ?? item.posterURL
                    if let logo = tmdbService.getBestLogo(from: images, preferredLanguage: selectedLanguage) {
                        self.logoURL = logo.fullURL
                    }
                    self.originalTitle = romaji
                    self.animeSeasonRomajiTitle = nil
                    self.enrichedPlaybackContext = nil
                    self.imdbId = details.imdbId
                    self.isAnimeContent = false
                    self.isLoaded = true
                    self.isMetadataReady = true
                    if self.pendingOpenSheet {
                        self.pendingOpenSheet = false
                        self.showingSearchResults = true
                    }
                }
            } else {
                // Fetch TMDB details, images, and romaji title in parallel
                async let detailsTask = tmdbService.getTVShowDetails(id: item.tmdbId)
                async let imagesTask = tmdbService.getTVShowImages(id: item.tmdbId, preferredLanguage: selectedLanguage)
                async let romajiTask = tmdbService.getRomajiTitle(for: "tv", id: item.tmdbId)
                async let episodeArtworkTask = resolveEpisodeArtworkURL()

                let (details, images, romaji, episodeArtworkURL) = try await (detailsTask, imagesTask, romajiTask, episodeArtworkTask)
                let showArtworkURL = details.fullBackdropURL ?? details.fullPosterURL ?? item.posterURL

                // Anime detection: same logic as MediaDetailView
                let isJapanese = details.originCountry?.contains("JP") ?? false
                let isAnimation = details.genres.contains { $0.id == 16 }
                let detectedAsAnime = item.isAnime ||
                    item.playbackContext?.hasAnimeMediaId == true ||
                    (isJapanese && isAnimation)

                // Set visual details immediately
                await MainActor.run {
                    self.title = details.name
                    self.backdropURL = episodeArtworkURL ?? showArtworkURL
                    if let logo = tmdbService.getBestLogo(from: images, preferredLanguage: selectedLanguage) {
                        self.logoURL = logo.fullURL
                    }
                    self.originalTitle = romaji
                    self.imdbId = details.externalIds?.imdbId
                    self.isLoaded = true
                }

                if detectedAsAnime {
                    // Fetch AniList data for correct season title mapping
                    do {
                        let animeData = try await AniListService.shared.fetchAnimeDetailsWithEpisodes(
                            title: details.name,
                            tmdbShowId: details.id,
                            tmdbService: tmdbService,
                            tmdbShowPoster: details.fullPosterURL,
                            token: nil
                        )
                        let animeEpisodeArtworkURL = resolveAnimeEpisodeArtworkURL(from: animeData)

                        // Register AniList season IDs for tracker sync (same as MediaDetailView)
                        let seasonMappings = animeData.seasons.map { (seasonNumber: $0.seasonNumber, anilistId: $0.anilistId) }
                        TrackerManager.shared.registerAniListAnimeData(tmdbId: details.id, seasons: seasonMappings)

                        // Find the season title for the episode the user was watching
                        let matchedSeason: AniListSeasonWithPoster? = {
                            if let anilistId = item.playbackContext?.anilistMediaId,
                               let season = animeData.seasons.first(where: { $0.anilistId == anilistId }) {
                                return season
                            }
                            if let kitsuId = item.playbackContext?.kitsuMediaId,
                               let season = animeData.seasons.first(where: { $0.kitsuId == kitsuId }) {
                                return season
                            }
                            guard let sn = item.seasonNumber else { return animeData.seasons.first }
                            return animeData.seasons.first(where: { $0.seasonNumber == sn })
                                ?? animeData.seasons.first
                        }()

                        let matchedSeasonTitle: String? = {
                            matchedSeason?.title
                        }()

                        let matchedSeasonRomajiTitle: String? = {
                            matchedSeason?.romajiTitle
                        }()

                        let updatedPlaybackContext = item.playbackContext?.withKitsuMediaId(matchedSeason?.kitsuId)

                        await MainActor.run {
                            self.isAnimeContent = true
                            self.animeSeasonTitle = matchedSeasonTitle
                            self.animeSeasonRomajiTitle = matchedSeasonRomajiTitle
                            self.enrichedPlaybackContext = updatedPlaybackContext
                            self.backdropURL = animeEpisodeArtworkURL ?? episodeArtworkURL ?? showArtworkURL
                            self.isMetadataReady = true
                            if self.pendingOpenSheet {
                                self.pendingOpenSheet = false
                                self.showingSearchResults = true
                            }
                        }

                        Logger.shared.log("ContinueWatchingCard: Resolved anime metadata for \(details.name), seasonTitle=\(matchedSeasonTitle ?? "nil")", type: "AniList")
                    } catch {
                        // AniList fetch failed – still mark as anime but without season title
                        Logger.shared.log("ContinueWatchingCard: AniList fetch failed for \(details.name): \(error.localizedDescription)", type: "AniList")
                        await MainActor.run {
                            self.isAnimeContent = true
                            self.animeSeasonRomajiTitle = nil
                            self.enrichedPlaybackContext = item.playbackContext
                            self.isMetadataReady = true
                            if self.pendingOpenSheet {
                                self.pendingOpenSheet = false
                                self.showingSearchResults = true
                            }
                        }
                    }
                } else {
                    // Not anime – metadata is ready
                    await MainActor.run {
                        self.isAnimeContent = false
                        self.animeSeasonRomajiTitle = nil
                        self.enrichedPlaybackContext = nil
                        self.isMetadataReady = true
                        if self.pendingOpenSheet {
                            self.pendingOpenSheet = false
                            self.showingSearchResults = true
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                if self.title.isEmpty {
                    self.title = item.title
                }
                self.backdropURL = item.posterURL
                self.animeSeasonRomajiTitle = nil
                self.enrichedPlaybackContext = nil
                self.isLoaded = true
                self.isMetadataReady = true
                if self.pendingOpenSheet {
                    self.pendingOpenSheet = false
                    self.showingSearchResults = true
                }
            }
        }
    }

    private func resolveEpisodeArtworkURL() async -> String? {
        guard !item.isMovie else { return nil }
        let seasonNumber = item.playbackContext?.resolvedTMDBSeasonNumber ?? item.seasonNumber
        let episodeNumber = item.playbackContext?.resolvedTMDBEpisodeNumber ?? item.episodeNumber
        guard let seasonNumber, let episodeNumber else { return nil }

        do {
            let detail = try await tmdbService.getSeasonDetails(tvShowId: item.tmdbId, seasonNumber: seasonNumber)
            return detail.episodes.first(where: { $0.episodeNumber == episodeNumber })?.fullStillURL
                ?? detail.fullPosterURL
        } catch {
            Logger.shared.log("ContinueWatchingCard: Episode artwork fetch failed showId=\(item.tmdbId) season=\(seasonNumber) episode=\(episodeNumber): \(error.localizedDescription)", type: "TMDB")
            return nil
        }
    }

    private func resolveAnimeEpisodeArtworkURL(from animeData: AniListAnimeWithSeasons) -> String? {
        guard let localSeasonNumber = item.seasonNumber,
              let localEpisodeNumber = item.episodeNumber else {
            return nil
        }

        let season = item.playbackContext.flatMap { context in
            if let anilistId = context.anilistMediaId,
               let season = animeData.seasons.first(where: { $0.anilistId == anilistId }) {
                return season
            }
            if let kitsuId = context.kitsuMediaId,
               let season = animeData.seasons.first(where: { $0.kitsuId == kitsuId }) {
                return season
            }
            return nil
        }
            ?? animeData.seasons.first(where: { $0.seasonNumber == localSeasonNumber })
            ?? animeData.seasons.first
        let episode = season?.episodes.first(where: { $0.number == localEpisodeNumber })
        return fullImageURL(from: episode?.stillPath)
            ?? season?.posterUrl
    }

    private func fullImageURL(from path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return path }
        return "\(TMDBService.tmdbImageBaseURL)\(path)"
    }

    @MainActor
    private func presentResolvedPlayback(_ request: PlayerResolvedPlaybackRequest) {
        showingSearchResults = false

        dismissContinueWatchingSheetAndPresent(request)
    }

    @MainActor
    private func dismissContinueWatchingSheetAndPresent(_ request: PlayerResolvedPlaybackRequest, attempt: Int = 0) {
        guard let presenter = rootPresentationController() else {
            Logger.shared.log("ContinueWatchingCard: unable to present resolved playback; no presenter", type: "Player")
            return
        }

        if let presented = presenter.presentedViewController, attempt < 3 {
            Logger.shared.log("ContinueWatchingCard: dismissing services sheet before resolved playback attempt=\(attempt) presented=\(type(of: presented))", type: "Player")
            presenter.dismiss(animated: true) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    Task { @MainActor in
                        self.dismissContinueWatchingSheetAndPresent(request, attempt: attempt + 1)
                    }
                }
            }
            return
        }

        presentResolvedPlaybackAfterSheetDismissal(request, presenter: presenter)
    }

    @MainActor
    private func presentResolvedPlaybackAfterSheetDismissal(_ request: PlayerResolvedPlaybackRequest, presenter: UIViewController) {
        let externalRaw = UserDefaults.standard.string(forKey: "externalPlayer") ?? ExternalPlayer.none.rawValue
        let external = ExternalPlayer(rawValue: externalRaw) ?? .none
        if let scheme = external.schemeURL(for: request.url.absoluteString),
           UIApplication.shared.canOpenURL(scheme) {
            UIApplication.shared.open(scheme, options: [:], completionHandler: nil)
            Logger.shared.log("ContinueWatchingCard: opening resolved playback in external player", type: "Player")
            return
        }

        let inAppRaw = UserDefaults.standard.string(forKey: "inAppPlayer") ?? "VLC"
        if inAppRaw == "mpv" || inAppRaw == "VLC" {
            let pvc = PlayerViewController(
                url: request.url,
                preset: request.preset,
                headers: request.headers,
                subtitles: request.subtitles,
                subtitleNames: request.subtitleNames,
                mediaInfo: request.mediaInfo,
                imdbId: request.imdbId
            )
            pvc.isAnimeHint = request.isAnimeHint
            pvc.originalTMDBSeasonNumber = request.originalTMDBSeasonNumber
            pvc.originalTMDBEpisodeNumber = request.originalTMDBEpisodeNumber
            pvc.episodePlaybackContext = request.episodePlaybackContext
            pvc.playbackLaunchContext = request.launchContext
            pvc.modalPresentationStyle = .fullScreen
            if !item.isMovie {
                pvc.onRequestNextEpisode = { seasonNumber, nextEpisodeNumber in
                    NotificationCenter.default.post(
                        name: .requestNextEpisode,
                        object: nil,
                        userInfo: [
                            "tmdbId": item.tmdbId,
                            "seasonNumber": seasonNumber,
                            "episodeNumber": nextEpisodeNumber
                        ]
                    )
                }
            }

            Logger.shared.log("ContinueWatchingCard: presenting resolved \(inAppRaw) playback from stable presenter", type: "Player")
            presenter.present(pvc, animated: true, completion: nil)
            return
        }

        let assetOptions: [String: Any]? = {
            guard let headers = request.headers, !headers.isEmpty else { return nil }
            return ["AVURLAssetHTTPHeaderFieldsKey": headers]
        }()
        let asset = AVURLAsset(url: request.url, options: assetOptions)
        let playerVC = NormalPlayer()
        playerVC.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        playerVC.mediaInfo = request.mediaInfo
        playerVC.episodePlaybackContext = request.episodePlaybackContext
        playerVC.playbackLaunchContext = request.launchContext
        playerVC.modalPresentationStyle = .fullScreen

        Logger.shared.log("ContinueWatchingCard: presenting resolved AVPlayer playback from stable presenter", type: "Player")
        presenter.present(playerVC, animated: true) {
            playerVC.playAtDefaultSpeed()
        }
    }

    @MainActor
    private func rootPresentationController() -> UIViewController? {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = windowScene?.windows.first { $0.isKeyWindow } ?? windowScene?.windows.first
        return window?.rootViewController
    }

    private func markAsWatched() {
        ProgressManager.shared.markContinueWatchingItemAsWatched(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onDataChanged()
        }
    }

    private func removeFromContinueWatching() {
        if let traktPlaybackId = item.traktPlaybackId {
            TrackerManager.shared.removeTraktContinueWatchingItem(traktPlaybackId) {
                onDataChanged()
            }
            return
        } else {
            ProgressManager.shared.removeContinueWatchingItem(item)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onDataChanged()
        }
    }
}

struct ContinuousHoverModifier: ViewModifier {
    @Binding var isHovering: Bool
    
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .onContinuousHover { phase in
                    switch phase {
                    case .active(_):
                        isHovering = true
                    case .ended:
                        isHovering = false
                    }
                }
        } else {
            content
        }
    }
}
