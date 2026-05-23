//
//  StremioAddonManager.swift
//  Luna
//
//  Created by Soupy on 2026.
//

import CryptoKit
import Foundation

@MainActor
class StremioAddonManager: ObservableObject {
    static let shared = StremioAddonManager()

    @Published var addons: [StremioAddon] = []
    @Published var isDownloading = false

    var activeAddons: [StremioAddon] {
        addons.filter { $0.isActive }
    }

    private init() {
        loadAddons()
    }

    // MARK: - Load

    func loadAddons() {
        addons = StremioAddonStore.shared.getAddons()
    }

    // MARK: - Add Addon

    func addAddon(from url: String) async throws {
        isDownloading = true
        defer { isDownloading = false }

        let manifest = try await StremioClient.shared.fetchManifest(from: url)

        guard manifest.supportsStreams else {
            throw StremioAddonError.noStreamSupport
        }

        // Check for duplicate by manifest id
        if addons.contains(where: { $0.manifest.id == manifest.id }) {
            throw StremioAddonError.alreadyExists
        }

        let id = generateAddonUUID(manifest: manifest)
        let manifestData = try JSONEncoder().encode(manifest)
        let manifestJSON = String(data: manifestData, encoding: .utf8) ?? ""

        // Normalize the URL
        var configuredURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if configuredURL.hasSuffix("/manifest.json") {
            configuredURL = String(configuredURL.dropLast("/manifest.json".count))
        }
        if configuredURL.hasSuffix("/") {
            configuredURL = String(configuredURL.dropLast())
        }

        StremioAddonStore.shared.storeAddon(
            id: id,
            configuredURL: configuredURL,
            manifestJSON: manifestJSON,
            isActive: true
        )
        AutoModeSourceSelection.appendSourceIfNeeded("stremio:\(id.uuidString)")

        loadAddons()
        Logger.shared.log("Stremio: Added addon '\(manifest.name)' (\(manifest.id))", type: "Stremio")
    }

    // MARK: - Remove Addon

    func removeAddon(_ addon: StremioAddon) {
        StremioAddonStore.shared.remove(addon)
        loadAddons()
    }

    // MARK: - Toggle Active

