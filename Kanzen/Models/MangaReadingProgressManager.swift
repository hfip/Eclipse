//
//  MangaReadingProgressManager.swift
//  Kanzen
//
//  Created by Luna on 2026.
//

import Foundation

// MARK: - Progress Model

struct MangaProgress: Codable {
    var readChapterNumbers: Set<String> = []
    var lastReadChapter: String?
    var lastReadDate: Date?
    /// Page index keyed by chapter number, so reader can resume mid-chapter.
    var pagePositions: [String: Int] = [:]
    /// Page count keyed by chapter number, so detail rows can display resume progress.
    var pageCounts: [String: Int] = [:]
    // Display metadata for history
    var title: String?
    var coverURL: String?
    var format: String?
    var totalChapters: Int?
    var latestChapterNumbers: [String]?
    var lastSourceRefresh: Date?
    var sourceRefreshError: String?
    var trackerAniListId: Int?
    var trackerMALId: Int?
    var trackerMatchConfidence: Double?
    var trackerResolvedAt: Date?
    // Module routing (for module-search sourced content)
    var moduleUUID: String?
    var contentParams: String?
    var isNovel: Bool?
    var route: MangaContentRoute?

    enum CodingKeys: String, CodingKey {
        case readChapterNumbers
        case lastReadChapter
        case lastReadDate
        case pagePositions
        case pageCounts
        case title
        case coverURL
        case format
        case totalChapters
        case latestChapterNumbers
        case lastSourceRefresh
        case sourceRefreshError
        case trackerAniListId
        case trackerMALId
        case trackerMatchConfidence
        case trackerResolvedAt
        case moduleUUID
        case contentParams
        case isNovel
        case route
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readChapterNumbers = try container.decodeIfPresent(Set<String>.self, forKey: .readChapterNumbers) ?? []
        lastReadChapter = try container.decodeIfPresent(String.self, forKey: .lastReadChapter)
        lastReadDate = try container.decodeIfPresent(Date.self, forKey: .lastReadDate)
        pagePositions = try container.decodeIfPresent([String: Int].self, forKey: .pagePositions) ?? [:]
        pageCounts = try container.decodeIfPresent([String: Int].self, forKey: .pageCounts) ?? [:]
        title = try container.decodeIfPresent(String.self, forKey: .title)
        coverURL = try container.decodeIfPresent(String.self, forKey: .coverURL)
        format = try container.decodeIfPresent(String.self, forKey: .format)
        totalChapters = try container.decodeIfPresent(Int.self, forKey: .totalChapters)
        latestChapterNumbers = try container.decodeIfPresent([String].self, forKey: .latestChapterNumbers)
        lastSourceRefresh = try container.decodeIfPresent(Date.self, forKey: .lastSourceRefresh)
        sourceRefreshError = try container.decodeIfPresent(String.self, forKey: .sourceRefreshError)
        trackerAniListId = try container.decodeIfPresent(Int.self, forKey: .trackerAniListId)
        trackerMALId = try container.decodeIfPresent(Int.self, forKey: .trackerMALId)
        trackerMatchConfidence = try container.decodeIfPresent(Double.self, forKey: .trackerMatchConfidence)
        trackerResolvedAt = try container.decodeIfPresent(Date.self, forKey: .trackerResolvedAt)
        moduleUUID = try container.decodeIfPresent(String.self, forKey: .moduleUUID)
        contentParams = try container.decodeIfPresent(String.self, forKey: .contentParams)
        isNovel = try container.decodeIfPresent(Bool.self, forKey: .isNovel)
        route = try container.decodeIfPresent(MangaContentRoute.self, forKey: .route)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(readChapterNumbers, forKey: .readChapterNumbers)
        try container.encodeIfPresent(lastReadChapter, forKey: .lastReadChapter)
        try container.encodeIfPresent(lastReadDate, forKey: .lastReadDate)
        try container.encode(pagePositions, forKey: .pagePositions)
        try container.encode(pageCounts, forKey: .pageCounts)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(coverURL, forKey: .coverURL)
        try container.encodeIfPresent(format, forKey: .format)
        try container.encodeIfPresent(totalChapters, forKey: .totalChapters)
        try container.encodeIfPresent(latestChapterNumbers, forKey: .latestChapterNumbers)
        try container.encodeIfPresent(lastSourceRefresh, forKey: .lastSourceRefresh)
        try container.encodeIfPresent(sourceRefreshError, forKey: .sourceRefreshError)
        try container.encodeIfPresent(trackerAniListId, forKey: .trackerAniListId)
        try container.encodeIfPresent(trackerMALId, forKey: .trackerMALId)
        try container.encodeIfPresent(trackerMatchConfidence, forKey: .trackerMatchConfidence)
        try container.encodeIfPresent(trackerResolvedAt, forKey: .trackerResolvedAt)
        try container.encodeIfPresent(moduleUUID, forKey: .moduleUUID)
        try container.encodeIfPresent(contentParams, forKey: .contentParams)
        try container.encodeIfPresent(isNovel, forKey: .isNovel)
        try container.encodeIfPresent(route, forKey: .route)
    }
}

