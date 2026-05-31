//
//  ScheduleViewModel.swift
//  Luna
//
//  Created by Soupy-dev
//

import Foundation

enum ScheduleMode: String, CaseIterable, Identifiable {
    case anime
    case western
    case combined
    case library

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anime:
            return "Anime"
        case .western:
            return "Western"
        case .combined:
            return "Combined"
        case .library:
            return "Library"
        }
    }

    var description: String {
        switch self {
        case .anime:
            return "Anime episodes from AniList."
        case .western:
            return "Regional Western TV and streaming episodes."
        case .combined:
            return "Anime and Western episodes together."
        case .library:
            return "Upcoming episodes from your saved library and bookmarks."
        }
    }

    static func sanitized(_ rawValue: String?) -> ScheduleMode {
        ScheduleMode(rawValue: rawValue ?? "") ?? .anime
    }

    static func sanitizedRawValue(_ rawValue: String?) -> String {
        sanitized(rawValue).rawValue
    }
}

enum ScheduleSource {
    case anime
    case western
    case library

    var displayName: String {
        switch self {
        case .anime:
            return "Anime"
        case .western:
            return "Western"
        case .library:
            return "Library"
        }
    }
}

struct ScheduleEntry: Identifiable {
    let id: String
    let source: ScheduleSource
    let sourceMediaId: Int
    let title: String
    let airingAt: Date
    let episode: Int
    let season: Int?
    let coverImage: String?
    let englishTitle: String?
    let romajiTitle: String?
    let nativeTitle: String?
    let format: String?
    let hasKnownAiringTime: Bool
    let tmdbResult: TMDBSearchResult?

    init(animeEntry: AniListAiringScheduleEntry) {
        id = "anime-\(animeEntry.id)"
        source = .anime
        sourceMediaId = animeEntry.mediaId
        title = animeEntry.title
        airingAt = animeEntry.airingAt
        episode = animeEntry.episode
        season = nil
        coverImage = animeEntry.coverImage
        englishTitle = animeEntry.englishTitle
        romajiTitle = animeEntry.romajiTitle
        nativeTitle = animeEntry.nativeTitle
        format = animeEntry.format
        hasKnownAiringTime = true
        tmdbResult = nil
    }

    fileprivate init(westernEpisode: TVMazeScheduleEpisode, airingAt: Date) {
        id = "western-\(westernEpisode.id)"
        source = .western
        sourceMediaId = westernEpisode.show.id
        title = westernEpisode.show.name
        self.airingAt = airingAt
        episode = westernEpisode.number ?? 0
        season = westernEpisode.season
        coverImage = westernEpisode.show.image?.medium ?? westernEpisode.show.image?.original
        englishTitle = westernEpisode.show.name
        romajiTitle = nil
        nativeTitle = nil
        format = nil
        hasKnownAiringTime = true
        tmdbResult = nil
    }

    fileprivate init(libraryResult: TMDBSearchResult, nextEpisode: TMDBEpisode, airingAt: Date) {
        id = "library-\(libraryResult.stableIdentity)-\(nextEpisode.id)"
        source = .library
        sourceMediaId = libraryResult.id
        title = libraryResult.displayTitle
        self.airingAt = airingAt
        episode = nextEpisode.episodeNumber
        season = nextEpisode.seasonNumber
        coverImage = libraryResult.posterPath.map { "https://image.tmdb.org/t/p/w342\($0)" }
        englishTitle = libraryResult.displayTitle
        romajiTitle = nil
        nativeTitle = nil
        format = nil
        hasKnownAiringTime = false
        tmdbResult = libraryResult
    }
}

