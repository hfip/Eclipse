//
//  contentView.swift
//  Kanzen
//
//  Created by Dawud Osman on 27/05/2025.
//

import SwiftUI
import Foundation
import Kingfisher

#if !os(tvOS)
struct contentView: View {
    @State var parentModule: ModuleDataContainer?
    @State  var title: String
    @State  var imageURL: String
    @State  var params: String
    @State var expandedDescription : Bool = false
    @State private var contentData: [String:Any]?
    @State private var contentChapters: [Chapters]?
    @EnvironmentObject var kanzen: KanzenEngine
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var favouriteManager : FavouriteManager
    @ObservedObject private var libraryManager = MangaLibraryManager.shared
    @ObservedObject private var progressManager = MangaReadingProgressManager.shared
    @ObservedObject private var downloadManager = ReaderDownloadManager.shared
    @State private var showAddToCollection: Bool = false
    @State private var width: CGFloat = 150
    @State private var langaugeIdx: Int = 0
    @State private var showChaptersMenu: Bool = false
    @State private var selectedChapterData: Chapter? = nil
    @State private var selectedChapterIdx: Int?
    @State var reverseChapterlist: Bool = false
    @State var toggleFavourite: Bool = false
    @State var loadingState : Bool = true
    @State private var scrollOffset: CGFloat = 0
    @AppStorage(ReaderDetailElement.orderStorageKey) private var readerDetailElementOrder = ReaderDetailElement.defaultOrderRawValue
    @AppStorage(ReaderDetailElement.hiddenStorageKey) private var readerDetailHiddenElements = ""

    private var heroHeight: CGFloat {
        min(max(UIScreen.main.bounds.height * 0.48, 360), isIPad ? 560 : 500)
    }

    /// Stable numeric ID derived from module + content params for progress & library.
    private var stableId: Int {
        guard let module = parentModule else { return 0 }
        let combined = "\(module.id.uuidString):\(params)"
        let hash = combined.utf8.reduce(into: 5381) { h, c in h = ((h &<< 5) &+ h) &+ Int(c) }
        return hash < 0 ? hash : -hash - 1
    }

    private var libraryItem: MangaLibraryItem {
        MangaLibraryItem.fromModule(
            moduleId: parentModule?.id ?? UUID(),
            contentId: params,
            title: title,
            coverURL: imageURL,
            isNovel: parentModule?.moduleData.novel == true,
            sourceName: parentModule?.moduleData.sourceName,
            latestChapterNumbers: currentChapterNumbers
        )
    }

    private var currentChapterNumbers: [String]? {
        chapterNumbers(from: contentChapters)
    }

    private func chapterNumbers(from groups: [Chapters]?) -> [String]? {
        let numbers = groups?
            .max(by: { $0.chapters.count < $1.chapters.count })?
            .chapters
            .map(\.chapterNumber)
        return numbers.map(ChapterIdentityNormalizer.deduplicatedNumbers)
    }

    private var contentRoute: MangaContentRoute? {
        guard let parentModule else { return nil }
        return .legacyModule(
            moduleUUID: parentModule.id.uuidString,
            contentParams: params,
            isNovel: parentModule.moduleData.novel == true
        )
    }

    private var visibleReaderDetailElements: [ReaderDetailElement] {
        ReaderDetailElement.orderedElements(from: readerDetailElementOrder)
            .filter { ReaderDetailElement.isVisible($0, hiddenRawValue: readerDetailHiddenElements) }
            .filter(readerDetailElementHasContent)
    }
    
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                primaryActionSection
                    .padding(.horizontal, 16)

