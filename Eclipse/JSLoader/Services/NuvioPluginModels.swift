import Foundation

struct NuvioPluginManifest: Decodable {
    let name: String
    let version: String
    let description: String?
    let author: String?
    let scrapers: [NuvioPluginManifestScraper]
}

struct NuvioPluginManifestScraper: Decodable {
    let id: String
    let name: String
    let description: String?
    let version: String
    let filename: String
    let supportedTypes: [String]
    let enabled: Bool
    let logo: String?
    let contentLanguage: [String]?
    let supportedPlatforms: [String]?
    let disabledPlatforms: [String]?
    let formats: [String]?
    let supportedFormats: [String]?
    let supportsExternalPlayer: Bool?
    let limited: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, description, version, filename, enabled, logo, formats, limited
        case supportedTypes, contentLanguage, supportedPlatforms, disabledPlatforms, supportedFormats, supportsExternalPlayer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        version = try container.decode(String.self, forKey: .version)
        filename = try container.decode(String.self, forKey: .filename)
        supportedTypes = try container.decodeIfPresent([String].self, forKey: .supportedTypes) ?? ["movie", "tv"]
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        logo = try container.decodeIfPresent(String.self, forKey: .logo)
        contentLanguage = try container.decodeIfPresent([String].self, forKey: .contentLanguage)
        supportedPlatforms = try container.decodeIfPresent([String].self, forKey: .supportedPlatforms)
        disabledPlatforms = try container.decodeIfPresent([String].self, forKey: .disabledPlatforms)
        formats = try container.decodeIfPresent([String].self, forKey: .formats)
        supportedFormats = try container.decodeIfPresent([String].self, forKey: .supportedFormats)
        supportsExternalPlayer = try container.decodeIfPresent(Bool.self, forKey: .supportsExternalPlayer)
        limited = try container.decodeIfPresent(Bool.self, forKey: .limited)
    }
}

struct NuvioPluginRepositoryItem: Codable, Identifiable, Hashable {
    var id: String { manifestUrl }
    let manifestUrl: String
    let name: String
    let description: String?
    let version: String?
    let scraperCount: Int
    let lastUpdated: TimeInterval
    var isRefreshing: Bool = false
    var errorMessage: String? = nil

    var hostLabel: String {
        URL(string: manifestUrl)?.host ?? manifestUrl
    }
}

struct NuvioPluginScraper: Codable, Identifiable, Hashable {
    let id: String
    let repositoryUrl: String
    let name: String
    let description: String
    let version: String
    let filename: String
    let supportedTypes: [String]
    var enabled: Bool
    let manifestEnabled: Bool
    let logo: String?
    let contentLanguage: [String]
    let formats: [String]?
    let code: String

    func supportsType(_ type: String) -> Bool {
        let normalized = NuvioPluginSupport.normalizeType(type)
        return supportedTypes.map(NuvioPluginSupport.normalizeType).contains(normalized)
    }
}

struct NuvioPluginStream: Identifiable, Codable, Hashable {
    let id: String
    let scraperId: String
    let scraperName: String
    let sourceId: String
    let sourceName: String
    let title: String
    let name: String?
    let url: String
    let quality: String?
    let size: String?
    let language: String?
    let provider: String?
    let type: String?
    let seeders: Int?
    let peers: Int?
    let infoHash: String?
    let headers: [String: String]?