    func setAddonState(_ addon: StremioAddon, isActive: Bool) {
        let manifestData = (try? JSONEncoder().encode(addon.manifest)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        StremioAddonStore.shared.storeAddon(
            id: addon.id,
            configuredURL: addon.configuredURL,
            manifestJSON: manifestData,
            isActive: isActive
        )
        loadAddons()
    }

    // MARK: - Reconfigure

    func reconfigureAddon(_ addon: StremioAddon, newURL: String) async throws {
        let manifest = try await StremioClient.shared.fetchManifest(from: newURL)

        guard manifest.supportsStreams else {
            throw StremioAddonError.noStreamSupport
        }

        var configuredURL = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if configuredURL.hasSuffix("/manifest.json") {
            configuredURL = String(configuredURL.dropLast("/manifest.json".count))
        }
        if configuredURL.hasSuffix("/") {
            configuredURL = String(configuredURL.dropLast())
        }

        let manifestData = try JSONEncoder().encode(manifest)
        let manifestJSON = String(data: manifestData, encoding: .utf8) ?? ""

        StremioAddonStore.shared.storeAddon(
            id: addon.id,
            configuredURL: configuredURL,
            manifestJSON: manifestJSON,
            isActive: addon.isActive
        )

        loadAddons()
        Logger.shared.log("Stremio: Reconfigured addon '\(manifest.name)' (\(manifest.id))", type: "Stremio")
    }

    // MARK: - Reorder

    func moveAddons(fromOffsets: IndexSet, toOffset: Int) {
        var mutable = addons
        mutable.move(fromOffsets: fromOffsets, toOffset: toOffset)

        let entities = StremioAddonStore.shared.getEntities()
        for (index, addon) in mutable.enumerated() {
            if let entity = entities.first(where: { $0.id == addon.id }) {
                entity.sortIndex = Int64(index)
            }
        }

        StremioAddonStore.shared.save()
        loadAddons()
    }

    // MARK: - Refresh Manifests

    func refreshAddons() async {
        for addon in addons {
            do {
                let manifest = try await StremioClient.shared.fetchManifest(from: addon.configuredURL)
                let manifestData = try JSONEncoder().encode(manifest)
                let manifestJSON = String(data: manifestData, encoding: .utf8) ?? ""

                StremioAddonStore.shared.storeAddon(
                    id: addon.id,
                    configuredURL: addon.configuredURL,
                    manifestJSON: manifestJSON,
                    isActive: addon.isActive
                )

                Logger.shared.log("Stremio: Refreshed addon '\(manifest.name)'", type: "Stremio")
            } catch {
                Logger.shared.log("Stremio: Failed to refresh '\(addon.manifest.name)': \(error.localizedDescription)", type: "Stremio")
            }
        }

        loadAddons()
    }

    // MARK: - Fetch Streams from All Active Addons

    struct AddonStreamResult: Identifiable {
        let id = UUID()
        let addon: StremioAddon
        let streams: [StremioStream]
    }

    private struct RankedCatalogMeta {
        let catalog: StremioCatalog
        let meta: StremioMetaPreview
        let score: Double
        let query: String
    }

    /// Fetches streams from all active addons for a given piece of content.
    /// Returns results as they come in via the callback, similar to progressive JS search.
    func fetchStreamsFromAddons(
        tmdbId: Int,
        imdbId: String?,
        type: String,
        season: Int?,
        episode: Int?,
        anilistId: Int? = nil,
        playbackContext: EpisodePlaybackContext? = nil,
        titleCandidates: [String] = [],
        expectedYear: Int? = nil,
        onResult: @escaping (StremioAddon, [StremioStream]) -> Void,
        onComplete: @escaping () -> Void
    ) async {
        let active = activeAddons
        Logger.shared.log("Stremio: fetchStreamsFromAddons — \(active.count) active addon(s), tmdbId=\(tmdbId) imdbId=\(imdbId ?? "nil") type=\(type) s=\(season?.description ?? "nil") e=\(episode?.description ?? "nil")", type: "Stremio")
        guard !active.isEmpty else {
            Logger.shared.log("Stremio: No active addons, skipping", type: "Stremio")
            onComplete()
            return
        }

        let client = StremioClient.shared
        let maxConcurrent = 2

        await withTaskGroup(of: (StremioAddon, [StremioStream])?.self) { group in
            var nextIndex = 0

            // Seed the group with the first batch
            while nextIndex < active.count && nextIndex < maxConcurrent {
                let addon = active[nextIndex]
                group.addTask {
                    await Self.fetchStreamsForAddon(
                        addon,
                        client: client,
                        tmdbId: tmdbId,
                        imdbId: imdbId,
                        type: type,
                        season: season,
                        episode: episode,
                        anilistId: anilistId,
                        playbackContext: playbackContext,
                        titleCandidates: titleCandidates,
                        expectedYear: expectedYear
                    )
                }
                nextIndex += 1
            }

            // As each completes, report it and start the next one
            for await result in group {
                if let (addon, streams) = result {
                    await MainActor.run {
                        onResult(addon, streams)
                    }
                }

                if nextIndex < active.count {
                    let addon = active[nextIndex]
                    group.addTask {
                        await Self.fetchStreamsForAddon(
                            addon,
                            client: client,
                            tmdbId: tmdbId,
                            imdbId: imdbId,
                            type: type,
                            season: season,
                            episode: episode,
                            anilistId: anilistId,
                            playbackContext: playbackContext,
                            titleCandidates: titleCandidates,
                            expectedYear: expectedYear
                        )
                    }
                    nextIndex += 1
                }
            }
        }

        onComplete()
    }

    func fetchStreamsFromAddon(
        _ addon: StremioAddon,
        tmdbId: Int,
        imdbId: String?,
        type: String,
        season: Int?,
        episode: Int?,
        anilistId: Int? = nil,
        playbackContext: EpisodePlaybackContext? = nil,
        titleCandidates: [String] = [],
        expectedYear: Int? = nil
    ) async -> [StremioStream] {
        await Self.resolveStreamsForAddon(
            addon,
            client: StremioClient.shared,
            tmdbId: tmdbId,
            imdbId: imdbId,
            type: type,
            season: season,
            episode: episode,
            anilistId: anilistId,
            playbackContext: playbackContext,
            titleCandidates: titleCandidates,
            expectedYear: expectedYear
        )
    }

    // MARK: - Helpers

    private static func fetchStreamsForAddon(
        _ addon: StremioAddon,
        client: StremioClient,
        tmdbId: Int,
        imdbId: String?,
        type: String,
        season: Int?,
        episode: Int?,
        anilistId: Int?,
        playbackContext: EpisodePlaybackContext?,
        titleCandidates: [String],
        expectedYear: Int?
    ) async -> (StremioAddon, [StremioStream])? {
        let streams = await resolveStreamsForAddon(
            addon,
            client: client,
            tmdbId: tmdbId,
            imdbId: imdbId,
            type: type,
            season: season,
            episode: episode,
            anilistId: anilistId,
            playbackContext: playbackContext,
            titleCandidates: titleCandidates,
            expectedYear: expectedYear
        )
        return (addon, streams)
    }

    private static func resolveStreamsForAddon(
        _ addon: StremioAddon,
        client: StremioClient,
        tmdbId: Int,
        imdbId: String?,
        type: String,
        season: Int?,
        episode: Int?,
        anilistId: Int?,
        playbackContext: EpisodePlaybackContext?,
        titleCandidates: [String],
        expectedYear: Int?
    ) async -> [StremioStream] {
        Logger.shared.log("Stremio: Starting fetch for addon '\(addon.manifest.name)' baseURL=\(addon.configuredURL)", type: "Stremio")

        let contentIds = client.buildContentIds(
            tmdbId: tmdbId,
            imdbId: imdbId,
            type: type,
            season: season,
            episode: episode,
            anilistId: anilistId,
            anilistSeason: animeLocalStremioSeason(from: playbackContext),
            anilistEpisode: animeLocalStremioEpisode(from: playbackContext),
            kitsuId: playbackContext?.kitsuMediaId,
            kitsuEpisode: animeLocalKitsuEpisode(from: playbackContext),
            alternateSeason: animeLocalSeriesSeason(from: playbackContext),
            alternateEpisode: animeLocalSeriesEpisode(from: playbackContext),
            addon: addon
        )

        var lastError: Error?
        var directStreams: [StremioStream] = []
        var directHitCount = 0
        for contentId in contentIds {
            Logger.shared.log("Stremio: \(addon.manifest.name) requesting streams with contentId='\(contentId)'", type: "Stremio")

            do {
                let streams = try await client.fetchStreams(
                    baseURL: addon.configuredURL,
                    type: type,
                    id: contentId
                )
                Logger.shared.log("Stremio: \(addon.manifest.name) returned \(streams.count) stream(s) for '\(contentId)'", type: "Stremio")
                if !streams.isEmpty {
                    directHitCount += 1
                    directStreams.append(contentsOf: streams)
                }
            } catch {
                lastError = error
                Logger.shared.log("Stremio: \(addon.manifest.name) FAILED with id '\(contentId)': \(error.localizedDescription)", type: "Stremio")
            }
        }

        let dedupedDirectStreams = dedupeStreams(directStreams)
        if !dedupedDirectStreams.isEmpty {
            Logger.shared.log("Stremio: \(addon.manifest.name) merged \(dedupedDirectStreams.count) stream(s) from \(directHitCount) direct content ID(s)", type: "Stremio")
            return dedupedDirectStreams
        }

        if contentIds.isEmpty {
            Logger.shared.log("Stremio: No direct content ID for \(addon.manifest.name); trying catalog fallback if available", type: "Stremio")
        } else if let lastError {
            Logger.shared.log("Stremio: \(addon.manifest.name) exhausted content IDs: \(lastError.localizedDescription)", type: "Stremio")
        }

        let fallbackStreams = await fetchStreamsByCatalogSearch(
            addon,
            client: client,
            requestedType: type,
            season: season,
            episode: episode,
            playbackContext: playbackContext,
            titleCandidates: titleCandidates,
            expectedYear: expectedYear
        )
        if !fallbackStreams.isEmpty {
            return fallbackStreams
        }

        return []
    }

    private static func fetchStreamsByCatalogSearch(
        _ addon: StremioAddon,
        client: StremioClient,
        requestedType: String,
        season: Int?,
        episode: Int?,
        playbackContext: EpisodePlaybackContext?,
        titleCandidates: [String],
        expectedYear: Int?
    ) async -> [StremioStream] {
        let searchQueries = normalizedSearchQueries(titleCandidates)
        guard !searchQueries.isEmpty else {
            Logger.shared.log("Stremio: Catalog fallback skipped for \(addon.manifest.name) because no title candidates were available", type: "Stremio")
            return []
        }

        let catalogs = addon.manifest.searchableCatalogs
            .filter { $0.supportsType(requestedType) }
            .prefix(3)

        guard !catalogs.isEmpty else {
            Logger.shared.log("Stremio: Catalog fallback unavailable for \(addon.manifest.name); no searchable \(requestedType) catalog", type: "Stremio")
            return []
        }

        var ranked = [RankedCatalogMeta]()
        for catalog in catalogs {
            for query in searchQueries.prefix(4) {
                do {
                    let metas = try await client.fetchCatalogMetas(
                        baseURL: addon.configuredURL,
                        catalog: catalog,
                        searchQuery: query
                    )
                    ranked.append(contentsOf: metas.prefix(12).compactMap { meta in
                        guard metaMatchesRequestedType(meta, catalog: catalog, requestedType: requestedType) else {
                            return nil
                        }
                        let score = catalogMetaScore(
                            meta,
                            titleCandidates: titleCandidates,
                            expectedYear: expectedYear
                        )
                        guard score >= 0.78 else { return nil }
                        return RankedCatalogMeta(catalog: catalog, meta: meta, score: score, query: query)
                    })
                } catch {
                    Logger.shared.log("Stremio: Catalog fallback query failed addon=\(addon.manifest.name) catalog=\(catalog.id) query='\(query)' error=\(error.localizedDescription)", type: "Stremio")
                }
            }
        }

        let candidates = ranked
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.0001 {
                    return lhs.score > rhs.score
                }
                return lhs.meta.name.count < rhs.meta.name.count
            }
            .prefix(5)

        guard !candidates.isEmpty else {
            Logger.shared.log("Stremio: Catalog fallback found no confident match for \(addon.manifest.name)", type: "Stremio")
            return []
        }

        for candidate in candidates {
            Logger.shared.log("Stremio: Catalog fallback trying \(candidate.meta.name) id=\(candidate.meta.id) score=\(String(format: "%.2f", candidate.score)) query='\(candidate.query)'", type: "Stremio")
            let streams = await fetchStreamsForCatalogMeta(
                candidate.meta,
                catalog: candidate.catalog,
                addon: addon,
                client: client,
                requestedType: requestedType,
                season: season,
                episode: episode,
                playbackContext: playbackContext
            )
            if !streams.isEmpty {
                Logger.shared.log("Stremio: Catalog fallback resolved \(streams.count) stream(s) from \(candidate.meta.name)", type: "Stremio")
                return streams
            }
        }

        Logger.shared.log("Stremio: Catalog fallback exhausted confident matches for \(addon.manifest.name)", type: "Stremio")
        return []
    }

