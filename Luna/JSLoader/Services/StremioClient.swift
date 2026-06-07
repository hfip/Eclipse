//
//  StremioClient.swift
//  Luna
//
//  Created by Soupy on 2026.
//

import Foundation

/// HTTP client for the Stremio addon protocol.
/// SAFETY: Only returns streams with direct HTTP(S) URLs. Torrent-only streams are discarded.
final class StremioClient {
    static let shared = StremioClient()
    static let openSubtitlesV3BaseURL = "https://opensubtitles-v3.strem.io"

    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: - Fetch Manifest

    func fetchManifest(from url: String) async throws -> StremioManifest {
        let manifestURL = normalizeManifestURL(url)
        Logger.shared.log("Stremio: Fetching manifest from \(manifestURL)", type: "Stremio")
        guard let requestURL = URL(string: manifestURL), requestURL.scheme != nil else {
            Logger.shared.log("Stremio: Invalid manifest URL: \(manifestURL)", type: "Stremio")
            throw StremioError.invalidURL
        }

        let (data, response) = try await session.data(from: requestURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            Logger.shared.log("Stremio: Manifest fetch failed HTTP \(code) from \(manifestURL)", type: "Stremio")
            throw StremioError.httpError(code)
        }

        let manifest = try decoder.decode(StremioManifest.self, from: data)
        Logger.shared.log("Stremio: Manifest OK — id=\(manifest.id) name=\(manifest.name) resources=\(manifest.resources?.count ?? 0) idPrefixes=\(manifest.idPrefixes ?? [])", type: "Stremio")
        return manifest
    }

    // MARK: - Fetch Streams

    /// Fetches streams for a given addon and content ID.
    /// **SAFETY**: Only returns streams with direct HTTP(S) URLs. Any torrent-only entry is stripped.
    func fetchStreams(baseURL: String, type: String, id: String) async throws -> [StremioStream] {
        let cleanBase = normalizedBaseURL(baseURL)
        let encodedId = encodePathSegment(id, preservingColon: true)
        let urlString = "\(cleanBase)/stream/\(type)/\(encodedId).json"
        guard let url = URL(string: urlString) else {
            throw StremioError.invalidURL
        }

        Logger.shared.log("Stremio: Fetching streams — type=\(type) id=\(id) url=\(urlString)", type: "Stremio")

        let (data, response) = try await session.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        Logger.shared.log("Stremio: Stream response HTTP \(statusCode) from \(cleanBase)", type: "Stremio")
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            Logger.shared.log("Stremio: Stream fetch FAILED HTTP \(statusCode) — base=\(cleanBase) type=\(type) id=\(id)", type: "Stremio")
            throw StremioError.httpError(statusCode)
        }

        let streamResponse: StremioStreamResponse
        do {
            streamResponse = try decoder.decode(StremioStreamResponse.self, from: data)
        } catch {
            // Log partial body so we can diagnose format mismatches
            let preview = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            Logger.shared.log("Stremio: Decode FAILED for \(cleanBase) — \(error.localizedDescription) body=\(preview)", type: "Stremio")
            throw error
        }
        let allStreams = streamResponse.streams ?? []

        if allStreams.isEmpty, let preview = String(data: data.prefix(512), encoding: .utf8) {
            Logger.shared.log("Stremio: 0 streams decoded from \(cleanBase) — body=\(preview)", type: "Stremio")
        }

        // SAFETY: Filter out any stream that is NOT a direct HTTP(S) link.
        // This ensures NO torrent (infoHash-only) streams ever reach the user.
        let safeStreams = allStreams.filter { $0.isDirectHTTP }

        let dropped = allStreams.count - safeStreams.count
        if dropped > 0 {
            Logger.shared.log("Stremio: Dropped \(dropped) non-HTTP stream(s) (torrent/infoHash only)", type: "Stremio")
        }

