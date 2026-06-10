//
//  KanzenHistoryView.swift
//  Kanzen
//
//  Created by Luna on 2026.
//

import SwiftUI
import Kingfisher

#if !os(tvOS)
struct KanzenHistoryView: View {
    @ObservedObject private var progressManager = MangaReadingProgressManager.shared
    @State private var scrollOffset: CGFloat = 0
    @State private var showClearHistoryConfirmation = false
    @State private var contextDetailItem: MangaLibraryItem?
    @State private var showContextDetail = false

    private var historyItems: [(id: Int, progress: MangaProgress)] {
        progressManager.recentlyReadMangaIds()
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    KanzenRootHeader("History") {
                        if !historyItems.isEmpty {
                            Button("Clear History") {
                                showClearHistoryConfirmation = true
                            }
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .accessibilityLabel("Clear History")
                        }
                    }
                        .padding(.horizontal, -16)

                    contextDetailLink

                    if historyItems.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 420)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(historyItems, id: \.id) { item in
                                NavigationLink(destination: mangaDestination(for: item)) {
                                    historyRow(for: item)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        contextDetailItem = libraryItem(for: item)
                                        showContextDetail = true
                                    } label: {
                                        Label("Open Details", systemImage: "info.circle")
                                    }

                                    Button(role: .destructive) {
                                        progressManager.removeFromHistory(mangaId: item.id)
                                    } label: {
                                        Label("Remove from History", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: -geo.frame(in: .named("kanzenHistoryScroll")).origin.y
                        )
                    }
                )
            }
            .coordinateSpace(name: "kanzenHistoryScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
            .background(GlobalGradientBackground(scrollOffset: scrollOffset).ignoresSafeArea())
            .alert("Clear History?", isPresented: $showClearHistoryConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear History", role: .destructive) {
                    progressManager.clearHistory()
                }
            } message: {
                Text("This removes entries from History without clearing read chapters or library items.")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var contextDetailLink: some View {
        NavigationLink(isActive: $showContextDetail) {
            if let contextDetailItem {
                MangaLibraryDestinationView(item: contextDetailItem)
            } else {
                EmptyView()
            }
        } label: {
            EmptyView()
        }
        .hidden()
        .frame(width: 0, height: 0)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No reading history")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Manga you read will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func historyRow(for item: (id: Int, progress: MangaProgress)) -> some View {
        HStack(spacing: 12) {
            KFImage(URL(string: item.progress.coverURL ?? ""))
                .placeholder { Rectangle().fill(Color.gray.opacity(0.2)) }
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 75)
                .clipped()
                .cornerRadius(12)
                .overlay(alignment: .topTrailing) {
                    if ReaderDownloadManager.shared.isDownloaded(route: item.progress.route) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Circle())
                            .padding(3)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.progress.title ?? "Unknown Manga")
                    .font(.headline)
                    .lineLimit(2)

                if let lastCh = item.progress.lastReadChapter {
                    Text("Ch. \(lastCh)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let date = item.progress.lastReadDate {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(LunaTheme.shared.cardBackground)
        .cornerRadius(12)
    }

    @ViewBuilder
    private func mangaDestination(for item: (id: Int, progress: MangaProgress)) -> some View {
        MangaLibraryDestinationView(item: libraryItem(for: item))
    }

    private func libraryItem(for item: (id: Int, progress: MangaProgress)) -> MangaLibraryItem {
        MangaLibraryItem(
            aniListId: item.id,
            title: item.progress.title ?? "Unknown Manga",
            coverURL: item.progress.coverURL,
            format: item.progress.format,
            totalChapters: item.progress.totalChapters,
            moduleUUID: item.progress.moduleUUID,
            contentParams: item.progress.contentParams,
            isNovel: item.progress.isNovel,
            route: item.progress.route,
            latestChapterNumbers: item.progress.latestChapterNumbers,
            lastSourceRefresh: item.progress.lastSourceRefresh,
            sourceRefreshError: item.progress.sourceRefreshError,
            trackerAniListId: item.progress.trackerAniListId,
            trackerMALId: item.progress.trackerMALId,
            trackerMatchConfidence: item.progress.trackerMatchConfidence,
            trackerResolvedAt: item.progress.trackerResolvedAt
        )
    }
}
#endif