    private static func fetchStreamsForCatalogMeta(
        _ preview: StremioMetaPreview,
        catalog: StremioCatalog,
        addon: StremioAddon,
        client: StremioClient,
        requestedType: String,
        season: Int?,
        episode: Int?,
        playbackContext: EpisodePlaybackContext?
    ) async -> [StremioStream] {
        let streamType = preview.type ?? catalog.type
        let directPreviewStreams = streamsFromMeta(preview, season: season, episode: episode, playbackContext: playbackContext)
        if !directPreviewStreams.isEmpty {
            return directPreviewStreams
        }

        var meta = preview
        if addon.manifest.supportsMeta {
            do {
                if let fetched = try await client.fetchMeta(baseURL: addon.configuredURL, type: streamType, id: preview.id) {
                    meta = fetched
                    let metaStreams = streamsFromMeta(fetched, season: season, episode: episode, playbackContext: playbackContext)
                    if !metaStreams.isEmpty {
                        return metaStreams
                    }
                }
            } catch {
                Logger.shared.log("Stremio: Catalog fallback meta fetch failed id=\(preview.id) error=\(error.localizedDescription)", type: "Stremio")
            }
        }

        for contentId in streamIdsFromMeta(meta, requestedType: requestedType, season: season, episode: episode, playbackContext: playbackContext) {
            do {
                let streams = try await client.fetchStreams(
                    baseURL: addon.configuredURL,
                    type: streamType,
                    id: contentId
                )
                if !streams.isEmpty {
                    return streams
                }
            } catch {
                Logger.shared.log("Stremio: Catalog fallback stream fetch failed id=\(contentId) error=\(error.localizedDescription)", type: "Stremio")
            }
        }

        return []
    }

