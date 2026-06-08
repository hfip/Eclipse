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
                    MangaSearchSourceCard(source: source)
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
                        MangaModuleSearchSectionView(section: section)
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

private struct MangaModuleSearchSectionView: View {
    let section: MangaModuleSearchSection

    private let posterWidth: CGFloat = isIPad ? 132 * iPadScaleSmall : 132

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(section.source.name)
                    .font(.largeTitle)
                    .fontWeight(.regular)
                    .lineLimit(1)

                Spacer()
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