    var displayName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty { return trimmedName }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Stream" : trimmedTitle
    }

    var metadataLabel: String {
        [quality, size, language, provider]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " - ")
    }

    var isDirectHTTP: Bool {
        guard let parsed = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parsed.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    var sanitizedHeaders: [String: String]? {
        let cleaned = headers
            .orEmpty
            .compactMap { key, value -> (String, String)? in
                let headerName = key.trimmingCharacters(in: .whitespacesAndNewlines)
                let headerValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !headerName.isEmpty,
                      !headerValue.isEmpty,
                      !headerName.caseInsensitiveCompare("Range").isSame else {
                    return nil
                }
                return (headerName, String(headerValue.prefix(8 * 1024)))
            }
        return cleaned.isEmpty ? nil : Dictionary(uniqueKeysWithValues: cleaned)
    }

    var qualitySearchLabel: String {
        [displayName, metadataLabel, type ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct NuvioPluginSource: Identifiable, Hashable {
    let id: String
    let name: String
    let repositoryUrl: String?
    let logo: String?
    let scrapers: [NuvioPluginScraper]

    var sourceHealthId: String { id }
}

struct NuvioStoredPluginsState: Codable, Hashable {
    var pluginsEnabled: Bool = true
    var groupStreamsByRepository: Bool = false
    var repositories: [NuvioPluginRepositoryItem] = []
    var scrapers: [NuvioPluginScraper] = []
}

enum NuvioPluginError: LocalizedError {
    case invalidRepositoryURL
    case emptyRepositoryURL
    case duplicateRepository
    case manifestNameMissing
    case manifestVersionMissing
    case manifestHasNoProviders
    case repositoryInstallFailed(String)
    case providerNotFound
    case getStreamsNotFound
    case runtimeTimeout
    case runtimeFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryURL:
            return "Enter a valid plugin repository URL."
        case .emptyRepositoryURL:
            return "Enter a plugin repository URL."
        case .duplicateRepository:
            return "That plugin repository is already installed."
        case .manifestNameMissing:
            return "Plugin manifest is missing a name."
        case .manifestVersionMissing:
            return "Plugin manifest is missing a version."
        case .manifestHasNoProviders:
            return "Plugin manifest does not contain any providers."
        case .repositoryInstallFailed(let message):
            return message.isEmpty ? "Plugin repository install failed." : message
        case .providerNotFound:
            return "Plugin provider was not found."
        case .getStreamsNotFound:
            return "Plugin does not export getStreams."
        case .runtimeTimeout:
            return "Plugin timed out while fetching streams."
        case .runtimeFailed(let message):
            return message.isEmpty ? "Plugin runtime failed." : message
        case .invalidResponse:
            return "Plugin returned an invalid stream response."
        }
    }
}

enum NuvioPluginSupport {
    static func normalizeType(_ value: String) -> String {
        switch value.lowercased() {
        case "series", "show", "other":
            return "tv"
        default:
            return value.lowercased()
        }
    }

    static func isDirectHTTPURL(_ value: String?) -> Bool {
        // Use a scheme prefix check rather than `URL(string:)`, which returns nil for
        // otherwise-valid stream URLs containing unencoded characters (spaces, `|`, `[]`,
        // etc.). The reference runtime keeps any non-blank URL; we only additionally
        // require http(s) because mpv playback goes over HTTP via the header proxy.
        guard let value else { return false }
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    static func streamID(scraperId: String, sourceId: String, url: String, title: String, index: Int) -> String {
        "\(sourceId)|\(scraperId)|\(index)|\(url)|\(title)".sha256
    }

    static func sourceGroups(
        scrapers: [NuvioPluginScraper],
        repositories: [NuvioPluginRepositoryItem],
        groupByRepository: Bool
    ) -> [NuvioPluginSource] {
        if !groupByRepository {
            return scrapers
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { scraper in
                    NuvioPluginSource(
                        id: "plugin:\(scraper.id)",
                        name: scraper.name,
                        repositoryUrl: scraper.repositoryUrl,
                        logo: scraper.logo,
                        scrapers: [scraper]
                    )
                }
        }

        let repoNameByUrl = Dictionary(uniqueKeysWithValues: repositories.map { ($0.manifestUrl, $0.name) })
        return Dictionary(grouping: scrapers, by: \.repositoryUrl)
            .map { repositoryUrl, scrapers in
                NuvioPluginSource(
                    id: "plugin-repo:\(repositoryUrl.lowercased())",
                    name: repoNameByUrl[repositoryUrl]?.nilIfBlank ?? fallbackRepositoryLabel(for: repositoryUrl),
                    repositoryUrl: repositoryUrl,
                    logo: scrapers.first?.logo,
                    scrapers: scrapers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func fallbackRepositoryLabel(for repositoryUrl: String) -> String {
        guard let url = URL(string: repositoryUrl) else { return repositoryUrl }
        return url.host ?? repositoryUrl
    }
}

private extension Optional where Wrapped == [String: String] {
    var orEmpty: [String: String] { self ?? [:] }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension ComparisonResult {
    var isSame: Bool { self == .orderedSame }
}
