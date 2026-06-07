//
//  CatalogManager.swift
//  Luna
//
//  Created by Soupy-dev
//

import Foundation
import Combine

class CatalogManager: ObservableObject {
    static let shared = CatalogManager()
    
    @Published var catalogs: [Catalog] = []
    
    private let userDefaults = UserDefaults.standard
    private let catalogsKey = "enabledCatalogs"
    
    init() {
        loadCatalogs()
    }
    
    private func loadCatalogs() {
        // Default catalogs
        let defaultCatalogs: [Catalog] = [
            Catalog(id: "forYou", name: "Just For You", source: .local, isEnabled: true, order: 0),
            Catalog(id: "becauseYouWatched", name: "Because You Watched", source: .local, isEnabled: true, order: 1),
            Catalog(id: "trending", name: "Trending This Week", source: .tmdb, isEnabled: true, order: 2),
            Catalog(id: "popularMovies", name: "Popular Movies", source: .tmdb, isEnabled: true, order: 3),
            Catalog(id: "networks", name: "Network", source: .tmdb, isEnabled: true, order: 4, displayStyle: .network),
            Catalog(id: "nowPlayingMovies", name: "Now Playing Movies", source: .tmdb, isEnabled: false, order: 5),
            Catalog(id: "upcomingMovies", name: "Upcoming Movies", source: .tmdb, isEnabled: false, order: 6),
            Catalog(id: "popularTVShows", name: "Popular TV Shows", source: .tmdb, isEnabled: true, order: 7),
            Catalog(id: "genres", name: "Category", source: .tmdb, isEnabled: true, order: 8, displayStyle: .genre),
            Catalog(id: "onTheAirTV", name: "On The Air TV Shows", source: .tmdb, isEnabled: false, order: 9),
            Catalog(id: "airingTodayTV", name: "Airing Today TV Shows", source: .tmdb, isEnabled: false, order: 10),
            Catalog(id: "topRatedTVShows", name: "Top Rated TV Shows", source: .tmdb, isEnabled: true, order: 11),
            Catalog(id: "topRatedMovies", name: "Top Rated Movies", source: .tmdb, isEnabled: true, order: 12),
            Catalog(id: "companies", name: "Company", source: .tmdb, isEnabled: true, order: 13, displayStyle: .company),
            Catalog(id: "trendingAnime", name: "Trending Anime", source: .anilist, isEnabled: true, order: 14),
            Catalog(id: "popularAnime", name: "Popular Anime", source: .anilist, isEnabled: true, order: 15),
            Catalog(id: "featured", name: "Featured", source: .tmdb, isEnabled: true, order: 16, displayStyle: .featured),
            Catalog(id: "topRatedAnime", name: "Top Rated Anime", source: .anilist, isEnabled: true, order: 17),
            Catalog(id: "airingAnime", name: "Currently Airing Anime", source: .anilist, isEnabled: false, order: 18),
            Catalog(id: "upcomingAnime", name: "Upcoming Anime", source: .anilist, isEnabled: false, order: 19),
            Catalog(id: "bestTVShows", name: "Best TV Shows", source: .tmdb, isEnabled: false, order: 20, displayStyle: .ranked),
            Catalog(id: "bestMovies", name: "Best Movies", source: .tmdb, isEnabled: false, order: 21, displayStyle: .ranked),
            Catalog(id: "bestAnime", name: "Best Anime", source: .anilist, isEnabled: false, order: 22, displayStyle: .ranked)
        ]
        
        // Try to load saved catalogs
        if let data = userDefaults.data(forKey: catalogsKey),
           let savedCatalogs = try? JSONDecoder().decode([Catalog].self, from: data) {
            // Merge any newly added defaults while preserving the user's order
            var merged = savedCatalogs.sorted { $0.order < $1.order }
            let existingIds = Set(savedCatalogs.map { $0.id })
            let missingDefaults = defaultCatalogs.filter { !existingIds.contains($0.id) }
            merged.append(contentsOf: missingDefaults)
            
            // Ensure orders stay sequential after adding new entries
            merged = merged.enumerated().map { index, catalog in
                var updated = catalog
                updated.order = index
                return updated
            }
            
            self.catalogs = merged
            saveCatalogs()
        } else {
            self.catalogs = defaultCatalogs
            saveCatalogs()
        }
    }
    