// MARK: - Progress Manager

final class MangaReadingProgressManager: ObservableObject {
    static let shared = MangaReadingProgressManager()

    /// Key = AniList manga ID, Value = progress data
    @Published private(set) var progressMap: [Int: MangaProgress] = [:]

    private let storageKey = "mangaReadingProgress"

    private init() {
        load()
    }

    // MARK: - Queries

    func isChapterRead(mangaId: Int, chapterNumber: String) -> Bool {
        guard let progress = progressMap[mangaId] else { return false }
        return containsChapter(chapterNumber, in: progress.readChapterNumbers)
    }

    func readChapters(for mangaId: Int) -> Set<String> {
        progressMap[mangaId]?.readChapterNumbers ?? []
    }

    func lastReadChapter(for mangaId: Int) -> String? {
        progressMap[mangaId]?.lastReadChapter
    }

    func pagePosition(mangaId: Int, chapterNumber: String) -> Int {
        guard let positions = progressMap[mangaId]?.pagePositions else { return 0 }
        return storedValue(in: positions, for: chapterNumber) ?? 0
    }

    func pageProgress(mangaId: Int, chapterNumber: String) -> (page: Int, total: Int)? {
        guard let progress = progressMap[mangaId] else { return nil }
        let zeroBasedPage = storedValue(in: progress.pagePositions, for: chapterNumber)
        let total = storedValue(in: progress.pageCounts, for: chapterNumber)
        guard let zeroBasedPage, let total, total > 0 else { return nil }
        return (page: min(max(zeroBasedPage + 1, 1), total), total: total)
    }

    func pageProgressLabel(mangaId: Int, chapterNumber: String) -> String? {
        guard let pageProgress = pageProgress(mangaId: mangaId, chapterNumber: chapterNumber) else { return nil }
        return "Page \(pageProgress.page) of \(pageProgress.total)"
    }

    func progress(for mangaId: Int) -> MangaProgress? {
        progressMap[mangaId]
    }

