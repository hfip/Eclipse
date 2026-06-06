//
//  KanzenGlobalSearchView.swift
//  Kanzen
//
//  Created by Luna on 2025.
//

import SwiftUI
import Kingfisher
import AidokuRunner

#if !os(tvOS)
private enum MangaSearchRecentStore {
    private static let key = "kanzenRecentSourceSearches"
    static let limit = 10

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    @discardableResult
    static func add(_ query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return load() }

        var searches = load().filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        searches.insert(trimmed, at: 0)
        searches = Array(searches.prefix(limit))
        UserDefaults.standard.set(searches, forKey: key)
        return searches
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private enum MangaSearchDictionaryReader {
    static func string(from dict: [String: Any], keys: [String]) -> String? {
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

    static func array(from dict: [String: Any], keys: [String]) -> [Any] {
        for key in keys {
            if let array = dict[key] as? [Any] {
                return array
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

private enum MangaSearchFilterSelection: String, Hashable {
    case single
    case multiple

    static func from(_ value: String?) -> MangaSearchFilterSelection {
        let normalized = (value ?? "")
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        if normalized.contains("single") || normalized.contains("radio") || normalized.contains("one") {
            return .single
        }
        return .multiple
    }
}

private enum MangaSearchFilterKind: Hashable {
    case legacy
    case aidokuSelect
    case aidokuMultiSelect
    case aidokuCheck
    case aidokuSort
    case unsupported(String)

    var isSupported: Bool {
        if case .unsupported = self { return false }
        return true
    }
}

private struct MangaSearchFilterOption: Identifiable, Hashable {
    let id: String
    let title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    init?(rawValue: Any) {
        if let string = rawValue as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            id = MangaSearchDictionaryReader.slug(trimmed).isEmpty ? trimmed : MangaSearchDictionaryReader.slug(trimmed)
            title = trimmed
            return
        }

        guard let dict = rawValue as? [String: Any],
              let title = MangaSearchDictionaryReader.string(from: dict, keys: ["title", "name", "label", "value"])
        else { return nil }

        self.title = title
        self.id = MangaSearchDictionaryReader.string(from: dict, keys: ["id", "key", "value", "slug", "tag"]) ?? title
    }
}

private struct MangaSearchFilterGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let selection: MangaSearchFilterSelection
    let options: [MangaSearchFilterOption]
    let kind: MangaSearchFilterKind

    init?(dict: [String: Any]) {
        guard let title = MangaSearchDictionaryReader.string(from: dict, keys: ["title", "name", "label"]) else {
            return nil
        }

        self.title = title
        self.id = MangaSearchDictionaryReader.string(from: dict, keys: ["id", "key", "slug"]) ?? MangaSearchDictionaryReader.slug(title)
        self.selection = MangaSearchFilterSelection.from(
            MangaSearchDictionaryReader.string(from: dict, keys: ["selection", "mode", "type"])
        )
        self.options = MangaSearchDictionaryReader
            .array(from: dict, keys: ["options", "items", "values", "tags"])
            .compactMap { MangaSearchFilterOption(rawValue: $0) }
        self.kind = .legacy
    }

    init(filter: AidokuRunner.Filter) {
        let title = filter.title?.isEmpty == false ? filter.title! : filter.id
        self.id = filter.id
        self.title = title

        switch filter.value {
        case .select(let filter):
            self.selection = .single
            self.options = Self.options(filter.options, ids: filter.ids)
            self.kind = .aidokuSelect
        case .multiselect(let filter):
            self.selection = .multiple
            self.options = Self.options(filter.options, ids: filter.ids)
            self.kind = .aidokuMultiSelect
        case .check(let name, _, _):
            self.selection = .single
            self.options = [MangaSearchFilterOption(id: "1", title: name ?? title)]
            self.kind = .aidokuCheck
        case .sort(_, let options, _):
            self.selection = .single
            self.options = options.enumerated().map { index, option in
                MangaSearchFilterOption(id: String(index), title: option)
            }
            self.kind = .aidokuSort
        case .text:
            self.selection = .single
            self.options = []
            self.kind = .unsupported("Use the search field above for text.")
        case .range:
            self.selection = .single
            self.options = []
            self.kind = .unsupported("Range filters are not supported yet.")
        case .note(let note):
            self.selection = .single
            self.options = []
            self.kind = .unsupported(note)
        }
    }

    private static func options(_ options: [String], ids: [String]?) -> [MangaSearchFilterOption] {
        options.enumerated().map { index, title in
            MangaSearchFilterOption(id: ids?[safe: index] ?? title, title: title)
        }
    }
}

private enum MangaModuleFilterLoadState: Equatable {
    case idle
    case loading
    case loaded
    case unsupported
    case failed(String)
}

private struct MangaModuleSearchSection: Identifiable, Equatable {
    let id: String
    let source: MangaHomeSource
    let items: [MangaHomeItem]
}

@MainActor
private final class MangaGlobalModuleSearchViewModel: ObservableObject {
    @Published var sources: [MangaHomeSource] = []
    @Published var sections: [MangaModuleSearchSection] = []
    @Published var failedSourceNames: [String] = []
    @Published var isSearching = false
    @Published var hasSearched = false

    private var searchToken = UUID()

    func refreshSources(from modules: [ModuleDataContainer], aidokuManager: AidokuSourceManager) {
        MangaHomeSourceManager.shared.refreshSources(from: modules)
        sources = MangaHomeSourceManager.shared.enabledSources(aidokuManager: aidokuManager, modules: modules)
    }

    func searchAll(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let activeSources = sources
        guard !activeSources.isEmpty else {
            sections = []
            failedSourceNames = []
            isSearching = false
            hasSearched = true
            return
        }

        let token = UUID()
        searchToken = token
        isSearching = true
        hasSearched = true
        sections = []
        failedSourceNames = []

        Task { @MainActor in
            var loadedSections: [MangaModuleSearchSection] = []
            var failures: [String] = []

            for source in activeSources {
                guard self.searchToken == token else { return }
                do {
                    let items = try await Self.searchSource(source, query: trimmed, page: 0)
                    if !items.isEmpty {
                        loadedSections.append(MangaModuleSearchSection(id: source.id, source: source, items: items))
                    }
                } catch {
                    failures.append(source.name)
                    ReaderLogger.shared.log("Search failed source=\(source.id): \(error.localizedDescription)", type: "AidokuSearch")
                }
            }

            guard self.searchToken == token else { return }
            self.sections = loadedSections
            self.failedSourceNames = failures.sorted()
            self.isSearching = false
        }
    }

    static func searchSource(_ source: MangaHomeSource, query: String, page: Int, filters: [AidokuRunner.FilterValue] = []) async throws -> [MangaHomeItem] {
        switch source.kind {
        case .aidoku:
            guard let sourceId = source.sourceId else { throw AidokuSourceError.sourceNotInstalled }
            let result = try await AidokuSourceManager.shared.search(sourceId: sourceId, query: query, page: page, filters: filters)
            return result.entries
                .prefix(MangaHomeViewModel.maxRetainedItemsPerSection)
                .map { MangaHomeItem(sourceId: sourceId, manga: $0) }

        case .legacyModule:
            guard let module = source.module else { return [] }
            return try await withCheckedThrowingContinuation { continuation in
                let engine = KanzenEngine()
                do {
                    let script = try ModuleManager.shared.getModuleScript(module: module)
                    try engine.loadScript(script, isNovel: module.moduleData.novel == true)
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                engine.searchInput(query, page: page) { rawItems in
                    let items = (rawItems ?? [])
                        .compactMap { MangaHomeItem(dict: $0, module: module, sectionKind: .custom) }
                        .prefix(MangaHomeViewModel.maxRetainedItemsPerSection)
                        .map { $0 }
                    continuation.resume(returning: items)
                }
            }
        }
    }
}

@MainActor
private final class MangaModuleAdvancedSearchViewModel: ObservableObject {
    let source: MangaHomeSource

    @Published var query: String
    @Published var filterGroups: [MangaSearchFilterGroup] = []
    @Published var selectedFilters: [String: Set<String>] = [:]
    @Published var filterLoadState: MangaModuleFilterLoadState = .idle
    @Published var items: [MangaHomeItem] = []
    @Published var isSearching = false
    @Published var hasSearched = false
    @Published var endOfPage = false
    @Published var warningMessage: String?
    @Published var errorMessage: String?

    private let engine = KanzenEngine()
    private var scriptLoaded = false
    private var page = 0
    private var searchToken = UUID()

    init(source: MangaHomeSource, initialQuery: String = "") {
        self.source = source
        self.query = initialQuery
    }

    var canSearch: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedFilters.isEmpty
    }

    func loadFiltersIfNeeded() {
        guard filterLoadState == .idle else { return }
        filterLoadState = .loading

        switch source.kind {
        case .aidoku:
            Task { @MainActor in
                do {
                    guard let sourceId = source.sourceId else { throw AidokuSourceError.sourceNotInstalled }
                    let filters = try await AidokuSourceManager.shared.filters(sourceId: sourceId)
                    filterGroups = filters.map(MangaSearchFilterGroup.init(filter:))
                    filterLoadState = filterGroups.isEmpty ? .unsupported : .loaded
                } catch {
                    filterLoadState = .failed(error.localizedDescription)
                }
            }

        case .legacyModule:
            do {
                try loadScriptIfNeeded()
            } catch {
                filterLoadState = .failed(error.localizedDescription)
                return
            }

            engine.searchFilters { rawFilters in
                DispatchQueue.main.async {
                    guard let rawFilters else {
                        self.filterLoadState = .unsupported
                        return
                    }

                    self.filterGroups = rawFilters
                        .compactMap { MangaSearchFilterGroup(dict: $0) }
                        .filter { !$0.options.isEmpty }

                    self.filterLoadState = self.filterGroups.isEmpty ? .unsupported : .loaded
                }
            }
        }
    }

    func toggle(group: MangaSearchFilterGroup, option: MangaSearchFilterOption) {
        guard group.kind.isSupported else { return }

        var updated = selectedFilters
        var values = updated[group.id] ?? []

        if group.selection == .single {
            values = values.contains(option.id) ? [] : [option.id]
        } else if values.contains(option.id) {
            values.remove(option.id)
        } else {
            values.insert(option.id)
        }

        if values.isEmpty {
            updated.removeValue(forKey: group.id)
        } else {
            updated[group.id] = values
        }

        selectedFilters = updated
    }

    func isSelected(group: MangaSearchFilterGroup, option: MangaSearchFilterOption) -> Bool {
        selectedFilters[group.id]?.contains(option.id) == true
    }

    func search(reset: Bool = true) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSearch else { return }
        guard !isSearching else { return }
        if endOfPage && !reset { return }

        if reset {
            page = 0
            items = []
            endOfPage = false
        }

        isSearching = true
        hasSearched = true
        warningMessage = nil
        errorMessage = nil

        let token = UUID()
        searchToken = token
        let loadPage = page

        switch source.kind {
        case .aidoku:
            Task { @MainActor in
                do {
                    guard let sourceId = source.sourceId else { throw AidokuSourceError.sourceNotInstalled }
                    let filters = aidokuSelectedFilters()
                    let result = try await AidokuSourceManager.shared.search(
                        sourceId: sourceId,
                        query: trimmed.isEmpty ? nil : trimmed,
                        page: loadPage,
                        filters: filters
                    )
                    let newItems = result.entries
                        .prefix(MangaHomeViewModel.maxRetainedItemsPerSection)
                        .map { MangaHomeItem(sourceId: sourceId, manga: $0) }
                    handleSearchResult(newItems, hasNextPage: result.hasNextPage, token: token, reset: reset)
                } catch {
                    guard searchToken == token else { return }
                    errorMessage = error.localizedDescription
                    isSearching = false
                }
            }

        case .legacyModule:
            do {
                try loadScriptIfNeeded()
            } catch {
                isSearching = false
                errorMessage = error.localizedDescription
                return
            }

            let filters = legacySelectedFiltersPayload()
            if filters.isEmpty {
                engine.searchInput(trimmed, page: loadPage) { rawItems in
                    let newItems = (rawItems ?? [])
                        .compactMap { item -> MangaHomeItem? in
                            guard let module = self.source.module else { return nil }
                            return MangaHomeItem(dict: item, module: module, sectionKind: .custom)
                        }
                    self.handleSearchResult(newItems, hasNextPage: !newItems.isEmpty, token: token, reset: reset)
                }
            } else {
                engine.searchAdvanced(trimmed, filters: filters, page: loadPage) { rawItems in
                    if let rawItems {
                        let newItems = rawItems
                            .compactMap { item -> MangaHomeItem? in
                                guard let module = self.source.module else { return nil }
                                return MangaHomeItem(dict: item, module: module, sectionKind: .custom)
                            }
                        self.handleSearchResult(newItems, hasNextPage: !newItems.isEmpty, token: token, reset: reset)
                    } else {
                        self.warningMessage = "This legacy source does not support filtered search. Showing title results."
                        self.engine.searchInput(trimmed, page: loadPage) { fallbackItems in
                            let newItems = (fallbackItems ?? [])
                                .compactMap { item -> MangaHomeItem? in
                                    guard let module = self.source.module else { return nil }
                                    return MangaHomeItem(dict: item, module: module, sectionKind: .custom)
                                }
                            self.handleSearchResult(newItems, hasNextPage: !newItems.isEmpty, token: token, reset: reset)
                        }
                    }
                }
            }
        }
    }

    private func loadScriptIfNeeded() throws {
        guard !scriptLoaded else { return }
        guard let module = source.module else { throw AidokuSourceError.sourceNotInstalled }

        let script = try ModuleManager.shared.getModuleScript(module: module)
        try engine.loadScript(script, isNovel: module.moduleData.novel == true)
        scriptLoaded = true
    }

    private func legacySelectedFiltersPayload() -> [String: Any] {
        var payload: [String: Any] = [:]

        for (key, values) in selectedFilters where !values.isEmpty {
            payload[key] = Array(values).sorted()
        }

        return payload
    }

    private func aidokuSelectedFilters() -> [AidokuRunner.FilterValue] {
        var values: [AidokuRunner.FilterValue] = []

        for group in filterGroups {
            let selected = Array(selectedFilters[group.id] ?? []).sorted()
            guard !selected.isEmpty else { continue }

            switch group.kind {
            case .aidokuSelect:
                if let value = selected.first {
                    values.append(.select(id: group.id, value: value))
                }
            case .aidokuMultiSelect:
                values.append(.multiselect(id: group.id, included: selected, excluded: []))
            case .aidokuCheck:
                values.append(.check(id: group.id, value: 1))
            case .aidokuSort:
                if let value = selected.first, let index = Int(value) {
                    values.append(.sort(AidokuRunner.SortFilterValue(id: group.id, index: index, ascending: true)))
                }
            case .legacy, .unsupported(_):
                continue
            }
        }

        return values
    }

    private func handleSearchResult(_ newItems: [MangaHomeItem], hasNextPage: Bool, token: UUID, reset: Bool) {
        DispatchQueue.main.async {
            guard self.searchToken == token else { return }

            let cappedItems = Array(newItems.prefix(MangaHomeViewModel.maxRetainedItemsPerSection))
            if cappedItems.isEmpty {
                self.endOfPage = true
            } else if reset {
                self.items = cappedItems
                self.page = 1
                self.endOfPage = !hasNextPage
            } else {
                let existing = Set(self.items.map(\.id))
                self.items.append(contentsOf: cappedItems.filter { !existing.contains($0.id) })
                self.page += 1
                self.endOfPage = !hasNextPage
            }

            self.isSearching = false
        }
    }
}

struct KanzenGlobalSearchView: View {
    @EnvironmentObject private var moduleManager: ModuleManager
    @StateObject private var viewModel = MangaGlobalModuleSearchViewModel()
    @StateObject private var sourceManager = MangaHomeSourceManager.shared
    @StateObject private var aidokuManager = AidokuSourceManager.shared
    @State private var searchText = ""
    @State private var recentSearches = MangaSearchRecentStore.load()
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    KanzenModuleSearchBar(
                        text: $searchText,
                        placeholder: "Search",
                        onSearch: performSearch
                    )
                    .padding(.top, 8)

                    sourceCards

                    searchStateContent
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: -geo.frame(in: .named("kanzenSearchScroll")).origin.y
                        )
                    }
                )
            }
            .coordinateSpace(name: "kanzenSearchScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
            .background(GlobalGradientBackground(scrollOffset: scrollOffset).ignoresSafeArea())
            .navigationTitle("Search Everything")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Search") {
                        performSearch()
                    }
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSearching)
                }
            }
        }
        .onAppear {
            syncSources()
        }
        .onChange(of: moduleManager.modules) { _ in
            syncSources()
        }
        .onReceive(sourceManager.objectWillChange) { _ in
            DispatchQueue.main.async { syncSources() }
        }
        .onReceive(aidokuManager.objectWillChange) { _ in
            DispatchQueue.main.async { syncSources() }
        }
    }

    @ViewBuilder
    private var sourceCards: some View {
        if viewModel.sources.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 34))
                    .foregroundColor(.secondary)
                Text("No searchable manga sources installed")
                    .font(.headline)
                    .foregroundColor(.secondary)
                NavigationLink(destination: AidokuSourcesSettingsView()) {
                    Label("Aidoku Sources", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(LunaTheme.shared.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 18)], alignment: .leading, spacing: 18) {
                ForEach(viewModel.sources) { source in
                    NavigationLink(destination: MangaModuleAdvancedSearchView(source: source)) {
                        MangaSearchSourceCard(source: source)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var searchStateContent: some View {
        if viewModel.isSearching {
            HStack(spacing: 10) {
                ProgressView()
                Text("Searching sources...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else if viewModel.hasSearched {
            if viewModel.sections.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    if !viewModel.failedSourceNames.isEmpty {
                        Text("Some sources did not respond: \(viewModel.failedSourceNames.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
            } else {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(viewModel.sections) { section in
                        MangaModuleSearchSectionView(section: section, query: searchText)
                    }

                    if !viewModel.failedSourceNames.isEmpty {
                        Text("Skipped unavailable sources: \(viewModel.failedSourceNames.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 2)
                    }
                }
            }
        } else {
            recentSearchesView
        }
    }

    @ViewBuilder
    private var recentSearchesView: some View {
        if !recentSearches.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text("RECENT SEARCHES")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("CLEAR") {
                        MangaSearchRecentStore.clear()
                        recentSearches = []
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                ForEach(recentSearches, id: \.self) { query in
                    Button {
                        searchText = query
                        performSearch()
                    } label: {
                        HStack {
                            Text(query)
                                .font(.title3)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)

                    if query != recentSearches.last {
                        Divider()
                    }
                }
            }
            .background(LunaTheme.shared.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        recentSearches = MangaSearchRecentStore.add(query)
        viewModel.searchAll(query)
    }

    private func syncSources() {
        viewModel.refreshSources(from: moduleManager.modules, aidokuManager: aidokuManager)
    }
}

struct MangaModuleAdvancedSearchView: View {
    @StateObject private var viewModel: MangaModuleAdvancedSearchViewModel
    @State private var scrollOffset: CGFloat = 0

    private let source: MangaHomeSource
    private let columns = [GridItem(.adaptive(minimum: 116), spacing: 12)]

    init(source: MangaHomeSource, initialQuery: String = "") {
        self.source = source
        _viewModel = StateObject(wrappedValue: MangaModuleAdvancedSearchViewModel(source: source, initialQuery: initialQuery))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                KanzenModuleSearchBar(
                    text: $viewModel.query,
                    placeholder: "Search",
                    onSearch: { viewModel.search(reset: true) }
                )
                .padding(.top, 8)

                filterContent

                if let warningMessage = viewModel.warningMessage {
                    Text(warningMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 2)
                }

                if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }

                if viewModel.items.isEmpty && viewModel.hasSearched && !viewModel.isSearching && viewModel.errorMessage == nil {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No results found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    resultGrid
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: -geo.frame(in: .named("kanzenAdvancedSearchScroll")).origin.y
                    )
                }
            )
        }
        .coordinateSpace(name: "kanzenAdvancedSearchScroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
        .background(GlobalGradientBackground(scrollOffset: scrollOffset).ignoresSafeArea())
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Search") {
                    viewModel.search(reset: true)
                }
                .disabled(!viewModel.canSearch || viewModel.isSearching)
            }
        }
        .task {
            viewModel.loadFiltersIfNeeded()
            if viewModel.canSearch && !viewModel.hasSearched {
                viewModel.search(reset: true)
            }
        }
    }

    @ViewBuilder
    private var filterContent: some View {
        switch viewModel.filterLoadState {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading filters...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)

        case .unsupported:
            VStack(alignment: .leading, spacing: 6) {
                Text("ADVANCED SEARCH")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("This source does not expose filters. Title search still works.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(LunaTheme.shared.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text("ADVANCED SEARCH")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button("Retry") {
                    viewModel.loadFiltersIfNeeded()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(LunaTheme.shared.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        case .loaded:
            LazyVStack(spacing: 18) {
                ForEach(viewModel.filterGroups) { group in
                    MangaSearchFilterGroupCard(group: group, viewModel: viewModel)
                }
            }
        }
    }

    @ViewBuilder
    private var resultGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(viewModel.items) { item in
                NavigationLink(destination: MangaSearchItemDestination(source: source, item: item)) {
                    MangaSearchPosterCard(item: item, width: 116)
                }
                .buttonStyle(.plain)
            }

            if viewModel.isSearching {
                ProgressView()
                    .frame(width: 116, height: 44)
                    .padding(.vertical, 16)
            } else if viewModel.hasSearched && !viewModel.endOfPage {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        viewModel.search(reset: false)
                    }
            }
        }
    }
}

