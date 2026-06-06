//
//  MangaLibraryItem.swift
//  Kanzen
//
//  Created by Luna on 2026.
//

import Foundation

struct MangaLibraryItem: Codable, Identifiable, Equatable {
    var id: Int { aniListId }

    let aniListId: Int
    let title: String
    let coverURL: String?
    let format: String?
    let totalChapters: Int?
    var moduleUUID: String? = nil
    var contentParams: String? = nil
    var isNovel: Bool? = nil
    var route: MangaContentRoute? = nil
    var dateAdded: Date = Date()

    /// Create a library item from module search content.
    /// Produces a stable negative ID from the module + content identifier
    /// so it never collides with AniList IDs (which are always positive).
    static func fromModule(moduleId: UUID, contentId: String, title: String, coverURL: String?, isNovel: Bool) -> MangaLibraryItem {
        let combined = "\(moduleId.uuidString):\(contentId)"
        // Use a stable hash; make it negative to avoid AniList ID collisions
        let hash = combined.utf8.reduce(into: 5381) { h, c in h = ((h &<< 5) &+ h) &+ Int(c) }
        let stableId = hash < 0 ? hash : -hash - 1
        return MangaLibraryItem(
            aniListId: stableId,
            title: title,
            coverURL: coverURL,
            format: isNovel ? "NOVEL" : "MANGA",
            totalChapters: nil,
            moduleUUID: moduleId.uuidString,
            contentParams: contentId,
            isNovel: isNovel,
            route: .legacyModule(moduleUUID: moduleId.uuidString, contentParams: contentId, isNovel: isNovel)
        )
    }

    static func fromAidoku(sourceId: String, mangaKey: String, title: String, coverURL: String?) -> MangaLibraryItem {
        let route = MangaContentRoute.aidoku(sourceId: sourceId, mangaKey: mangaKey)
        return MangaLibraryItem(
            aniListId: route.stableNegativeId,
            title: title,
            coverURL: coverURL,
            format: "MANGA",
            totalChapters: nil,
            route: route
        )
    }

    static func == (lhs: MangaLibraryItem, rhs: MangaLibraryItem) -> Bool {
        lhs.aniListId == rhs.aniListId
    }
}