    func savePagePosition(
        mangaId: Int,
        chapterNumber: String,
        page: Int,
        pageCount: Int? = nil,
        mangaTitle: String? = nil,
        coverURL: String? = nil,
        format: String? = nil,
        totalChapters: Int? = nil,
        latestChapterNumbers: [String]? = nil,
        moduleUUID: String? = nil,
        contentParams: String? = nil,
        isNovel: Bool? = nil,
        route: MangaContentRoute? = nil,
        trackerAniListId: Int? = nil,
        trackerMALId: Int? = nil,
        readThreshold: Double = 0.8
    ) {
        var progress = progressMap[mangaId] ?? MangaProgress()
        let safePageCount = pageCount.map { max($0, 0) }
        let safePage = max(page, 0)
        let chapterKeys = chapterKeyCandidates(for: chapterNumber)
        for key in chapterKeys {
            progress.pagePositions[key] = safePage
        }
        if let safePageCount, safePageCount > 0 {
            for key in chapterKeys {
                progress.pageCounts[key] = safePageCount
            }
        }
        progress.lastReadChapter = chapterNumber
        progress.lastReadDate = Date()
        if let t = mangaTitle { progress.title = t }
        if let c = coverURL { progress.coverURL = c }
        if let f = format { progress.format = f }
        let uniqueLatestChapterNumbers = latestChapterNumbers.map(ChapterIdentityNormalizer.deduplicatedNumbers)
        if let uniqueLatestChapterNumbers {
            progress.latestChapterNumbers = uniqueLatestChapterNumbers
            progress.totalChapters = uniqueLatestChapterNumbers.count
        } else if let totalChapters {
            progress.totalChapters = totalChapters
        }
        if let moduleUUID { progress.moduleUUID = moduleUUID }
        if let contentParams { progress.contentParams = contentParams }
        if let isNovel { progress.isNovel = isNovel }
        if let trackerAniListId { progress.trackerAniListId = trackerAniListId }
        if let trackerMALId { progress.trackerMALId = trackerMALId }
        applyRoute(route, to: &progress)

        let totalPages = safePageCount ?? storedValue(in: progress.pageCounts, for: chapterNumber) ?? 0
        var didMarkRead = false
        if totalPages > 0 {
            let completion = Double(min(safePage + 1, totalPages)) / Double(totalPages)
            if completion >= readThreshold, !containsChapter(chapterNumber, in: progress.readChapterNumbers) {
                insertChapter(chapterNumber, into: &progress.readChapterNumbers)
                didMarkRead = true
            }
        }

        progressMap[mangaId] = progress
        save()

        if didMarkRead, let numericChapter = extractChapterNumber(from: chapterNumber) {
            syncTrackerProgress(
                mangaId: mangaId,
                progress: progress,
                chapterNumber: numericChapter,
                explicitTitle: mangaTitle,
                explicitTotalChapters: totalChapters
            )
        }
    }

    // MARK: - Mutations

    /// Mark a chapter as read and optionally sync to AniList.
    func markChapterRead(mangaId: Int, chapterNumber: String, mangaTitle: String? = nil, coverURL: String? = nil, format: String? = nil, totalChapters: Int? = nil, latestChapterNumbers: [String]? = nil, moduleUUID: String? = nil, contentParams: String? = nil, isNovel: Bool? = nil, route: MangaContentRoute? = nil, trackerAniListId: Int? = nil, trackerMALId: Int? = nil) {
        var progress = progressMap[mangaId] ?? MangaProgress()
        let uniqueLatestChapterNumbers = latestChapterNumbers.map(ChapterIdentityNormalizer.deduplicatedNumbers)

        guard !containsChapter(chapterNumber, in: progress.readChapterNumbers) else {
            // Still update metadata if provided even for already-read chapters
            var changed = false
            if let t = mangaTitle, progress.title != t { progress.title = t; changed = true }
            if let c = coverURL, progress.coverURL != c { progress.coverURL = c; changed = true }
            if let f = format, progress.format != f { progress.format = f; changed = true }
            if let uniqueLatestChapterNumbers {
                if progress.totalChapters != uniqueLatestChapterNumbers.count {
                    progress.totalChapters = uniqueLatestChapterNumbers.count
                    changed = true
                }
                if progress.latestChapterNumbers != uniqueLatestChapterNumbers {
                    progress.latestChapterNumbers = uniqueLatestChapterNumbers
                    changed = true
                }
            } else if let tc = totalChapters, progress.totalChapters != tc {
                progress.totalChapters = tc
                changed = true
            }
            if let m = moduleUUID, progress.moduleUUID != m { progress.moduleUUID = m; changed = true }
            if let cp = contentParams, progress.contentParams != cp { progress.contentParams = cp; changed = true }
            if let n = isNovel, progress.isNovel != n { progress.isNovel = n; changed = true }
            if let trackerAniListId, progress.trackerAniListId != trackerAniListId { progress.trackerAniListId = trackerAniListId; changed = true }
            if let trackerMALId, progress.trackerMALId != trackerMALId { progress.trackerMALId = trackerMALId; changed = true }
            if let route, progress.route != route {
                applyRoute(route, to: &progress)
                changed = true
            }
            if changed { progressMap[mangaId] = progress; save() }
            return
        }

        insertChapter(chapterNumber, into: &progress.readChapterNumbers)
        progress.lastReadChapter = chapterNumber
        progress.lastReadDate = Date()
        if let t = mangaTitle { progress.title = t }
        if let c = coverURL { progress.coverURL = c }
        if let f = format { progress.format = f }
        if let uniqueLatestChapterNumbers {
            progress.latestChapterNumbers = uniqueLatestChapterNumbers
            progress.totalChapters = uniqueLatestChapterNumbers.count
        } else if let tc = totalChapters {
            progress.totalChapters = tc
        }
        if let m = moduleUUID { progress.moduleUUID = m }
        if let cp = contentParams { progress.contentParams = cp }
        if let n = isNovel { progress.isNovel = n }
        if let trackerAniListId { progress.trackerAniListId = trackerAniListId }
        if let trackerMALId { progress.trackerMALId = trackerMALId }
        applyRoute(route, to: &progress)
        progressMap[mangaId] = progress
        save()

        if let numericChapter = extractChapterNumber(from: chapterNumber) {
            syncTrackerProgress(
                mangaId: mangaId,
                progress: progress,
                chapterNumber: numericChapter,
                explicitTitle: mangaTitle,
                explicitTotalChapters: totalChapters
            )
        }
    }

