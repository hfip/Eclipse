//
//  IntroDBService.swift
//  Luna
//
//  Created on 28/02/26.
//

import Foundation

// MARK: - TheIntroDB API Response Models

private struct IntroDBResponse: Codable {
    let tmdb_id: Int?
    let type: String?
    let intro: [IntroDBSegment]?
    let recap: [IntroDBSegment]?
    let credits: [IntroDBSegment]?
    let preview: [IntroDBSegment]?
}

private struct IntroDBSegment: Codable {
    let start_ms: Int?
    let end_ms: Int?
    let confidence: Double?
    let submission_count: Int?
}

// MARK: - IntroDB.app API Response Models

private struct IntroDBAppResponse: Decodable {
    let imdbId: String?
    let season: Int?
    let episode: Int?
    let intro: IntroDBAppSegmentList?
    let recap: IntroDBAppSegmentList?
    let outro: IntroDBAppSegmentList?
    let credits: IntroDBAppSegmentList?
    let preview: IntroDBAppSegmentList?

    enum CodingKeys: String, CodingKey {
        case imdbId = "imdb_id"
        case season
        case episode
        case intro
        case recap
        case outro
        case credits
        case preview
    }
}

private struct IntroDBAppSegmentList: Decodable {
    let segments: [IntroDBAppSegment]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            segments = []
        } else if let list = try? container.decode([IntroDBAppSegment].self) {
            segments = list
        } else if let segment = try? container.decode(IntroDBAppSegment.self) {
            segments = [segment]
        } else {
            segments = []
        }
    }
}

private struct IntroDBAppSegment: Decodable {
    let startSec: Double?
    let endSec: Double?
    let startMs: Int?
    let endMs: Int?
    let confidence: Double?
    let submissionCount: Int?

    enum CodingKeys: String, CodingKey {
        case startSec = "start_sec"
        case endSec = "end_sec"
        case startMs = "start_ms"
        case endMs = "end_ms"
        case confidence
        case submissionCount = "submission_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startSec = Self.decodeSeconds(from: container, key: .startSec)
        endSec = Self.decodeSeconds(from: container, key: .endSec)
        startMs = try? container.decodeIfPresent(Int.self, forKey: .startMs)
        endMs = try? container.decodeIfPresent(Int.self, forKey: .endMs)
        confidence = try? container.decodeIfPresent(Double.self, forKey: .confidence)
        submissionCount = try? container.decodeIfPresent(Int.self, forKey: .submissionCount)
    }

    private static func decodeSeconds(from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return parseClockOrSeconds(raw)
    }

    private static func parseClockOrSeconds(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let value = Double(trimmed) {
            return value
        }

        let parts = trimmed.split(separator: ":").compactMap { Double($0) }
        guard parts.count >= 2, parts.count <= 3 else { return nil }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }
}

// MARK: - TheIntroDB Service

final class IntroDBService {
    static let shared = IntroDBService()

    private let baseURL = "https://api.theintrodb.org/v2"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    /// Fetches skip-time segments from TheIntroDB using TMDB ID.
    /// - Parameters:
    ///   - tmdbId: The TMDB ID of the movie or TV show.
    ///   - seasonNumber: Season number (nil for movies).
    ///   - episodeNumber: Episode number (nil for movies).
    ///   - episodeDuration: The total duration in seconds (used for clamping and null end times).
    /// - Returns: Array of skip segments (intro, outro/credits, recap, preview).
    func fetchSkipTimes(tmdbId: Int, seasonNumber: Int?, episodeNumber: Int?, episodeDuration: Double) async throws -> [SkipSegment] {
        var urlString = "\(baseURL)/media?tmdb_id=\(tmdbId)"
        if let season = seasonNumber {
            urlString += "&season=\(season)"
        }
        if let episode = episodeNumber {
            urlString += "&episode=\(episode)"
        }

        guard let url = URL(string: urlString) else {
            Logger.shared.log("IntroDBService: Invalid URL: \(urlString)", type: "Error")
            return []
        }

        Logger.shared.log("IntroDBService: Fetching skip times for tmdbId=\(tmdbId) s=\(seasonNumber ?? -1) ep=\(episodeNumber ?? -1)", type: "IntroDB")

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.shared.log("IntroDBService: Non-HTTP response", type: "Error")
            return []
        }

        guard httpResponse.statusCode == 200 else {
            Logger.shared.log("IntroDBService: HTTP \(httpResponse.statusCode) for tmdbId=\(tmdbId)", type: "IntroDB")
            return []
        }

        let decoded = try JSONDecoder().decode(IntroDBResponse.self, from: data)

        var segments: [SkipSegment] = []
        let maxDuration = episodeDuration.isFinite && episodeDuration > 0 ? episodeDuration : nil

        // Parse intro segments
        if let intros = decoded.intro {
            for seg in intros {
                if let parsed = parseSegment(seg, type: .intro, maxDuration: maxDuration) {
                    segments.append(parsed)
                }
            }
        }

        // Parse recap segments
        if let recaps = decoded.recap {
            for seg in recaps {
                if let parsed = parseSegment(seg, type: .recap, maxDuration: maxDuration) {
                    segments.append(parsed)
                }
            }
        }

        // Parse credits → map to .outro (functionally equivalent — "Skip Outro")
        if let credits = decoded.credits {
            for seg in credits {
                if let parsed = parseSegment(seg, type: .outro, maxDuration: maxDuration) {
                    segments.append(parsed)
                }
            }
        }

        // Parse preview segments
        if let previews = decoded.preview {
            for seg in previews {
                if let parsed = parseSegment(seg, type: .preview, maxDuration: maxDuration) {
                    segments.append(parsed)
                }
            }
        }