final class ScheduleViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var scheduleEntries: [ScheduleEntry] = []
    @Published var dayBuckets: [DayBucket] = []
    @Published var currentDayAnchor = Date()

    private let scheduleDayCount = 7
    private var animeScheduleEntries: [ScheduleEntry]?
    private var westernScheduleEntries: [ScheduleEntry]?
    private var libraryScheduleEntries: [ScheduleEntry]?
    private var libraryScheduleCacheKey: [String]?

    init() {}

    func loadSchedule(mode: ScheduleMode, localTimeZone: Bool, forceRefresh: Bool = false) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let entries = try await entries(for: mode, forceRefresh: forceRefresh)
            await MainActor.run {
                isLoading = false
                scheduleEntries = entries
                currentDayAnchor = Date()
                updateBuckets(with: entries, localTimeZone: localTimeZone)
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func entries(for mode: ScheduleMode, forceRefresh: Bool) async throws -> [ScheduleEntry] {
        switch mode {
        case .anime:
            return try await animeEntries(forceRefresh: forceRefresh)
        case .western:
            return try await westernEntries(forceRefresh: forceRefresh)
        case .combined:
            var combinedEntries: [ScheduleEntry] = []
            var firstError: Error?
            var loadedSource = false

            do {
                combinedEntries += try await animeEntries(forceRefresh: forceRefresh)
                loadedSource = true
            } catch {
                firstError = error
            }

            do {
                combinedEntries += try await westernEntries(forceRefresh: forceRefresh)
                loadedSource = true
            } catch {
                firstError = firstError ?? error
            }

            if !loadedSource, let firstError {
                throw firstError
            }
            return combinedEntries
        case .library:
            return await libraryEntries(forceRefresh: forceRefresh)
        }
    }

    private func animeEntries(forceRefresh: Bool) async throws -> [ScheduleEntry] {
        if !forceRefresh, let animeScheduleEntries {
            return animeScheduleEntries
        }
        let entries = try await AniListService.shared.fetchAiringSchedule(daysAhead: scheduleDayCount)
            .map(ScheduleEntry.init(animeEntry:))
        animeScheduleEntries = entries
        return entries
    }

    private func westernEntries(forceRefresh: Bool) async throws -> [ScheduleEntry] {
        if !forceRefresh, let westernScheduleEntries {
            return westernScheduleEntries
        }
        let entries = try await TVMazeService.shared.fetchSchedule(dayCount: scheduleDayCount)
        westernScheduleEntries = entries
        return entries
    }

    private func libraryEntries(forceRefresh: Bool) async -> [ScheduleEntry] {
        let savedResults = uniqueSavedTVResults()
        let cacheKey = savedResults.map(\.stableIdentity).sorted()
        if !forceRefresh,
           cacheKey == libraryScheduleCacheKey,
           let libraryScheduleEntries {
            return libraryScheduleEntries
        }

        let batchSize = 4
        let dayCount = scheduleDayCount
        var entries: [ScheduleEntry] = []
        for start in stride(from: 0, to: savedResults.count, by: batchSize) {
            let end = min(start + batchSize, savedResults.count)
            let batch = savedResults[start..<end]
            let batchEntries = await withTaskGroup(of: ScheduleEntry?.self, returning: [ScheduleEntry].self) { group in
                for result in batch {
                    group.addTask {
                        await Self.libraryEntry(for: result, dayCount: dayCount)
                    }
                }

                var resolved: [ScheduleEntry] = []
                for await entry in group {
                    if let entry {
                        resolved.append(entry)
                    }
                }
                return resolved
            }
            entries.append(contentsOf: batchEntries)
        }

        let sortedEntries = entries.sorted { $0.airingAt < $1.airingAt }
        libraryScheduleCacheKey = cacheKey
        libraryScheduleEntries = sortedEntries
        return sortedEntries
    }

    private func uniqueSavedTVResults() -> [TMDBSearchResult] {
        var seen = Set<String>()
        return LibraryManager.shared.collections
            .flatMap(\.items)
            .map(\.searchResult)
            .filter(\.isTVShow)
            .filter { seen.insert($0.stableIdentity).inserted }
    }

    private static func libraryEntry(for result: TMDBSearchResult, dayCount: Int) async -> ScheduleEntry? {
        guard let detail = try? await TMDBService.shared.getTVShowDetails(id: result.id),
              let nextEpisode = detail.nextEpisodeToAir,
              let airDate = nextEpisode.airDate,
              let airingAt = tmdbDate(from: airDate) else {
            return nil
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: dayCount, to: start),
              airingAt >= start,
              airingAt < end else {
            return nil
        }

        return ScheduleEntry(libraryResult: result, nextEpisode: nextEpisode, airingAt: airingAt)
    }

    private static func tmdbDate(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    func updateBuckets(with entries: [ScheduleEntry], localTimeZone: Bool) {
        let calendar = makeCalendar(localTimeZone: localTimeZone)
        let startOfToday = calendar.startOfDay(for: Date())

        var buckets: [DayBucket] = []
        for offset in 0..<scheduleDayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else {
                continue
            }

            let dayItems = entries
                .filter { entry in
                    entry.airingAt >= calendar.startOfDay(for: day) && entry.airingAt < nextDay
                }
                .sorted { $0.airingAt < $1.airingAt }

            buckets.append(DayBucket(date: calendar.startOfDay(for: day), items: dayItems))
        }

        dayBuckets = buckets
    }

    func regroupBuckets(localTimeZone: Bool) {
        updateBuckets(with: scheduleEntries, localTimeZone: localTimeZone)
    }

    func handleDayChangeIfNeeded(mode: ScheduleMode, localTimeZone: Bool) async {
        let calendar = makeCalendar(localTimeZone: localTimeZone)
        let trackedDay = calendar.startOfDay(for: currentDayAnchor)
        let today = calendar.startOfDay(for: Date())

        if today != trackedDay {
            await loadSchedule(mode: mode, localTimeZone: localTimeZone, forceRefresh: true)
        } else {
            await MainActor.run {
                currentDayAnchor = Date()
                updateBuckets(with: scheduleEntries, localTimeZone: localTimeZone)
            }
        }
    }

    private func makeCalendar(localTimeZone: Bool) -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = localTimeZone ? .current : TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    // MARK: - TMDB Lookup

    /// Cache keyed by schedule source and media ID so both feeds can reuse TMDB results.
    /// Stores Optional<TMDBSearchResult> so we also cache "not found" results.
    private var tmdbCache: [String: TMDBSearchResult?] = [:]

    func lookupTMDBResult(for entry: ScheduleEntry) async -> TMDBSearchResult? {
        if let tmdbResult = entry.tmdbResult {
            return tmdbResult
        }

        let cacheKey = "\(entry.source.displayName)-\(entry.sourceMediaId)"
        if let cached = tmdbCache[cacheKey] {
            return cached
        }

        let result = await performTMDBLookup(for: entry)
        tmdbCache[cacheKey] = .some(result)
        return result
    }

    private func performTMDBLookup(for entry: ScheduleEntry) async -> TMDBSearchResult? {
        func normalized(_ value: String) -> String {
            value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        }

        var seen = Set<String>()
        let titleCandidates = [entry.englishTitle, entry.romajiTitle, entry.nativeTitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        let candidates = titleCandidates.isEmpty ? [entry.title] : titleCandidates
        let tmdbService = TMDBService.shared
        let preferAnimation = entry.source == .anime
        let isMovie = preferAnimation && entry.format?.uppercased() == "MOVIE"

        for candidate in candidates {
            if isMovie {
                if let result = try? await tmdbService.searchMovies(query: candidate),
                   let best = bestMovieMatch(results: result, candidateKey: normalized(candidate)) {
                    return best.asSearchResult
                }
            } else {
                if let result = try? await tmdbService.searchTVShows(query: candidate),
                   let best = bestTVMatch(results: result, candidateKey: normalized(candidate), preferAnimation: preferAnimation) {
                    return best.asSearchResult
                }
            }
        }

        for candidate in candidates {
            if let results = try? await tmdbService.searchMulti(query: candidate, maxPages: 1),
               let best = bestMultiMatch(results: results, candidateKey: normalized(candidate), preferAnimation: preferAnimation) {
                return best
            }
        }

        guard entry.source == .anime else {
            return nil
        }

        // Relation fallback: walk up AniList parent/prequel chain and try TMDB on each ancestor.
        let parentCandidates = await AniListService.shared.fetchParentTitleCandidates(forMediaId: entry.sourceMediaId)
        for parent in parentCandidates {
            var parentSeen = Set<String>()
            let parentTitles = [parent.englishTitle, parent.romajiTitle, parent.nativeTitle]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && parentSeen.insert($0).inserted }

            for candidate in parentTitles {
                if let results = try? await tmdbService.searchTVShows(query: candidate),
                   let best = bestTVMatch(results: results, candidateKey: normalized(candidate), preferAnimation: true) {
                    return best.asSearchResult
                }
                if let results = try? await tmdbService.searchMulti(query: candidate, maxPages: 1),
                   let best = bestMultiMatch(results: results, candidateKey: normalized(candidate), preferAnimation: true) {
                    return best
                }
            }
        }

        return nil
    }

    private func bestTVMatch(results: [TMDBTVShow], candidateKey: String, preferAnimation: Bool) -> TMDBTVShow? {
        func normalized(_ value: String) -> String {
            value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        }
        guard !results.isEmpty else { return nil }

        let exactMatches = results.filter { normalized($0.name) == candidateKey }
        if !exactMatches.isEmpty {
            return bestTVResult(from: exactMatches, preferAnimation: preferAnimation)
        }

        let partialMatches = results.filter {
            let nameKey = normalized($0.name)
            return nameKey.contains(candidateKey) || candidateKey.contains(nameKey)
        }
        if !partialMatches.isEmpty {
            return bestTVResult(from: partialMatches, preferAnimation: preferAnimation)
        }

        return bestTVResult(from: results, preferAnimation: preferAnimation)
    }

    private func bestTVResult(from results: [TMDBTVShow], preferAnimation: Bool) -> TMDBTVShow? {
        results.min { a, b in
            let aAnim = a.genreIds?.contains(16) == true
            let bAnim = b.genreIds?.contains(16) == true
            if preferAnimation, aAnim != bAnim { return aAnim }
            return a.popularity > b.popularity
        }
    }

    private func bestMovieMatch(results: [TMDBMovie], candidateKey: String) -> TMDBMovie? {
        func normalized(_ value: String) -> String {
            value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        }
        guard !results.isEmpty else { return nil }

        let exactMatches = results.filter { normalized($0.title) == candidateKey }
        if !exactMatches.isEmpty {
            return bestMovieResult(from: exactMatches)
        }

        let partialMatches = results.filter {
            let nameKey = normalized($0.title)
            return nameKey.contains(candidateKey) || candidateKey.contains(nameKey)
        }
        if !partialMatches.isEmpty {
            return bestMovieResult(from: partialMatches)
        }

        return bestMovieResult(from: results)
    }

    private func bestMovieResult(from results: [TMDBMovie]) -> TMDBMovie? {
        results.min { a, b in
            let aAnim = a.genreIds?.contains(16) == true
            let bAnim = b.genreIds?.contains(16) == true
            if aAnim != bAnim { return aAnim }
            return a.popularity > b.popularity
        }
    }

    private func bestMultiMatch(results: [TMDBSearchResult], candidateKey: String, preferAnimation: Bool) -> TMDBSearchResult? {
        guard !results.isEmpty else { return nil }
        let filtered = results.filter { result in
            let nameKey = result.displayTitle.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
            return nameKey == candidateKey || nameKey.contains(candidateKey) || candidateKey.contains(nameKey)
        }
        let pool = filtered.isEmpty ? results : filtered
        return pool.min { a, b in
            let aAnim = a.genreIds?.contains(16) == true
            let bAnim = b.genreIds?.contains(16) == true
            if preferAnimation, aAnim != bAnim { return aAnim }
            return a.popularity > b.popularity
        }
    }
}