    /// Mark a chapter as unread.
    func markChapterUnread(mangaId: Int, chapterNumber: String) {
        guard var progress = progressMap[mangaId] else { return }
        removeChapter(chapterNumber, from: &progress.readChapterNumbers)
        progressMap[mangaId] = progress
        save()
    }

    /// Mark multiple chapters as read and sync the highest chapter to AniList.
    func markAllRead(mangaId: Int, chapterNumbers: [String], mangaTitle: String? = nil, coverURL: String? = nil, format: String? = nil, totalChapters: Int? = nil, latestChapterNumbers: [String]? = nil, moduleUUID: String? = nil, contentParams: String? = nil, isNovel: Bool? = nil, route: MangaContentRoute? = nil, trackerAniListId: Int? = nil, trackerMALId: Int? = nil) {
        var progress = progressMap[mangaId] ?? MangaProgress()
        let uniqueChapterNumbers = ChapterIdentityNormalizer.deduplicatedNumbers(chapterNumbers)
        let uniqueLatestChapterNumbers = latestChapterNumbers.map(ChapterIdentityNormalizer.deduplicatedNumbers)
        for ch in uniqueChapterNumbers {
            insertChapter(ch, into: &progress.readChapterNumbers)
        }
        if let last = uniqueChapterNumbers.last {
            progress.lastReadChapter = last
            progress.lastReadDate = Date()
        }
        if let mangaTitle { progress.title = mangaTitle }
        if let coverURL { progress.coverURL = coverURL }
        if let format { progress.format = format }
        if let uniqueLatestChapterNumbers {
            progress.latestChapterNumbers = uniqueLatestChapterNumbers
            progress.totalChapters = uniqueLatestChapterNumbers.count
        } else if let totalChapters {
            progress.totalChapters = totalChapters
        }
        if let moduleUUID { progress.moduleUUID = moduleUUID }
        if let contentParams { progress.contentParams = contentParams }
        if let isNovel { progress.isNovel = isNovel }
        if let trackerAniListId { progress.trackerAniListId = trackerAniListId }
        if let trackerMALId { progress.trackerMALId = trackerMALId }
        applyRoute(route, to: &progress)
        progressMap[mangaId] = progress
        save()

        let highest = uniqueChapterNumbers.compactMap { extractChapterNumber(from: $0) }.max()
        if let highest = highest {
            syncTrackerProgress(
                mangaId: mangaId,
                progress: progress,
                chapterNumber: highest,
                explicitTitle: mangaTitle,
                explicitTotalChapters: totalChapters
            )
        }
    }

