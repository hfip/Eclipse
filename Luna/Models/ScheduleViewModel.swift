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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anime:
            return "Anime"
        case .western:
            return "Western"
        case .combined:
            return "Combined"
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

    var displayName: String {
        switch self {
        case .anime:
            return "Anime"
        case .western:
            return "Western"
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
    }

    fileprivate init(westernEpisode: TVMazeScheduleEpisode, airing: TVMazeAiringInfo) {
        id = "western-\(westernEpisode.id)"
        source = .western
        sourceMediaId = westernEpisode.show.id
        title = westernEpisode.show.name
        airingAt = airing.date
        episode = westernEpisode.number ?? 0
        season = westernEpisode.season
        coverImage = westernEpisode.show.image?.medium ?? westernEpisode.show.image?.original
        englishTitle = westernEpisode.show.name
        romajiTitle = nil
        nativeTitle = nil
        format = nil
        hasKnownAiringTime = airing.hasKnownAiringTime
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
            let feeds = [
                (
                    path: "schedule",
                    requiresEnglishLanguage: false,
                    isOptional: false,
                    queryItems: [
                        URLQueryItem(name: "country", value: regionCode),
                        URLQueryItem(name: "date", value: dateString)
                    ]
                ),
                (
                    path: "schedule/web",
                    requiresEnglishLanguage: true,
                    isOptional: true,
                    queryItems: [
                        URLQueryItem(name: "country", value: ""),
                        URLQueryItem(name: "date", value: dateString)
                    ]
                )
            ]

            for feed in feeds {
                let episodes: [TVMazeScheduleEpisode]
                do {
                    episodes = try await fetchEpisodes(path: feed.path, queryItems: feed.queryItems)
                } catch {
                    guard feed.isOptional else {
                        throw error
                    }
                    Logger.shared.log(
                        "TVMazeService: optional feed failed path=\(feed.path) date=\(dateString) error=\(error.localizedDescription)",
                        type: "TMDB"
                    )
                    continue
                }
                for episode in episodes where episode.show.isWesternScheduleCandidate
                    && (!feed.requiresEnglishLanguage || episode.show.isEnglishLanguage) {
                    episodesById[episode.id] = episode
                }
            }
        }

        let dailyShowIds = Set(
            Dictionary(grouping: episodesById.values, by: { $0.show.id })
                .compactMap { entry in
                    Set(entry.value.map(\.airdate)).count >= 4 ? entry.key : nil
                }
        )

        return episodesById.values.compactMap { episode in
            guard !dailyShowIds.contains(episode.show.id) else {
                return nil
            }
            guard let airing = episode.airing else {
                return nil
            }
            return ScheduleEntry(westernEpisode: episode, airing: airing)
        }
    }

    private func fetchEpisodes(path: String, queryItems: [URLQueryItem], retryAfterRateLimit: Bool = true) async throws -> [TVMazeScheduleEpisode] {
        let data = try await fetchData(path: path, queryItems: queryItems, retryAfterRateLimit: retryAfterRateLimit)
        return try JSONDecoder().decode([TVMazeScheduleEpisode].self, from: data)
    }

    private func fetchData(
        path: String,
        queryItems: [URLQueryItem],
        retryAfterRateLimit: Bool = true
    ) async throws -> Data {
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
            return try await fetchData(
                path: path,
                queryItems: queryItems,
                retryAfterRateLimit: false
            )
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TVMazeError.httpStatus(httpResponse.statusCode)
        }

        return data
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

    var airing: TVMazeAiringInfo? {
        tvMazeAiringInfo(
            airdate: airdate,
            airtime: airtime,
            airstamp: airstamp,
            timeZoneIdentifier: show.network?.country?.timezone ?? show.webChannel?.country?.timezone
        )
    }
}

fileprivate struct TVMazeAiringInfo {
    let date: Date
    let hasKnownAiringTime: Bool
}

private func tvMazeAiringInfo(airdate: String, airtime: String?, airstamp: String?, timeZoneIdentifier: String?) -> TVMazeAiringInfo? {
    let normalizedAirtime = airtime?.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasKnownAiringTime = normalizedAirtime?.isEmpty == false

    if let airstamp, let date = ISO8601DateFormatter().date(from: airstamp) {
        return TVMazeAiringInfo(date: date, hasKnownAiringTime: hasKnownAiringTime)
    }

    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = hasKnownAiringTime ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
    if let timeZoneIdentifier {
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
    }
    let value = hasKnownAiringTime ? "\(airdate) \(normalizedAirtime ?? "")" : airdate
    guard let date = formatter.date(from: value) else {
        return nil
    }
    return TVMazeAiringInfo(date: date, hasKnownAiringTime: hasKnownAiringTime)
}

fileprivate struct TVMazeEmbedded: Decodable {
    let show: TVMazeShow
}

fileprivate struct TVMazeShow: Decodable {
    let id: Int
    let name: String
    let language: String?
    let type: String?
    let genres: [String]
    let image: TVMazeImage?
    let network: TVMazeChannel?
    let webChannel: TVMazeChannel?
    let schedule: TVMazeShowSchedule?

    var isLikelyAnime: Bool {
        let hasAnimeGenre = genres.contains { genre in
            let normalized = genre.lowercased()
            return normalized == "anime" || normalized == "animation"
        }
        return language?.lowercased() == "japanese" && hasAnimeGenre
    }

    var isWesternScheduleCandidate: Bool {
        guard !isLikelyAnime, (schedule?.days.count ?? 0) < 4 else { return false }
        switch type?.lowercased() {
        case "scripted", "animation":
            return true
        default:
            return false
        }
    }

    var isEnglishLanguage: Bool {
        language?.lowercased() == "english"
    }
}

fileprivate struct TVMazeShowSchedule: Decodable {
    let days: [String]
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
