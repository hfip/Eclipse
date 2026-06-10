//
//  AidokuMangaDetailView.swift
//  Kanzen
//

#if !os(tvOS)
import SwiftUI
import Kingfisher
import AidokuRunner

struct AidokuMangaRouteLoaderView: View {
    let sourceId: String
    let mangaKey: String
    let title: String
    let coverURL: String?

    @State private var manga: AidokuRunner.Manga?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @StateObject private var sourceManager = AidokuSourceManager.shared

    var body: some View {
        Group {
            if let manga {
                AidokuMangaDetailView(sourceId: sourceId, initialManga: manga)
            } else if let metadata = sourceManager.metadata(id: sourceId), !metadata.isEnabled {
                MangaSourceRepairView(
                    title: title,
                    message: "\(metadata.name) is disabled.",
                    actionTitle: "Enable Source"
                ) {
                    sourceManager.toggle(metadata)
                    Task { await load() }
                }
            } else if let errorMessage {
                MangaSourceRepairView(
                    title: title,
                    message: errorMessage,
                    actionTitle: "Aidoku Sources"
                )
            } else if isLoading {
                ProgressView("Loading source...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        await load()
                    }
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil

        guard sourceManager.metadata(id: sourceId) != nil else {
            errorMessage = "The Aidoku source for this manga is missing. Reinstall the source to repair this item."
            isLoading = false
            return
        }

        do {
            let seed = AidokuRunner.Manga(
                sourceKey: sourceId,
                key: mangaKey,
                title: title,
                cover: coverURL
            )
            manga = try await sourceManager.mangaUpdate(
                sourceId: sourceId,
                manga: seed,
                needsDetails: true,
                needsChapters: true
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct AidokuMangaDetailView: View {
    let sourceId: String
    let initialManga: AidokuRunner.Manga

    @ObservedObject private var libraryManager = MangaLibraryManager.shared
    @ObservedObject private var progressManager = MangaReadingProgressManager.shared
    @ObservedObject private var downloadManager = ReaderDownloadManager.shared
    @StateObject private var sourceManager = AidokuSourceManager.shared
    @StateObject private var kanzen = KanzenEngine()
    @State private var manga: AidokuRunner.Manga
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedChapterData: Chapter?
    @State private var showAddToCollection = false
    @State private var reverseChapterList = false
    @State private var scrollOffset: CGFloat = 0
    @AppStorage(ReaderDetailElement.orderStorageKey) private var readerDetailElementOrder = ReaderDetailElement.defaultOrderRawValue
    @AppStorage(ReaderDetailElement.hiddenStorageKey) private var readerDetailHiddenElements = ""

    private var route: MangaContentRoute {
        .aidoku(sourceId: sourceId, mangaKey: manga.key)
    }

    private var stableId: Int {
        route.stableNegativeId
    }

    private var coverURL: String {
        manga.cover ?? initialManga.cover ?? ""
    }

    private var libraryItem: MangaLibraryItem {
        MangaLibraryItem.fromAidoku(
            sourceId: sourceId,
            mangaKey: manga.key,
            title: manga.title,
            coverURL: coverURL,
            sourceName: sourceManager.metadata(id: sourceId)?.name,
            latestChapterNumbers: latestChapterNumbers,
            format: viewerFormat(manga.viewer)
        )
    }

    private var latestChapterNumbers: [String]? {
        chapterNumbers(from: manga)
    }

    private var visibleReaderDetailElements: [ReaderDetailElement] {
        ReaderDetailElement.orderedElements(from: readerDetailElementOrder)
            .filter { ReaderDetailElement.isVisible($0, hiddenRawValue: readerDetailHiddenElements) }
            .filter(readerDetailElementHasContent)
    }

    init(sourceId: String, initialManga: AidokuRunner.Manga) {
        self.sourceId = sourceId
        self.initialManga = initialManga
        _manga = State(initialValue: initialManga)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                ForEach(visibleReaderDetailElements) { element in
                    Divider()
                    readerDetailElementView(element)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: -geo.frame(in: .named("aidokuContentScroll")).origin.y
                    )
                }
            )
        }
        .coordinateSpace(name: "aidokuContentScroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
        .task {
            await loadDetails(force: false)
        }
        .fullScreenCover(item: $selectedChapterData, onDismiss: {
            if let chapter = selectedChapterData {
                progressManager.markChapterRead(
                    mangaId: stableId,
                    chapterNumber: chapter.chapterNumber,
                    mangaTitle: manga.title,
                    coverURL: coverURL,
                    format: viewerFormat(manga.viewer),
                    totalChapters: latestChapterNumbers?.count,
                    latestChapterNumbers: latestChapterNumbers,
                    route: route
                )
            }
        }) { chapter in
            let chapters = readerChapters(from: chapterModels())
            let selected = chapters.first { $0.chapterNumber == chapter.chapterNumber } ?? chapters.first ?? chapter
            readerManagerView(
                chapters: chapters,
                selectedChapter: selected,
                kanzen: kanzen,
                mangaId: stableId,
                mangaTitle: manga.title,
                mangaCoverURL: coverURL,
                mangaRoute: route
            )
        }
        .navigationTitle(manga.title)
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

    @MainActor
    private func loadDetails(force: Bool) async {
        guard force || manga.description == nil || manga.chapters == nil else { return }
        guard sourceManager.metadata(id: sourceId) != nil else {
            errorMessage = "This Aidoku source is missing. Reinstall it from Aidoku Sources to repair the route."
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let updated = try await sourceManager.mangaUpdate(
                sourceId: sourceId,
                manga: manga,
                needsDetails: true,
                needsChapters: true
            )
            let latestNumbers = chapterNumbers(from: updated) ?? []
            manga = updated
            libraryManager.updateSavedItem(libraryItem)
            progressManager.updateSourceMetadata(
                mangaId: stableId,
                title: updated.title,
                coverURL: updated.cover ?? initialManga.cover,
                format: viewerFormat(updated.viewer),
                latestChapterNumbers: latestNumbers,
                route: route,
                sourceRefreshError: nil
            )
        } catch {
            errorMessage = error.localizedDescription
            ReaderLogger.shared.log("Aidoku detail failed source=\(sourceId) manga=\(manga.key): \(error.localizedDescription)", type: "AidokuDetails")
        }
        isLoading = false
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 14) {
            KFImage(URL(string: coverURL))
                .placeholder { Rectangle().fill(Color.gray.opacity(0.22)) }
                .resizable()
                .scaledToFill()
                .frame(width: 150, height: 225)
                .clipped()
                .cornerRadius(16)

            VStack(alignment: .leading, spacing: 7) {
                Text(manga.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(3)

                Text(viewerTitle(manga.viewer))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)

                if manga.status != .unknown {
                    Label(statusTitle(manga.status), systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                let creators = (manga.authors ?? []) + (manga.artists ?? [])
                if !creators.isEmpty {
                    Text(Array(Set(creators)).joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if let source = sourceManager.metadata(id: sourceId) {
                    Label(source.name, systemImage: "shippingbox")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func descriptionSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Synopsis")
                .font(.headline)
            Text(cleanedDescription(text))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func tagsSection(_ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(6)
                }
            }
        }
    }

    private func readerDetailElementHasContent(_ element: ReaderDetailElement) -> Bool {
        switch element {
        case .overview:
            return !(manga.description ?? "").isEmpty
        case .tags:
            return !(manga.tags ?? []).isEmpty
        case .ratingNotes, .chapters:
            return true
        }
    }

    @ViewBuilder
    private func readerDetailElementView(_ element: ReaderDetailElement) -> some View {
        switch element {
        case .overview:
            if let description = manga.description, !description.isEmpty {
                descriptionSection(description)
            }
        case .tags:
            if let tags = manga.tags, !tags.isEmpty {
                tagsSection(tags)
            }
        case .ratingNotes:
            let progress = progressManager.progress(for: stableId)
            ReaderRatingNotesView(
                itemId: stableId,
                title: manga.title,
                routeKey: route.stableKey,
                knownAniListId: progress?.trackerAniListId,
                knownMALId: progress?.trackerMALId,
                totalChapters: latestChapterNumbers?.count,
                format: viewerFormat(manga.viewer)
            )
        case .chapters:
            chaptersElementView()
        }
    }

    @ViewBuilder
    private func chaptersElementView() -> some View {
        if isLoading && (manga.chapters?.isEmpty ?? true) {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading chapters...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if let errorMessage {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await loadDetails(force: true) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else {
            chaptersView()
        }
    }

    @ViewBuilder
    private func chaptersView() -> some View {
        let chapters = chapterModels()
        if chapters.isEmpty {
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
        } else {
            let displayed = reverseChapterList ? Array(chapters.reversed()) : chapters
            VStack(alignment: .leading, spacing: 0) {
                readButton(chapters: chapters)
                    .padding(.bottom, 8)

                HStack {
                    Text("\(chapters.count) Chapters")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                    Spacer()
                    Button {
                        downloadManager.enqueueChapters(
                            route: route,
                            mangaId: stableId,
                            title: manga.title,
                            coverURL: coverURL,
                            sourceName: sourceManager.metadata(id: sourceId)?.name,
                            format: viewerFormat(manga.viewer),
                            chapters: chapters,
                            kanzen: kanzen
                        )
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.accentColor)
                    }
                    .accessibilityLabel("Download All")

                    Button {
                        reverseChapterList.toggle()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.accentColor)
                    }
                }

                Divider().padding(.vertical, 4)

                ForEach(Array(displayed.enumerated()), id: \.element.id) { index, chapter in
                    chapterRow(chapter, displayedChapters: displayed, displayIndex: index)
                    Divider()
                }
            }
        }
    }

    private func chapterRow(_ chapter: Chapter, displayedChapters: [Chapter], displayIndex: Int) -> some View {
        let isRead = progressManager.isChapterRead(mangaId: stableId, chapterNumber: chapter.chapterNumber)
        let chapterTitle = chapter.chapterData?.first?.title ?? ""
        let downloadStatus = downloadManager.status(for: route, chapterNumber: chapter.chapterNumber)
        let downloadProgress = downloadManager.progress(for: route, chapterNumber: chapter.chapterNumber)

        return Button {
            selectedChapterData = chapter
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.chapterNumber)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isRead ? .secondary : .primary)
                        .lineLimit(1)

                    if !chapterTitle.isEmpty {
                        Text(chapterTitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if let group = chapter.chapterData?.first?.scanlationGroup, !group.isEmpty {
                        Text(group)
                            .font(.caption2)
                            .foregroundColor(.accentColor.opacity(0.8))
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
        }
        .buttonStyle(.plain)
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
                        mangaTitle: manga.title,
                        coverURL: coverURL,
                        format: viewerFormat(manga.viewer),
                        totalChapters: latestChapterNumbers?.count,
                        latestChapterNumbers: latestChapterNumbers,
                        route: route
                    )
                } label: {
                    Label("Mark as Read", systemImage: "eye")
                }
            }

            Divider()

            markRangeMenu(displayedChapters: displayedChapters, displayIndex: displayIndex)

            Divider()

            downloadContextMenu(for: chapter, status: downloadStatus)
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
    private func markRangeMenu(displayedChapters: [Chapter], displayIndex: Int) -> some View {
        Button {
            let numbers = displayedChapters.prefix(displayIndex + 1).map(\.chapterNumber)
            markChaptersRead(numbers)
        } label: {
            Label("Mark Above as Read", systemImage: "arrow.up.circle")
        }

        Button {
            let numbers = displayedChapters.suffix(displayedChapters.count - displayIndex).map(\.chapterNumber)
            markChaptersRead(Array(numbers))
        } label: {
            Label("Mark Below as Read", systemImage: "arrow.down.circle")
        }
    }

    @ViewBuilder
    private func downloadContextMenu(for chapter: Chapter, status: ReaderDownloadStatus) -> some View {
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
                    title: manga.title,
                    coverURL: coverURL,
                    sourceName: sourceManager.metadata(id: sourceId)?.name,
                    format: viewerFormat(manga.viewer),
                    chapter: chapter,
                    kanzen: kanzen
                )
            } label: {
                Label(status == .failed ? "Retry Download" : "Download", systemImage: "arrow.down.circle")
            }
        }
    }

    private func markChaptersRead(_ chapterNumbers: [String]) {
        progressManager.markAllRead(
            mangaId: stableId,
            chapterNumbers: chapterNumbers,
            mangaTitle: manga.title,
            coverURL: coverURL,
            format: viewerFormat(manga.viewer),
            totalChapters: latestChapterNumbers?.count,
            latestChapterNumbers: latestChapterNumbers,
            route: route
        )
    }

    private func readButton(chapters: [Chapter]) -> some View {
        let lastRead = progressManager.lastReadChapter(for: stableId)
        let readChapters = progressManager.readChapters(for: stableId)
        let target = targetChapterForReading(chapters: chapters, lastRead: lastRead, readChapters: readChapters)

        return Button {
            selectedChapterData = target
        } label: {
            HStack {
                Image(systemName: lastRead == nil && readChapters.isEmpty ? "play.fill" : "book.fill")
                    .font(.subheadline)
                Text(lastRead == nil && readChapters.isEmpty ? "Start Reading" : "Continue Reading")
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
        .disabled(target == nil)
    }

    private func targetChapterForReading(chapters: [Chapter], lastRead: String?, readChapters: Set<String>) -> Chapter? {
        let readKeys = Set(readChapters.map { ChapterIdentityNormalizer.key(for: $0) })
        if let lastRead,
           let chapter = chapters.first(where: {
               $0.chapterNumber == lastRead ||
               ChapterIdentityNormalizer.key(for: $0.chapterNumber) == ChapterIdentityNormalizer.key(for: lastRead)
           }) {
            return chapter
        }

        let chronological = chronologicalChapters(chapters)
        if let unread = chronological.first(where: { !readKeys.contains(ChapterIdentityNormalizer.key(for: $0.chapterNumber)) }) {
            return unread
        }
        return chronological.first
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

    private func chapterModels() -> [Chapter] {
        let rawChapters = manga.chapters ?? []
        let chapters = rawChapters.enumerated().map { index, aidokuChapter in
            let title = aidokuChapter.title ?? ""
            let number = chapterNumberTitle(aidokuChapter, fallbackIndex: index)
            let payload = AidokuChapterPayload(sourceId: sourceId, manga: manga, chapter: aidokuChapter)
            let group = aidokuChapter.scanlators?.joined(separator: ", ") ?? ""
            return Chapter(
                chapterNumber: number,
                idx: index,
                chapterData: [ChapterData(params: payload, title: title, scanlationGroup: group)]
            )
        }
        return ChapterIdentityNormalizer.deduplicatedChapters(chapters)
    }

    private func chapterNumbers(from manga: AidokuRunner.Manga) -> [String]? {
        let numbers = (manga.chapters ?? []).enumerated().map { index, chapter in
            chapterNumberTitle(chapter, fallbackIndex: index)
        }
        let unique = ChapterIdentityNormalizer.deduplicatedNumbers(numbers)
        return unique.isEmpty ? nil : unique
    }

    private func chapterNumberTitle(_ chapter: AidokuRunner.Chapter, fallbackIndex: Int) -> String {
        if let volume = chapter.volumeNumber, let number = chapter.chapterNumber {
            return "Vol. \(formatNumber(volume)) Ch. \(formatNumber(number))"
        }
        if let number = chapter.chapterNumber {
            return "Chapter \(formatNumber(number))"
        }
        if let title = chapter.title, !title.isEmpty {
            return title
        }
        return "Chapter \(fallbackIndex + 1)"
    }

    private func viewerTitle(_ viewer: AidokuRunner.Viewer) -> String {
        switch viewer {
        case .leftToRight:
            return "Manga LTR"
        case .rightToLeft:
            return "Manga RTL"
        case .vertical, .webtoon:
            return "Webtoon"
        default:
            return "Manga"
        }
    }

    private func viewerFormat(_ viewer: AidokuRunner.Viewer) -> String {
        switch viewer {
        case .vertical, .webtoon:
            return "WEBTOON"
        default:
            return "MANGA"
        }
    }

    private func statusTitle(_ status: AidokuRunner.PublishingStatus) -> String {
        switch status {
        case .ongoing:
            return "Ongoing"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        case .hiatus:
            return "Hiatus"
        default:
            return "Unknown"
        }
    }

    private func cleanedDescription(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private func formatNumber(_ value: Float) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}

struct MangaSourceRepairView: View {
    let title: String
    let message: String
    let actionTitle: String
    var action: (() -> Void)?

    init(title: String, message: String, actionTitle: String = "Aidoku Sources", action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 42))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            } else {
                NavigationLink(destination: AidokuSourcesSettingsView()) {
                    Label(actionTitle, systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
