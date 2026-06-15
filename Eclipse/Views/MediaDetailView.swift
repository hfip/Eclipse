//
//  MediaDetailView.swift
//  Sora
//
//  Created by Francesco on 07/08/25.
//

import SwiftUI
import Kingfisher
import AVKit

// MARK: - View-Level Detail Cache
// Stores the fully-loaded state for a media detail screen so back-navigation is instant.
private final class MediaDetailCacheStore {
    static let shared = MediaDetailCacheStore()
    
    struct CachedDetail {
        let movieDetail: TMDBMovieDetail?
        let tvShowDetail: TMDBTVShowWithSeasons?
        let selectedSeason: TMDBSeason?
        let synopsis: String
        let romajiTitle: String?
        let logoURL: String?
        let isAnimeShow: Bool
        let animeRating: AnimeMetadataRating?
        let anilistEpisodes: [AniListEpisode]?
        let animeSeasonTitles: [Int: String]?
        let animeSeasonRomajiTitles: [Int: String]
        let animeSeasonAniListIds: [Int: Int]
        let animeSeasonKitsuIds: [Int: Int]
        let animeSpecialEntries: [AniListSpecialSearchEntry]
        let castMembers: [TMDBCastMember]
        let timestamp: Date
    }
    
    private var cache: [String: CachedDetail] = [:]
    private let lock = NSLock()
    private let ttl: TimeInterval = 300 // 5 minutes
    
    func get(key: String) -> CachedDetail? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cache[key],
              Date().timeIntervalSince(entry.timestamp) < ttl else {
            return nil
        }
        return entry
    }
    
    func set(key: String, detail: CachedDetail) {
        lock.lock()
        defer { lock.unlock() }
        cache[key] = detail
        // Evict old entries if cache grows too large
        if cache.count > 50 {
            let cutoff = Date().addingTimeInterval(-ttl)
            cache = cache.filter { $0.value.timestamp > cutoff }
        }
    }

    func updateSpecialEntries(key: String, entries: [AniListSpecialSearchEntry]) {
        lock.lock()
        defer { lock.unlock() }
        guard let existing = cache[key] else { return }
        cache[key] = CachedDetail(
            movieDetail: existing.movieDetail,
            tvShowDetail: existing.tvShowDetail,
            selectedSeason: existing.selectedSeason,
            synopsis: existing.synopsis,
            romajiTitle: existing.romajiTitle,
            logoURL: existing.logoURL,
            isAnimeShow: existing.isAnimeShow,
            animeRating: existing.animeRating,
            anilistEpisodes: existing.anilistEpisodes,
            animeSeasonTitles: existing.animeSeasonTitles,
            animeSeasonRomajiTitles: existing.animeSeasonRomajiTitles,
            animeSeasonAniListIds: existing.animeSeasonAniListIds,
            animeSeasonKitsuIds: existing.animeSeasonKitsuIds,
            animeSpecialEntries: entries,
            castMembers: existing.castMembers,
            timestamp: Date()
        )
    }
}

struct MediaDetailView: View {
    let searchResult: TMDBSearchResult
    
    @StateObject private var tmdbService = TMDBService.shared
    @StateObject private var trackerManager = TrackerManager.shared
    @State private var movieDetail: TMDBMovieDetail?
    @State private var tvShowDetail: TMDBTVShowWithSeasons?
    @State private var selectedSeason: TMDBSeason?
    @State private var seasonDetail: TMDBSeasonDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var ambientColor: Color = Color.black
    @State private var scrollOffset: CGFloat = 0
    @State private var showFullSynopsis: Bool = false
    @State private var synopsis: String = ""
    @State private var isBookmarked: Bool = false
    @State private var showingSearchResults = false
    @State private var showingDownloadSheet = false
    @State private var showingAddToCollection = false
    @State private var selectedEpisodeForSearch: TMDBEpisode?
    @State private var romajiTitle: String?
    @State private var logoURL: String?
    @State private var isAnimeShow = false
    @State private var animeRating: AnimeMetadataRating?
    @State private var anilistEpisodes: [AniListEpisode]? = nil
    @State private var animeSeasonTitles: [Int: String]? = nil
    @State private var animeSeasonRomajiTitles: [Int: String] = [:]
    @State private var animeSeasonAniListIds: [Int: Int] = [:]
    @State private var animeSeasonKitsuIds: [Int: Int] = [:]
    @State private var animeSpecialEntries: [AniListSpecialSearchEntry] = []
    @State private var isLoadingAnimeSpecials = false
    @State private var selectedSpecialEpisodeContext: SpecialEpisodeListContext?
    @State private var specialSearchRequest: AnimeSpecialSearchRequest?
    @State private var nextEpisodePresentationToken = 0
    @State private var playSheetRequestId = UUID()
    
    @State private var castMembers: [TMDBCastMember] = []
    @State private var detailStills: [TMDBImage] = []
    @State private var detailTrailers: [TMDBVideo] = []
    @State private var isLoadingExperimentalExtras = false
    @State private var traktComments: [TraktCommentReview] = []
    @State private var traktRating: TraktMediaRating?
    @State private var isLoadingTraktComments = false
    @State private var hasLoadedContent = false
    @State private var detailLoadTask: Task<Void, Never>?
    @State private var specialsLoadTask: Task<Void, Never>?
    @State private var traktFeatureLoadTask: Task<Void, Never>?
    @State private var experimentalExtrasLoadTask: Task<Void, Never>?
    @State private var specialsLoadGeneration = 0
    @State private var detailContentRefreshTick = 0
    
    @StateObject private var serviceManager = ServiceManager.shared
    @StateObject private var stremioManager = StremioAddonManager.shared
    @StateObject private var pluginManager = NuvioPluginManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var libraryManager = LibraryManager.shared
    @ObservedObject private var theme = EclipseTheme.shared
    private let progressManager = ProgressManager.shared
    
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("tmdbLanguage") private var selectedLanguage = "en-US"
    @AppStorage("mediaDetailElementOrder") private var mediaDetailElementOrder = MediaDetailElement.defaultOrderRawValue
    @AppStorage("mediaDetailHiddenElements") private var mediaDetailHiddenElements = ""
    @AppStorage("showCastSection") private var legacyShowCastSection = true
    @AppStorage("seasonMenu") private var useSeasonMenu = false
    @AppStorage(ExperimentalMediaDesignPreset.storageKey) private var experimentalDesignPreset = ExperimentalMediaDesignPreset.defaultValue.rawValue
    @AppStorage(ExperimentalHeroBleedLevel.storageKey) private var experimentalHeroBleedLevel = ExperimentalHeroBleedLevel.defaultValue.rawValue
    @AppStorage(ExperimentalHomeCardShape.storageKey) private var experimentalHomeCardShape = ExperimentalHomeCardShape.defaultValue.rawValue
    private let nextEpisodeSheetPresentationDelay: TimeInterval = 1.2

    private var atmosphereColor: Color {
        theme.atmosphereColor(dominant: ambientColor)
    }

    private var designMetrics: ExperimentalMediaDesignMetrics {
        ExperimentalMediaDesignMetrics(
            preset: ExperimentalMediaDesignPreset(rawValue: experimentalDesignPreset) ?? ExperimentalMediaDesignPreset.defaultValue,
            heroBleedLevel: ExperimentalHeroBleedLevel(rawValue: experimentalHeroBleedLevel) ?? ExperimentalHeroBleedLevel.defaultValue,
            cardShape: ExperimentalHomeCardShape(rawValue: experimentalHomeCardShape) ?? ExperimentalHomeCardShape.defaultValue
        )
    }

    private var backgroundScrollOffset: CGFloat {
#if os(iOS)
        isIPad ? 0 : scrollOffset
#else
        scrollOffset
#endif
    }

    private var scrollOffsetUpdateThreshold: CGFloat {
        ExperimentalFeatureState.isEnabledAtLaunch ? designMetrics.scrollOffsetThreshold : 8
    }

    private var hasActiveSources: Bool {
        !serviceManager.activeServices.isEmpty ||
        !stremioManager.activeAddons.isEmpty ||
        !pluginManager.activeSources(for: searchResult.isMovie ? "movie" : "tv").isEmpty
    }

    private var preferDownloadedMedia: Bool {
        UserDefaults.standard.bool(forKey: "preferDownloadedMedia")
    }

    private var visibleMediaDetailElements: [MediaDetailElement] {
        MediaDetailElement.orderedElements(from: mediaDetailElementOrder).filter { element in
            guard MediaDetailElement.isVisible(
                element,
                hiddenRawValue: mediaDetailHiddenElements,
                legacyShowCastSection: legacyShowCastSection
            ) else {
                return false
            }
            return searchResult.isMovie ? element.appliesToMovies : element.appliesToSeries
        }
    }

    private var experimentalHeroElements: Set<MediaDetailElement> {
        [.actions, .overview, .details]
    }

    private var visibleHeroElements: Set<MediaDetailElement> {
        Set(visibleMediaDetailElements)
    }

    private var visibleBodyMediaDetailElements: [MediaDetailElement] {
        guard ExperimentalFeatureState.isEnabledAtLaunch else {
            return visibleMediaDetailElements
        }
        return visibleMediaDetailElements.filter { !experimentalHeroElements.contains($0) }
    }

    private var shouldShowHeroActions: Bool {
        visibleHeroElements.contains(.actions)
    }

    private var shouldShowHeroOverview: Bool {
        visibleHeroElements.contains(.overview) && currentOverviewText != nil
    }

    private var shouldShowHeroDetails: Bool {
        visibleHeroElements.contains(.details)
    }

    private var hasPlayableDownloadForMainButton: Bool {
        guard preferDownloadedMedia else { return false }
        if searchResult.isMovie {
            return downloadManager.completedDownloadItem(tmdbId: searchResult.id, isMovie: true) != nil
        }
        return downloadManager.completedDownloads.contains {
            !$0.isMovie && $0.tmdbId == searchResult.id && downloadManager.localFileURL(for: $0) != nil
        }
    }

    private var canUseMainPlayButton: Bool {
        hasActiveSources || hasPlayableDownloadForMainButton
    }

    private var headerHeight: CGFloat {
#if os(tvOS)
        UIScreen.main.bounds.height * 0.8
#else
        if ExperimentalFeatureState.isEnabledAtLaunch {
            return designMetrics.detailHeroHeight(screenHeight: UIScreen.main.bounds.height, isIPad: isIPad)
        }
        return isIPad ? 720 : min(max(UIScreen.main.bounds.height * 0.76, 620), 780)
#endif
    }


    private var minHeaderHeight: CGFloat {
#if os(tvOS)
        UIScreen.main.bounds.height * 0.8
#else
        isIPad ? 520 : 420
#endif
    }

    private struct MainPlayEpisodeKey: Hashable {
        let seasonNumber: Int
        let episodeNumber: Int
    }

    private struct MainPlayEpisodeCandidate {
        let key: MainPlayEpisodeKey
        let episode: TMDBEpisode?
    }

    private var playButtonText: String {
        if searchResult.isMovie {
            return "Play"
        }

        if selectedSpecialEpisodeContext != nil, let selectedEpisode = selectedEpisodeForSearch {
            return "Play \(episodeLabel(seasonNumber: selectedEpisode.seasonNumber, episodeNumber: selectedEpisode.episodeNumber, forceEpisodeOnly: true))"
        }

        if let target = resolveMainPlayEpisodeTarget() {
            return "Play \(episodeLabel(seasonNumber: target.key.seasonNumber, episodeNumber: target.key.episodeNumber))"
        }

        if let selectedEpisode = selectedEpisodeForSearch {
            return "Play \(episodeLabel(seasonNumber: selectedEpisode.seasonNumber, episodeNumber: selectedEpisode.episodeNumber))"
        }

        return "Play"
    }

    private func episodeLabel(seasonNumber: Int, episodeNumber: Int, forceEpisodeOnly: Bool = false) -> String {
        if forceEpisodeOnly || isAnimeShow {
            return "E\(episodeNumber)"
        }
        return "S\(seasonNumber)E\(episodeNumber)"
    }
    
