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
    @StateObject private var sourceManager = AidokuSourceManager.shared
    @StateObject private var kanzen = KanzenEngine()
    @State private var manga: AidokuRunner.Manga
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedChapterData: Chapter?
    @State private var showAddToCollection = false
    @State private var reverseChapterList = false
    @State private var scrollOffset: CGFloat = 0

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
            coverURL: coverURL
        )
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

                if let description = manga.description, !description.isEmpty {
                    Divider()
                    descriptionSection(description)
                }

                if let tags = manga.tags, !tags.isEmpty {
                    Divider()
                    tagsSection(tags)
                }

                Divider()

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
                    route: route
                )
            }
        }) { chapter in
            let chapters = chapterModels()
            readerManagerView(
                chapters: chapters,
                selectedChapter: chapter,
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
            manga = try await sourceManager.mangaUpdate(
                sourceId: sourceId,
                manga: manga,
                needsDetails: true,
                needsChapters: true
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
            let displayed = reverseChapterList ? chapters.reversed() : chapters
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
                        reverseChapterList.toggle()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.accentColor)
                    }
                }

                Divider().padding(.vertical, 4)

                ForEach(displayed) { chapter in
                    chapterRow(chapter)
                    Divider()
                }
            }
        }
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        let isRead = progressManager.isChapterRead(mangaId: stableId, chapterNumber: chapter.chapterNumber)
        let chapterTitle = chapter.chapterData?.first?.title ?? ""

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
                }

                Spacer(minLength: 8)

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
                        route: route
                    )
                } label: {
                    Label("Mark as Read", systemImage: "eye")
                }
            }
        }
    }

    private func readButton(chapters: [Chapter]) -> some View {
        let lastRead = progressManager.lastReadChapter(for: stableId)
        let target = lastRead.flatMap { lastRead in
            chapters.first { $0.chapterNumber == lastRead }
        } ?? chapters.first

        return Button {
            selectedChapterData = target
        } label: {
            HStack {
                Image(systemName: lastRead == nil ? "play.fill" : "book.fill")
                    .font(.subheadline)
                Text(lastRead == nil ? "Start Reading" : "Continue Reading")
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

    private func chapterModels() -> [Chapter] {
        let rawChapters = manga.chapters ?? []
        return rawChapters.enumerated().map { index, aidokuChapter in
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