    func saveCatalogs() {
        if let data = try? JSONEncoder().encode(catalogs) {
            userDefaults.set(data, forKey: catalogsKey)
            userDefaults.synchronize()
        }
        // Dispatch to main thread to notify observers after persistence
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    func toggleCatalog(id: String) {
        if let index = catalogs.firstIndex(where: { $0.id == id }) {
            catalogs[index].isEnabled.toggle()
            saveCatalogs()
        }
    }
    
    func moveCatalog(from: IndexSet, to: Int) {
        catalogs.move(fromOffsets: from, toOffset: to)
        for (index, _) in catalogs.enumerated() {
            catalogs[index].order = index
        }
        saveCatalogs()
    }
    
    func getEnabledCatalogs() -> [Catalog] {
        catalogs.filter { $0.isEnabled }.sorted { $0.order < $1.order }
    }

    func syncStremioAddonCatalogs(from addons: [StremioAddon]) {
        let addonCatalogs = addons.flatMap { addon in
            addon.manifest.homeCatalogs.compactMap { stremioCatalog -> Catalog? in
                guard !stremioCatalog.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let mediaType = stremioCatalog.lunaMediaType else {
                    return nil
                }
                let catalogId = Catalog.stremioCatalogId(addon: addon, stremioCatalog: stremioCatalog)
                let name = Self.stremioCatalogDisplayName(addon: addon, stremioCatalog: stremioCatalog)
                return Catalog(
                    id: catalogId,
                    name: name,
                    source: .stremio,
                    isEnabled: true,
                    order: 0,
                    stremioAddonId: addon.id,
                    stremioAddonName: addon.manifest.name,
                    stremioCatalogId: stremioCatalog.id,
                    stremioCatalogType: stremioCatalog.type,
                    stremioMediaType: mediaType
                )
            }
        }

        let validStremioIds = Set(addonCatalogs.map(\.id))
        var existingById = Dictionary(uniqueKeysWithValues: catalogs.map { ($0.id, $0) })
        var merged = catalogs.filter { catalog in
            catalog.source != .stremio || validStremioIds.contains(catalog.id)
        }

        for addonCatalog in addonCatalogs {
            if let index = merged.firstIndex(where: { $0.id == addonCatalog.id }) {
                let existing = merged[index]
                merged[index] = addonCatalog.updatingUserState(isEnabled: existing.isEnabled, order: existing.order)
            } else if let existing = existingById[addonCatalog.id] {
                merged.append(addonCatalog.updatingUserState(isEnabled: existing.isEnabled, order: existing.order))
            } else {
                let nextOrder = (merged.map(\.order).max() ?? -1) + 1
                merged.append(addonCatalog.updatingUserState(isEnabled: true, order: nextOrder))
            }
            existingById[addonCatalog.id] = addonCatalog
        }

        merged = merged
            .sorted { $0.order < $1.order }
            .enumerated()
            .map { index, catalog in
                var updated = catalog
                updated.order = index
                return updated
            }

        guard merged.map(\.id) != catalogs.map(\.id) ||
              zip(merged, catalogs).contains(where: { $0.name != $1.name || $0.isEnabled != $1.isEnabled || $0.order != $1.order }) else {
            return
        }

        catalogs = merged
        saveCatalogs()
    }

    private static func stremioCatalogDisplayName(addon: StremioAddon, stremioCatalog: StremioCatalog) -> String {
        let rawName = stremioCatalog.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalogName = rawName?.isEmpty == false ? rawName! : stremioCatalog.type.capitalized
        let addonName = addon.manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addonName.isEmpty else { return catalogName }
        if catalogName.localizedCaseInsensitiveContains(addonName) {
            return catalogName
        }
        return "\(addonName) - \(catalogName)"
    }
}

struct Catalog: Identifiable, Codable {
    let id: String
    let name: String
    let source: CatalogSource
    var isEnabled: Bool
    var order: Int
    var displayStyle: CatalogDisplayStyle
    var stremioAddonId: UUID?
    var stremioAddonName: String?
    var stremioCatalogId: String?
    var stremioCatalogType: String?
    var stremioMediaType: String?

    enum CodingKeys: String, CodingKey {
        case id, name, source, isEnabled, order, displayStyle
        case stremioAddonId, stremioAddonName, stremioCatalogId, stremioCatalogType, stremioMediaType
    }
    
    enum CatalogSource: String, Codable {
        case tmdb = "TMDB"
        case anilist = "AniList"
        case local = "Local"
        case stremio = "Stremio"
    }
    
    enum CatalogDisplayStyle: String, Codable {
        case standard
        case network
        case genre
        case company
        case ranked
        case featured
    }
    
    init(
        id: String,
        name: String,
        source: CatalogSource,
        isEnabled: Bool,
        order: Int,
        displayStyle: CatalogDisplayStyle = .standard,
        stremioAddonId: UUID? = nil,
        stremioAddonName: String? = nil,
        stremioCatalogId: String? = nil,
        stremioCatalogType: String? = nil,
        stremioMediaType: String? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.isEnabled = isEnabled
        self.order = order
        self.displayStyle = displayStyle
        self.stremioAddonId = stremioAddonId
        self.stremioAddonName = stremioAddonName
        self.stremioCatalogId = stremioCatalogId
        self.stremioCatalogType = stremioCatalogType
        self.stremioMediaType = stremioMediaType
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decode(CatalogSource.self, forKey: .source)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        order = try container.decode(Int.self, forKey: .order)
        displayStyle = try container.decodeIfPresent(CatalogDisplayStyle.self, forKey: .displayStyle) ?? .standard
        stremioAddonId = try container.decodeIfPresent(UUID.self, forKey: .stremioAddonId)
        stremioAddonName = try container.decodeIfPresent(String.self, forKey: .stremioAddonName)
        stremioCatalogId = try container.decodeIfPresent(String.self, forKey: .stremioCatalogId)
        stremioCatalogType = try container.decodeIfPresent(String.self, forKey: .stremioCatalogType)
        stremioMediaType = try container.decodeIfPresent(String.self, forKey: .stremioMediaType)
    }

    static func stremioCatalogId(addon: StremioAddon, stremioCatalog: StremioCatalog) -> String {
        "stremio:\(addon.id.uuidString):\(stremioCatalog.type):\(stremioCatalog.id)"
    }

    func updatingUserState(isEnabled: Bool, order: Int) -> Catalog {
        Catalog(
            id: id,
            name: name,
            source: source,
            isEnabled: isEnabled,
            order: order,
            displayStyle: displayStyle,
            stremioAddonId: stremioAddonId,
            stremioAddonName: stremioAddonName,
            stremioCatalogId: stremioCatalogId,
            stremioCatalogType: stremioCatalogType,
            stremioMediaType: stremioMediaType
        )
    }
}