    var body: some View {
        let _ = Logger.shared.log("MediaDetailView body evaluate: id=\(searchResult.id) type=\(searchResult.mediaType) isLoading=\(isLoading) hasLoaded=\(hasLoadedContent) error=\(errorMessage != nil) movieDetail=\(movieDetail != nil) tvDetail=\(tvShowDetail != nil) selectedSeason=\(selectedSeason?.seasonNumber.description ?? "nil") seasonDetailEpisodes=\(seasonDetail?.episodes.count ?? 0) selectedEpisode=\(selectedEpisodeForSearch.map { "S\($0.seasonNumber)E\($0.episodeNumber)" } ?? "nil") sheets=play:\(showingSearchResults),download:\(showingDownloadSheet)", type: "CrashProbe")
        ZStack {
            EclipseTheme.shared.backgroundBase
                .ignoresSafeArea(.all)

            detailBackground
                .ignoresSafeArea(.all)

            if isLoading {
                let _ = Logger.shared.log("MediaDetailView body branch loading: id=\(searchResult.id)", type: "CrashProbe")
                loadingView
            } else if let errorMessage = errorMessage {
                let _ = Logger.shared.log("MediaDetailView body branch error: id=\(searchResult.id) message=\(errorMessage)", type: "CrashProbe")
                errorView(errorMessage)
            } else {
                let _ = Logger.shared.log("MediaDetailView body branch content: id=\(searchResult.id) isMovie=\(searchResult.isMovie)", type: "CrashProbe")
                mainScrollView
            }
#if !os(tvOS)
            navigationOverlay
#endif
        }
        .navigationBarHidden(true)
#if !os(tvOS)
        .simultaneousGesture(edgeBackSwipeGesture)
#else
        .onExitCommand {
            presentationMode.wrappedValue.dismiss()
        }
#endif
        .onAppear {
            Logger.shared.log("MediaDetailView onAppear: id=\(searchResult.id) hasLoaded=\(hasLoadedContent) isLoading=\(isLoading) taskActive=\(detailLoadTask != nil)", type: "CrashProbe")
            if !hasLoadedContent {
                loadMediaDetails()
            } else {
                Logger.shared.log("MediaDetailView onAppear using existing loaded state: id=\(searchResult.id) tvSeasons=\(tvShowDetail?.seasons.count ?? 0) selectedSeason=\(selectedSeason?.seasonNumber.description ?? "nil")", type: "CrashProbe")
                startTraktFeatureLoad()
                startExperimentalExtrasLoadIfNeeded()
            }
            updateBookmarkStatus()
        }
        .onDisappear {
            if let detailLoadTask {
                Logger.shared.log("MediaDetail load task cancelled on disappear: id=\(searchResult.id)", type: "CrashProbe")
                detailLoadTask.cancel()
                self.detailLoadTask = nil
            } else {
                Logger.shared.log("MediaDetailView onDisappear: id=\(searchResult.id) no active load task", type: "CrashProbe")
            }
            if let specialsLoadTask {
                Logger.shared.log("MediaDetail specials load task cancelled on disappear: id=\(searchResult.id)", type: "CrashProbe")
                specialsLoadTask.cancel()
                self.specialsLoadTask = nil
            }
            if let traktFeatureLoadTask {
                Logger.shared.log("MediaDetail Trakt feature load task cancelled on disappear: id=\(searchResult.id)", type: "Tracker")
                traktFeatureLoadTask.cancel()
                self.traktFeatureLoadTask = nil
            }
            if let experimentalExtrasLoadTask {
                Logger.shared.log("MediaDetail experimental extras task cancelled on disappear: id=\(searchResult.id)", type: "TMDB")
                experimentalExtrasLoadTask.cancel()
                self.experimentalExtrasLoadTask = nil
            }
            specialsLoadGeneration += 1
        }
        .onChange(of: trackerManager.trackerState.traktCommentsEnabled) { _ in
            if hasLoadedContent {
                startTraktFeatureLoad()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestNextEpisode)) { notification in
            Logger.shared.log("MediaDetailView nextEpisode notification received: id=\(searchResult.id) userInfo=\(notification.userInfo ?? [:])", type: "CrashProbe")
            guard let userInfo = notification.userInfo,
                  let tmdbId = userInfo["tmdbId"] as? Int,
                  tmdbId == searchResult.id,
                  let seasonNumber = userInfo["seasonNumber"] as? Int,
                  let episodeNumber = userInfo["episodeNumber"] as? Int else {
                Logger.shared.log("MediaDetailView nextEpisode ignored: id=\(searchResult.id) did not match/parse", type: "CrashProbe")
                return
            }

            if let specialContext = selectedSpecialEpisodeContext,
               let nextSpecialEpisode = specialContext.episodes.first(where: { $0.seasonNumber == seasonNumber && $0.episodeNumber == episodeNumber }) {
                Logger.shared.log("MediaDetailView nextEpisode matched special: id=\(searchResult.id) S\(seasonNumber)E\(episodeNumber) delay=\(nextEpisodeSheetPresentationDelay)", type: "CrashProbe")
                selectedEpisodeForSearch = nextSpecialEpisode
                scheduleNextEpisodePresentation {
                    beginSpecialSearch(context: specialContext, episode: nextSpecialEpisode)
                }
                return
            }

            // Find the next episode in the current season detail
            if let episodes = seasonDetail?.episodes,
               let nextEp = episodes.first(where: { $0.seasonNumber == seasonNumber && $0.episodeNumber == episodeNumber }) {
                Logger.shared.log("MediaDetailView nextEpisode matched: id=\(searchResult.id) S\(seasonNumber)E\(episodeNumber) delay=\(nextEpisodeSheetPresentationDelay)", type: "CrashProbe")
                selectedEpisodeForSearch = nextEp
                showingSearchResults = false
                scheduleNextEpisodePresentation {
                    Logger.shared.log("MediaDetailView nextEpisode presenting search sheet: id=\(searchResult.id) S\(seasonNumber)E\(episodeNumber)", type: "CrashProbe")
                    playSheetRequestId = UUID()
                    showingSearchResults = true
                }
            } else {
                Logger.shared.log("NextEpisode: Could not find S\(seasonNumber)E\(episodeNumber) in loaded season detail for tmdbId=\(tmdbId) loadedEpisodes=\(seasonDetail?.episodes.count ?? 0)", type: "Player")
            }
        }
        .onChangeComp(of: libraryManager.collections) { _, _ in
            Logger.shared.log("MediaDetailView collections changed: id=\(searchResult.id)", type: "CrashProbe")
            updateBookmarkStatus()
        }
        .onChangeComp(of: isLoading) { _, newValue in
            Logger.shared.log("MediaDetailView isLoading changed: id=\(searchResult.id) isLoading=\(newValue)", type: "CrashProbe")
        }
        .onChangeComp(of: hasLoadedContent) { _, newValue in
            Logger.shared.log("MediaDetailView hasLoadedContent changed: id=\(searchResult.id) hasLoaded=\(newValue)", type: "CrashProbe")
        }
        .onChangeComp(of: selectedSeason?.seasonNumber) { _, newValue in
            Logger.shared.log("MediaDetailView selectedSeason changed: id=\(searchResult.id) season=\(newValue?.description ?? "nil")", type: "CrashProbe")
        }
        .onChangeComp(of: seasonDetail?.episodes.count) { _, newValue in
            Logger.shared.log("MediaDetailView seasonDetail episode count changed: id=\(searchResult.id) count=\(newValue?.description ?? "nil")", type: "CrashProbe")
        }
        .onChangeComp(of: selectedEpisodeForSearch?.id) { _, _ in
            Logger.shared.log("MediaDetailView selectedEpisode changed: id=\(searchResult.id) episode=\(selectedEpisodeForSearch.map { "S\($0.seasonNumber)E\($0.episodeNumber):id\($0.id)" } ?? "nil")", type: "CrashProbe")
        }
        .onChangeComp(of: showingSearchResults) { _, newValue in
            Logger.shared.log("MediaDetailView showingSearchResults changed: id=\(searchResult.id) visible=\(newValue) episode=\(selectedEpisodeForSearch.map { "S\($0.seasonNumber)E\($0.episodeNumber)" } ?? "nil")", type: "CrashProbe")
            if !newValue {
                refreshDetailContentLayout(reason: "play sheet dismissed")
            }
        }
        .onChangeComp(of: showingDownloadSheet) { _, newValue in
            Logger.shared.log("MediaDetailView showingDownloadSheet changed: id=\(searchResult.id) visible=\(newValue) episode=\(selectedEpisodeForSearch.map { "S\($0.seasonNumber)E\($0.episodeNumber)" } ?? "nil")", type: "CrashProbe")
            if !newValue {
                refreshDetailContentLayout(reason: "download sheet dismissed")
            }
        }
        .onChangeComp(of: specialSearchRequest?.id) { _, newValue in
            if newValue == nil {
                refreshDetailContentLayout(reason: "special search sheet dismissed")
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                updateBookmarkStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerDidClose)) { notification in
            guard playerCloseNotificationMatchesDetail(notification) else { return }
            refreshDetailContentLayout(reason: "player closed")
        }
        .onDisappear {
            invalidatePendingNextEpisodePresentation()
        }
        .sheet(isPresented: $showingSearchResults) {
            let _ = Logger.shared.log("MediaDetailView constructing play sheet: id=\(searchResult.id) isAnime=\(isAnimeShow) selectedEpisode=\(selectedEpisodeForSearch.map { "S\($0.seasonNumber)E\($0.episodeNumber)" } ?? "nil") autoMode=\(UserDefaults.standard.bool(forKey: "servicesAutoModeEnabled"))", type: "CrashProbe")
            let playbackContext = playbackContextForSearchSheet(selectedEpisodeForSearch)
            ModulesSearchResultsSheet(
                mediaTitle: {
                    if isAnimeShow, let episode = selectedEpisodeForSearch,
                       let seasonTitle = animeSeasonTitles?[episode.seasonNumber] {
                        return seasonTitle
                    }
                    return searchResult.displayTitle
                }(),
                seasonTitleOverride: {
                    if isAnimeShow, let episode = selectedEpisodeForSearch,
                       let seasonTitle = animeSeasonTitles?[episode.seasonNumber] {
                        return seasonTitle
                    }
                    return nil
                }(),
                originalTitle: originalTitleForSearchSheet(selectedEpisodeForSearch),
                isMovie: searchResult.isMovie,
                isAnimeContent: isAnimeShow,
                selectedEpisode: selectedEpisodeForSearch,
                tmdbId: searchResult.id,
                animeSeasonTitle: isAnimeShow ? "anime" : nil,
                posterPath: searchResult.isMovie ? movieDetail?.posterPath : tvShowDetail?.posterPath,
                imdbId: searchResult.isMovie ? movieDetail?.imdbId : tvShowDetail?.externalIds?.imdbId,
                originalTMDBSeasonNumber: playbackContext?.resolvedTMDBSeasonNumber,
                originalTMDBEpisodeNumber: playbackContext?.resolvedTMDBEpisodeNumber,
                episodePlaybackContext: playbackContext,
                autoModeOnly: UserDefaults.standard.bool(forKey: "servicesAutoModeEnabled")
            )
            .id(playSheetRequestId)
        }
        .sheet(isPresented: $showingDownloadSheet) {
            let _ = Logger.shared.log("MediaDetailView constructing download sheet: id=\(searchResult.id) isAnime=\(isAnimeShow) selectedEpisode=\(selectedEpisodeForSearch.map { "S\($0.seasonNumber)E\($0.episodeNumber)" } ?? "nil") autoMode=\(UserDefaults.standard.bool(forKey: "servicesAutoModeEnabled"))", type: "CrashProbe")
            let playbackContext = playbackContextForSearchSheet(selectedEpisodeForSearch)
            ModulesSearchResultsSheet(
                mediaTitle: {
                    if isAnimeShow, let episode = selectedEpisodeForSearch,
                       let seasonTitle = animeSeasonTitles?[episode.seasonNumber] {
                        return seasonTitle
                    }
                    return searchResult.displayTitle
                }(),
                seasonTitleOverride: {
                    if isAnimeShow, let episode = selectedEpisodeForSearch,
                       let seasonTitle = animeSeasonTitles?[episode.seasonNumber] {
                        return seasonTitle
                    }
                    return nil
                }(),
                originalTitle: originalTitleForSearchSheet(selectedEpisodeForSearch),
                isMovie: searchResult.isMovie,
                isAnimeContent: isAnimeShow,
                selectedEpisode: selectedEpisodeForSearch,
                tmdbId: searchResult.id,
                animeSeasonTitle: isAnimeShow ? "anime" : nil,
                posterPath: searchResult.isMovie ? movieDetail?.posterPath : tvShowDetail?.posterPath,
                imdbId: searchResult.isMovie ? movieDetail?.imdbId : tvShowDetail?.externalIds?.imdbId,
                originalTMDBSeasonNumber: playbackContext?.resolvedTMDBSeasonNumber,
                originalTMDBEpisodeNumber: playbackContext?.resolvedTMDBEpisodeNumber,
                episodePlaybackContext: playbackContext,
                downloadMode: true,
                autoModeOnly: UserDefaults.standard.bool(forKey: "servicesAutoModeEnabled")
            )
        }
        .sheet(item: $specialSearchRequest) { request in
            ModulesSearchResultsSheet(
                mediaTitle: request.title,
                seasonTitleOverride: request.title,
                originalTitle: request.originalTitle,
                isMovie: false,
                isAnimeContent: true,
                selectedEpisode: request.episode,
                tmdbId: searchResult.id,
                animeSeasonTitle: request.title,
                posterPath: request.posterUrl ?? tvShowDetail?.posterPath,
                imdbId: request.imdbId ?? tvShowDetail?.externalIds?.imdbId,
                originalTMDBSeasonNumber: request.originalSeasonNumber,
                originalTMDBEpisodeNumber: request.originalEpisodeNumber,
                specialTitleOnlySearch: request.titleOnly,
                episodePlaybackContext: request.playbackContext,
                autoModeOnly: UserDefaults.standard.bool(forKey: "servicesAutoModeEnabled")
            )
        }
        .sheet(isPresented: $showingAddToCollection) {
            let _ = Logger.shared.log("MediaDetailView constructing add-to-collection sheet: id=\(searchResult.id)", type: "CrashProbe")
            AddToCollectionView(searchResult: searchResult)
        }
    }

    @ViewBuilder
    private var detailBackground: some View {
        if ExperimentalFeatureState.isEnabledAtLaunch {
            HeroBleedGradientBackground(
                dominantColor: atmosphereColor,
                scrollOffset: backgroundScrollOffset,
                heroHeight: headerHeight,
                fadeDistance: designMetrics.heroBleedDistance * 1.15,
                bleedStrength: designMetrics.heroWashStrength * 1.08,
                style: theme.atmosphereStyle
            )
        } else if theme.atmosphereStyle == .solid {
            atmosphereColor
        } else {
            LinearGradient(
                stops: [
                    .init(color: EclipseTheme.shared.backgroundBase, location: 0.0),
                    .init(color: ambientColor.opacity(0.74), location: 0.12),
                    .init(color: ambientColor.opacity(0.30), location: 0.34),
                    .init(color: EclipseTheme.shared.backgroundBase, location: 0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    @ViewBuilder
    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading...")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Error")
                .font(.title2)
                .padding(.top)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                loadMediaDetails()
            }
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var navigationOverlay: some View {
        VStack {
            HStack {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: ExperimentalFeatureState.isEnabledAtLaunch ? 28 : 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(
                            width: ExperimentalFeatureState.isEnabledAtLaunch ? 58 : 32,
                            height: ExperimentalFeatureState.isEnabledAtLaunch ? 58 : 32
                        )
                        .background(
                            Circle()
                                .fill(ExperimentalFeatureState.isEnabledAtLaunch ? atmosphereColor.opacity(0.36) : Color.clear)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .opacity(ExperimentalFeatureState.isEnabledAtLaunch ? 0.72 : 0)
                                )
                        )
                        .applyLiquidGlassBackground(cornerRadius: ExperimentalFeatureState.isEnabledAtLaunch ? 29 : 16)
                }
                
                Spacer()
            }
            .padding(.horizontal, ExperimentalFeatureState.isEnabledAtLaunch ? 22 : 16)
            .padding(.top, ExperimentalFeatureState.isEnabledAtLaunch ? 20 : 0)
            
            Spacer()
        }
    }

#if !os(tvOS)
    private var edgeBackSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .global)
            .onEnded { value in
                guard value.startLocation.x <= 32,
                      value.translation.width > 70,
                      abs(value.translation.height) < 70 else {
                    return
                }
                presentationMode.wrappedValue.dismiss()
            }
    }
