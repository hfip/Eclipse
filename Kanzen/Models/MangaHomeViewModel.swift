//
//  MangaHomeViewModel.swift
//  Kanzen
//
//  Created by Eclipse on 2025.
//

import Foundation
import SwiftUI
import AidokuRunner

enum MangaHomeSectionKind: String, Codable {
    case genres
    case hotUpdates
    case latestUpdates
    case popular
    case custom

    static func from(_ value: String?, title: String) -> MangaHomeSectionKind {
        let normalized = (value ?? title)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        if normalized.contains("genre") || normalized.contains("tag") { return .genres }
        if normalized.contains("hot") { return .hotUpdates }
        if normalized.contains("latest") || normalized.contains("recent") || normalized.contains("update") { return .latestUpdates }
        if normalized.contains("popular") || normalized.contains("trend") { return .popular }
        return .custom
    }
}

struct MangaHomeItem: Identifiable, Equatable {
    let id: String
    let title: String
    let imageURL: String
    let params: String
    let subtitle: String?
    let isContainer: Bool
    let route: MangaContentRoute?
    let aidokuManga: AidokuRunner.Manga?
    let aidokuListing: AidokuRunner.Listing?
    let aidokuFilterValues: [AidokuRunner.FilterValue]?

    init?(
        dict: [String: Any],
        module: ModuleDataContainer,
        sectionKind: MangaHomeSectionKind
    ) {
        let title = Self.string(from: dict, keys: ["title", "name", "label"])
        let params = Self.string(from: dict, keys: ["params", "id", "href", "url", "link"])

        guard let title, !title.isEmpty else { return nil }

        let resolvedParams = params?.isEmpty == false ? params! : title
        self.title = title
        self.params = resolvedParams
        self.imageURL = Self.string(from: dict, keys: ["imageURL", "imageUrl", "image", "cover", "coverURL", "poster"]) ?? ""
        self.subtitle = Self.string(from: dict, keys: ["subtitle", "chapter", "episode", "description", "latest"])

        let rawType = Self.string(from: dict, keys: ["type", "kind"])
        let normalizedType = rawType?.lowercased() ?? ""
        self.isContainer = sectionKind == .genres
            || normalizedType == "genre"
            || normalizedType == "section"
            || normalizedType == "category"

        self.route = .legacyModule(
            moduleUUID: module.id.uuidString,
            contentParams: resolvedParams,
            isNovel: module.moduleData.novel == true
        )
        self.aidokuManga = nil
        self.aidokuListing = nil
        self.aidokuFilterValues = nil
        self.id = "module:\(module.id.uuidString):\(resolvedParams):\(title)"
    }

    init(
        sourceId: String,
        manga: AidokuRunner.Manga,
        subtitle: String? = nil,
        idSuffix: String = ""
    ) {
        self.title = manga.title
        self.imageURL = manga.cover ?? ""
        self.params = manga.key
        self.subtitle = subtitle ?? manga.authors?.joined(separator: ", ")
        self.isContainer = false
        self.route = .aidoku(sourceId: sourceId, mangaKey: manga.key)
        self.aidokuManga = manga
        self.aidokuListing = nil
        self.aidokuFilterValues = nil
        self.id = "aidoku:\(sourceId):manga:\(manga.key):\(idSuffix)"
    }

    init(
        sourceId: String,
        link: AidokuRunner.HomeComponent.Value.Link,
        sectionKind: MangaHomeSectionKind,
        idSuffix: String = ""
    ) {
        self.title = link.title
        self.imageURL = link.imageUrl ?? ""
        self.subtitle = link.subtitle

        switch link.value {
        case .manga(let manga):
            self.params = manga.key
            self.isContainer = false
            self.route = .aidoku(sourceId: sourceId, mangaKey: manga.key)
            self.aidokuManga = manga
            self.aidokuListing = nil
            self.aidokuFilterValues = nil
        case .listing(let listing):
            self.params = listing.id
            self.isContainer = true
            self.route = nil
            self.aidokuManga = nil
            self.aidokuListing = listing
            self.aidokuFilterValues = nil
        case .url(let url):
            self.params = url
            self.isContainer = sectionKind == .genres
            self.route = nil
            self.aidokuManga = nil
            self.aidokuListing = nil
            self.aidokuFilterValues = nil
        case nil:
            self.params = link.title
            self.isContainer = sectionKind == .genres
            self.route = nil
            self.aidokuManga = nil
            self.aidokuListing = nil
            self.aidokuFilterValues = nil
        }

        self.id = "aidoku:\(sourceId):link:\(params):\(title):\(idSuffix)"
    }