private struct MangaSearchFilterGroupCard: View {
    let group: MangaSearchFilterGroup
    @ObservedObject var viewModel: MangaModuleAdvancedSearchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.title.uppercased())
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            Divider()

            if case .unsupported(let message) = group.kind {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(12)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(group.options) { option in
                        Button {
                            viewModel.toggle(group: group, option: option)
                        } label: {
                            Text(option.title)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(viewModel.isSelected(group: group, option: option) ? Color.accentColor.opacity(0.82) : Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .background(LunaTheme.shared.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MangaModuleSearchSectionView: View {
    let section: MangaModuleSearchSection
    let query: String

    private let posterWidth: CGFloat = isIPad ? 132 * iPadScaleSmall : 132

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(section.source.name)
                    .font(.largeTitle)
                    .fontWeight(.regular)
                    .lineLimit(1)

                Spacer()

                NavigationLink(destination: MangaModuleAdvancedSearchView(source: section.source, initialQuery: query)) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.34))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(section.items.prefix(MangaHomeViewModel.maxVisibleItemsPerSection))) { item in
                        NavigationLink(destination: MangaSearchItemDestination(source: section.source, item: item)) {
                            MangaSearchPosterCard(item: item, width: posterWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .modifier(KanzenScrollClipModifier())
        }
    }
}

private struct MangaSearchItemDestination: View {
    let source: MangaHomeSource
    let item: MangaHomeItem

    var body: some View {
        if let manga = item.aidokuManga, let sourceId = source.sourceId {
            AidokuMangaDetailView(sourceId: sourceId, initialManga: manga)
        } else if case .aidoku(let sourceId, let mangaKey) = item.route {
            AidokuMangaRouteLoaderView(sourceId: sourceId, mangaKey: mangaKey, title: item.title, coverURL: item.imageURL)
        } else if let module = source.module {
            MangaModuleContentLoaderView(
                module: module,
                title: item.title,
                imageURL: item.imageURL,
                contentParams: item.params,
                isNovel: module.moduleData.novel == true
            )
        } else {
            MangaModuleUnavailableView(title: item.title, message: "This source is no longer available.")
        }
    }
}

private struct MangaSearchPosterCard: View {
    let item: MangaHomeItem
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KFImage(URL(string: item.imageURL))
                .placeholder {
                    Rectangle().fill(Color.gray.opacity(0.22))
                }
                .resizable()
                .setProcessor(DownsamplingImageProcessor(size: CGSize(width: width, height: width * 1.45)))
                .scaledToFill()
                .frame(width: width, height: width * 1.45)
                .clipped()
                .cornerRadius(10)

            Text(item.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundColor(.primary)
                .frame(width: width, alignment: .leading)

            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
    }
}

private struct MangaSearchSourceCard: View {
    let source: MangaHomeSource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LunaTheme.shared.cardBackground)

                KFImage(URL(string: source.iconURL))
                    .placeholder {
                        Image(systemName: source.isAidoku ? "shippingbox" : "puzzlepiece.extension")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    }
                    .resizable()
                    .scaledToFit()
                    .padding(18)
            }
            .aspectRatio(1, contentMode: .fit)

            Text(source.name)
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundColor(.primary)
        }
    }
}

private struct KanzenModuleSearchBar: View {
    @Binding var text: String
    let placeholder: String
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text, onCommit: onSearch)
                .font(.title2)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