#endif
    
    @ViewBuilder
    private var mainScrollView: some View {
        let _ = Logger.shared.log("MediaDetailView construct mainScrollView: id=\(searchResult.id) isLoading=\(isLoading) hasLoaded=\(hasLoadedContent) isAnime=\(isAnimeShow) tvSeasons=\(tvShowDetail?.seasons.count ?? 0) selectedSeason=\(selectedSeason?.seasonNumber.description ?? "nil")", type: "CrashProbe")
        let _ = detailContentRefreshTick
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroImageSection
                contentContainer
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: -geo.frame(in: .named("mediaDetailScroll")).origin.y
                    )
                }
            )
        }
        .coordinateSpace(name: "mediaDetailScroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { newOffset in
            guard abs(scrollOffset - newOffset) >= scrollOffsetUpdateThreshold else { return }
            scrollOffset = newOffset
        }
    }

    private func refreshDetailContentLayout(reason: String) {
        guard hasLoadedContent, !isLoading else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard hasLoadedContent, !isLoading else { return }
            detailContentRefreshTick += 1
            Logger.shared.log("MediaDetailView refreshed content layout: id=\(searchResult.id) reason=\(reason)", type: "CrashProbe")
        }
    }

    private func playerCloseNotificationMatchesDetail(_ notification: Notification) -> Bool {
        guard let tmdbId = notification.userInfo?["tmdbId"] as? Int else {
            return true
        }
        return tmdbId == searchResult.id
    }
    
    @ViewBuilder
    private var heroImageSection: some View {
        ZStack(alignment: .bottom) {
            StretchyHeaderView(
                backdropURL: detailHeroImageURL,
                isMovie: searchResult.isMovie,
                headerHeight: headerHeight,
                minHeaderHeight: minHeaderHeight,
                onAmbientColorExtracted: { color in
                    ambientColor = color
                }
            )
            
            gradientOverlay
            headerSection
        }
    }
    
    @ViewBuilder
    private var contentContainer: some View {
        let _ = Logger.shared.log("MediaDetailView construct contentContainer: id=\(searchResult.id) movie=\(searchResult.isMovie) cast=\(castMembers.count)", type: "CrashProbe")
        VStack(spacing: 0) {
            VStack(
                alignment: .leading,
                spacing: ExperimentalFeatureState.isEnabledAtLaunch ? max(18, designMetrics.sectionSpacing * 0.62) : 16
            ) {
                ForEach(visibleBodyMediaDetailElements) { element in
                    mediaDetailElementView(element)
                }

                if ExperimentalFeatureState.isEnabledAtLaunch {
                    experimentalExtrasSection
                }
                
                Spacer(minLength: 50)
            }
            .background(
                detailContentBackground
            )
            .padding(.top, ExperimentalFeatureState.isEnabledAtLaunch ? max(18, designMetrics.sectionSpacing * 0.45) : 0)
            .padding(.bottom, ExperimentalFeatureState.isEnabledAtLaunch ? 28 : 0)
        }
    }

    @ViewBuilder
    private var detailContentBackground: some View {
        if ExperimentalFeatureState.isEnabledAtLaunch {
            Color.clear
        } else if theme.atmosphereStyle == .solid {
            atmosphereColor
        } else {
            LinearGradient(
                colors: [ambientColor, Color.clear, EclipseTheme.shared.backgroundBase],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.34)
            )
        }
    }
    
    @ViewBuilder
    private var gradientOverlay: some View {
        if ExperimentalFeatureState.isEnabledAtLaunch {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.42), location: 0.0),
                            .init(color: Color.black.opacity(0.14), location: 0.48),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: isIPad ? 260 : 210)

                    Spacer(minLength: 0)
                }

                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color.black.opacity(0.12), location: 0.18),
                        .init(color: atmosphereColor.opacity(theme.atmosphereStyle == .solid ? 0.42 : 0.32), location: 0.42),
                        .init(color: atmosphereColor.opacity(theme.atmosphereStyle == .solid ? 0.78 : 0.66), location: 0.72),
                        .init(color: EclipseTheme.shared.backgroundBase.opacity(theme.atmosphereStyle == .solid ? 0.24 : 0.76), location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: max(designMetrics.heroBottomFadeHeight + 150, isIPad ? 680 : 570))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        } else {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: atmosphereColor.opacity(theme.atmosphereStyle == .solid ? 0.0 : 0.0), location: 0.0),
                    .init(color: atmosphereColor.opacity(theme.atmosphereStyle == .solid ? 0.25 : 0.16), location: 0.20),
                    .init(color: atmosphereColor.opacity(theme.atmosphereStyle == .solid ? 0.62 : 0.42), location: 0.62),
                    .init(color: atmosphereColor.opacity(1), location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 0))
        }
    }

    private var detailHeroImageURL: String? {
        if ExperimentalFeatureState.isEnabledAtLaunch && !isIPad && !isTvOS {
            if searchResult.isMovie {
                return movieDetail?.fullPosterURL
                    ?? searchResult.fullPosterURL
                    ?? movieDetail?.fullBackdropURL
                    ?? searchResult.fullBackdropURL
            }
            return tvShowDetail?.fullPosterURL
                ?? searchResult.fullPosterURL
                ?? tvShowDetail?.fullBackdropURL
                ?? searchResult.fullBackdropURL
        }

        if searchResult.isMovie {
            return movieDetail?.fullBackdropURL ?? searchResult.fullBackdropURL ?? movieDetail?.fullPosterURL ?? searchResult.fullPosterURL
        }
        return tvShowDetail?.fullBackdropURL ?? searchResult.fullBackdropURL ?? tvShowDetail?.fullPosterURL ?? searchResult.fullPosterURL
    }
    
    @ViewBuilder
    private var headerSection: some View {
        if ExperimentalFeatureState.isEnabledAtLaunch {
            experimentalHeaderSection
        } else {
            legacyHeaderSection
        }
    }

    @ViewBuilder
    private var legacyHeaderSection: some View {
        VStack(alignment: .center, spacing: 8) {
            titleArtwork
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 10)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var experimentalHeaderSection: some View {
        VStack(alignment: .center, spacing: isIPad ? 15 : 12) {
            titleArtwork

            if shouldShowHeroDetails, let metadata = detailMetadataLine {
                Text(metadata)
                    .font(.system(size: isIPad ? 20 : 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, isIPad ? 82 : 20)
                    .shadow(color: .black.opacity(0.70), radius: 8, x: 0, y: 3)
            }

            if shouldShowHeroActions {
                experimentalPlayAndBookmarkSection
                    .padding(.top, isIPad ? 6 : 2)
            }

            if shouldShowHeroOverview {
                experimentalHeroSynopsisSection
                    .padding(.top, isIPad ? 2 : 0)
            }

            if shouldShowHeroDetails {
                detailRatingChips
                    .padding(.top, isIPad ? 2 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, isIPad ? 52 : 34)
    }

    @ViewBuilder
    private var titleArtwork: some View {
        if let logoURL = logoURL {
            KFImage(URL(string: logoURL))
                .placeholder {
                    titleText
                }
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    maxWidth: ExperimentalFeatureState.isEnabledAtLaunch ? (isIPad ? 520 : 334) : (isIPad ? 400 : 280),
                    maxHeight: ExperimentalFeatureState.isEnabledAtLaunch ? (isIPad ? 178 : 132) : (isIPad ? 140 : 100)
                )
                .shadow(color: .black.opacity(0.52), radius: 6, x: 0, y: 3)
                .padding(.horizontal, ExperimentalFeatureState.isEnabledAtLaunch ? (isIPad ? 82 : 26) : 0)
        } else {
            titleText
                .padding(.horizontal, ExperimentalFeatureState.isEnabledAtLaunch ? (isIPad ? 82 : 26) : 0)
        }
    }
    
    @ViewBuilder
    private var titleText: some View {
        Text(searchResult.displayTitle)
            .font(ExperimentalFeatureState.isEnabledAtLaunch ? .system(size: isIPad ? 54 : 40, weight: .heavy) : .largeTitle)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var detailMetadataLine: String? {
        let date = detailDate
        let genreText = detailGenres.prefix(2).map(\.name).joined(separator: ", ")
        let parts = [date, genreText].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private var detailDate: String? {
        let rawDate = searchResult.isMovie
            ? (movieDetail?.releaseDate ?? searchResult.releaseDate)
            : (tvShowDetail?.firstAirDate ?? searchResult.firstAirDate)
        guard let rawDate, !rawDate.isEmpty else { return nil }
        return String(rawDate.prefix(10))
    }

    private var detailGenres: [TMDBGenre] {
        searchResult.isMovie ? (movieDetail?.genres ?? []) : (tvShowDetail?.genres ?? [])
    }

    private var detailVoteAverage: Double? {
        searchResult.isMovie ? (movieDetail?.voteAverage ?? searchResult.voteAverage) : (tvShowDetail?.voteAverage ?? searchResult.voteAverage)
    }

    @ViewBuilder
    private var detailRatingChips: some View {
        let tmdbRating = detailVoteAverage
        if (tmdbRating ?? 0) > 0 || traktRating != nil || (isAnimeShow && animeRating?.source == .myAnimeList) {
            HStack(spacing: isIPad ? 15 : 11) {
                if let tmdbRating, tmdbRating > 0 {
                    ratingChip(label: "TMDB", value: String(format: "%.1f", tmdbRating), tint: .cyan)
                }

                if let traktRating {
                    ratingChip(label: "Trakt", value: traktRating.displayText, tint: .red)
                }

                if isAnimeShow, let animeRating, animeRating.source == .myAnimeList {
                    ratingChip(label: "MAL", value: String(format: "%.1f", animeRating.value), tint: .blue)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .padding(.horizontal, isIPad ? 82 : 24)
        }
    }

    private func ratingChip(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: isIPad ? 12 : 10, weight: .heavy))
                .foregroundColor(label == "TMDB" ? .white : tint)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(label == "TMDB" ? tint.opacity(0.42) : tint.opacity(0.22))
                )
            Text(value)
                .font(.system(size: isIPad ? 21 : 18, weight: .semibold))
                .foregroundColor(.white)
        }
        .shadow(color: .black.opacity(0.55), radius: 5, x: 0, y: 2)
    }
    
    @ViewBuilder
    private var synopsisSection: some View {
        if ExperimentalFeatureState.isEnabledAtLaunch {
            experimentalSynopsisSection
        } else {
            legacySynopsisSection
        }
    }

    @ViewBuilder
    private var legacySynopsisSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let overviewText = currentOverviewText {
                Text(showFullSynopsis ? overviewText : String(overviewText.prefix(200)) + (overviewText.count > 200 ? "..." : ""))
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(showFullSynopsis ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showFullSynopsis.toggle()
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var experimentalSynopsisSection: some View {
        if let overviewText = currentOverviewText {
            VStack(spacing: 10) {
                Text(showFullSynopsis ? overviewText : String(overviewText.prefix(240)) + (overviewText.count > 240 ? "..." : ""))
                    .font(.system(size: isIPad ? 21 : 18, weight: .regular))
                    .foregroundColor(.white.opacity(0.90))
                    .lineLimit(showFullSynopsis ? nil : 4)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.42), radius: 6, x: 0, y: 3)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showFullSynopsis.toggle()
                        }
                    }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, isIPad ? 80 : 28)
        }
    }

    @ViewBuilder
    private var experimentalHeroSynopsisSection: some View {
        if let overviewText = currentOverviewText {
            Text(showFullSynopsis ? overviewText : String(overviewText.prefix(220)) + (overviewText.count > 220 ? "..." : ""))
                .font(.system(size: isIPad ? 21 : 18, weight: .regular))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(showFullSynopsis ? 8 : 4)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, isIPad ? 98 : 28)
                .shadow(color: .black.opacity(0.60), radius: 7, x: 0, y: 3)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showFullSynopsis.toggle()
                    }
                }
        }
    }

    private var currentOverviewText: String? {
        let trimmedSynopsis = synopsis.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSynopsis.isEmpty {
            return trimmedSynopsis
        }

        let overview = searchResult.isMovie ? movieDetail?.overview : tvShowDetail?.overview
        let trimmedOverview = overview?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedOverview, !trimmedOverview.isEmpty else { return nil }
        return trimmedOverview
    }
    
    @ViewBuilder
    private var playAndBookmarkSection: some View {
        if ExperimentalFeatureState.isEnabledAtLaunch {
            experimentalPlayAndBookmarkSection
        } else {
            legacyPlayAndBookmarkSection
        }
    }

    @ViewBuilder
    private var legacyPlayAndBookmarkSection: some View {
        HStack(spacing: 8) {
            Button(action: {
                searchInServices()
            }) {
                HStack {
                    Image(systemName: canUseMainPlayButton ? "play.fill" : "exclamationmark.triangle")
                    
                    Text(canUseMainPlayButton ? playButtonText : "No Services")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 25)
                .applyLiquidGlassBackground(
                    cornerRadius: 12,
                    fallbackFill: canUseMainPlayButton ? Color.black.opacity(0.2) : Color.gray.opacity(0.3),
                    fallbackMaterial: canUseMainPlayButton ? .ultraThinMaterial : .thinMaterial,
                    glassTint: canUseMainPlayButton ? nil : Color.gray.opacity(0.3)
                )
                .foregroundColor(canUseMainPlayButton ? .white : .secondary)
                .cornerRadius(8)
            }
            .disabled(!canUseMainPlayButton)
            
            Button(action: {
                toggleBookmark()
            }) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.title2)
                    .frame(width: 42, height: 42)
                    .applyLiquidGlassBackground(cornerRadius: 12)
                    .foregroundColor(isBookmarked ? .yellow : .white)
                    .cornerRadius(8)
            }
            
            if searchResult.isMovie {
                Button(action: {
                    downloadInServices()
                }) {
                    Image(systemName: downloadButtonIcon)
                        .font(.title2)
                        .frame(width: 42, height: 42)
                        .applyLiquidGlassBackground(
                            cornerRadius: 12,
                            glassTint: downloadButtonTint
                        )
                        .foregroundColor(downloadButtonColor)
                        .cornerRadius(8)
                }
                .disabled(!hasActiveSources || isCurrentlyDownloading)
            }
            
            Button(action: {
                showingAddToCollection = true
            }) {
                Image(systemName: "plus")
                    .font(.title2)
                    .frame(width: 42, height: 42)
                    .applyLiquidGlassBackground(cornerRadius: 12)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var experimentalPlayAndBookmarkSection: some View {
        VStack(spacing: isIPad ? 26 : 22) {
            Button(action: {
                searchInServices()
            }) {
                Text(canUseMainPlayButton ? playButtonText : "No Services")
                    .font(.system(size: isIPad ? 30 : 27, weight: .heavy))
                    .foregroundColor(canUseMainPlayButton ? .black : .white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(maxWidth: .infinity)
                    .frame(height: isIPad ? 66 : 58)
                    .background(
                        RoundedRectangle(cornerRadius: isIPad ? 24 : 20, style: .continuous)
                            .fill(canUseMainPlayButton ? Color.white.opacity(0.72) : Color.white.opacity(0.16))
                            .background(
                                RoundedRectangle(cornerRadius: isIPad ? 24 : 20, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.72)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: isIPad ? 24 : 20, style: .continuous)
                            .stroke(Color.white.opacity(0.32), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canUseMainPlayButton)

            HStack(spacing: isIPad ? 56 : 44) {
                experimentalActionButton(systemName: "rectangle.stack.badge.plus", foregroundColor: .white) {
                    showingAddToCollection = true
                }

                experimentalActionButton(systemName: isBookmarked ? "heart.fill" : "heart", foregroundColor: isBookmarked ? .white : .white) {
                    toggleBookmark()
                }

                if searchResult.isMovie {
                    experimentalActionButton(systemName: downloadButtonIcon, foregroundColor: downloadButtonColor) {
                        downloadInServices()
                    }
                    .disabled(!hasActiveSources || isCurrentlyDownloading)
                }
            }
        }
        .padding(.horizontal, isIPad ? 90 : 28)
    }

    private func experimentalActionButton(systemName: String, foregroundColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isIPad ? 36 : 31, weight: .semibold))
                .foregroundColor(foregroundColor)
                .frame(width: isIPad ? 70 : 58, height: isIPad ? 70 : 58)
                .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var episodesSection: some View {
        if !searchResult.isMovie {
            let _ = Logger.shared.log("MediaDetailView construct episodesSection: tmdbId=\(searchResult.id) isAnime=\(isAnimeShow) tvSeasons=\(tvShowDetail?.seasons.count ?? 0) selectedSeason=\(selectedSeason?.seasonNumber.description ?? "nil") anilistEpisodes=\(anilistEpisodes?.count ?? 0)", type: "CrashProbe")
            TVShowSeasonsSection(
                tvShow: tvShowDetail,
                isAnime: isAnimeShow,
                selectedSeason: $selectedSeason,
                seasonDetail: $seasonDetail,
                selectedEpisodeForSearch: $selectedEpisodeForSearch,
                specialEpisodeContext: $selectedSpecialEpisodeContext,
                seasonSelectorInsertedContent: AnyView(specialsOVASection),
                hasSpecialEpisodeChoices: !animeSpecialEntries.isEmpty,
                animeEpisodes: anilistEpisodes,
                animeSeasonTitles: animeSeasonTitles,
                animeSeasonRomajiTitles: animeSeasonRomajiTitles,
                animeSeasonAniListIds: animeSeasonAniListIds,
                animeSeasonKitsuIds: animeSeasonKitsuIds,
                showsMetadataDetails: false,
                showsInsertedContent: false,
                tmdbService: tmdbService
            ) {
                EmptyView()
            }
            .onAppear {
                Logger.shared.log("MediaDetailView episodesSection appeared: tmdbId=\(searchResult.id) isAnime=\(isAnimeShow) tvSeasons=\(tvShowDetail?.seasons.count ?? 0) selectedSeason=\(selectedSeason?.seasonNumber.description ?? "nil") anilistEpisodes=\(anilistEpisodes?.count ?? 0)", type: "CrashProbe")
            }
        }
    }

    @ViewBuilder
    private func mediaDetailElementView(_ element: MediaDetailElement) -> some View {
        switch element {
        case .actions:
            playAndBookmarkSection
        case .overview:
            synopsisSection
        case .details:
            if searchResult.isMovie {
                MovieDetailsSection(
                    movie: movieDetail,
                    compactHeroMetadata: ExperimentalFeatureState.isEnabledAtLaunch
                )
            } else {
                TVShowDetailsSection(
                    tvShow: tvShowDetail,
                    ratingOverride: isAnimeShow ? animeRating?.displayText : nil,
                    compactHeroMetadata: ExperimentalFeatureState.isEnabledAtLaunch
                )
            }
        case .cast:
            if !castMembers.isEmpty {
                castSection
            }
        case .ratingNotes:
            StarRatingView(mediaId: searchResult.id, isAnime: isAnimeShow)
        case .traktComments:
            traktCommentsSection
        case .episodes:
            episodesSection
        }
    }

    private func originalTitleForSearchSheet(_ episode: TMDBEpisode?) -> String? {
        guard isAnimeShow,
              let seasonNumber = episode?.seasonNumber,
              let seasonRomaji = animeSeasonRomajiTitles[seasonNumber],
              !seasonRomaji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return romajiTitle
        }
        return seasonRomaji
    }

    private func playbackContextForSearchSheet(_ episode: TMDBEpisode?) -> EpisodePlaybackContext? {
        guard isAnimeShow, let episode else { return nil }

        if PerformanceModeSettings.isEnabled || PerformanceModeSettings.skipsAniListTraversalForAnimeDetails {
            return EpisodePlaybackContext(
                localSeasonNumber: episode.seasonNumber,
                localEpisodeNumber: episode.episodeNumber,
                anilistMediaId: nil,
                kitsuMediaId: nil,
                tmdbSeasonNumber: episode.seasonNumber,
                tmdbEpisodeNumber: episode.episodeNumber,
                tmdbEpisodeOffset: nil,
                animeAbsoluteEpisodeNumber: nil,
                animeSeasonEpisodeCount: nil,
                isSpecial: false,
                titleOnlySearch: false
            )
        }

        let aniEpisode = anilistEpisodes?.first {
            $0.seasonNumber == episode.seasonNumber && $0.number == episode.episodeNumber
        }
        let absoluteEpisodeNumber = animeAbsoluteEpisodeNumber(for: episode)

        guard aniEpisode != nil ||
              absoluteEpisodeNumber != nil ||
              animeSeasonAniListIds[episode.seasonNumber] != nil ||
              animeSeasonKitsuIds[episode.seasonNumber] != nil else {
            return nil
        }

        return EpisodePlaybackContext(
            localSeasonNumber: episode.seasonNumber,
            localEpisodeNumber: episode.episodeNumber,
            anilistMediaId: animeSeasonAniListIds[episode.seasonNumber],
            kitsuMediaId: animeSeasonKitsuIds[episode.seasonNumber],
            tmdbSeasonNumber: aniEpisode?.tmdbSeasonNumber,
            tmdbEpisodeNumber: aniEpisode?.tmdbEpisodeNumber,
            tmdbEpisodeOffset: nil,
            animeAbsoluteEpisodeNumber: absoluteEpisodeNumber,
            animeSeasonEpisodeCount: animeSeasonEpisodeCount(for: episode.seasonNumber),
            isSpecial: false,
            titleOnlySearch: false
        )
    }

    private func animeAbsoluteEpisodeNumber(for episode: TMDBEpisode) -> Int? {
        guard let anilistEpisodes else { return nil }

        var absolute = 0
        for aniEpisode in anilistEpisodes.sorted(by: episodeSort) {
            absolute += 1
            if aniEpisode.seasonNumber == episode.seasonNumber && aniEpisode.number == episode.episodeNumber {
                return absolute
            }
        }

        return nil
    }

    private func animeSeasonEpisodeCount(for seasonNumber: Int) -> Int? {
        guard let anilistEpisodes else { return nil }
        let count = anilistEpisodes.filter { $0.seasonNumber == seasonNumber }.count
        return count > 0 ? count : nil
    }
    
    private func toggleBookmark() {
        Logger.shared.log("MediaDetailView toggleBookmark: id=\(searchResult.id) wasBookmarked=\(isBookmarked)", type: "CrashProbe")
        withAnimation(.easeInOut(duration: 0.2)) {
            libraryManager.toggleBookmark(for: searchResult)
            updateBookmarkStatus()
        }
        Logger.shared.log("MediaDetailView toggleBookmark complete: id=\(searchResult.id) isBookmarked=\(isBookmarked)", type: "CrashProbe")
    }

    @ViewBuilder
    private var experimentalExtrasSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            experimentalStillsSection
            experimentalTrailersSection
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var experimentalStillsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            experimentalSectionTitle("Stills", isLoading: isLoadingExperimentalExtras && detailStills.isEmpty)

            if detailStills.isEmpty && !isLoadingExperimentalExtras {
                experimentalEmptyCard(title: nil, message: "No stills available")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(detailStills.prefix(10).enumerated()), id: \.offset) { _, still in
                            KFImage(URL(string: still.fullURL))
                                .placeholder {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                }
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                                .frame(width: isIPad ? 330 : 250, height: isIPad ? 186 : 142)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder
    private var experimentalTrailersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            experimentalSectionTitle("Trailers", isLoading: isLoadingExperimentalExtras && detailTrailers.isEmpty)

            if detailTrailers.isEmpty && !isLoadingExperimentalExtras {
                experimentalEmptyCard(title: nil, message: "No trailers available")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(detailTrailers.prefix(8).enumerated()), id: \.offset) { _, trailer in
                            if let destination = trailer.playbackURL {
                                Link(destination: destination) {
                                    experimentalTrailerCard(trailer)
                                }
                                .buttonStyle(.plain)
                            } else {
                                experimentalTrailerCard(trailer)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func experimentalTrailerCard(_ trailer: TMDBVideo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let thumbnailURL = trailer.thumbnailURL {
                    KFImage(thumbnailURL)
                        .placeholder {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        }
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                }

                Circle()
                    .fill(Color.black.opacity(0.48))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .offset(x: 1)
                    )
            }
            .frame(width: isIPad ? 330 : 250, height: isIPad ? 186 : 142)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            Text(trailer.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: isIPad ? 330 : 250, alignment: .leading)
        }
    }

    private func experimentalSectionTitle(_ title: String, isLoading: Bool) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            if isLoading {
                ProgressView()
                    .scaleEffect(0.75)
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    private func experimentalEmptyCard(title: String?, message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }

            HStack(spacing: 12) {
                Image(systemName: "rectangle.slash")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.5))

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.62))

                Spacer()
            }
            .padding(16)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }

    // MARK: - Cast Section
    
    @ViewBuilder
    private var castSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(Array(castMembers.prefix(20).enumerated()), id: \.offset) { _, member in
                        VStack(spacing: 8) {
                            if let url = member.fullProfileURL {
                                KFImage(URL(string: url))
                                    .placeholder {
                                        castPlaceholder
                                    }
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            } else {
                                castPlaceholder
                            }
                            
                            Text(member.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            if let character = member.character, !character.isEmpty {
                                Text(character)
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 85)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
    }
    
    private var castPlaceholder: some View {
        Circle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.3))
            )
    }

    @ViewBuilder
    private var traktCommentsSection: some View {
        if trackerManager.trackerState.traktCommentsEnabled && (isLoadingTraktComments || !traktComments.isEmpty) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("Trakt Reviews")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    if isLoadingTraktComments {
                        ProgressView()
                            .scaleEffect(0.75)
                    }

                    Spacer()
                }
                .padding(.horizontal)

                if !traktComments.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(traktComments.prefix(5)) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(item.authorName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .lineLimit(1)

                                    if item.isReview {
                                        Text("Review")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white.opacity(0.75))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.white.opacity(0.12))
                                            .clipShape(Capsule())
                                    }

                                    Spacer()

                                    Label("\(item.likes)", systemImage: "heart.fill")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.55))
                                }

                                Text(item.comment)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.82))
                                    .lineLimit(6)
                                    .fixedSize(horizontal: false, vertical: true)

                                if let createdAt = formattedTraktDate(item.createdAt) {
                                    Text(createdAt)
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.45))
                                }
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var specialsOVASection: some View {
        if isAnimeShow && (isLoadingAnimeSpecials || !animeSpecialEntries.isEmpty) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("Specials & OVAs")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    if isLoadingAnimeSpecials {
                        ProgressView()
                            .scaleEffect(0.75)
                    }

                    Spacer()
                }
                .padding(.horizontal)

                if !animeSpecialEntries.isEmpty {
                    if useSeasonMenu {
                        specialsOVAMenu
                            .padding(.horizontal)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(animeSpecialEntries) { entry in
                                    specialEntryButton(entry)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var specialsOVAMenu: some View {
        Menu {
            ForEach(animeSpecialEntries) { entry in
                Button(action: {
                    selectSpecialEntry(entry)
                }) {
                    HStack {
                        Text("\(entry.preferredTitle) (\(entry.formatLabel))")
                        if selectedSpecialEpisodeContext?.id == entry.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedSpecialEpisodeContext?.title ?? "Select Special or OVA")
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .applyLiquidGlassBackground(cornerRadius: 12)
        }
    }

    @ViewBuilder
    private func specialEntryButton(_ entry: AniListSpecialSearchEntry) -> some View {
        Button(action: {
            selectSpecialEntry(entry)
        }) {
            VStack(spacing: 8) {
                specialPoster(urlString: entry.posterUrl, fallbackText: entry.formatLabel)

                Text(entry.preferredTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 84, height: 34)
                    .foregroundColor(selectedSpecialEpisodeContext?.id == entry.id ? .white : .white.opacity(0.82))

                Text(entry.episodeCount == 1 ? entry.formatLabel : "\(entry.formatLabel) - \(entry.episodeCount) eps")
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundColor(.white.opacity(0.65))
                    .frame(width: 84)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func specialPoster(urlString: String?, fallbackText: String) -> some View {
        if let urlString, let url = URL(string: urlString) {
            KFImage(url)
                .placeholder {
                    specialPosterPlaceholder(fallbackText)
                }
                .resizable()
                .aspectRatio(2/3, contentMode: .fill)
                .frame(width: 80, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            specialPosterPlaceholder(fallbackText)
        }
    }

    private func specialPosterPlaceholder(_ fallbackText: String) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.08))
            .frame(width: 80, height: 120)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                    Text(fallbackText)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .lineLimit(1)
                }
                .foregroundColor(.white.opacity(0.7))
            )
    }

    private func startAnimeSpecialsLoad(tmdbShowId: Int, fallbackPosterURL: String?, baseAniListIds: [Int] = []) {
        guard isAnimeShow, !searchResult.isMovie else {
            animeSpecialEntries = []
            isLoadingAnimeSpecials = false
            selectedSpecialEpisodeContext = nil
            return
        }
        guard !PerformanceModeSettings.skipsAniListTraversalForAnimeDetails else {
            animeSpecialEntries = []
            isLoadingAnimeSpecials = false
            selectedSpecialEpisodeContext = nil
            Logger.shared.log("MediaDetailView skipped anime specials because AniList traversal is disabled", type: "AniList")
            return
        }

        specialsLoadTask?.cancel()
        specialsLoadGeneration += 1
        let generation = specialsLoadGeneration
        if animeSpecialEntries.isEmpty {
            isLoadingAnimeSpecials = true
        }
        selectedSpecialEpisodeContext = nil

        specialsLoadTask = Task {
            let entries = await AniListService.shared.fetchSpecialSearchEntries(
                tmdbShowId: tmdbShowId,
                fallbackPosterURL: fallbackPosterURL,
                baseAniListIds: baseAniListIds,
                tmdbService: tmdbService
            )

            await MainActor.run {
                guard !Task.isCancelled,
                      generation == self.specialsLoadGeneration,
                      self.searchResult.id == tmdbShowId else { return }
                self.animeSpecialEntries = entries
                if let selected = self.selectedSpecialEpisodeContext, !entries.contains(where: { $0.id == selected.id }) {
                    self.selectedSpecialEpisodeContext = nil
                }
                self.isLoadingAnimeSpecials = false
                self.specialsLoadTask = nil
                if !entries.isEmpty {
                    MediaDetailCacheStore.shared.updateSpecialEntries(
                        key: PerformanceModeSettings.detailCacheKey(for: self.searchResult.stableIdentity),
                        entries: entries
                    )
                }
                Logger.shared.log("MediaDetailView loaded specials: tmdbId=\(tmdbShowId) count=\(entries.count)", type: "AniList")
            }
        }
    }

    private func selectSpecialEntry(_ entry: AniListSpecialSearchEntry) {
        guard let context = SpecialEpisodeListContext(entry: entry, tmdbShowId: searchResult.id) else {
            return
        }
        selectedSpecialEpisodeContext = context
        selectedEpisodeForSearch = context.episodes.first
        TrackerManager.shared.cacheAniListSeasonId(
            tmdbId: searchResult.id,
            seasonNumber: context.localSeasonNumber,
            anilistId: context.anilistId
        )
    }

    private func beginSpecialSearch(context: SpecialEpisodeListContext, episode: TMDBEpisode?) {
        guard hasActiveSources else { return }

        let playbackContext = episode.map { context.playbackContext(for: $0) }
        specialSearchRequest = AnimeSpecialSearchRequest(
            title: context.title,
            originalTitle: context.alternateTitle,
            episode: episode,
            originalSeasonNumber: playbackContext?.resolvedTMDBSeasonNumber,
            originalEpisodeNumber: playbackContext?.resolvedTMDBEpisodeNumber,
            imdbId: context.imdbId,
            posterUrl: context.posterUrl,
            titleOnly: playbackContext?.titleOnlySearch ?? true,
            playbackContext: playbackContext
        )
    }

    private func scheduleNextEpisodePresentation(action: @escaping () -> Void) {
        nextEpisodePresentationToken += 1
        let token = nextEpisodePresentationToken

        DispatchQueue.main.asyncAfter(deadline: .now() + nextEpisodeSheetPresentationDelay) {
            guard token == nextEpisodePresentationToken else { return }
            action()
        }
    }

    private func invalidatePendingNextEpisodePresentation() {
        nextEpisodePresentationToken += 1
    }
    
    private func updateBookmarkStatus() {
        isBookmarked = libraryManager.isBookmarked(searchResult)
        Logger.shared.log("MediaDetailView updateBookmarkStatus: id=\(searchResult.id) isBookmarked=\(isBookmarked)", type: "CrashProbe")
    }

    private func resolveMainPlayEpisodeTarget() -> MainPlayEpisodeCandidate? {
        let candidates = mainPlayEpisodeCandidates()
        guard !candidates.isEmpty else { return nil }

        let progressByEpisode = episodeProgressByKey()
        let latestWatchedIndex = candidates.indices.last(where: { index in
            guard let progress = progressByEpisode[candidates[index].key] else { return false }
            return isWatchedForMainPlay(progress)
        })

        let inProgressIndices = candidates.indices.filter { index in
            guard let progress = progressByEpisode[candidates[index].key] else { return false }
            return hasResumeProgress(progress)
        }

        let eligibleInProgressIndices: [Int]
        if let latestWatchedIndex {
            eligibleInProgressIndices = inProgressIndices.filter { $0 > latestWatchedIndex }
        } else {
            eligibleInProgressIndices = inProgressIndices
        }

        if let index = eligibleInProgressIndices.last {
            return candidates[index]
        }

        if let latestWatchedIndex {
            let nextIndex = candidates.index(after: latestWatchedIndex)
            if nextIndex < candidates.endIndex {
                return candidates[nextIndex]
            }
        }

        if let index = inProgressIndices.last {
            return candidates[index]
        }

        return candidates.first
    }

    private func mainPlayEpisodeCandidates() -> [MainPlayEpisodeCandidate] {
        if isAnimeShow, let anilistEpisodes, !anilistEpisodes.isEmpty {
            return uniqueMainPlayCandidates(
                anilistEpisodes
                    .sorted(by: episodeSort)
                    .map {
                        MainPlayEpisodeCandidate(
                            key: .init(seasonNumber: $0.seasonNumber, episodeNumber: $0.number),
                            episode: nil
                        )
                    }
            )
        }

        if let tvShowDetail {
            let regularSeasons = tvShowDetail.seasons
                .filter { $0.seasonNumber > 0 }
                .sorted { $0.seasonNumber < $1.seasonNumber }

            var candidates: [MainPlayEpisodeCandidate] = []
            for season in regularSeasons {
                if let loadedSeason = seasonDetail, loadedSeason.seasonNumber == season.seasonNumber {
                    candidates.append(contentsOf: loadedSeason.episodes
                        .sorted { $0.episodeNumber < $1.episodeNumber }
                        .map {
                            MainPlayEpisodeCandidate(
                                key: .init(seasonNumber: $0.seasonNumber, episodeNumber: $0.episodeNumber),
                                episode: $0
                            )
                        }
                    )
                    continue
                }

                guard season.episodeCount > 0 else { continue }
                candidates.append(contentsOf: (1...season.episodeCount).map { episodeNumber in
                    MainPlayEpisodeCandidate(
                        key: .init(seasonNumber: season.seasonNumber, episodeNumber: episodeNumber),
                        episode: nil
                    )
                })
            }

            if !candidates.isEmpty {
                return uniqueMainPlayCandidates(candidates)
            }
        }

        if let seasonDetail {
            return uniqueMainPlayCandidates(
                seasonDetail.episodes
                    .sorted { $0.episodeNumber < $1.episodeNumber }
                    .map {
                        MainPlayEpisodeCandidate(
                            key: .init(seasonNumber: $0.seasonNumber, episodeNumber: $0.episodeNumber),
                            episode: $0
                        )
                    }
            )
        }

        return []
    }

    private func uniqueMainPlayCandidates(_ candidates: [MainPlayEpisodeCandidate]) -> [MainPlayEpisodeCandidate] {
        var indexesByKey: [MainPlayEpisodeKey: Int] = [:]
        var result: [MainPlayEpisodeCandidate] = []

        for candidate in candidates {
            if let index = indexesByKey[candidate.key] {
                if result[index].episode == nil, candidate.episode != nil {
                    result[index] = candidate
                }
                continue
            }

            indexesByKey[candidate.key] = result.count
            result.append(candidate)
        }

        return result
    }

    private func episodeProgressByKey() -> [MainPlayEpisodeKey: EpisodeProgressEntry] {
        let entries = progressManager.getProgressData().episodeProgress
        var result: [MainPlayEpisodeKey: EpisodeProgressEntry] = [:]

        for entry in entries where entry.showId == searchResult.id {
            let key = MainPlayEpisodeKey(seasonNumber: entry.seasonNumber, episodeNumber: entry.episodeNumber)
            if let existing = result[key], existing.lastUpdated >= entry.lastUpdated {
                continue
            }
            result[key] = entry
        }

        return result
    }

    private func isWatchedForMainPlay(_ entry: EpisodeProgressEntry) -> Bool {
        entry.isWatched || entry.progress >= 0.85
    }

    private func hasResumeProgress(_ entry: EpisodeProgressEntry) -> Bool {
        !isWatchedForMainPlay(entry) && (entry.currentTime > 0 || entry.progress > 0)
    }
    
    private func searchInServices() {
        Logger.shared.log("MediaDetailView searchInServices begin: id=\(searchResult.id) isMovie=\(searchResult.isMovie) hasActiveSources=\(hasActiveSources) selectedEpisodeBefore=\(selectedEpisodeForSearch.map { "S\($0.seasonNumber)E\($0.episodeNumber)" } ?? "nil") seasonDetailEpisodes=\(seasonDetail?.episodes.count ?? 0)", type: "CrashProbe")
        if searchResult.isMovie {
            selectedEpisodeForSearch = nil
            Logger.shared.log("MediaDetailView searchInServices movie selected: id=\(searchResult.id)", type: "CrashProbe")
            if preferDownloadedMedia,
               let item = downloadManager.completedDownloadItem(tmdbId: searchResult.id, isMovie: true) {
                playDownloadedItem(item)
                return
            }

            guard hasActiveSources else { return }
            Logger.shared.log("MediaDetailView searchInServices presenting: id=\(searchResult.id) selectedEpisode=nil", type: "CrashProbe")
            playSheetRequestId = UUID()
            showingSearchResults = true
            return
        }

        Task { @MainActor in
            await prepareMainEpisodeAndPresent()
        }
    }

    @MainActor
    private func prepareMainEpisodeAndPresent() async {
        if let specialContext = selectedSpecialEpisodeContext {
            let episode = selectedEpisodeForSearch.flatMap { selected in
                specialContext.episodes.first(where: { $0.id == selected.id })
            } ?? specialContext.episodes.first
            selectedEpisodeForSearch = episode
            if preferDownloadedMedia,
               let episode,
               let item = downloadedItem(for: episode) {
                playDownloadedItem(item)
                return
            }
            guard hasActiveSources else { return }
            beginSpecialSearch(context: specialContext, episode: episode)
            return
        }

        let episode = await resolveContinueEpisodeForMainPlay()
        selectedEpisodeForSearch = episode

        if preferDownloadedMedia,
           let episode,
           let item = downloadedItem(for: episode) {
            playDownloadedItem(item)
            return
        }
        if preferDownloadedMedia,
           !hasActiveSources,
           let item = latestDownloadedItemForShow() {
            playDownloadedItem(item)
            return
        }

        guard hasActiveSources else { return }
        Logger.shared.log("MediaDetailView searchInServices presenting: id=\(searchResult.id) selectedEpisode=\(selectedEpisodeForSearch.map { "S\($0.seasonNumber)E\($0.episodeNumber)" } ?? "nil")", type: "CrashProbe")
        playSheetRequestId = UUID()
        showingSearchResults = true
    }

    @MainActor
    private func resolveContinueEpisodeForMainPlay() async -> TMDBEpisode? {
        if let target = resolveMainPlayEpisodeTarget() {
            let episode: TMDBEpisode?
            if let targetEpisode = target.episode {
                episode = targetEpisode
            } else {
                episode = await episodeForPlayback(
                    seasonNumber: target.key.seasonNumber,
                    episodeNumber: target.key.episodeNumber
                )
            }

            if let episode {
                Logger.shared.log("MediaDetailView main play using target episode: id=\(searchResult.id) S\(target.key.seasonNumber)E\(target.key.episodeNumber)", type: "Progress")
                return episode
            } else {
                Logger.shared.log("MediaDetailView main play target episode missing: id=\(searchResult.id) S\(target.key.seasonNumber)E\(target.key.episodeNumber)", type: "Progress")
            }
        }

        if let first = await firstPlayableEpisode() {
            Logger.shared.log("MediaDetailView main play defaulted first episode: id=\(searchResult.id) S\(first.seasonNumber)E\(first.episodeNumber)", type: "Progress")
            return first
        }

        Logger.shared.log("MediaDetailView main play found no episode: id=\(searchResult.id)", type: "Progress")
        return nil
    }

    @MainActor
    private func firstPlayableEpisode() async -> TMDBEpisode? {
        if let first = seasonDetail?.episodes.first {
            return first
        }

        if isAnimeShow, let first = anilistEpisodes?.sorted(by: episodeSort).first {
            return tmdbEpisode(from: first)
        }

        guard let tvShowDetail,
              let firstSeason = tvShowDetail.seasons.filter({ $0.seasonNumber > 0 }).sorted(by: { $0.seasonNumber < $1.seasonNumber }).first else {
            return nil
        }

        return await episodeForPlayback(seasonNumber: firstSeason.seasonNumber, episodeNumber: 1)
    }

    @MainActor
    private func episodeForPlayback(seasonNumber: Int, episodeNumber: Int) async -> TMDBEpisode? {
        if let loaded = seasonDetail,
           loaded.seasonNumber == seasonNumber,
           let episode = loaded.episodes.first(where: { $0.episodeNumber == episodeNumber }) {
            return episode
        }

        if isAnimeShow,
           let aniEpisode = anilistEpisodes?.first(where: { $0.seasonNumber == seasonNumber && $0.number == episodeNumber }) {
            return tmdbEpisode(from: aniEpisode)
        }

        if let show = tvShowDetail,
           let season = show.seasons.first(where: { $0.seasonNumber == seasonNumber }) {
            do {
                let detail = try await tmdbService.getSeasonDetails(tvShowId: searchResult.id, seasonNumber: seasonNumber)
                selectedSeason = season
                seasonDetail = detail
                return detail.episodes.first(where: { $0.episodeNumber == episodeNumber }) ?? detail.episodes.first
            } catch {
                Logger.shared.log("MediaDetailView failed loading last watched season S\(seasonNumber): \(error.localizedDescription)", type: "Progress")
            }
        }

        return seasonDetail?.episodes.first
    }

    private func tmdbEpisode(from aniEpisode: AniListEpisode) -> TMDBEpisode {
        TMDBEpisode(
            id: searchResult.id * 1000 + aniEpisode.seasonNumber * 100 + aniEpisode.number,
            name: aniEpisode.title,
            overview: aniEpisode.description,
            stillPath: aniEpisode.stillPath,
            episodeNumber: aniEpisode.number,
            seasonNumber: aniEpisode.seasonNumber,
            airDate: aniEpisode.airDate,
            runtime: aniEpisode.runtime,
            voteAverage: 0,
            voteCount: 0
        )
    }

    private func episodeSort(_ lhs: AniListEpisode, _ rhs: AniListEpisode) -> Bool {
        if lhs.seasonNumber == rhs.seasonNumber {
            return lhs.number < rhs.number
        }
        return lhs.seasonNumber < rhs.seasonNumber
    }

    private func downloadedItem(for episode: TMDBEpisode) -> DownloadItem? {
        downloadManager.completedDownloadItem(
            tmdbId: searchResult.id,
            isMovie: false,
            seasonNumber: episode.seasonNumber,
            episodeNumber: episode.episodeNumber
        )
    }

    private func latestDownloadedItemForShow() -> DownloadItem? {
        downloadManager.completedDownloads
            .filter { !$0.isMovie && $0.tmdbId == searchResult.id && downloadManager.localFileURL(for: $0) != nil }
            .sorted {
                let lhsDate = $0.dateCompleted ?? $0.dateAdded
                let rhsDate = $1.dateCompleted ?? $1.dateAdded
                return lhsDate > rhsDate
            }
            .first
    }

    private func playDownloadedItem(_ item: DownloadItem) {
        guard let fileURL = downloadManager.localFileURL(for: item) else {
            Logger.shared.log("Downloaded file not found for: \(item.id)", type: "Download")
            return
        }

        let inAppRaw = Settings.normalizedInAppPlayer(UserDefaults.standard.string(forKey: "inAppPlayer"))
        let subtitleArray: [String]? = downloadManager.localSubtitleURL(for: item).map { [$0.absoluteString] }

        if inAppRaw == "mpv" {
            let preset = PlayerPreset.presets.first
            let pvc = PlayerViewController(
                url: fileURL,
                preset: preset ?? PlayerPreset(id: .sdrRec709, title: "Default", summary: "", stream: nil, commands: []),
                headers: [:],
                subtitles: subtitleArray,
                mediaInfo: item.mediaInfo
            )
            pvc.isAnimeHint = item.isAnime || item.episodePlaybackContext?.hasAnimeMediaId == true
            pvc.episodePlaybackContext = item.episodePlaybackContext
            pvc.originalTMDBSeasonNumber = item.episodePlaybackContext?.resolvedTMDBSeasonNumber
            pvc.originalTMDBEpisodeNumber = item.episodePlaybackContext?.resolvedTMDBEpisodeNumber
            pvc.modalPresentationStyle = .fullScreen

            if !item.isMovie {
                pvc.onRequestNextEpisode = { seasonNumber, episodeNumber in
                    guard let nextItem = nextDownloadedEpisode(
                        for: item.tmdbId,
                        requestedSeasonNumber: seasonNumber,
                        requestedEpisodeNumber: episodeNumber,
                        currentItemId: item.id
                    ) else {
                        Logger.shared.log("NextEpisode: No downloaded next episode found for tmdbId=\(item.tmdbId) after \(item.id)", type: "Player")
                        return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    playDownloadedItem(nextItem)
                }
            }
        }

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController,
               let topmostVC = rootVC.topmostViewController() as UIViewController? {
                topmostVC.present(pvc, animated: true, completion: nil)
            }
        } else {
            let playerVC = NormalPlayer()
            let item2 = AVPlayerItem(url: fileURL)
            playerVC.player = AVPlayer(playerItem: item2)
            playerVC.mediaInfo = item.mediaInfo
            playerVC.episodePlaybackContext = item.episodePlaybackContext
            playerVC.modalPresentationStyle = .fullScreen

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController,
               let topmostVC = rootVC.topmostViewController() as UIViewController? {
                topmostVC.present(playerVC, animated: true) {
                    playerVC.playAtDefaultSpeed()
                }
            }
        }
    }

    private func nextDownloadedEpisode(
        for tmdbId: Int,
        requestedSeasonNumber: Int,
        requestedEpisodeNumber: Int,
        currentItemId: String
    ) -> DownloadItem? {
        let episodes = downloadManager.completedDownloads
            .filter {
                !$0.isMovie &&
                $0.tmdbId == tmdbId &&
                $0.seasonNumber != nil &&
                $0.episodeNumber != nil &&
                downloadManager.localFileURL(for: $0) != nil
            }
            .sorted {
                if $0.seasonNumber == $1.seasonNumber {
                    return ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0)
                }
                return ($0.seasonNumber ?? 0) < ($1.seasonNumber ?? 0)
            }

        if let requested = episodes.first(where: {
            $0.seasonNumber == requestedSeasonNumber && $0.episodeNumber == requestedEpisodeNumber
        }) {
            return requested
        }

        guard let currentIndex = episodes.firstIndex(where: { $0.id == currentItemId }) else { return nil }
        let nextIndex = episodes.index(after: currentIndex)
        guard nextIndex < episodes.endIndex else { return nil }
        return episodes[nextIndex]
    }
    
    private func downloadInServices() {
        Logger.shared.log("MediaDetailView downloadInServices begin: id=\(searchResult.id) isMovie=\(searchResult.isMovie) hasActiveSources=\(hasActiveSources) selectedEpisodeBefore=\(selectedEpisodeForSearch.map { "S\($0.seasonNumber)E\($0.episodeNumber)" } ?? "nil") seasonDetailEpisodes=\(seasonDetail?.episodes.count ?? 0)", type: "CrashProbe")
        if !searchResult.isMovie {
            if selectedEpisodeForSearch != nil {
                Logger.shared.log("MediaDetailView downloadInServices keeping selected episode: id=\(searchResult.id) episode=\(selectedEpisodeForSearch.map { "S\($0.seasonNumber)E\($0.episodeNumber)" } ?? "nil")", type: "CrashProbe")
            } else if let seasonDetail = seasonDetail, !seasonDetail.episodes.isEmpty {
                selectedEpisodeForSearch = seasonDetail.episodes.first
                Logger.shared.log("MediaDetailView downloadInServices defaulted first episode: id=\(searchResult.id) episode=\(selectedEpisodeForSearch.map { "S\($0.seasonNumber)E\($0.episodeNumber)" } ?? "nil")", type: "CrashProbe")
            } else {
                selectedEpisodeForSearch = nil
                Logger.shared.log("MediaDetailView downloadInServices no episode available: id=\(searchResult.id)", type: "CrashProbe")
            }
        } else {
            selectedEpisodeForSearch = nil
            Logger.shared.log("MediaDetailView downloadInServices movie selected: id=\(searchResult.id)", type: "CrashProbe")
        }
        
        Logger.shared.log("MediaDetailView downloadInServices presenting: id=\(searchResult.id) selectedEpisode=\(selectedEpisodeForSearch.map { "S\($0.seasonNumber)E\($0.episodeNumber)" } ?? "nil")", type: "CrashProbe")
        showingDownloadSheet = true
    }
    
    private var isCurrentlyDownloading: Bool {
        if searchResult.isMovie {
            return DownloadManager.shared.isDownloading(tmdbId: searchResult.id, isMovie: true)
        } else if let ep = selectedEpisodeForSearch {
            return DownloadManager.shared.isDownloading(tmdbId: searchResult.id, isMovie: false, seasonNumber: ep.seasonNumber, episodeNumber: ep.episodeNumber)
        }
        return false
    }
    
    private var isAlreadyDownloaded: Bool {
        if searchResult.isMovie {
            return DownloadManager.shared.isDownloaded(tmdbId: searchResult.id, isMovie: true)
        } else if let ep = selectedEpisodeForSearch {
            return DownloadManager.shared.isDownloaded(tmdbId: searchResult.id, isMovie: false, seasonNumber: ep.seasonNumber, episodeNumber: ep.episodeNumber)
        }
        return false
    }
    
    private var downloadButtonIcon: String {
        if isAlreadyDownloaded {
            return "checkmark.circle.fill"
        } else if isCurrentlyDownloading {
            return "arrow.down.circle"
        }
        return "arrow.down.circle"
    }
    
    private var downloadButtonColor: Color {
        if isAlreadyDownloaded {
            return .green
        } else if isCurrentlyDownloading {
            return .blue
        }
        return .white
    }
    
    private var downloadButtonTint: Color? {
        if isAlreadyDownloaded {
            return Color.green.opacity(0.2)
        } else if isCurrentlyDownloading {
            return Color.blue.opacity(0.2)
        }
        return nil
    }

    private func startTraktFeatureLoad() {
        traktFeatureLoadTask?.cancel()

        let shouldLoadComments = trackerManager.trackerState.traktCommentsEnabled

        guard shouldLoadComments || traktRating == nil else {
            traktComments = []
            isLoadingTraktComments = false
            return
        }

        isLoadingTraktComments = shouldLoadComments && traktComments.isEmpty

        let tmdbId = searchResult.id
        let isMovie = searchResult.isMovie
        traktFeatureLoadTask = Task {
            async let loadedComments: [TraktCommentReview] = shouldLoadComments
                ? TrackerManager.shared.fetchTraktComments(tmdbId: tmdbId, isMovie: isMovie)
                : []
            async let loadedRating: TraktMediaRating? = TrackerManager.shared.fetchTraktRating(tmdbId: tmdbId, isMovie: isMovie)

            guard !Task.isCancelled else { return }
            let comments = await loadedComments
            let rating = await loadedRating
            await MainActor.run {
                self.traktComments = comments
                self.traktRating = rating
                self.isLoadingTraktComments = false
                self.refreshDetailContentLayout(reason: "trakt-features")
            }
        }
    }

    private func startExperimentalExtrasLoadIfNeeded() {
        experimentalExtrasLoadTask?.cancel()

        guard ExperimentalFeatureState.isEnabledAtLaunch else {
            detailStills = []
            detailTrailers = []
            isLoadingExperimentalExtras = false
            return
        }

        let tmdbId = searchResult.id
        let isMovie = searchResult.isMovie
        isLoadingExperimentalExtras = detailStills.isEmpty && detailTrailers.isEmpty

        experimentalExtrasLoadTask = Task {
            let images: TMDBImagesResponse?
            let trailers: [TMDBVideo]

            if isMovie {
                async let imagesResult: TMDBImagesResponse? = try? tmdbService.getMovieImages(id: tmdbId, preferredLanguage: selectedLanguage)
                async let videosResult: [TMDBVideo]? = try? tmdbService.getMovieVideos(id: tmdbId)

                images = await imagesResult
                let loadedVideos = (await videosResult) ?? []
                trailers = loadedVideos.filter { $0.isTrailerLike && $0.playbackURL != nil }
            } else {
                async let imagesResult: TMDBImagesResponse? = try? tmdbService.getTVShowImages(id: tmdbId, preferredLanguage: selectedLanguage)
                async let videosResult: [TMDBVideo]? = try? tmdbService.getTVShowVideos(id: tmdbId)

                images = await imagesResult
                let loadedVideos = (await videosResult) ?? []
                trailers = loadedVideos.filter { $0.isTrailerLike && $0.playbackURL != nil }
            }

            let stills = (images?.backdrops ?? [])
                .sorted {
                    let lhsVotes = $0.voteCount ?? 0
                    let rhsVotes = $1.voteCount ?? 0
                    if lhsVotes != rhsVotes { return lhsVotes > rhsVotes }
                    return ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0)
                }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled, self.searchResult.id == tmdbId else { return }
                self.detailStills = stills
                self.detailTrailers = trailers
                self.isLoadingExperimentalExtras = false
                self.experimentalExtrasLoadTask = nil
                self.refreshDetailContentLayout(reason: "experimental-extras")
            }
        }
    }

    private func formattedTraktDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return nil }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func loadMediaDetails() {
        if let existingTask = detailLoadTask {
            Logger.shared.log("MediaDetail cancelling previous task before reload: id=\(searchResult.id)", type: "CrashProbe")
            existingTask.cancel()
            detailLoadTask = nil
        }
        if let specialsLoadTask {
            Logger.shared.log("MediaDetail cancelling stale specials task before reload: id=\(searchResult.id)", type: "CrashProbe")
            specialsLoadTask.cancel()
            self.specialsLoadTask = nil
        }
        if let traktFeatureLoadTask {
            Logger.shared.log("MediaDetail cancelling stale Trakt feature task before reload: id=\(searchResult.id)", type: "Tracker")
            traktFeatureLoadTask.cancel()
            self.traktFeatureLoadTask = nil
        }
        if let experimentalExtrasLoadTask {
            Logger.shared.log("MediaDetail cancelling stale experimental extras task before reload: id=\(searchResult.id)", type: "TMDB")
            experimentalExtrasLoadTask.cancel()
            self.experimentalExtrasLoadTask = nil
        }
        specialsLoadGeneration += 1
        let detailCacheKey = PerformanceModeSettings.detailCacheKey(for: searchResult.stableIdentity)
        Logger.shared.log("MediaDetail load start: id=\(searchResult.id) type=\(searchResult.mediaType) title=\(searchResult.displayTitle)", type: "CrashProbe")
        Logger.shared.log("MediaDetail cache lookup begin: key=\(detailCacheKey)", type: "CrashProbe")

        // Check view-level cache first for instant back-navigation
        if let cached = MediaDetailCacheStore.shared.get(key: detailCacheKey) {
            Logger.shared.log("MediaDetail cache hit: key=\(detailCacheKey) type=\(searchResult.mediaType)", type: "CrashProbe")
            // Defer state update to next run loop tick so SwiftUI properly re-renders
            Task { @MainActor in
                Logger.shared.log("MediaDetail cache apply begin: key=\(detailCacheKey) movie=\(cached.movieDetail != nil) tv=\(cached.tvShowDetail != nil) cachedSeasons=\(cached.tvShowDetail?.seasons.count ?? 0) cachedEpisodes=\(cached.anilistEpisodes?.count ?? 0)", type: "CrashProbe")
                self.movieDetail = cached.movieDetail
                self.tvShowDetail = cached.tvShowDetail
                self.selectedSeason = cached.selectedSeason
                self.seasonDetail = nil
                self.synopsis = cached.synopsis
                self.romajiTitle = cached.romajiTitle
                self.logoURL = cached.logoURL
                self.isAnimeShow = cached.isAnimeShow
                self.animeRating = cached.animeRating
                self.anilistEpisodes = cached.anilistEpisodes
                self.animeSeasonTitles = cached.animeSeasonTitles
                self.animeSeasonRomajiTitles = cached.animeSeasonRomajiTitles
                self.animeSeasonAniListIds = cached.animeSeasonAniListIds
                self.animeSeasonKitsuIds = cached.animeSeasonKitsuIds
                self.animeSpecialEntries = cached.animeSpecialEntries
                self.selectedEpisodeForSearch = nil
                self.castMembers = cached.castMembers
                self.selectedSpecialEpisodeContext = nil
                self.isLoading = false
                self.hasLoadedContent = true
                Logger.shared.log("MediaDetail cache state applied: key=\(detailCacheKey) tvSeasons=\(cached.tvShowDetail?.seasons.count ?? 0) selectedSeason=\(cached.selectedSeason?.seasonNumber.description ?? "nil") anilistEpisodes=\(cached.anilistEpisodes?.count ?? 0)", type: "CrashProbe")
                if cached.isAnimeShow, !self.searchResult.isMovie, cached.animeSpecialEntries.isEmpty {
                    self.startAnimeSpecialsLoad(
                        tmdbShowId: self.searchResult.id,
                        fallbackPosterURL: cached.tvShowDetail?.fullPosterURL,
                        baseAniListIds: Array(cached.animeSeasonAniListIds.values)
                    )
                } else {
                    self.isLoadingAnimeSpecials = false
                }
                self.startTraktFeatureLoad()
                self.startExperimentalExtrasLoadIfNeeded()
            }
            return
        }
        Logger.shared.log("MediaDetail cache miss: key=\(detailCacheKey)", type: "CrashProbe")

        isLoading = true
        errorMessage = nil
        seasonDetail = nil
        selectedEpisodeForSearch = nil
        animeRating = nil
        animeSeasonRomajiTitles = [:]
        animeSeasonAniListIds = [:]
        animeSeasonKitsuIds = [:]
        animeSpecialEntries = []
        isLoadingAnimeSpecials = false
        traktComments = []
        traktRating = nil
        detailStills = []
        detailTrailers = []
        isLoadingTraktComments = false
        isLoadingExperimentalExtras = false
        selectedSpecialEpisodeContext = nil
        Logger.shared.log("MediaDetail scheduling async task: id=\(searchResult.id)", type: "CrashProbe")
        
        detailLoadTask = Task {
            Logger.shared.log("MediaDetail async task entered: id=\(searchResult.id)", type: "CrashProbe")
            defer {
                if Task.isCancelled {
                    Logger.shared.log("MediaDetail async task finished as cancelled: id=\(searchResult.id)", type: "CrashProbe")
                } else {
                    Logger.shared.log("MediaDetail async task finished: id=\(searchResult.id)", type: "CrashProbe")
                }
            }
            do {
                if searchResult.isMovie {
                    Logger.shared.log("Movie detail fetch begin: tmdbId=\(searchResult.id)", type: "CrashProbe")
                    Logger.shared.log("Movie detail step: getMovieDetails start id=\(searchResult.id)", type: "CrashProbe")
                    let detail = try await tmdbService.getMovieDetails(id: searchResult.id)
                    Logger.shared.log("Movie detail step: getMovieDetails done id=\(searchResult.id)", type: "CrashProbe")

                    Logger.shared.log("Movie detail step: getMovieImages start id=\(searchResult.id)", type: "CrashProbe")
                    let images = try await tmdbService.getMovieImages(id: searchResult.id, preferredLanguage: selectedLanguage)
                    Logger.shared.log("Movie detail step: getMovieImages done id=\(searchResult.id)", type: "CrashProbe")

                    Logger.shared.log("Movie detail step: getRomajiTitle start id=\(searchResult.id)", type: "CrashProbe")
                    let romaji = await tmdbService.getRomajiTitle(for: "movie", id: searchResult.id)
                    Logger.shared.log("Movie detail step: getRomajiTitle done id=\(searchResult.id)", type: "CrashProbe")

                    Logger.shared.log("Movie detail step: getMovieCredits start id=\(searchResult.id)", type: "CrashProbe")
                    let credits = try? await tmdbService.getMovieCredits(id: searchResult.id)
                    Logger.shared.log("Movie detail step: getMovieCredits done id=\(searchResult.id) cast=\(credits?.cast.count ?? 0)", type: "CrashProbe")

                    Logger.shared.log("Movie detail fetch complete: tmdbId=\(searchResult.id) cast=\(credits?.cast.count ?? 0)", type: "CrashProbe")
                    
                    if Task.isCancelled { return }
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        Logger.shared.log("Movie detail apply state begin: tmdbId=\(searchResult.id)", type: "CrashProbe")
                        self.movieDetail = detail
                        self.synopsis = detail.overview ?? ""
                        self.romajiTitle = romaji
                        if let logo = tmdbService.getBestLogo(from: images, preferredLanguage: selectedLanguage) {
                            self.logoURL = logo.fullURL
                        }
                        self.castMembers = credits?.cast ?? []
                        self.animeRating = nil
                        self.animeSpecialEntries = []
                        self.isLoadingAnimeSpecials = false
                        self.selectedSpecialEpisodeContext = nil
                        self.isLoading = false
                        self.hasLoadedContent = true
                        
                        // Store in view-level cache for instant back-navigation
                        MediaDetailCacheStore.shared.set(key: detailCacheKey, detail: .init(
                            movieDetail: detail,
                            tvShowDetail: nil,
                            selectedSeason: nil,
                            synopsis: self.synopsis,
                            romajiTitle: self.romajiTitle,
                            logoURL: self.logoURL,
                            isAnimeShow: false,
                            animeRating: nil,
                            anilistEpisodes: nil,
                            animeSeasonTitles: nil,
                            animeSeasonRomajiTitles: [:],
                            animeSeasonAniListIds: [:],
                            animeSeasonKitsuIds: [:],
                            animeSpecialEntries: [],
                            castMembers: self.castMembers,
                            timestamp: Date()
                        ))
                        Logger.shared.log("Movie detail apply state complete: tmdbId=\(searchResult.id) cast=\(self.castMembers.count) logo=\(self.logoURL != nil)", type: "CrashProbe")
                        self.startTraktFeatureLoad()
                        self.startExperimentalExtrasLoadIfNeeded()
                    }
                } else {
                    Logger.shared.log("TV detail fetch begin: tmdbId=\(searchResult.id)", type: "CrashProbe")
                    Logger.shared.log("TV detail step: queue getTVShowWithSeasons id=\(searchResult.id)", type: "CrashProbe")
                    Logger.shared.log("TV detail step: queue getTVShowImages id=\(searchResult.id)", type: "CrashProbe")
                    Logger.shared.log("TV detail step: queue getRomajiTitle id=\(searchResult.id)", type: "CrashProbe")
                    Logger.shared.log("TV detail step: queue getTVCredits id=\(searchResult.id)", type: "CrashProbe")
                    async let detailTask = tmdbService.getTVShowWithSeasons(id: searchResult.id)
                    async let imagesTask = tmdbService.getTVShowImages(id: searchResult.id, preferredLanguage: selectedLanguage)
                    async let romajiTask = tmdbService.getRomajiTitle(for: "tv", id: searchResult.id)
                    async let creditsTask = tmdbService.getTVCredits(id: searchResult.id)

                    let detail = try await detailTask
                    Logger.shared.log("TV detail step: getTVShowWithSeasons done id=\(searchResult.id) seasons=\(detail.seasons.count)", type: "CrashProbe")

                    let images: TMDBImagesResponse?
                    do {
                        images = try await imagesTask
                        Logger.shared.log("TV detail step: getTVShowImages done id=\(searchResult.id) hasImages=true", type: "CrashProbe")
                    } catch {
                        images = nil
                        Logger.shared.log("TV detail step: getTVShowImages failed id=\(searchResult.id) error=\(error.localizedDescription)", type: "CrashProbe")
                    }

                    let romaji = await romajiTask
                    Logger.shared.log("TV detail step: getRomajiTitle done id=\(searchResult.id)", type: "CrashProbe")

                    let credits: TMDBCreditsResponse?
                    do {
                        credits = try await creditsTask
                        Logger.shared.log("TV detail step: getTVCredits done id=\(searchResult.id) cast=\(credits?.cast.count ?? 0)", type: "CrashProbe")
                    } catch {
                        credits = nil
                        Logger.shared.log("TV detail step: getTVCredits failed id=\(searchResult.id) error=\(error.localizedDescription)", type: "CrashProbe")
                    }

                    
                    // Detect anime/donghua for tracking/catalog — includes JP, CN, KR, TW animation
                    let asianAnimationCountries: Set<String> = ["JP", "CN", "KR", "TW"]
                    let isAsianAnimation = detail.originCountry?.contains(where: { asianAnimationCountries.contains($0) }) ?? false
                    let isAnimation = detail.genres.contains { $0.id == 16 }
                    let detectedAsAnime = isAsianAnimation && isAnimation
                    let performanceModeEnabled = PerformanceModeSettings.isEnabled
                    let skipAniListTraversal = PerformanceModeSettings.skipsAniListTraversalForAnimeDetails
                    Logger.shared.log("MediaDetailView: \(detail.name) — isAsianAnimation=\(isAsianAnimation) isAnimation=\(isAnimation) detectedAsAnime=\(detectedAsAnime) originCountry=\(detail.originCountry ?? []) genres=\(detail.genres.map { $0.id })", type: "AniList")
                    
                    // Full anime structure stays available unless the user opts into the detail-only skip mode.
                    var animeData: AniListAnimeWithSeasons? = nil
                    if detectedAsAnime && !skipAniListTraversal {
                        do {
                            Logger.shared.log("MediaDetailView: Starting AniMap-backed anime detail fetch for \(detail.name) (tmdbId=\(detail.id)) performanceMode=\(performanceModeEnabled)", type: "AniList")
                            animeData = try await AniListService.shared.fetchAnimeDetailsWithEpisodes(
                                title: detail.name,
                                tmdbShowId: detail.id,
                                tmdbService: tmdbService,
                                tmdbShowPoster: detail.fullPosterURL,
                                token: nil
                            )
                            Logger.shared.log("MediaDetailView: Fetched AniList hybrid data for \(detail.name) with \(animeData?.seasons.count ?? 0) seasons, \(animeData?.totalEpisodes ?? 0) total episodes", type: "AniList")
                            
                            // Register AniList season IDs with tracker for accurate syncing
                            if let animeData = animeData {
                                let seasonMappings = animeData.seasons.map { (seasonNumber: $0.seasonNumber, anilistId: $0.anilistId) }
                                TrackerManager.shared.registerAniListAnimeData(tmdbId: detail.id, seasons: seasonMappings)
                            }
                        } catch {
                            Logger.shared.log("MediaDetailView: FAILED AniList fetch for \(detail.name): \(error.localizedDescription)", type: "Error")
                        }
                    } else if detectedAsAnime {
                        Logger.shared.log("MediaDetailView: Skipping AniList traversal for \(detail.name) because detail traversal performance mode is enabled", type: "AniList")
                    } else {
                        Logger.shared.log("MediaDetailView: Skipping AniList fetch - not detected as anime", type: "AniList")
                    }
                    
                    let resolvedAnimeRating: AnimeMetadataRating?
                    if detectedAsAnime {
                        resolvedAnimeRating = await AniListService.shared.preferredAnimeRating(
                            title: detail.name,
                            tmdbShowId: detail.id,
                            tmdbShowDetail: detail,
                            tmdbService: tmdbService,
                            animeData: animeData
                        )
                    } else {
                        resolvedAnimeRating = nil
                    }

                    Logger.shared.log("TV detail step: apply state start id=\(searchResult.id)", type: "CrashProbe")
                    if Task.isCancelled { return }
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        Logger.shared.log("TV detail apply state on main begin: tmdbId=\(searchResult.id) detectedAsAnime=\(detectedAsAnime) animeData=\(animeData != nil) tmdbSeasons=\(detail.seasons.count)", type: "CrashProbe")
                        self.synopsis = detail.overview ?? ""
                        self.romajiTitle = romaji
                        self.isAnimeShow = detectedAsAnime
                        self.animeRating = resolvedAnimeRating
                        self.castMembers = credits?.cast ?? []
                        
                        if let animeData = animeData {
                            Logger.shared.log("MediaDetailView: Using AniList structure — \(animeData.seasons.count) seasons", type: "AniList")
                            // Build AniList seasons list with TMDB-compatible fields
                            let aniSeasons: [TMDBSeason] = animeData.seasons.map { aniSeason in
                                Logger.shared.log("MediaDetailView: converting AniList season tmdbId=\(detail.id) anilistId=\(aniSeason.anilistId) season=\(aniSeason.seasonNumber) title=\(aniSeason.title) episodes=\(aniSeason.episodes.count) poster=\(aniSeason.posterUrl != nil)", type: "CrashProbe")
                                var posterPath: String?
                                if let posterUrl = aniSeason.posterUrl {
                                    if posterUrl.contains("image.tmdb.org") {
                                        if let range = posterUrl.range(of: "/original") {
                                            posterPath = String(posterUrl[range.lowerBound...]).replacingOccurrences(of: "/original", with: "")
                                        }
                                    } else {
                                        posterPath = posterUrl
                                    }
                                } else {
                                    posterPath = detail.posterPath
                                }
                                
                                return TMDBSeason(
                                    id: detail.id * 1000 + aniSeason.seasonNumber,
                                    name: aniSeason.title,
                                    overview: "",
                                    posterPath: posterPath,
                                    seasonNumber: aniSeason.seasonNumber,
                                    episodeCount: aniSeason.episodes.count,
                                    airDate: nil
                                )
                            }
                            
                            let detailWithAniSeasons = TMDBTVShowWithSeasons(
                                id: detail.id,
                                name: detail.name,
                                overview: detail.overview,
                                posterPath: detail.posterPath,
                                backdropPath: detail.backdropPath,
                                firstAirDate: detail.firstAirDate,
                                lastAirDate: detail.lastAirDate,
                                voteAverage: detail.voteAverage,
                                popularity: detail.popularity,
                                genres: detail.genres,
                                tagline: detail.tagline,
                                status: detail.status,
                                originalLanguage: detail.originalLanguage,
                                originalName: detail.originalName,
                                adult: detail.adult,
                                voteCount: detail.voteCount,
                                numberOfSeasons: animeData.seasons.count,
                                numberOfEpisodes: animeData.totalEpisodes,
                                episodeRunTime: detail.episodeRunTime,
                                inProduction: detail.inProduction,
                                languages: detail.languages,
                                originCountry: detail.originCountry,
                                type: detail.type,
                                seasons: aniSeasons,
                                contentRatings: detail.contentRatings,
                                externalIds: detail.externalIds
                            )
                            
                            self.tvShowDetail = detailWithAniSeasons
                            Logger.shared.log("MediaDetailView: assigned detailWithAniSeasons tmdbId=\(detail.id) seasons=\(detailWithAniSeasons.seasons.count) totalEpisodes=\(detailWithAniSeasons.numberOfEpisodes ?? 0)", type: "CrashProbe")
                            
                            var seasonTitles: [Int: String] = [:]
                            var seasonRomajiTitles: [Int: String] = [:]
                            var seasonAniListIds: [Int: Int] = [:]
                            var seasonKitsuIds: [Int: Int] = [:]
                            var allEpisodes: [AniListEpisode] = []
                            for season in animeData.seasons {
                                Logger.shared.log("MediaDetailView: flatten AniList season tmdbId=\(detail.id) season=\(season.seasonNumber) title=\(season.title) episodes=\(season.episodes.count)", type: "CrashProbe")
                                seasonTitles[season.seasonNumber] = season.title
                                if let romaji = season.romajiTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !romaji.isEmpty {
                                    seasonRomajiTitles[season.seasonNumber] = romaji
                                }
                                seasonAniListIds[season.seasonNumber] = season.anilistId
                                if let kitsuId = season.kitsuId, kitsuId > 0 {
                                    seasonKitsuIds[season.seasonNumber] = kitsuId
                                }
                                allEpisodes.append(contentsOf: season.episodes)
                            }
                            Logger.shared.log("MediaDetailView: AniList season conversion complete tmdbId=\(detail.id) aniSeasons=\(aniSeasons.count) summary=\(aniSeasons.prefix(8).map { "s\($0.seasonNumber):id\($0.id):eps\($0.episodeCount)" }.joined(separator: "|"))", type: "CrashProbe")
                            Logger.shared.log("MediaDetailView: anime state preassign tmdbId=\(detail.id) aniSeasons=\(aniSeasons.count) allEpisodes=\(allEpisodes.count) seasonTitles=\(seasonTitles.count)", type: "CrashProbe")
                            self.animeSeasonTitles = seasonTitles
                            self.animeSeasonRomajiTitles = seasonRomajiTitles
                            self.animeSeasonAniListIds = seasonAniListIds
                            self.animeSeasonKitsuIds = seasonKitsuIds
                            self.anilistEpisodes = allEpisodes
                            
                            if let firstSeason = aniSeasons.first {
                                self.selectedSeason = firstSeason
                                Logger.shared.log("MediaDetailView: selected first AniList season tmdbId=\(detail.id) season=\(firstSeason.seasonNumber) episodeCount=\(firstSeason.episodeCount)", type: "CrashProbe")
                            } else {
                                self.selectedSeason = nil
                                Logger.shared.log("MediaDetailView: AniList data had no seasons to select tmdbId=\(detail.id)", type: "CrashProbe")
                            }
                        } else {
                            // Fallback to TMDB seasons
                            Logger.shared.log("MediaDetailView: animeData is nil — falling back to pure TMDB seasons (\(detail.seasons.count) seasons)", type: "AniList")
                            self.tvShowDetail = detail
                            self.anilistEpisodes = nil
                            self.animeSeasonTitles = nil
                            self.animeSeasonRomajiTitles = [:]
                            self.animeSeasonAniListIds = [:]
                            self.animeSeasonKitsuIds = [:]
                            if let firstSeason = detail.seasons.first(where: { $0.seasonNumber > 0 }) {
                                self.selectedSeason = firstSeason
                                Logger.shared.log("MediaDetailView: selected first TMDB season tmdbId=\(detail.id) season=\(firstSeason.seasonNumber) episodeCount=\(firstSeason.episodeCount)", type: "CrashProbe")
                            } else {
                                self.selectedSeason = nil
                                Logger.shared.log("MediaDetailView: TMDB detail had no positive seasons tmdbId=\(detail.id) seasons=\(detail.seasons.count)", type: "CrashProbe")
                            }
                        }
                        
                        if let images, let logo = tmdbService.getBestLogo(from: images, preferredLanguage: selectedLanguage) {
                            self.logoURL = logo.fullURL
                            Logger.shared.log("MediaDetailView: assigned logo tmdbId=\(detail.id) hasLogo=true", type: "CrashProbe")
                        } else {
                            Logger.shared.log("MediaDetailView: assigned logo tmdbId=\(detail.id) hasLogo=false", type: "CrashProbe")
                        }
                        self.selectedEpisodeForSearch = nil
                        self.isLoading = false
                        self.hasLoadedContent = true
                        Logger.shared.log("MediaDetailView: state applied tmdbId=\(searchResult.id) isAnime=\(self.isAnimeShow) tvSeasons=\(self.tvShowDetail?.seasons.count ?? 0) selectedSeason=\(self.selectedSeason?.seasonNumber.description ?? "nil") anilistEpisodes=\(self.anilistEpisodes?.count ?? 0) hasLoaded=\(self.hasLoadedContent)", type: "CrashProbe")
                        
                        // Store in view-level cache for instant back-navigation
                        MediaDetailCacheStore.shared.set(key: detailCacheKey, detail: .init(
                            movieDetail: nil,
                            tvShowDetail: self.tvShowDetail,
                            selectedSeason: self.selectedSeason,
                            synopsis: self.synopsis,
                            romajiTitle: self.romajiTitle,
                            logoURL: self.logoURL,
                            isAnimeShow: self.isAnimeShow,
                            animeRating: self.animeRating,
                            anilistEpisodes: self.anilistEpisodes,
                            animeSeasonTitles: self.animeSeasonTitles,
                            animeSeasonRomajiTitles: self.animeSeasonRomajiTitles,
                            animeSeasonAniListIds: self.animeSeasonAniListIds,
                            animeSeasonKitsuIds: self.animeSeasonKitsuIds,
                            animeSpecialEntries: self.animeSpecialEntries,
                            castMembers: self.castMembers,
                            timestamp: Date()
                        ))
                        Logger.shared.log("MediaDetailView: cache stored key=\(detailCacheKey) selectedSeason=\(self.selectedSeason?.seasonNumber.description ?? "nil")", type: "CrashProbe")
                        if detectedAsAnime {
                            self.startAnimeSpecialsLoad(
                                tmdbShowId: detail.id,
                                fallbackPosterURL: detail.fullPosterURL,
                                baseAniListIds: Array(self.animeSeasonAniListIds.values)
                            )
                        } else {
                            self.animeSpecialEntries = []
                            self.isLoadingAnimeSpecials = false
                            self.selectedSpecialEpisodeContext = nil
                        }
                        self.startTraktFeatureLoad()
                        self.startExperimentalExtrasLoadIfNeeded()
                    }
                    Logger.shared.log("TV detail fetch complete: tmdbId=\(searchResult.id)", type: "CrashProbe")
                }
            } catch is CancellationError {
                Logger.shared.log("MediaDetail load cancelled: id=\(searchResult.id) type=\(searchResult.mediaType)", type: "CrashProbe")
            } catch {
                Logger.shared.log("MediaDetail load failed: id=\(searchResult.id) type=\(searchResult.mediaType) error=\(error.localizedDescription)", type: "CrashProbe")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.hasLoadedContent = true
                }
            }
        }
    }

}