    init(sourceId: String, listing: AidokuRunner.Listing) {
        self.title = listing.name
        self.imageURL = ""
        self.params = listing.id
        self.subtitle = nil
        self.isContainer = true
        self.route = nil
        self.aidokuManga = nil
        self.aidokuListing = listing
        self.aidokuFilterValues = nil
        self.id = "aidoku:\(sourceId):listing:\(listing.id)"
    }

    init(sourceId: String, filterTitle: String, values: [AidokuRunner.FilterValue]) {
        self.title = filterTitle
        self.imageURL = ""
        self.params = filterTitle
        self.subtitle = nil
        self.isContainer = true
        self.route = nil
        self.aidokuManga = nil
        self.aidokuListing = nil
        self.aidokuFilterValues = values
        self.id = "aidoku:\(sourceId):filters:\(filterTitle):\(values.map(\.id).joined(separator: ","))"
    }

    private static func string(from dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let string = dict[key] as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let number = dict[key] as? NSNumber {
                return number.stringValue
            }
            if let value = dict[key], !(value is NSNull) {
                let string = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !string.isEmpty { return string }
            }
        }
        return nil
    }
}

struct MangaHomeSection: Identifiable, Equatable {
    let id: String
    let title: String
    let kind: MangaHomeSectionKind
    var items: [MangaHomeItem]
    let aidokuListing: AidokuRunner.Listing?
    let aidokuFilterValues: [AidokuRunner.FilterValue]?

    init?(dict: [String: Any], module: ModuleDataContainer) {
        guard
            let title = Self.string(from: dict, keys: ["title", "name", "label"]),
            !title.isEmpty
        else { return nil }

        let rawKind = Self.string(from: dict, keys: ["kind", "type"])
        let kind = MangaHomeSectionKind.from(rawKind, title: title)
        let sectionId = Self.string(from: dict, keys: ["id", "sectionId", "href", "params", "slug"]) ?? Self.slug(title)
        let rawItems = Self.array(from: dict, keys: ["items", "data", "results", "manga", "entries", "list"])

        self.id = "module:\(module.id.uuidString):section:\(sectionId)"
        self.title = title
        self.kind = kind
        self.items = rawItems
            .compactMap { MangaHomeItem(dict: $0, module: module, sectionKind: kind) }
            .prefix(MangaHomeViewModel.maxRetainedItemsPerSection)
            .map { $0 }
        self.aidokuListing = nil
        self.aidokuFilterValues = nil
    }

    static func section(
        title: String,
        id: String,
        kind: MangaHomeSectionKind,
        items: [MangaHomeItem],
        aidokuListing: AidokuRunner.Listing? = nil,
        aidokuFilterValues: [AidokuRunner.FilterValue]? = nil
    ) -> MangaHomeSection {
        MangaHomeSection(
            id: id,
            title: title,
            kind: kind,
            items: items,
            aidokuListing: aidokuListing,
            aidokuFilterValues: aidokuFilterValues
        )
    }

    private init(
        id: String,
        title: String,
        kind: MangaHomeSectionKind,
        items: [MangaHomeItem],
        aidokuListing: AidokuRunner.Listing?,
        aidokuFilterValues: [AidokuRunner.FilterValue]?
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.items = items
        self.aidokuListing = aidokuListing
        self.aidokuFilterValues = aidokuFilterValues
    }