                ForEach(visibleReaderDetailElements) { element in
                    readerDetailElementView(element)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: -geo.frame(in: .named("moduleContentScroll")).origin.y
                    )
                }
            )
        }
        .coordinateSpace(name: "moduleContentScroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
        .onAppear {
            getContentData()
            toggleFavourite = checkIfFavorited()
        }
        .fullScreenCover(item: $selectedChapterData) { chapter in
            if let contentChapters = self.contentChapters{
                let chapterList = contentChapters[langaugeIdx].chapters
                let readerChapterList = readerChapters(from: chapterList)
                let selectedReaderChapter = readerChapterList.first {
                    $0.chapterNumber == chapter.chapterNumber
                } ?? readerChapterList.first ?? chapter
                readerManagerView(
                    chapters: readerChapterList,
                    selectedChapter: selectedReaderChapter,
                    kanzen: kanzen,
                    mangaId: stableId,
                    mangaTitle: title,
                    mangaCoverURL: imageURL,
                    mangaRoute: contentRoute,
                    mangaFormat: parentModule?.moduleData.novel == true ? "NOVEL" : "MANGA",
                    totalChapters: currentChapterNumbers?.count,
                    latestChapterNumbers: currentChapterNumbers
                )
            }
            
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .kanzenGradientBackground(scrollOffset: scrollOffset)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddToCollection = true
                } label: {
                    Image(systemName: libraryManager.isBookmarked(libraryItem) ? "bookmark.fill" : "bookmark")
                }
            }
        }
        .sheet(isPresented: $showAddToCollection) {
            MangaAddToCollectionView(item: libraryItem)
                .environmentObject(libraryManager)
        }
    }
    
    func checkIfFavorited() -> Bool {
        if let module = parentModule {
            return FavouriteManager.shared.isFavourite(moduleId: module.id, contentId: params)
        }
        return false
    }
    
    func getContentData() {
        kanzen.extractDetails(params: self.params) { result in
            DispatchQueue.main.async { self.contentData = result }
        }
        kanzen.extractChapters(params: self.params) { result in
            DispatchQueue.main.async {
                if let result = result {
                    var temp: [Chapters] = []

                    if let dictResult = result as? [String: Any] {
                        for (key, value) in dictResult {
                            var tempChapters: [Chapter] = []
                            if let chapters = value as? [Any?] {
                                for (idx, chapter) in chapters.enumerated() {
                                    if let chapter = chapter as? [Any?], let chapterName = chapter[0] as? String, let rawData = chapter[1] as? [[String: Any?]], let chapterData = rawData.compactMap({ChapterData(dict: $0 as [String : Any])}) as? [ChapterData] {
                                        tempChapters.append(Chapter(chapterNumber: chapterName, idx: idx, chapterData: chapterData))
                                    }
                                }
                            }
                            if !tempChapters.isEmpty {
                                temp.append(Chapters(language: key, chapters: tempChapters))
                            }
                        }
                    } else if let arrResult = result as? [[String: Any]] {
                        var tempChapters: [Chapter] = []
                        for (idx, chapterDict) in arrResult.enumerated() {
                            let name = (chapterDict["number"] as? Int).map { "Chapter \($0)" }
                                ?? (chapterDict["title"] as? String)
                                ?? "Chapter \(idx + 1)"
                            if let data = ChapterData(dict: chapterDict) {
                                tempChapters.append(Chapter(chapterNumber: name, idx: idx, chapterData: [data]))
                            }
                        }
                        if !tempChapters.isEmpty {
                            temp.append(Chapters(language: "default", chapters: tempChapters))
                        }
                    }

                    temp = temp.map {
                        Chapters(
                            language: $0.language,
                            chapters: ChapterIdentityNormalizer.deduplicatedChapters($0.chapters, reindex: true)
                        )
                    }

                    self.contentChapters = temp
                    if !temp.isEmpty {
                        let latestNumbers = chapterNumbers(from: temp) ?? []
                        libraryManager.updateSavedItem(libraryItem)
                        progressManager.updateSourceMetadata(
                            mangaId: stableId,
                            title: title,
                            coverURL: imageURL,
                            format: parentModule?.moduleData.novel == true ? "NOVEL" : "MANGA",
                            latestChapterNumbers: latestNumbers,
                            route: contentRoute,
                            sourceRefreshError: nil
                        )
                    }
                }
                self.loadingState = false
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        ZStack(alignment: .bottomLeading) {
            KFImage(URL(string: imageURL))
                .placeholder { Color.black.opacity(0.18) }
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: heroHeight)
                .clipped()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.45),
                    Color.black.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: isIPad ? 52 : 42, weight: .bold))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)

                HStack(spacing: 10) {
                    if let status = contentData?["status"] as? String {
                        Text(status)
                    }

                    if let authorArtist = contentData?["authorArtist"] as? [String], !authorArtist.isEmpty {
                        Image(systemName: "person.fill")
                        Text(authorArtist.joined(separator: ", "))
                            .lineLimit(1)
                    }

                    Text(parentModule?.moduleData.novel == true ? "Light Novel" : "Manga")
                }
                .font(.title3)
                .foregroundColor(.white.opacity(0.82))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 22)
        }
    }

    @ViewBuilder
    private var primaryActionSection: some View {
        let chapters = selectedChapterGroupForReading()
        HStack(spacing: 12) {
            readButton(chapters: chapters)

            Button {
                showAddToCollection = true
            } label: {
                Image(systemName: libraryManager.isBookmarked(libraryItem) ? "bookmark.fill" : "bookmark")
            }
            .readerDetailIconButton()

            Menu {
                if let parentModule {
                    Button { } label: {
                        Label(parentModule.moduleData.sourceName, systemImage: "puzzlepiece.extension")
                    }
                    .disabled(true)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .readerDetailIconButton()
        }
    }

    private func selectedChapterGroupForReading() -> [Chapter] {
        guard let contentChapters, !contentChapters.isEmpty else { return [] }
        let index = min(max(langaugeIdx, 0), contentChapters.count - 1)
        return contentChapters[index].chapters
    }

    // MARK: - Description

    @ViewBuilder
    private func descriptionSection(_ text: String) -> some View {
        let cleaned = text
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        VStack(alignment: .leading, spacing: 4) {
            Text(cleaned)
                .font(.system(size: isIPad ? 30 : 27, weight: .regular))
                .lineSpacing(4)
                .foregroundColor(.primary.opacity(0.92))
                .lineLimit(expandedDescription ? nil : 5)
                .onTapGesture {
                    withAnimation { expandedDescription.toggle() }
                }

            if !expandedDescription {
                HStack {
                    Spacer()
                    Text("More")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .onTapGesture {
                            withAnimation { expandedDescription.toggle() }
                        }
                }
            }
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private func tagsSection(_ tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.callout)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .overlay(
                            Capsule()
                                .stroke(Color.primary.opacity(0.75), lineWidth: 1)
                        )
                }
            }
        }
    }

    private func readerDetailElementHasContent(_ element: ReaderDetailElement) -> Bool {
        switch element {
        case .overview:
            return !(contentData?["description"] as? String ?? "").isEmpty
        case .tags:
            return !(contentData?["tags"] as? [String] ?? []).isEmpty
        case .ratingNotes, .chapters:
            return true
        }
    }

    @ViewBuilder
    private func readerDetailElementView(_ element: ReaderDetailElement) -> some View {
        switch element {
        case .overview:
            if let description = contentData?["description"] as? String, !description.isEmpty {
                descriptionSection(description)
            }
        case .tags:
            if let tags = contentData?["tags"] as? [String], !tags.isEmpty {
                tagsSection(tags)
            }
        case .ratingNotes:
            let progress = progressManager.progress(for: stableId)
            ReaderRatingNotesView(
                itemId: stableId,
                title: title,
                routeKey: contentRoute?.stableKey,
                knownAniListId: progress?.trackerAniListId,
                knownMALId: progress?.trackerMALId,
                totalChapters: currentChapterNumbers?.count,
                format: parentModule?.moduleData.novel == true ? "NOVEL" : "MANGA"
            )
        case .chapters:
            chaptersElementView()
        }
    }

    @ViewBuilder
    private func chaptersElementView() -> some View {
        if loadingState {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading chapters...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else {
            chaptersView()
        }
    }

    // MARK: - Chapters

    @ViewBuilder
    func chaptersView() -> some View {
        if let chaptersData = self.contentChapters, !chaptersData.isEmpty {
            let selected = chaptersData[langaugeIdx]
            let displayed: [Chapter] = reverseChapterlist ? Array(selected.chapters.reversed()) : selected.chapters

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(selected.chapters.count) Chapters")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                    Spacer()

                    if chaptersData.count > 1 {
                        Menu {
                            ForEach(Array(chaptersData.enumerated()), id: \.offset) { idx, lang in
                                Button(lang.language) { langaugeIdx = idx }
                            }
                        } label: {
                            Image(systemName: "globe")
                                .foregroundColor(.accentColor)
                        }
                    }

                    if let contentRoute {
                        Button {
                            downloadManager.enqueueChapters(
                                route: contentRoute,
                                mangaId: stableId,
                                title: title,
                                coverURL: imageURL,
                                sourceName: parentModule?.moduleData.sourceName,
                                format: parentModule?.moduleData.novel == true ? "NOVEL" : "MANGA",
                                chapters: selected.chapters,
                                kanzen: kanzen
                            )
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .foregroundColor(.accentColor)
                        }
                        .accessibilityLabel("Download All")
                    }

                    Button {
                        reverseChapterlist.toggle()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.accentColor)
                    }
                }

                Divider().padding(.vertical, 4)

                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayed.enumerated()), id: \.element.id) { displayIndex, chapter in
                        let isRead = progressManager.isChapterRead(mangaId: stableId, chapterNumber: chapter.chapterNumber)
                        let chapterTitle = chapter.chapterData?.first?.title ?? ""
                        let downloadStatus = downloadManager.status(for: contentRoute, chapterNumber: chapter.chapterNumber)
                        let downloadProgress = downloadManager.progress(for: contentRoute, chapterNumber: chapter.chapterNumber)

                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 3) {
                            if !chapterTitle.isEmpty {
                                Text(chapter.chapterNumber)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(isRead ? .secondary : .primary)
                                    .lineLimit(1)
                                Text(chapterTitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text(chapter.chapterNumber)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(isRead ? .secondary : .primary)
                                    .lineLimit(1)
                            }

                            if let data = chapter.chapterData, let first = data.first, !first.scanlationGroup.isEmpty {
                                Text(first.scanlationGroup)
                                    .font(.caption2)
                                    .foregroundColor(.accentColor.opacity(0.8))
                                    .lineLimit(1)
                            }

                            if !isRead, let progressLabel = progressManager.pageProgressLabel(mangaId: stableId, chapterNumber: chapter.chapterNumber) {
                                Text(progressLabel)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            if downloadStatus == .downloading || downloadStatus == .queued || downloadStatus == .paused {
                                ProgressView(value: downloadProgress)
                                    .tint(downloadStatus == .paused ? .gray : .accentColor)
                                    .frame(maxWidth: 180)
                            }
                        }

                        Spacer(minLength: 8)

                        downloadBadge(for: downloadStatus)

                        if isRead {
                            Text("Read")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .opacity(isRead ? 0.6 : 1.0)
                    .onTapGesture {
                        selectedChapterData = chapter
                    }
                    .contextMenu {
                        if isRead {
                            Button {
                                progressManager.markChapterUnread(mangaId: stableId, chapterNumber: chapter.chapterNumber)
                            } label: {
                                Label("Mark as Unread", systemImage: "eye.slash")
                            }
                        } else {
                            Button {
                                progressManager.markChapterRead(
                                    mangaId: stableId,
                                    chapterNumber: chapter.chapterNumber,
                                    mangaTitle: title,
                                    coverURL: imageURL,
                                    format: parentModule?.moduleData.novel == true ? "NOVEL" : "MANGA",
                                    totalChapters: currentChapterNumbers?.count,
                                    latestChapterNumbers: currentChapterNumbers,
                                    moduleUUID: parentModule?.id.uuidString,
                                    contentParams: params,
                                    isNovel: parentModule?.moduleData.novel == true,
                                    route: contentRoute
                                )
                            } label: {
                                Label("Mark as Read", systemImage: "eye")
                            }
                        }

                        Divider()

                        Button {
                            markVisibleChaptersRead(Array(displayed.prefix(displayIndex + 1)))
                        } label: {
                            Label("Mark Above as Read", systemImage: "arrow.up.circle")
                        }

                        Button {
                            markVisibleChaptersRead(Array(displayed.suffix(displayed.count - displayIndex)))
                        } label: {
                            Label("Mark Below as Read", systemImage: "arrow.down.circle")
                        }

                        Button {
                            let allNums = selected.chapters.map { $0.chapterNumber }
                            progressManager.markAllRead(
                                mangaId: stableId,
                                chapterNumbers: allNums,
                                mangaTitle: title,
                                coverURL: imageURL,
                                format: parentModule?.moduleData.novel == true ? "NOVEL" : "MANGA",
                                totalChapters: currentChapterNumbers?.count,
                                latestChapterNumbers: currentChapterNumbers,
                                moduleUUID: parentModule?.id.uuidString,
                                contentParams: params,
                                isNovel: parentModule?.moduleData.novel == true,
                                route: contentRoute
                            )
                        } label: {
                            Label("Mark All as Read", systemImage: "checkmark.circle.fill")
                        }

                        Button(role: .destructive) {
                            progressManager.markAllUnread(mangaId: stableId)
                        } label: {
                            Label("Mark All as Unread", systemImage: "xmark.circle")
                        }

                        Divider()

                        downloadContextMenu(for: chapter, status: downloadStatus)
                    }
                        Divider()
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("No chapters found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func downloadBadge(for status: ReaderDownloadStatus) -> some View {
        switch status {
        case .completed:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        case .downloading, .queued, .paused:
            Image(systemName: status == .paused ? "pause.circle" : "arrow.down.circle")
                .foregroundColor(.secondary)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func downloadContextMenu(for chapter: Chapter, status: ReaderDownloadStatus) -> some View {
        if let route = contentRoute {
            switch status {
            case .completed:
                Button(role: .destructive) {
                    downloadManager.removeDownload(id: ReaderDownloadManager.downloadId(route: route, chapterNumber: chapter.chapterNumber))
                } label: {
                    Label("Remove Download", systemImage: "trash")
                }
            case .queued, .downloading, .paused:
                Button(role: .destructive) {
                    downloadManager.cancelDownload(id: ReaderDownloadManager.downloadId(route: route, chapterNumber: chapter.chapterNumber))
                } label: {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }
            case .failed, .none:
                Button {
                    downloadManager.enqueueChapter(
                        route: route,
                        mangaId: stableId,
                        title: title,
                        coverURL: imageURL,
                        sourceName: parentModule?.moduleData.sourceName,
                        format: parentModule?.moduleData.novel == true ? "NOVEL" : "MANGA",
                        chapter: chapter,
                        kanzen: kanzen
                    )
                } label: {
                    Label(status == .failed ? "Retry Download" : "Download", systemImage: "arrow.down.circle")
                }
            }
        } else {
            Button { } label: {
                Label("Download unavailable", systemImage: "exclamationmark.triangle")
            }
            .disabled(true)
        }
    }

    private func markVisibleChaptersRead(_ chapters: [Chapter]) {
        progressManager.markAllRead(
            mangaId: stableId,
            chapterNumbers: chapters.map(\.chapterNumber),
            mangaTitle: title,
            coverURL: imageURL,
            format: parentModule?.moduleData.novel == true ? "NOVEL" : "MANGA",
            totalChapters: currentChapterNumbers?.count,
            latestChapterNumbers: currentChapterNumbers,
            moduleUUID: parentModule?.id.uuidString,
            contentParams: params,
            isNovel: parentModule?.moduleData.novel == true,
            route: contentRoute
        )
    }

    // MARK: - Read / Continue Button

    @ViewBuilder
    private func readButton(chapters: [Chapter]) -> some View {
        let lastRead = progressManager.lastReadChapter(for: stableId)
        let readChapters = progressManager.readChapters(for: stableId)
        let readKeys = Set(readChapters.map { ChapterIdentityNormalizer.key(for: $0) })
        let hasProgress = lastRead != nil || !readChapters.isEmpty

        let targetChapter: Chapter? = {
            if let lastRead = lastRead {
                let lastReadKey = ChapterIdentityNormalizer.key(for: lastRead)
                if !readKeys.contains(lastReadKey),
                   let ch = chapters.first(where: {
                    $0.chapterNumber == lastRead ||
                    ChapterIdentityNormalizer.key(for: $0.chapterNumber) == lastReadKey
                }) {
                    return ch
                }
            }
            if let unread = chronologicalChapters(chapters).first(where: {
                !readKeys.contains(ChapterIdentityNormalizer.key(for: $0.chapterNumber))
            }) {
                return unread
            }
            return chronologicalChapters(chapters).first
        }()

        if let target = targetChapter {
            Button {
                selectedChapterData = target
            } label: {
                HStack {
                    Image(systemName: hasProgress ? "book.fill" : "play.fill")
                        .font(.subheadline)
                    Text(hasProgress ? "Continue Reading" : "Start Reading")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundColor(.white)
                .background(Color.accentColor)
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
        }
    }

    private func chronologicalChapters(_ chapters: [Chapter]) -> [Chapter] {
        chapters.sorted { lhs, rhs in
            let lhsNumber = numericChapterValue(lhs.chapterNumber)
            let rhsNumber = numericChapterValue(rhs.chapterNumber)
            switch (lhsNumber, rhsNumber) {
            case let (lhsValue?, rhsValue?):
                if lhsValue != rhsValue { return lhsValue < rhsValue }
                return lhs.idx < rhs.idx
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.idx > rhs.idx
            }
        }
    }

    private func numericChapterValue(_ text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard let match = matches.last,
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[valueRange])
    }

    private func readerChapters(from chapters: [Chapter]) -> [Chapter] {
        ChapterIdentityNormalizer.deduplicatedChapters(chronologicalChapters(chapters), reindex: false).enumerated().map { index, chapter in
            Chapter(
                chapterNumber: chapter.chapterNumber,
                idx: index,
                chapterData: chapter.chapterData
            )
        }
    }
}

struct MangaModuleContentLoaderView: View {
    let module: ModuleDataContainer
    let title: String
    let imageURL: String
    let contentParams: String
    let isNovel: Bool

    @StateObject private var kanzen = KanzenEngine()
    @State private var moduleLoaded = false
    @State private var loadError: String?

    var body: some View {
        Group {
            if moduleLoaded {
                contentView(
                    parentModule: module,
                    title: title,
                    imageURL: imageURL,
                    params: contentParams
                )
                .environmentObject(kanzen)
            } else if let loadError {
                MangaModuleUnavailableView(
                    title: title,
                    message: loadError
                )
            } else {
                ProgressView("Loading source...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task(id: "\(module.id.uuidString):\(contentParams)") {
                        loadModule()
                    }
            }
        }
    }

    private func loadModule() {
        do {
            let content = try ModuleManager.shared.getModuleScript(module: module)
            try kanzen.loadScript(content, isNovel: isNovel)
            moduleLoaded = true
        } catch {
            ReaderLogger.shared.log("Error loading module content: \(error.localizedDescription)", type: "Error")
            loadError = error.localizedDescription
        }
    }
}

struct MangaModuleUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 42))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