struct SpecialEpisodeListContext: Identifiable {
    let id: Int
    let anilistId: Int
    let title: String
    let alternateTitle: String?
    let formatLabel: String
    let posterUrl: String?
    let localSeasonNumber: Int
    let mappedSeasonNumber: Int?
    let episodeOffset: Int?
    let imdbId: String?
    let episodes: [TMDBEpisode]

    init?(entry: AniListSpecialSearchEntry, tmdbShowId: Int) {
        let localSeasonNumber = 100_000 + entry.id
        let title = entry.preferredTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        self.id = entry.id
        self.anilistId = entry.id
        self.title = title
        self.alternateTitle = entry.alternateSearchTitle
        self.formatLabel = entry.formatLabel
        self.posterUrl = entry.posterUrl
        self.localSeasonNumber = localSeasonNumber
        self.mappedSeasonNumber = entry.tmdbSeasonNumber
        self.episodeOffset = entry.episodeOffset ?? 0
        self.imdbId = entry.imdbId

        let count = max(1, entry.episodeCount)
        self.episodes = (1...count).map { episodeNumber in
            let sourceEpisode = entry.episodes.first(where: { $0.number == episodeNumber })
            let resolvedEpisodeTitle: String
            if count == 1 {
                resolvedEpisodeTitle = title
            } else if let sourceTitle = sourceEpisode?.title.trimmingCharacters(in: .whitespacesAndNewlines),
                      !sourceTitle.isEmpty {
                resolvedEpisodeTitle = sourceTitle
            } else {
                resolvedEpisodeTitle = "Episode \(episodeNumber)"
            }
            return TMDBEpisode(
                id: tmdbShowId * 1_000_000 + entry.id * 100 + episodeNumber,
                name: resolvedEpisodeTitle,
                overview: sourceEpisode?.description,
                stillPath: sourceEpisode?.stillPath,
                episodeNumber: episodeNumber,
                seasonNumber: localSeasonNumber,
                airDate: sourceEpisode?.airDate,
                runtime: sourceEpisode?.runtime,
                voteAverage: 0,
                voteCount: 0
            )
        }
    }