        Logger.shared.log("Stremio: Got \(safeStreams.count) safe HTTP stream(s) from \(cleanBase)", type: "Stremio")
        return safeStreams
    }

    // MARK: - Fetch Catalogs and Meta

    func fetchCatalogMetas(baseURL: String, catalog: StremioCatalog, searchQuery: String? = nil, skip: Int? = nil) async throws -> [StremioMetaPreview] {
        let cleanBase = normalizedBaseURL(baseURL)
        let encodedType = encodePathSegment(catalog.type, preservingColon: false)
        let encodedCatalogId = encodePathSegment(catalog.id, preservingColon: true)
        var extras: [String] = []
        if let skip {
            extras.append("skip=\(max(skip, 0))")
        }
        if let searchQuery {
            extras.append("search=\(encodeExtraValue(searchQuery))")
        }
        let extraPath = extras.isEmpty ? "" : "/\(extras.joined(separator: "&"))"
        let urlString = "\(cleanBase)/catalog/\(encodedType)/\(encodedCatalogId)\(extraPath).json"

        guard let url = URL(string: urlString) else {
            throw StremioError.invalidURL
        }

        Logger.shared.log("Stremio: Fetching catalog \(catalog.id) query='\(searchQuery ?? "nil")' skip=\(skip?.description ?? "nil") url=\(urlString)", type: "Stremio")

        let (data, response) = try await session.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            Logger.shared.log("Stremio: Catalog fetch failed HTTP \(statusCode) catalog=\(catalog.id) query='\(searchQuery ?? "nil")' skip=\(skip?.description ?? "nil")", type: "Stremio")
            throw StremioError.httpError(statusCode)
        }

        do {
            let response = try decoder.decode(StremioCatalogResponse.self, from: data)
            Logger.shared.log("Stremio: Catalog \(catalog.id) returned \(response.metas.count) meta candidate(s)", type: "Stremio")
            return response.metas
        } catch {
            let preview = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            Logger.shared.log("Stremio: Catalog decode FAILED for \(catalog.id) - \(error.localizedDescription) body=\(preview)", type: "Stremio")
            throw error
        }
    }

    func fetchMeta(baseURL: String, type: String, id: String) async throws -> StremioMetaPreview? {
        let cleanBase = normalizedBaseURL(baseURL)
        let encodedType = encodePathSegment(type, preservingColon: false)
        let encodedId = encodePathSegment(id, preservingColon: true)
        let urlString = "\(cleanBase)/meta/\(encodedType)/\(encodedId).json"

        guard let url = URL(string: urlString) else {
            throw StremioError.invalidURL
        }

        Logger.shared.log("Stremio: Fetching meta type=\(type) id=\(id) url=\(urlString)", type: "Stremio")

        let (data, response) = try await session.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            Logger.shared.log("Stremio: Meta fetch failed HTTP \(statusCode) type=\(type) id=\(id)", type: "Stremio")
            throw StremioError.httpError(statusCode)
        }

        do {
            let response = try decoder.decode(StremioMetaResponse.self, from: data)
            return response.meta
        } catch {
            let preview = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            Logger.shared.log("Stremio: Meta decode FAILED for id=\(id) - \(error.localizedDescription) body=\(preview)", type: "Stremio")
            throw error
        }
    }

    // MARK: - Fetch Subtitles

    func fetchSubtitles(baseURL: String, type: String, id: String) async throws -> [StremioSubtitle] {
        let cleanBase = normalizedBaseURL(baseURL)
        let encodedType = encodePathSegment(type, preservingColon: false)
        let encodedId = encodePathSegment(id, preservingColon: true)
        let urlString = "\(cleanBase)/subtitles/\(encodedType)/\(encodedId).json"

        guard let url = URL(string: urlString) else {
            throw StremioError.invalidURL
        }

        Logger.shared.log("Stremio: Fetching subtitles - type=\(type) id=\(id) url=\(urlString)", type: "Stremio")

        let (data, response) = try await session.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            Logger.shared.log("Stremio: Subtitle fetch FAILED HTTP \(statusCode) - base=\(cleanBase) type=\(type) id=\(id)", type: "Stremio")
            throw StremioError.httpError(statusCode)
        }

        let subtitleResponse: StremioSubtitleResponse
        do {
            subtitleResponse = try decoder.decode(StremioSubtitleResponse.self, from: data)
        } catch {
            let preview = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            Logger.shared.log("Stremio: Subtitle decode FAILED for \(cleanBase) - \(error.localizedDescription) body=\(preview)", type: "Stremio")
            throw error
        }

        let subtitles = (subtitleResponse.subtitles ?? []).filter { subtitle in
            guard let url = subtitle.url?.lowercased(), !url.isEmpty else { return false }
            return url.hasPrefix("http://") || url.hasPrefix("https://")
        }

        Logger.shared.log("Stremio: Got \(subtitles.count) HTTP subtitle(s) from \(cleanBase)", type: "Stremio")
        return subtitles
    }

    func fetchOpenSubtitlesV3(tmdbId: Int, imdbId: String?, type: String, season: Int?, episode: Int?) async throws -> [StremioSubtitle] {
        let manifest = try await fetchManifest(from: Self.openSubtitlesV3BaseURL)
        guard manifest.supportsSubtitles else {
            Logger.shared.log("Stremio: OpenSubtitles v3 manifest does not advertise subtitles", type: "Stremio")
            return []
        }

        guard let contentId = buildContentId(
            tmdbId: tmdbId,
            imdbId: imdbId,
            type: type,
            season: season,
            episode: episode,
            idPrefixes: manifest.subtitleIdPrefixes,
            addonName: manifest.name
        ) else {
            Logger.shared.log("Stremio: OpenSubtitles v3 missing supported content ID", type: "Stremio")
            return []
        }

        return try await fetchSubtitles(
            baseURL: Self.openSubtitlesV3BaseURL,
            type: type,
            id: contentId
        )
    }

    // MARK: - Build Stremio Content ID

    /// Builds the Stremio content ID string for a given item.
    /// - Parameters:
    ///   - tmdbId: The TMDB ID
    ///   - imdbId: The IMDB ID (tt-prefixed string), if available
    ///   - type: "movie" or "series"
    ///   - season: Season number (for series only)
    ///   - episode: Episode number (for series only)
    ///   - addon: The addon to build the ID for (checks idPrefixes)
    /// - Returns: The single best content ID to use for this addon
    func buildContentId(tmdbId: Int, imdbId: String?, type: String, season: Int?, episode: Int?, addon: StremioAddon) -> String? {
        return buildContentIds(
            tmdbId: tmdbId,
            imdbId: imdbId,
            type: type,
            season: season,
            episode: episode,
            anilistId: nil,
            idPrefixes: addon.manifest.streamIdPrefixes,
            addonName: addon.manifest.name
        ).first
    }

    func buildContentId(tmdbId: Int, imdbId: String?, type: String, season: Int?, episode: Int?, anilistId: Int? = nil, anilistSeason: Int? = nil, anilistEpisode: Int? = nil, kitsuId: Int? = nil, kitsuEpisode: Int? = nil, alternateSeason: Int? = nil, alternateEpisode: Int? = nil, idPrefixes: [String]?, addonName: String) -> String? {
        buildContentIds(
            tmdbId: tmdbId,
            imdbId: imdbId,
            type: type,
            season: season,
            episode: episode,
            anilistId: anilistId,
            anilistSeason: anilistSeason,
            anilistEpisode: anilistEpisode,
            kitsuId: kitsuId,
            kitsuEpisode: kitsuEpisode,
            alternateSeason: alternateSeason,
            alternateEpisode: alternateEpisode,
            idPrefixes: idPrefixes,
            addonName: addonName
        ).first
    }

    func buildContentIds(tmdbId: Int, imdbId: String?, type: String, season: Int?, episode: Int?, anilistId: Int? = nil, anilistSeason: Int? = nil, anilistEpisode: Int? = nil, kitsuId: Int? = nil, kitsuEpisode: Int? = nil, alternateSeason: Int? = nil, alternateEpisode: Int? = nil, addon: StremioAddon) -> [String] {
        buildContentIds(
            tmdbId: tmdbId,
            imdbId: imdbId,
            type: type,
            season: season,
            episode: episode,
            anilistId: anilistId,
            anilistSeason: anilistSeason,
            anilistEpisode: anilistEpisode,
            kitsuId: kitsuId,
            kitsuEpisode: kitsuEpisode,
            alternateSeason: alternateSeason,
            alternateEpisode: alternateEpisode,
            idPrefixes: addon.manifest.streamIdPrefixes,
            addonName: addon.manifest.name
        )
    }

    func buildContentIds(tmdbId: Int, imdbId: String?, type: String, season: Int?, episode: Int?, anilistId: Int? = nil, anilistSeason: Int? = nil, anilistEpisode: Int? = nil, kitsuId: Int? = nil, kitsuEpisode: Int? = nil, alternateSeason: Int? = nil, alternateEpisode: Int? = nil, idPrefixes: [String]?, addonName: String) -> [String] {
        let prefixes = idPrefixes ?? []
        let normalizedPrefixes = prefixes.map { $0.lowercased() }
        let supportsTMDB = normalizedPrefixes.isEmpty || normalizedPrefixes.contains { $0 == "tmdb" || $0.hasPrefix("tmdb:") }
        let supportsIMDB = normalizedPrefixes.isEmpty || normalizedPrefixes.contains { $0 == "tt" || $0.hasPrefix("tt") || $0 == "imdb" || $0 == "imdb:" }
        let supportsIMDBNamespace = normalizedPrefixes.contains { $0 == "imdb:" }
        let supportsAniList = normalizedPrefixes.isEmpty || normalizedPrefixes.contains { $0 == "anilist" || $0 == "anilist:" }
        let supportsKitsu = normalizedPrefixes.isEmpty || normalizedPrefixes.contains { $0 == "kitsu" || $0 == "kitsu:" }

        Logger.shared.log("Stremio: buildContentId addon=\(addonName) prefixes=\(prefixes) imdbId=\(imdbId ?? "nil") tmdbId=\(tmdbId) anilistId=\(anilistId?.description ?? "nil") kitsuId=\(kitsuId?.description ?? "nil") type=\(type) s=\(season?.description ?? "nil") e=\(episode?.description ?? "nil") anilistS=\(anilistSeason?.description ?? "nil") anilistE=\(anilistEpisode?.description ?? "nil") kitsuE=\(kitsuEpisode?.description ?? "nil") altS=\(alternateSeason?.description ?? "nil") altE=\(alternateEpisode?.description ?? "nil")", type: "Stremio")
        var candidates: [String] = []
        let seriesTuples = contentIdSeriesTuples(
            type: type,
            season: season,
            episode: episode,
            alternateSeason: alternateSeason,
            alternateEpisode: alternateEpisode
        )

        // Prefer IMDB because it is the universal Stremio standard, then try TMDB too.
        if supportsIMDB, let imdb = imdbId, !imdb.isEmpty {
            let ttId = imdb.hasPrefix("tt") ? imdb : "tt\(imdb)"
            if type == "series", !seriesTuples.isEmpty {
                for tuple in seriesTuples {
                    candidates.append("\(ttId):\(tuple.season):\(tuple.episode)")
                }
            } else {
                candidates.append(ttId)
            }

            if supportsIMDBNamespace {
                if type == "series", !seriesTuples.isEmpty {
                    for tuple in seriesTuples {
                        candidates.append("imdb:\(ttId):\(tuple.season):\(tuple.episode)")
                    }
                } else {
                    candidates.append("imdb:\(ttId)")
                }
            }
        }

        if supportsTMDB {
            if type == "series", !seriesTuples.isEmpty {
                for tuple in seriesTuples {
                    candidates.append("tmdb:\(tmdbId):\(tuple.season):\(tuple.episode)")
                }
            } else {
                candidates.append("tmdb:\(tmdbId)")
            }
        }

        if supportsAniList, let anilistId {
            if type == "series" {
                if let animeSeason = anilistSeason, let animeEpisode = anilistEpisode {
                    candidates.append("anilist:\(anilistId):\(animeSeason):\(animeEpisode)")
                }
                if let s = season, let e = episode {
                    candidates.append("anilist:\(anilistId):\(s):\(e)")
                }
            } else {
                candidates.append("anilist:\(anilistId)")
            }
        }

        if supportsKitsu, let kitsuId, kitsuId > 0 {
            if type == "series" {
                if let kitsuEpisode, kitsuEpisode > 0 {
                    candidates.append("kitsu:\(kitsuId):\(kitsuEpisode)")
                }
            } else {
                candidates.append("kitsu:\(kitsuId)")
            }
        }

        var seen = Set<String>()
        let unique = candidates.filter { seen.insert($0).inserted }
        if unique.isEmpty {
            Logger.shared.log("Stremio: No supported prefix for addon \(addonName)", type: "Stremio")
        } else {
            Logger.shared.log("Stremio: Content ID candidates for \(addonName): \(unique.joined(separator: ", "))", type: "Stremio")
        }
        return unique
    }

    private func contentIdSeriesTuples(type: String, season: Int?, episode: Int?, alternateSeason: Int?, alternateEpisode: Int?) -> [(season: Int, episode: Int)] {
        guard type == "series" else { return [] }
        var tuples: [(season: Int, episode: Int)] = []

        if let season, let episode {
            tuples.append((season, episode))
        }

        if let alternateSeason, let alternateEpisode {
            tuples.append((alternateSeason, alternateEpisode))
        }

        var seen = Set<String>()
        return tuples.filter { tuple in
            tuple.season > 0 &&
            tuple.episode > 0 &&
            seen.insert("\(tuple.season):\(tuple.episode)").inserted
        }
    }

    // MARK: - Helpers

    static func normalizedConfiguredURL(from url: String) -> String {
        var cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.lowercased().hasPrefix("stremio://") {
            cleaned = "https://" + String(cleaned.dropFirst("stremio://".count))
        }

        if cleaned.hasSuffix("/") {
            cleaned = String(cleaned.dropLast())
        }

        if cleaned.hasSuffix("/manifest.json") {
            cleaned = String(cleaned.dropLast("/manifest.json".count))
        }

        return cleaned
    }

    /// Normalizes a user-provided URL to point to manifest.json
    private func normalizeManifestURL(_ url: String) -> String {
        "\(Self.normalizedConfiguredURL(from: url))/manifest.json"
    }

    private func normalizedBaseURL(_ url: String) -> String {
        Self.normalizedConfiguredURL(from: url)
    }

    private func encodePathSegment(_ value: String, preservingColon: Bool) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ":/?#[]@!$&'()*+,;=")
        if preservingColon {
            allowed.insert(charactersIn: ":")
        }
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func encodeExtraValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "+", with: "%20") ?? value
    }

    enum StremioError: LocalizedError {
        case invalidURL
        case httpError(Int)
        case noStreams

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Stremio addon URL"
            case .httpError(let code): return "HTTP error \(code)"
            case .noStreams: return "No streams available"
            }
        }
    }
}