    func updateSourceMetadata(mangaId: Int, title: String? = nil, coverURL: String? = nil, format: String? = nil, latestChapterNumbers: [String], route: MangaContentRoute? = nil, sourceRefreshError: String? = nil) {
        var progress = progressMap[mangaId] ?? MangaProgress()
        let uniqueLatestChapterNumbers = ChapterIdentityNormalizer.deduplicatedNumbers(latestChapterNumbers)
        if let title { progress.title = title }
        if let coverURL { progress.coverURL = coverURL }
        if let format { progress.format = format }
        progress.latestChapterNumbers = uniqueLatestChapterNumbers
        progress.totalChapters = uniqueLatestChapterNumbers.count
        progress.lastSourceRefresh = Date()
        progress.sourceRefreshError = sourceRefreshError
        applyRoute(route, to: &progress)
        progressMap[mangaId] = progress
        save()
    }

    func updateTrackerMatch(mangaId: Int, aniListId: Int?, malId: Int?, confidence: Double?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.updateTrackerMatch(mangaId: mangaId, aniListId: aniListId, malId: malId, confidence: confidence)
            }
            return
        }

        var progress = progressMap[mangaId] ?? MangaProgress()
        var changed = false

        if let aniListId, aniListId > 0, progress.trackerAniListId != aniListId {
            progress.trackerAniListId = aniListId
            changed = true
        }
        if let malId, malId > 0, progress.trackerMALId != malId {
            progress.trackerMALId = malId
            changed = true
        }
        if let confidence, progress.trackerMatchConfidence != confidence {
            progress.trackerMatchConfidence = confidence
            changed = true
        }
        if changed {
            progress.trackerResolvedAt = Date()
            progressMap[mangaId] = progress
            save()
        }
    }

    /// Import chapters without syncing back to trackers. Existing local reads are only advanced.
    func bulkMarkChaptersReadForImport(mangaId: Int, throughChapter: Int, mangaTitle: String? = nil, coverURL: String? = nil, totalChapters: Int? = nil) {
        guard throughChapter >= 1 else { return }

        var progress = progressMap[mangaId] ?? MangaProgress()
        for chapter in 1...throughChapter {
            progress.readChapterNumbers.insert(String(chapter))
        }

        let highest = progress.readChapterNumbers.compactMap { extractChapterNumber(from: $0) }.max() ?? throughChapter
        progress.lastReadChapter = String(highest)
        progress.lastReadDate = Date()
        if let mangaTitle { progress.title = mangaTitle }
        if let coverURL { progress.coverURL = coverURL }
        if let totalChapters { progress.totalChapters = totalChapters }

        progressMap[mangaId] = progress
        save()
    }

    /// Mark all chapters as unread.
    func markAllUnread(mangaId: Int) {
        guard var progress = progressMap[mangaId] else { return }
        progress.readChapterNumbers.removeAll()
        progress.lastReadChapter = nil
        progressMap[mangaId] = progress
        save()
    }

    func removeFromHistory(mangaId: Int) {
        guard var progress = progressMap[mangaId] else { return }
        progress.lastReadChapter = nil
        progress.lastReadDate = nil
        progress.pagePositions.removeAll()
        progress.pageCounts.removeAll()
        progressMap[mangaId] = progress
        save()
    }

    func clearHistory() {
        guard progressMap.values.contains(where: { $0.lastReadDate != nil }) else { return }
        for mangaId in progressMap.keys {
            progressMap[mangaId]?.lastReadChapter = nil
            progressMap[mangaId]?.lastReadDate = nil
            progressMap[mangaId]?.pagePositions.removeAll()
            progressMap[mangaId]?.pageCounts.removeAll()
        }
        save()
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Int: MangaProgress].self, from: data) {
            progressMap = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(progressMap) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - History

    /// Returns all manga IDs that have reading progress, sorted by most recently read.
    func recentlyReadMangaIds() -> [(id: Int, progress: MangaProgress)] {
        progressMap
            .filter { $0.value.lastReadDate != nil }
            .sorted { ($0.value.lastReadDate ?? .distantPast) > ($1.value.lastReadDate ?? .distantPast) }
            .map { (id: $0.key, progress: $0.value) }
    }

    /// Bulk-replace progress map (used during backup restore).
    func replaceProgressMapForRestore(_ newMap: [Int: MangaProgress]) {
        progressMap = newMap
        save()
    }

    // MARK: - Helpers

    /// Extracts the leading integer from a chapter string like "Ch. 129" or "127.2".
    private func extractChapterNumber(from string: String) -> Int? {
        // Look for patterns like "Ch. 129", "Chapter 5", or just "129.2"
        let pattern = #"(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range(at: 1), in: string) else { return nil }
        return Int(string[range])
    }

    private func applyRoute(_ route: MangaContentRoute?, to progress: inout MangaProgress) {
        guard let route else { return }
        progress.route = route

        if case .legacyModule(let moduleUUID, let contentParams, let isNovel) = route {
            progress.moduleUUID = moduleUUID
            progress.contentParams = contentParams
            progress.isNovel = isNovel
        }
    }

    private func chapterKeyCandidates(for chapterNumber: String) -> [String] {
        let trimmed = chapterNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = ChapterIdentityNormalizer.key(for: chapterNumber)
        var keys: [String] = []
        for key in [chapterNumber, trimmed, normalized] where !key.isEmpty && !keys.contains(key) {
            keys.append(key)
        }
        return keys
    }

    private func containsChapter(_ chapterNumber: String, in chapters: Set<String>) -> Bool {
        let candidates = Set(chapterKeyCandidates(for: chapterNumber))
        if !chapters.isDisjoint(with: candidates) {
            return true
        }

        let normalized = ChapterIdentityNormalizer.key(for: chapterNumber)
        return chapters.contains { ChapterIdentityNormalizer.key(for: $0) == normalized }
    }

    private func insertChapter(_ chapterNumber: String, into chapters: inout Set<String>) {
        for key in chapterKeyCandidates(for: chapterNumber) {
            chapters.insert(key)
        }
    }

    private func removeChapter(_ chapterNumber: String, from chapters: inout Set<String>) {
        let candidates = Set(chapterKeyCandidates(for: chapterNumber))
        let normalized = ChapterIdentityNormalizer.key(for: chapterNumber)
        chapters = chapters.filter { saved in
            !candidates.contains(saved) && ChapterIdentityNormalizer.key(for: saved) != normalized
        }
    }

    private func storedValue<Value>(in dictionary: [String: Value], for chapterNumber: String) -> Value? {
        for key in chapterKeyCandidates(for: chapterNumber) {
            if let value = dictionary[key] {
                return value
            }
        }

        let normalized = ChapterIdentityNormalizer.key(for: chapterNumber)
        return dictionary.first { ChapterIdentityNormalizer.key(for: $0.key) == normalized }?.value
    }

    private func syncTrackerProgress(mangaId: Int, progress: MangaProgress, chapterNumber: Int, explicitTitle: String?, explicitTotalChapters: Int?) {
        if mangaId > 0 {
            TrackerManager.shared.syncMangaProgress(
                aniListId: mangaId,
                malId: progress.trackerMALId,
                title: explicitTitle ?? progress.title,
                chapterNumber: chapterNumber,
                totalChapters: explicitTotalChapters ?? progress.totalChapters ?? progress.latestChapterNumbers?.count,
                format: progress.format,
                routeKey: progress.route?.stableKey
            )
            return
        }

        guard let title = explicitTitle ?? progress.title else {
            ReaderLogger.shared.log("Skipping tracker sync for generated manga id \(mangaId): missing title", type: "Tracker")
            return
        }

        TrackerManager.shared.syncMangaProgress(
            title: title,
            chapterNumber: chapterNumber,
            totalChapters: explicitTotalChapters ?? progress.totalChapters ?? progress.latestChapterNumbers?.count,
            format: progress.format,
            routeKey: progress.route?.stableKey,
            knownAniListId: progress.trackerAniListId,
            knownMALId: progress.trackerMALId
        )
    }
}