    var seasonDetail: TMDBSeasonDetail {
        TMDBSeasonDetail(
            id: id,
            name: title,
            overview: "",
            posterPath: posterUrl,
            seasonNumber: localSeasonNumber,
            airDate: nil,
            episodes: episodes
        )
    }

    func playbackContext(for episode: TMDBEpisode) -> EpisodePlaybackContext {
        EpisodePlaybackContext(
            localSeasonNumber: localSeasonNumber,
            localEpisodeNumber: episode.episodeNumber,
            anilistMediaId: anilistId,
            tmdbSeasonNumber: mappedSeasonNumber,
            tmdbEpisodeNumber: mappedSeasonNumber == nil ? nil : (episodeOffset ?? 0) + episode.episodeNumber,
            tmdbEpisodeOffset: episodeOffset,
            animeAbsoluteEpisodeNumber: nil,
            animeSeasonEpisodeCount: nil,
            isSpecial: true,
            titleOnlySearch: episodes.count == 1
        )
    }
}

private struct AnimeSpecialSearchRequest: Identifiable {
    let id = UUID()
    let title: String
    let originalTitle: String?
    let episode: TMDBEpisode?
    let originalSeasonNumber: Int?
    let originalEpisodeNumber: Int?
    let imdbId: String?
    let posterUrl: String?
    let titleOnly: Bool
    let playbackContext: EpisodePlaybackContext?
}