struct DayBucket: Identifiable {
    let id = UUID()
    let date: Date
    let items: [ScheduleEntry]
}

// MARK: - TVMaze Western Schedule

private final class TVMazeService {
    static let shared = TVMazeService()

    private let baseURL = URL(string: "https://api.tvmaze.com")!

    private init() {}

    func fetchSchedule(dayCount: Int) async throws -> [ScheduleEntry] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let regionCode = Locale.current.regionCode?.uppercased() ?? "US"
        var episodesById: [Int: TVMazeScheduleEpisode] = [:]

        for offset in 0..<dayCount {
            guard let date = calendar.date(byAdding: .day, value: offset, to: startOfToday) else {
                continue
            }
            let dateString = formatter.string(from: date)
            let episodes = try await fetchEpisodes(
                path: "schedule",
                queryItems: [
                    URLQueryItem(name: "country", value: regionCode),
                    URLQueryItem(name: "date", value: dateString)
                ]
            )
            for episode in episodes where !episode.show.isLikelyAnime {
                episodesById[episode.id] = episode
            }
        }

        return episodesById.values.compactMap { episode in
            guard let airingAt = episode.airingDate else {
                return nil
            }
            return ScheduleEntry(westernEpisode: episode, airingAt: airingAt)
        }
    }

    private func fetchEpisodes(path: String, queryItems: [URLQueryItem], retryAfterRateLimit: Bool = true) async throws -> [TVMazeScheduleEpisode] {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw TVMazeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Eclipse Luna iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TVMazeError.invalidResponse
        }

        if httpResponse.statusCode == 429, retryAfterRateLimit {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return try await fetchEpisodes(path: path, queryItems: queryItems, retryAfterRateLimit: false)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TVMazeError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode([TVMazeScheduleEpisode].self, from: data)
    }
}