    private static func streamsFromMeta(_ meta: StremioMetaPreview, season: Int?, episode: Int?, playbackContext: EpisodePlaybackContext?) -> [StremioStream] {
        guard let videos = meta.videos else { return [] }

        let matchingVideos: [StremioVideo]
        if let season, let episode {
            let exactMatches = videos.filter { $0.season == season && $0.episode == episode }
            matchingVideos = exactMatches.isEmpty ? autoEpisodeMatches(videos: videos, playbackContext: playbackContext) : exactMatches
        } else if let defaultVideoId = meta.behaviorHints?.defaultVideoId,
                  let defaultVideo = videos.first(where: { $0.id == defaultVideoId }) {
            matchingVideos = [defaultVideo]
        } else {
            matchingVideos = videos
        }

        return dedupeStreams(
            matchingVideos
                .flatMap { $0.streams ?? [] }
                .filter { $0.isDirectHTTP }
        )
    }

    private static func streamIdsFromMeta(_ meta: StremioMetaPreview, requestedType: String, season: Int?, episode: Int?, playbackContext: EpisodePlaybackContext?) -> [String] {
        var candidates = [String]()

        if let season, let episode {
            if let videoId = meta.videos?.first(where: { $0.season == season && $0.episode == episode })?.id {
                candidates.append(videoId)
            }
            candidates.append(contentsOf: autoEpisodeMatches(videos: meta.videos ?? [], playbackContext: playbackContext).map(\.id))
            if isKitsuMetaId(meta.id) {
                if let localEpisode = animeLocalKitsuEpisode(from: playbackContext) {
                    candidates.append(kitsuStreamId(from: meta.id, episode: localEpisode))
                } else if episode > 0 {
                    candidates.append(kitsuStreamId(from: meta.id, episode: episode))
                }
            } else {
                candidates.append("\(meta.id):\(season):\(episode)")
                if let localSeason = animeLocalSeriesSeason(from: playbackContext),
                   let localEpisode = animeLocalSeriesEpisode(from: playbackContext) {
                    candidates.append("\(meta.id):\(localSeason):\(localEpisode)")
                }
                if shouldTrySeasonScopedAnimeMetaId(meta.id, playbackContext: playbackContext),
                   let localSeason = animeLocalStremioSeason(from: playbackContext),
                   let localEpisode = animeLocalStremioEpisode(from: playbackContext) {
                    candidates.append("\(meta.id):\(localSeason):\(localEpisode)")
                }
            }
        } else if requestedType == "movie" {
            candidates.append(meta.id)
        } else if let defaultVideoId = meta.behaviorHints?.defaultVideoId {
            candidates.append(defaultVideoId)
        }

        if candidates.isEmpty {
            candidates.append(meta.id)
        }

        var seen = Set<String>()
        return candidates.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func animeLocalStremioSeason(from context: EpisodePlaybackContext?) -> Int? {
        guard let context,
              !context.isSpecial,
              !context.titleOnlySearch,
              context.anilistMediaId != nil,
              context.localEpisodeNumber > 0 else {
            return nil
        }
        return 1
    }

    private static func animeLocalStremioEpisode(from context: EpisodePlaybackContext?) -> Int? {
        guard let context,
              !context.isSpecial,
              !context.titleOnlySearch,
              context.anilistMediaId != nil,
              context.localEpisodeNumber > 0 else {
            return nil
        }
        return context.localEpisodeNumber
    }

    private static func animeLocalKitsuEpisode(from context: EpisodePlaybackContext?) -> Int? {
        guard let context,
              !context.isSpecial,
              !context.titleOnlySearch,
              context.kitsuMediaId != nil,
              context.localEpisodeNumber > 0 else {
            return nil
        }
        return context.localEpisodeNumber
    }

    private static func animeLocalSeriesSeason(from context: EpisodePlaybackContext?) -> Int? {
        guard let context,
              !context.isSpecial,
              !context.titleOnlySearch,
              context.anilistMediaId != nil,
              context.localSeasonNumber > 0 else {
            return nil
        }
        return context.localSeasonNumber
    }

    private static func animeLocalSeriesEpisode(from context: EpisodePlaybackContext?) -> Int? {
        guard let context,
              !context.isSpecial,
              !context.titleOnlySearch,
              context.anilistMediaId != nil,
              context.localEpisodeNumber > 0 else {
            return nil
        }
        return context.localEpisodeNumber
    }

    private static func shouldTrySeasonScopedAnimeMetaId(_ metaId: String, playbackContext: EpisodePlaybackContext?) -> Bool {
        guard playbackContext?.anilistMediaId != nil else { return false }
        let lowercased = metaId.lowercased()
        return !lowercased.hasPrefix("tt") &&
            !lowercased.hasPrefix("imdb:") &&
            !lowercased.hasPrefix("tmdb:") &&
            !lowercased.hasPrefix("kitsu:")
    }

    private static func isKitsuMetaId(_ metaId: String) -> Bool {
        metaId.lowercased().hasPrefix("kitsu:")
    }

    private static func kitsuStreamId(from metaId: String, episode: Int) -> String {
        let parts = metaId.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count >= 3,
           let last = parts.last,
           Int(last) != nil {
            return metaId
        }
        return "\(metaId):\(episode)"
    }

    private static func autoEpisodeMatches(videos: [StremioVideo], playbackContext: EpisodePlaybackContext?) -> [StremioVideo] {
        guard let context = playbackContext,
              !context.isSpecial,
              !context.titleOnlySearch,
              let seasonEpisodeCount = context.animeSeasonEpisodeCount,
              seasonEpisodeCount > 0,
              context.localEpisodeNumber > 0 else {
            return []
        }

        let episodeNumbers = videos.compactMap(\.episode)
        guard let maxEpisode = episodeNumbers.max() else { return [] }

        if let absoluteEpisode = context.animeAbsoluteEpisodeNumber,
           absoluteEpisode > 0,
           maxEpisode > seasonEpisodeCount {
            return videos.filter { $0.episode == absoluteEpisode }
        }

        if maxEpisode <= seasonEpisodeCount {
            return videos.filter { $0.episode == context.localEpisodeNumber }
        }

        return []
    }

    private static func metaMatchesRequestedType(_ meta: StremioMetaPreview, catalog: StremioCatalog, requestedType: String) -> Bool {
        let metaType = meta.type ?? catalog.type
        return metaType == requestedType || (requestedType == "series" && metaType == "tv")
    }

    private static func catalogMetaScore(_ meta: StremioMetaPreview, titleCandidates: [String], expectedYear: Int?) -> Double {
        let titleScores = titleCandidates.map { titleSimilarity(expected: $0, result: meta.name) }
        var score = titleScores.max() ?? 0

        if let expectedYear, let releaseYear = releaseYear(from: meta) {
            let distance = abs(expectedYear - releaseYear)
            if distance == 0 {
                score += 0.08
            } else if distance == 1 {
                score += 0.03
            } else if distance > 3 {
                score -= 0.12
            }
        }

        return min(max(score, 0), 1)
    }

    private static func titleSimilarity(expected: String, result: String) -> Double {
        let expectedCanonical = normalizedTitle(expected)
        let resultCanonical = normalizedTitle(result)
        guard !expectedCanonical.isEmpty, !resultCanonical.isEmpty else { return 0 }

        let raw = HybridSimilarity.calculateSimilarity(original: expected, result: result)
        let canonical = HybridSimilarity.calculateSimilarity(original: expectedCanonical, result: resultCanonical)
        let token = tokenOverlapScore(expectedCanonical, resultCanonical)

        var score = max(raw, canonical) * 0.68 + token * 0.32
        if expectedCanonical == resultCanonical {
            score += 0.12
        } else if expectedCanonical.contains(resultCanonical) || resultCanonical.contains(expectedCanonical) {
            score += 0.05
        }
        return min(max(score, 0), 1)
    }

    private static func normalizedSearchQueries(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { stripEpisodeSuffix(from: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert(normalizedTitle($0)).inserted }
    }

    private static func normalizedTitle(_ title: String) -> String {
        title
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripEpisodeSuffix(from title: String) -> String {
        let patterns = [
            #"(?i)\s*-\s*S\d{1,3}E\d{1,4}$"#,
            #"(?i)\s*S\d{1,3}E\d{1,4}$"#,
            #"(?i)\s*-\s*E\d{1,4}$"#,
            #"(?i)\s*E\d{1,4}$"#,
            #"(?i)\s*episode\s+\d{1,4}$"#
        ]

        var stripped = title
        for pattern in patterns {
            if let range = stripped.range(of: pattern, options: .regularExpression) {
                stripped.removeSubrange(range)
                break
            }
        }
        return stripped
    }

    private static func tokenOverlapScore(_ lhs: String, _ rhs: String) -> Double {
        let ignored: Set<String> = ["a", "an", "and", "the", "of", "to", "in", "on", "tv", "series", "episode"]
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init).filter { $0.count > 1 && !ignored.contains($0) })
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init).filter { $0.count > 1 && !ignored.contains($0) })
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        return Double(lhsTokens.intersection(rhsTokens).count) / Double(max(lhsTokens.count, rhsTokens.count))
    }

    private static func releaseYear(from meta: StremioMetaPreview) -> Int? {
        let source = meta.releaseInfo ?? meta.released
        guard let source else { return nil }
        let pattern = #"\b(19|20)\d{2}\b"#
        guard let range = source.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return Int(source[range])
    }

    private static func dedupeStreams(_ streams: [StremioStream]) -> [StremioStream] {
        var seen = Set<String>()
        return streams.filter { stream in
            let key = stream.url ?? stream.infoHash ?? stream.id
            return seen.insert(key).inserted
        }
    }

    private func generateAddonUUID(manifest: StremioManifest) -> UUID {
        let input = manifest.id
        let hash = SHA256.hash(data: Data(input.utf8))
        let hashBytes = Array(hash)
        return UUID(uuid: (
            hashBytes[0], hashBytes[1], hashBytes[2], hashBytes[3],
            hashBytes[4], hashBytes[5], hashBytes[6], hashBytes[7],
            hashBytes[8], hashBytes[9], hashBytes[10], hashBytes[11],
            hashBytes[12], hashBytes[13], hashBytes[14], hashBytes[15]
        ))
    }

    enum StremioAddonError: LocalizedError {
        case noStreamSupport
        case alreadyExists

        var errorDescription: String? {
            switch self {
            case .noStreamSupport: return "This addon does not support streams"
            case .alreadyExists: return "This addon is already installed"
            }
        }
    }
}