    private static func string(from dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let string = dict[key] as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let number = dict[key] as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private static func array(from dict: [String: Any], keys: [String]) -> [[String: Any]] {
        for key in keys {
            if let array = dict[key] as? [[String: Any]] {
                return array
            }
            if let array = dict[key] as? [Any] {
                return array.compactMap { $0 as? [String: Any] }
            }
        }
        return []
    }

    static func slug(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

enum MangaHomeLoadState: Equatable {
    case idle
    case loading
    case loaded
    case unsupported
    case failed(String)
}

final class MangaHomeViewModel: ObservableObject {
    static let maxSections = 8
    static let maxRetainedItemsPerSection = 30
    static let maxVisibleItemsPerSection = 15

    @Published var sources: [MangaHomeSource] = []
    @Published var selectedSourceID: String?
    @Published var sectionsBySource: [String: [MangaHomeSection]] = [:]
    @Published var loadStates: [String: MangaHomeLoadState] = [:]

    private let selectedSourceKey = "kanzenHomeSelectedSourceID"
    private var loadTokens: [String: UUID] = [:]

    var selectedSource: MangaHomeSource? {
        guard let selectedSourceID else { return nil }
        return sources.first { $0.id == selectedSourceID }
    }

    func updateSources(_ newSources: [MangaHomeSource]) {
        sources = newSources

        let savedID = UserDefaults.standard.string(forKey: selectedSourceKey)
        if let selectedSourceID, newSources.contains(where: { $0.id == selectedSourceID }) {
            return
        }
        if let savedID, newSources.contains(where: { $0.id == savedID }) {
            selectedSourceID = savedID
        } else {
            selectedSourceID = newSources.first?.id
        }
    }

    func selectSource(_ source: MangaHomeSource) {
        selectedSourceID = source.id
        UserDefaults.standard.set(source.id, forKey: selectedSourceKey)
        loadHome(for: source, force: false)
    }

    func loadSelectedSource(force: Bool = false) {
        guard let source = selectedSource else { return }
        loadHome(for: source, force: force)
    }

    func loadHome(for source: MangaHomeSource, force: Bool = false) {
        if !force, sectionsBySource[source.id] != nil {
            return
        }

        let token = UUID()
        loadTokens[source.id] = token
        loadStates[source.id] = .loading

        switch source.kind {
        case .aidoku:
            Task { @MainActor in
                await loadAidokuHome(for: source, token: token)
            }
        case .legacyModule:
            loadLegacyModuleHome(for: source, token: token)
        }
    }

    static func loadSectionItems(source: MangaHomeSource, section: MangaHomeSection, page: Int) async throws -> [MangaHomeItem] {
        switch source.kind {
        case .aidoku:
            guard let sourceId = source.sourceId else {
                throw AidokuSourceError.sourceNotInstalled
            }

            if let listing = section.aidokuListing {
                let result = try await AidokuSourceManager.shared.mangaList(sourceId: sourceId, listing: listing, page: page)
                return result.entries
                    .prefix(Self.maxRetainedItemsPerSection)
                    .map { MangaHomeItem(sourceId: sourceId, manga: $0) }
            }

            if let values = section.aidokuFilterValues, !values.isEmpty {
                let result = try await AidokuSourceManager.shared.search(sourceId: sourceId, query: nil, page: page, filters: values)
                return result.entries
                    .prefix(Self.maxRetainedItemsPerSection)
                    .map { MangaHomeItem(sourceId: sourceId, manga: $0) }
            }

            return []

        case .legacyModule:
            guard let module = source.module else {
                return []
            }

            return try await withCheckedThrowingContinuation { continuation in
                let engine = KanzenEngine()
                do {
                    let script = try ModuleManager.shared.getModuleScript(module: module)
                    try engine.loadScript(script, isNovel: module.moduleData.novel == true)
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let rawSectionId = section.id.components(separatedBy: ":section:").last ?? section.id
                engine.homeSectionItems(sectionId: rawSectionId, page: page) { rawItems in
                    let items = (rawItems ?? [])
                        .compactMap { MangaHomeItem(dict: $0, module: module, sectionKind: section.kind) }
                        .prefix(Self.maxRetainedItemsPerSection)
                        .map { $0 }
                    continuation.resume(returning: items)
                }
            }
        }
    }

    @MainActor
    private func loadAidokuHome(for source: MangaHomeSource, token: UUID) async {
        guard loadTokens[source.id] == token, let sourceId = source.sourceId else { return }

        do {
            await AidokuSourceManager.shared.ensureRuntimeReady()
            guard let runtime = AidokuSourceManager.shared.source(id: sourceId) else {
                throw AidokuSourceError.sourceNotInstalled
            }

            var sections: [MangaHomeSection] = []

            if runtime.features.providesHome {
                let home = try await AidokuSourceManager.shared.home(sourceId: sourceId)
                sections = home.components
                    .compactMap { Self.section(from: $0, sourceId: sourceId) }
                    .prefix(Self.maxSections)
                    .map { $0 }
            }

            if sections.isEmpty, runtime.hasListings {
                let listings = try await AidokuSourceManager.shared.listings(sourceId: sourceId)
                sections = listings
                    .prefix(Self.maxSections)
                    .map {
                        MangaHomeSection.section(
                            title: $0.name,
                            id: "aidoku:\(sourceId):listing:\($0.id)",
                            kind: MangaHomeSectionKind.from(nil, title: $0.name),
                            items: [],
                            aidokuListing: $0
                        )
                    }
            }

            for index in sections.indices where sections[index].items.isEmpty {
                let items = try await Self.loadSectionItems(source: source, section: sections[index], page: 0)
                sections[index].items = items
            }

            guard loadTokens[source.id] == token else { return }
            sectionsBySource[source.id] = sections.filter { !$0.items.isEmpty || $0.aidokuListing != nil || $0.aidokuFilterValues != nil }
            loadStates[source.id] = sectionsBySource[source.id]?.isEmpty == true ? .unsupported : .loaded
        } catch {
            guard loadTokens[source.id] == token else { return }
            sectionsBySource[source.id] = []
            loadStates[source.id] = .failed(error.localizedDescription)
            ReaderLogger.shared.log("Aidoku home failed source=\(sourceId): \(error.localizedDescription)", type: "AidokuHome")
        }
    }

    private func loadLegacyModuleHome(for source: MangaHomeSource, token: UUID) {
        guard let module = source.module else {
            loadStates[source.id] = .unsupported
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let engine = KanzenEngine()
            do {
                let script = try ModuleManager.shared.getModuleScript(module: module)
                try engine.loadScript(script, isNovel: module.moduleData.novel == true)
            } catch {
                DispatchQueue.main.async {
                    guard self.loadTokens[source.id] == token else { return }
                    self.loadStates[source.id] = .failed(error.localizedDescription)
                }
                return
            }

            engine.homeSections(page: 0) { rawSections in
                guard self.loadTokens[source.id] == token else { return }

                guard let rawSections else {
                    DispatchQueue.main.async {
                        guard self.loadTokens[source.id] == token else { return }
                        self.sectionsBySource[source.id] = []
                        self.loadStates[source.id] = .unsupported
                    }
                    return
                }

                var sections = rawSections
                    .compactMap { MangaHomeSection(dict: $0, module: module) }
                    .prefix(Self.maxSections)
                    .map { $0 }

                guard !sections.isEmpty else {
                    DispatchQueue.main.async {
                        guard self.loadTokens[source.id] == token else { return }
                        self.sectionsBySource[source.id] = []
                        self.loadStates[source.id] = .loaded
                    }
                    return
                }

                let group = DispatchGroup()
                let lock = NSLock()

                for index in sections.indices where sections[index].items.isEmpty {
                    let sectionID = sections[index].id.components(separatedBy: ":section:").last ?? sections[index].id
                    let sectionKind = sections[index].kind
                    group.enter()
                    engine.homeSectionItems(sectionId: sectionID, page: 0) { rawItems in
                        let items = (rawItems ?? [])
                            .compactMap { MangaHomeItem(dict: $0, module: module, sectionKind: sectionKind) }
                            .prefix(Self.maxRetainedItemsPerSection)
                            .map { $0 }

                        lock.lock()
                        sections[index].items = items
                        lock.unlock()
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    guard self.loadTokens[source.id] == token else { return }
                    self.sectionsBySource[source.id] = sections.filter { !$0.items.isEmpty }
                    self.loadStates[source.id] = .loaded
                }
            }
        }
    }

    private static func section(from component: AidokuRunner.HomeComponent, sourceId: String) -> MangaHomeSection? {
        let title = component.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title?.isEmpty == false ? title! : "Featured"
        let kind = MangaHomeSectionKind.from(nil, title: resolvedTitle)
        let slug = MangaHomeSection.slug(resolvedTitle)

        switch component.value {
        case .imageScroller(let links, _, _, _), .scroller(let links, _), .mangaList(_, _, let links, _), .links(let links):
            let listing = component.listing
            let items = links
                .compactMap { link -> MangaHomeItem? in
                    let item = MangaHomeItem(sourceId: sourceId, link: link, sectionKind: kind, idSuffix: slug)
                    return item.title.isEmpty ? nil : item
                }
                .prefix(Self.maxRetainedItemsPerSection)
                .map { $0 }
            return MangaHomeSection.section(
                title: resolvedTitle,
                id: "aidoku:\(sourceId):home:\(slug)",
                kind: kind,
                items: items,
                aidokuListing: listing
            )

        case .bigScroller(let entries, _):
            let items = entries
                .prefix(Self.maxRetainedItemsPerSection)
                .map { MangaHomeItem(sourceId: sourceId, manga: $0, idSuffix: slug) }
            return MangaHomeSection.section(
                title: resolvedTitle,
                id: "aidoku:\(sourceId):home:\(slug)",
                kind: kind,
                items: items
            )

        case .mangaChapterList(_, let entries, let listing):
            let items = entries
                .prefix(Self.maxRetainedItemsPerSection)
                .map { entry in
                    MangaHomeItem(
                        sourceId: sourceId,
                        manga: entry.manga,
                        subtitle: chapterSubtitle(entry.chapter),
                        idSuffix: slug
                    )
                }
            return MangaHomeSection.section(
                title: resolvedTitle,
                id: "aidoku:\(sourceId):home:\(slug)",
                kind: .latestUpdates,
                items: items,
                aidokuListing: listing
            )

        case .filters(let filters):
            let items = filters
                .compactMap { item -> MangaHomeItem? in
                    guard let values = item.values, !values.isEmpty else { return nil }
                    return MangaHomeItem(sourceId: sourceId, filterTitle: item.title, values: values)
                }
                .prefix(Self.maxRetainedItemsPerSection)
                .map { $0 }
            return MangaHomeSection.section(
                title: resolvedTitle,
                id: "aidoku:\(sourceId):filters:\(slug)",
                kind: .genres,
                items: items
            )
        }
    }

    private static func chapterSubtitle(_ chapter: AidokuRunner.Chapter) -> String {
        if let volume = chapter.volumeNumber, let number = chapter.chapterNumber {
            return "Vol. \(formatNumber(volume)) Ch. \(formatNumber(number))"
        }
        if let number = chapter.chapterNumber {
            return "Ch. \(formatNumber(number))"
        }
        return chapter.title ?? "Latest chapter"
    }

    private static func formatNumber(_ value: Float) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}

private extension AidokuRunner.HomeComponent {
    var listing: AidokuRunner.Listing? {
        switch value {
        case .scroller(_, let listing), .mangaList(_, _, _, let listing), .mangaChapterList(_, _, let listing):
            return listing
        default:
            return nil
        }
    }
}