private enum TVMazeError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The Western schedule URL could not be created."
        case .invalidResponse:
            return "The Western schedule service returned an invalid response."
        case .httpStatus(let status):
            return "The Western schedule service returned HTTP \(status)."
        }
    }
}

fileprivate struct TVMazeScheduleEpisode: Decodable {
    let id: Int
    let season: Int
    let number: Int?
    let airdate: String
    let airtime: String?
    let airstamp: String?
    let show: TVMazeShow

    private enum CodingKeys: String, CodingKey {
        case id, season, number, airdate, airtime, airstamp, show
        case embedded = "_embedded"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        season = try container.decode(Int.self, forKey: .season)
        number = try container.decodeIfPresent(Int.self, forKey: .number)
        airdate = try container.decode(String.self, forKey: .airdate)
        airtime = try container.decodeIfPresent(String.self, forKey: .airtime)
        airstamp = try container.decodeIfPresent(String.self, forKey: .airstamp)
        show = try container.decodeIfPresent(TVMazeShow.self, forKey: .show)
            ?? container.decode(TVMazeEmbedded.self, forKey: .embedded).show
    }

    var airingDate: Date? {
        if let airstamp, let date = ISO8601DateFormatter().date(from: airstamp) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        if let timezone = show.network?.country?.timezone ?? show.webChannel?.country?.timezone {
            formatter.timeZone = TimeZone(identifier: timezone)
        }
        return formatter.date(from: "\(airdate) \(airtime ?? "00:00")")
    }
}

fileprivate struct TVMazeEmbedded: Decodable {
    let show: TVMazeShow
}

fileprivate struct TVMazeShow: Decodable {
    let id: Int
    let name: String
    let language: String?
    let genres: [String]
    let image: TVMazeImage?
    let network: TVMazeChannel?
    let webChannel: TVMazeChannel?

    var isLikelyAnime: Bool {
        let hasAnimeGenre = genres.contains { genre in
            let normalized = genre.lowercased()
            return normalized == "anime" || normalized == "animation"
        }
        return language?.lowercased() == "japanese" && hasAnimeGenre
    }
}

fileprivate struct TVMazeImage: Decodable {
    let medium: String?
    let original: String?
}

fileprivate struct TVMazeChannel: Decodable {
    let country: TVMazeCountry?
}

fileprivate struct TVMazeCountry: Decodable {
    let timezone: String?
}
