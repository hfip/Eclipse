//
//  LibraryView.swift
//  Kanzen
//
//  Created by Dawud Osman on 22/05/2025.
//
import SwiftUI
import CoreData
import Kingfisher

#if !os(tvOS)
struct KanzenLibraryView: View {
    @ObservedObject private var libraryManager = MangaLibraryManager.shared
    @EnvironmentObject var moduleManager: ModuleManager
    @State private var showCreateCollection = false
    @State private var scrollOffset: CGFloat = 0
    @State private var isRefreshingSources = false
    @State private var refreshStatus: String?

    private var bookmarksCollection: MangaLibraryCollection? {
        libraryManager.collections.first { $0.name == "Bookmarks" }
    }

    private var userCollections: [MangaLibraryCollection] {
        libraryManager.collections.filter { $0.name != "Bookmarks" }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    KanzenRootHeader("Library") {
                        Button {
                            refreshLibrarySources()
                        } label: {
                            if isRefreshingSources {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(isRefreshingSources)
                        .accessibilityLabel("Refresh Sources")
                    }
                    .padding(.horizontal, -16)

                    if let refreshStatus {
                        Text(refreshStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }

                    // MARK: - Bookmarks
                    if let bookmarks = bookmarksCollection, !bookmarks.items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bookmarks")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(bookmarks.items.sorted(by: { $0.dateAdded < $1.dateAdded })) { item in
                                        NavigationLink(destination: mangaDestination(for: item)) {
                                            bookmarkCard(item)
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                libraryManager.removeItem(from: bookmarks.id, item: item)
                                            } label: {
                                                Label("Remove", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    // MARK: - Collections
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Collections")
                                .font(.title2)
                                .fontWeight(.bold)
                            Spacer()
                            Button {
                                showCreateCollection = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                            }
                        }
                        .padding(.horizontal, 16)

                        if userCollections.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.title)
                                    .foregroundColor(.secondary)
                                Text("No collections yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 14) {
                                    ForEach(userCollections) { collection in
                                        NavigationLink(destination: MangaCollectionDetailView(collection: collection, libraryManager: libraryManager)) {
                                            collectionCard(collection)
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                libraryManager.deleteCollection(collection)
                                            } label: {
                                                Label("Delete Collection", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    if (bookmarksCollection?.items.isEmpty ?? true) && userCollections.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "books.vertical")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Your library is empty")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Bookmark manga from the Home or Search tabs to see them here.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(.vertical, 8)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: -geo.frame(in: .named("kanzenLibScroll")).origin.y
                        )
                    }
                )
            }
            .coordinateSpace(name: "kanzenLibScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
            .background(GlobalGradientBackground(scrollOffset: scrollOffset).ignoresSafeArea())
            .sheet(isPresented: $showCreateCollection) {
                MangaCreateCollectionView()
                    .environmentObject(libraryManager)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - Card Views

    @ViewBuilder
    private func bookmarkCard(_ item: MangaLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            KFImage(URL(string: item.coverURL ?? ""))
                .placeholder { Rectangle().fill(Color.gray.opacity(0.2)) }
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 180)
                .clipped()
                .cornerRadius(16)
                .overlay(alignment: .topLeading) {
                    unreadBadge(for: item)
                }
                .overlay(alignment: .topTrailing) {
                    downloadedBadge(for: item)
                }

            Text(item.title)
                .font(.caption)
                .lineLimit(2)
                .foregroundColor(.primary)
        }
        .frame(width: 120)
    }

    @ViewBuilder
    private func mangaGridCard(_ item: MangaLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            KFImage(URL(string: item.coverURL ?? ""))
                .placeholder { Rectangle().fill(Color.gray.opacity(0.2)) }
                .resizable()
                .scaledToFill()
                .frame(height: 180)
                .clipped()
                .cornerRadius(16)
                .overlay(alignment: .topLeading) {
                    unreadBadge(for: item)
                }

            Text(item.title)
                .font(.caption)
                .lineLimit(2)
                .foregroundColor(.primary)
        }
    }

    @ViewBuilder
    private func collectionCard(_ collection: MangaLibraryCollection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 2x2 preview grid
            let previews = Array(collection.items.prefix(4))
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LunaTheme.shared.cardBackground)
                    .frame(width: 140, height: 140)

                if previews.isEmpty {
                    Image(systemName: "folder")
                        .font(.title)
                        .foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.fixed(62)), GridItem(.fixed(62))], spacing: 4) {
                        ForEach(previews) { item in
                            KFImage(URL(string: item.coverURL ?? ""))
                                .placeholder { Rectangle().fill(Color.gray.opacity(0.2)) }
                                .resizable()
                                .scaledToFill()
                                .frame(width: 62, height: 62)
                                .clipped()
                                .cornerRadius(4)
                        }
                    }
                    .padding(4)
                }
            }
            .frame(width: 140, height: 140)

            Text(collection.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundColor(.primary)

            Text("\(collection.items.count) items")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 140)
    }

    @ViewBuilder
    private func unreadBadge(for item: MangaLibraryItem) -> some View {
        let unread = item.unreadCount(readChapters: MangaReadingProgressManager.shared.readChapters(for: item.aniListId))
        if unread > 0 {
            Text("\(unread)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.red)
                .clipShape(Capsule())
                .padding(4)
        }
    }

    @ViewBuilder
    private func downloadedBadge(for item: MangaLibraryItem) -> some View {
        if ReaderDownloadManager.shared.isDownloaded(route: item.route) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundColor(.white)
                .padding(5)
                .background(Color.black.opacity(0.65))
                .clipShape(Circle())
                .padding(4)
        }
    }

    private func refreshLibrarySources() {
        guard !isRefreshingSources else { return }
        isRefreshingSources = true
        refreshStatus = "Refreshing saved sources..."
        Task { @MainActor in
            let summary = await libraryManager.refreshAllSources()
            refreshStatus = summary.statusText
            isRefreshingSources = false
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func mangaDestination(for item: MangaLibraryItem) -> some View {
        MangaLibraryDestinationView(item: item)
    }
}

struct MangaLibraryDestinationView: View {
    let item: MangaLibraryItem
    @ObservedObject private var progressManager = MangaReadingProgressManager.shared

    var body: some View {
        if let route = contentRoute {
            routeDestination(route)
        } else if item.aniListId < 0 {
            MangaModuleUnavailableView(
                title: item.title,
                message: "This saved item is missing its source route. Open it again from its source to repair the bookmark."
            )
        } else {
            let manga = AniListManga(
                id: item.aniListId,
                title: AniListManga.AniListMangaTitle(romaji: item.title, english: nil, native: nil),
                chapters: item.totalChapters,
                volumes: nil,
                status: nil,
                coverImage: item.coverURL.map { AniListManga.AniListMangaCover(large: $0, medium: nil) },
                format: item.format,
                description: nil,
                genres: nil,
                averageScore: nil,
                countryOfOrigin: nil,
                startDate: nil
            )
            MangaDetailView(manga: manga)
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: MangaContentRoute) -> some View {
        switch route {
        case .legacyModule(let moduleUUIDString, let contentParams, let isNovel):
            if let moduleUUID = UUID(uuidString: moduleUUIDString),
               let module = ModuleManager.shared.getModule(moduleUUID) {
                MangaModuleContentLoaderView(
                    module: module,
                    title: item.title,
                    imageURL: item.coverURL ?? "",
                    contentParams: contentParams,
                    isNovel: isNovel
                )
            } else {
                if let downloaded = ReaderDownloadManager.shared.downloadedTitle(for: route) {
                    ReaderDownloadedTitleDetailView(title: downloaded)
                } else {
                    MangaModuleUnavailableView(
                        title: item.title,
                        message: "The legacy source module may have been removed."
                    )
                }
            }

        case .aidoku(let sourceId, let mangaKey):
            if (AidokuSourceManager.shared.metadata(id: sourceId) == nil || AidokuSourceManager.shared.metadata(id: sourceId)?.isEnabled == false),
               let downloaded = ReaderDownloadManager.shared.downloadedTitle(for: route) {
                ReaderDownloadedTitleDetailView(title: downloaded)
            } else {
                AidokuMangaRouteLoaderView(
                    sourceId: sourceId,
                    mangaKey: mangaKey,
                    title: item.title,
                    coverURL: item.coverURL
                )
            }
        }
    }

    private var contentRoute: MangaContentRoute? {
        if let route = item.route {
            return route
        }

        if let progress = progressManager.progress(for: item.aniListId),
           let route = progress.route {
            return route
        }

        if let moduleUUIDString = item.moduleUUID,
           let contentParams = item.contentParams {
            return .legacyModule(moduleUUID: moduleUUIDString, contentParams: contentParams, isNovel: item.isNovel ?? false)
        }

        if let progress = progressManager.progress(for: item.aniListId),
           let moduleUUIDString = progress.moduleUUID,
           let contentParams = progress.contentParams {
            return .legacyModule(moduleUUID: moduleUUIDString, contentParams: contentParams, isNovel: progress.isNovel ?? false)
        }

        return nil
    }
}
#endif