        Logger.shared.log(
            "IntroDBService: Found \(segments.count) skip segments for tmdbId=\(tmdbId): "
            + segments.map { "\($0.type.rawValue) \(formatSeconds($0.startTime))-\(formatSeconds($0.endTime))s" }.joined(separator: ", "),
            type: "IntroDB"
        )

        return segments
    }

    /// Converts an IntroDB segment (milliseconds, nullable) into a SkipSegment (seconds).
    private func parseSegment(_ seg: IntroDBSegment, type: SkipType, maxDuration: Double?) -> SkipSegment? {
        let startSec = seg.start_ms.map { Double($0) / 1000.0 } ?? 0
        guard startSec.isFinite else { return nil }

        let endSec: Double
        if let rawEnd = seg.end_ms {
            endSec = Double(rawEnd) / 1000.0
        } else if let maxDuration {
            endSec = maxDuration
        } else {
            return nil
        }
        guard endSec.isFinite else { return nil }

        let clampedStart = max(0, startSec)
        let clampedEnd = maxDuration.map { min($0, endSec) } ?? endSec
        guard clampedEnd > clampedStart else { return nil }

        return SkipSegment(startTime: clampedStart, endTime: clampedEnd, type: type)
    }

    private func formatSeconds(_ value: Double) -> String {
        guard value.isFinite else { return "nil" }
        return "\(Int(value.rounded()))"
    }
}

// MARK: - IntroDB.app Service

final class IntroDBAppService {
    static let shared = IntroDBAppService()

    private let baseURL = URL(string: "https://api.introdb.app")!
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    /// Fetches skip-time segments from introdb.app using IMDb ID.
    /// No API key is required for read access.
    func fetchSkipTimes(imdbId: String, seasonNumber: Int?, episodeNumber: Int?, episodeDuration: Double) async throws -> [SkipSegment] {
        let cleanIMDbId = imdbId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIMDbId.isEmpty else { return [] }

        var components = URLComponents(url: baseURL.appendingPathComponent("segments"), resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "imdb_id", value: cleanIMDbId)]
        if let seasonNumber {
            queryItems.append(URLQueryItem(name: "season", value: String(seasonNumber)))
        }
        if let episodeNumber {
            queryItems.append(URLQueryItem(name: "episode", value: String(episodeNumber)))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            Logger.shared.log("IntroDBAppService: Invalid URL for imdbId=\(cleanIMDbId)", type: "Error")
            return []
        }

        Logger.shared.log("IntroDBAppService: Fetching skip times for imdbId=\(cleanIMDbId) s=\(seasonNumber ?? -1) ep=\(episodeNumber ?? -1)", type: "IntroDB")

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.shared.log("IntroDBAppService: Non-HTTP response", type: "Error")
            return []
        }

        guard httpResponse.statusCode == 200 else {
            Logger.shared.log("IntroDBAppService: HTTP \(httpResponse.statusCode) for imdbId=\(cleanIMDbId)", type: "IntroDB")
            return []
        }

        let decoded = try JSONDecoder().decode(IntroDBAppResponse.self, from: data)
        let maxDuration = episodeDuration.isFinite && episodeDuration > 0 ? episodeDuration : nil

        var segments: [SkipSegment] = []
        segments.append(contentsOf: parseSegments(decoded.intro, type: .intro, maxDuration: maxDuration))
        segments.append(contentsOf: parseSegments(decoded.recap, type: .recap, maxDuration: maxDuration))
        segments.append(contentsOf: parseSegments(decoded.outro, type: .outro, maxDuration: maxDuration))
        segments.append(contentsOf: parseSegments(decoded.credits, type: .outro, maxDuration: maxDuration))
        segments.append(contentsOf: parseSegments(decoded.preview, type: .preview, maxDuration: maxDuration))

        Logger.shared.log(
            "IntroDBAppService: Found \(segments.count) skip segments for imdbId=\(cleanIMDbId): "
            + segments.map { "\($0.type.rawValue) \(formatSeconds($0.startTime))-\(formatSeconds($0.endTime))s" }.joined(separator: ", "),
            type: "IntroDB"
        )

        return dedupe(segments).sorted { $0.startTime < $1.startTime }
    }

    private func parseSegments(_ list: IntroDBAppSegmentList?, type: SkipType, maxDuration: Double?) -> [SkipSegment] {
        (list?.segments ?? []).compactMap { parseSegment($0, type: type, maxDuration: maxDuration) }
    }

    private func parseSegment(_ seg: IntroDBAppSegment, type: SkipType, maxDuration: Double?) -> SkipSegment? {
        let startSec = seg.startSec ?? seg.startMs.map { Double($0) / 1000.0 } ?? 0
        let endSec = seg.endSec ?? seg.endMs.map { Double($0) / 1000.0 }
        guard startSec.isFinite else { return nil }

        let resolvedEnd: Double
        if let endSec {
            resolvedEnd = endSec
        } else if let maxDuration {
            resolvedEnd = maxDuration
        } else {
            return nil
        }
        guard resolvedEnd.isFinite else { return nil }

        let clampedStart = max(0, startSec)
        let clampedEnd = maxDuration.map { min($0, resolvedEnd) } ?? resolvedEnd
        guard clampedEnd > clampedStart else { return nil }

        return SkipSegment(startTime: clampedStart, endTime: clampedEnd, type: type)
    }

    private func dedupe(_ segments: [SkipSegment]) -> [SkipSegment] {
        var seen = Set<String>()
        return segments.filter { segment in
            let key = "\(segment.type.rawValue)-\(Int(segment.startTime.rounded()))-\(Int(segment.endTime.rounded()))"
            return seen.insert(key).inserted
        }
    }

    private func formatSeconds(_ value: Double) -> String {
        guard value.isFinite else { return "nil" }
        return "\(Int(value.rounded()))"
    }
}
