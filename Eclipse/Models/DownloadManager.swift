// Created on 27/02/26.

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Download Item Model

enum DownloadStatus: String, Codable {
    case queued
    case downloading
    case paused
    case completed
    case failed
}

struct DownloadItem: Codable, Identifiable {
    let id: String
    let tmdbId: Int
    let isMovie: Bool
    let title: String
    let displayTitle: String
    let posterURL: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeName: String?
    let streamURL: String
    let headers: [String: String]
    let subtitleURL: String?
    let subtitleHeaders: [String: String]?
    let serviceBaseURL: String
    let episodePlaybackContext: EpisodePlaybackContext?
    var status: DownloadStatus
    var progress: Double
    var totalBytes: Int64
    var downloadedBytes: Int64
    var localFileName: String?
    var subtitleFileName: String?
    var error: String?
    var dateAdded: Date
    var dateCompleted: Date?
    let isAnime: Bool

    // HLS resume checkpoint (nil for non-HLS or downloads with no progress yet).
    var hlsResumeSegmentIndex: Int?   // segments fully written to the partial file
    var hlsResumeByteCount: Int64?    // partial byte length at that checkpoint
    var hlsVariantURL: String?        // pinned variant playlist for an identical resume
    var hlsTotalSegments: Int?        // segment count, used to validate a resume
    
    var isHLS: Bool {
        streamURL.lowercased().contains(".m3u8")
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        if totalBytes > 0 {
            return "\(formatter.string(fromByteCount: downloadedBytes)) / \(formatter.string(fromByteCount: totalBytes))"
        } else if downloadedBytes > 0 {
            return formatter.string(fromByteCount: downloadedBytes)
        }
        return ""
    }

    var playerTitleBase: String {
        guard isAnime else { return title }
        guard !isMovie else { return nonEmptyTrimmed(displayTitle) ?? title }
        return animeDisplayTitleWithoutEpisodeSuffix
    }

    private var animeDisplayTitleWithoutEpisodeSuffix: String {
        var base = nonEmptyTrimmed(displayTitle) ?? title
        let suffixPatterns = [
            #"(?i)\s*-\s*S\d{1,2}E\d{1,4}$"#,
            #"(?i)\s*S\d{1,2}E\d{1,4}$"#,
            #"(?i)\s*-\s*E\d{1,4}$"#,
            #"(?i)\s*E\d{1,4}$"#,
            #"(?i)\s*Episode\s+\d{1,4}$"#
        ]

        for pattern in suffixPatterns {
            if let range = base.range(of: pattern, options: .regularExpression) {
                base.removeSubrange(range)
                break
            }
        }

        return nonEmptyTrimmed(base) ?? title
    }

    private func nonEmptyTrimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
    
    var mediaInfo: MediaInfo {
        if isMovie {
            return .movie(id: tmdbId, title: playerTitleBase, posterURL: posterURL, isAnime: isAnime)
        } else {
            return .episode(
                showId: tmdbId,
                seasonNumber: seasonNumber ?? 1,
                episodeNumber: episodeNumber ?? 1,
                showTitle: playerTitleBase,
                showPosterURL: posterURL,
                isAnime: isAnime
            )
        }
    }
}

// MARK: - Download Manager

final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    @Published private(set) var downloads: [DownloadItem] = []
    
    private var backgroundSession: URLSession!
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var resumeDataStore: [String: Data] = [:]
    private var lastProgressUpdate: [String: Date] = [:]
    private var lastHLSCheckpointSave: [String: Date] = [:]
    private var activeHLSDownloaders: [String: HLSDownloader] = [:]
    #if canImport(UIKit)
    private var lifecycleObservers: [NSObjectProtocol] = []
    #endif
    
    private let maxConcurrentDownloads = 2
    private let maxConcurrentHLSDownloads = 1
    private let minimumFreeBytesForHLS: Int64 = 750 * 1024 * 1024
    private let fileManager = FileManager.default
    private let accessQueue = DispatchQueue(label: "app.eclipse.soupy.download-manager", attributes: .concurrent)
    private var backgroundHLSPipelineEnabled: Bool {
        UserDefaults.standard.bool(forKey: "backgroundHLSPipelineEnabled")
    }
    
    private var persistenceURL: URL {
        downloadsDirectory.appendingPathComponent(".downloads_metadata.json")
    }
    
    var downloadsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Downloads")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    /// Background session completion handler set by AppDelegate/SceneDelegate
    var backgroundCompletionHandler: (() -> Void)?
    
    private override init() {
        super.init()

        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
        
        let config = URLSessionConfiguration.background(withIdentifier: "app.eclipse.soupy.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true
        config.httpMaximumConnectionsPerHost = 4
        backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        loadDownloads()
        observeAppLifecycle()
        
        // Clean up orphaned files that aren't tracked in metadata
        cleanOrphanedFiles()
        
        // Resume any downloads that were marked as downloading (app was killed)
        resumeInterruptedDownloads()
    }

    deinit {
        #if canImport(UIKit)
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }

    private func observeAppLifecycle() {
        #if canImport(UIKit) && !os(watchOS)
        lifecycleObservers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.processQueue()
            }
        )
        #endif
    }
    
    // MARK: - Public API
    
    var activeDownloads: [DownloadItem] {
        downloads.filter { $0.status == .downloading || $0.status == .queued }
    }
    
    var completedDownloads: [DownloadItem] {
        downloads.filter { $0.status == .completed }
    }
    
    var failedDownloads: [DownloadItem] {
        downloads.filter { $0.status == .failed }
    }
    
    var activeDownloadCount: Int {
        downloads.filter { $0.status == .downloading }.count
    }
    
    func enqueueDownload(
        tmdbId: Int,
        isMovie: Bool,
        title: String,
        displayTitle: String,
        posterURL: String?,
        seasonNumber: Int?,
        episodeNumber: Int?,
        episodeName: String?,
        streamURL: String,
        headers: [String: String],
        subtitleURL: String?,
        subtitleHeaders: [String: String]? = nil,
        serviceBaseURL: String,
        isAnime: Bool,
        episodePlaybackContext: EpisodePlaybackContext? = nil
    ) {
        let id: String
        if isMovie {
            id = "dl_movie_\(tmdbId)"
        } else {
            id = "dl_ep_\(tmdbId)_s\(seasonNumber ?? 0)_e\(episodeNumber ?? 0)"
        }
        
        // Check if already downloading or completed
        if let existing = downloads.first(where: { $0.id == id }) {
            if existing.status == .completed || existing.status == .downloading || existing.status == .queued {
                Logger.shared.log("Download already exists: \(id) status=\(existing.status.rawValue)", type: "Download")
                return
            }
            // If failed, remove and re-queue
            removeDownload(id: id, deleteFile: true)
        }
        
        let item = DownloadItem(
            id: id,
            tmdbId: tmdbId,
            isMovie: isMovie,
            title: title,
            displayTitle: displayTitle,
            posterURL: posterURL,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeName: episodeName,
            streamURL: streamURL,
            headers: headers,
            subtitleURL: subtitleURL,
            subtitleHeaders: subtitleHeaders,
            serviceBaseURL: serviceBaseURL,
            episodePlaybackContext: episodePlaybackContext,
            status: .queued,
            progress: 0,
            totalBytes: 0,
            downloadedBytes: 0,
            localFileName: nil,
            subtitleFileName: nil,
            error: nil,
            dateAdded: Date(),
            dateCompleted: nil,
            isAnime: isAnime
        )
        
        DispatchQueue.main.async {
            self.downloads.append(item)
            self.saveDownloads()
            self.processQueue()
        }
        
        Logger.shared.log("Enqueued download: \(displayTitle) id=\(id)", type: "Download")
    }
    
    func pauseDownload(id: String) {
        guard let index = downloads.firstIndex(where: { $0.id == id }),
              downloads[index].status == .downloading else { return }
        
        if let task = activeTasks[id] {
            task.cancel(byProducingResumeData: { [weak self] data in
                if let data = data {
                    self?.resumeDataStore[id] = data
                }
            })
            activeTasks.removeValue(forKey: id)
        } else if let downloader = activeHLSDownloaders[id] {
            // HLS downloads do not support resume; cancel and restart on resume.
            // Keep the HLS lane occupied until cancellation is confirmed.
            downloader.cancel()
        }
        
        DispatchQueue.main.async {
            self.downloads[index].status = .paused
            self.saveDownloads()
            self.processQueue()
        }
        
        Logger.shared.log("Paused download: \(id)", type: "Download")
    }
    
    func resumeDownload(id: String) {
        guard let index = downloads.firstIndex(where: { $0.id == id }),
              downloads[index].status == .paused || downloads[index].status == .failed else { return }
        
        DispatchQueue.main.async {
            self.downloads[index].status = .queued
            self.downloads[index].error = nil
            // HLS downloads resume from the last checkpointed segment when one exists;
            // otherwise they restart from scratch.
            if self.downloads[index].isHLS && self.downloads[index].hlsResumeSegmentIndex == nil {
                self.downloads[index].progress = 0
                self.downloads[index].downloadedBytes = 0
                self.downloads[index].totalBytes = 0
            }
            self.saveDownloads()
            self.processQueue()
        }
        
        Logger.shared.log("Resumed download: \(id)", type: "Download")
    }
    
    func cancelDownload(id: String) {
        if let task = activeTasks[id] {
            task.cancel()
            activeTasks.removeValue(forKey: id)
        }
        if let downloader = activeHLSDownloaders[id] {
            downloader.cancel()
            activeHLSDownloaders.removeValue(forKey: id)
        }
        resumeDataStore.removeValue(forKey: id)
        lastHLSCheckpointSave.removeValue(forKey: id)
        removeDownload(id: id, deleteFile: true)
        processQueue()

        Logger.shared.log("Cancelled download: \(id)", type: "Download")
    }
    
    func removeDownload(id: String, deleteFile: Bool) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            if deleteFile, let fileName = downloads[index].localFileName {
                let fileURL = downloadsDirectory.appendingPathComponent(fileName)
                try? fileManager.removeItem(at: fileURL)
            }
            if deleteFile, let subFile = downloads[index].subtitleFileName {
                let subURL = downloadsDirectory.appendingPathComponent(subFile)
                try? fileManager.removeItem(at: subURL)
            }
            if deleteFile {
                // Remove any in-progress HLS partial file as well.
                let partialURL = downloadsDirectory.appendingPathComponent(".\(id).ts.partial")
                try? fileManager.removeItem(at: partialURL)
            }
            DispatchQueue.main.async {
                self.downloads.remove(at: index)
                self.saveDownloads()
            }
        }
    }
    
    func deleteAllForShow(tmdbId: Int) {
        let matchingIds = Set(downloads.filter { $0.tmdbId == tmdbId && $0.status == .completed }.map { $0.id })
        guard !matchingIds.isEmpty else { return }

        for item in downloads where matchingIds.contains(item.id) {
            if let fileName = item.localFileName {
                let fileURL = downloadsDirectory.appendingPathComponent(fileName)
                try? fileManager.removeItem(at: fileURL)
            }
            if let subFile = item.subtitleFileName {
                let subURL = downloadsDirectory.appendingPathComponent(subFile)
                try? fileManager.removeItem(at: subURL)
            }
        }

        DispatchQueue.main.async {
            self.downloads.removeAll { matchingIds.contains($0.id) }
            self.saveDownloads()
        }
    }

    func deleteAllCompleted() {
        let completedIds = Set(downloads.filter { $0.status == .completed }.map { $0.id })
        guard !completedIds.isEmpty else { return }

        // Delete files first
        for item in downloads where completedIds.contains(item.id) {
            if let fileName = item.localFileName {
                let fileURL = downloadsDirectory.appendingPathComponent(fileName)
                try? fileManager.removeItem(at: fileURL)
            }
            if let subFile = item.subtitleFileName {
                let subURL = downloadsDirectory.appendingPathComponent(subFile)
                try? fileManager.removeItem(at: subURL)
            }
        }

        // Remove all completed items from the array in one pass
        DispatchQueue.main.async {
            self.downloads.removeAll { completedIds.contains($0.id) }
            self.saveDownloads()
        }
    }
    
    func deleteAll() {
        // Cancel all active tasks
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
        for (_, downloader) in activeHLSDownloaders {
            downloader.cancel()
        }
        activeHLSDownloaders.removeAll()
        resumeDataStore.removeAll()
        
        // Wipe the entire downloads directory to guarantee no orphans remain
        let dir = downloadsDirectory
        if let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for fileURL in contents {
                // Preserve the metadata JSON itself; it gets overwritten below
                if fileURL.lastPathComponent == ".downloads_metadata.json" { continue }
                try? fileManager.removeItem(at: fileURL)
            }
        }
        
        DispatchQueue.main.async {
            self.downloads.removeAll()
            self.saveDownloads()
        }
    }
    
    func pauseAll() {
        let active = downloads.filter { $0.status == .downloading || $0.status == .queued }
        for item in active {
            if item.status == .downloading {
                pauseDownload(id: item.id)
            } else {
                if let index = downloads.firstIndex(where: { $0.id == item.id }) {
                    DispatchQueue.main.async {
                        self.downloads[index].status = .paused
                    }
                }
            }
        }
        saveDownloads()
    }
    
    func resumeAll() {
        let paused = downloads.filter { $0.status == .paused }
        for item in paused {
            resumeDownload(id: item.id)
        }
    }
    
    func retryAllFailed() {
        let failed = downloads.filter { $0.status == .failed }
        for item in failed {
            resumeDownload(id: item.id)
        }
    }
    
    func cancelAllActive() {
        let active = downloads.filter { $0.status == .downloading || $0.status == .queued || $0.status == .paused }
        for item in active {
            cancelDownload(id: item.id)
        }
    }
    
    func localFileURL(for item: DownloadItem) -> URL? {
        guard let fileName = item.localFileName else { return nil }
        let url = downloadsDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
    
    func localSubtitleURL(for item: DownloadItem) -> URL? {
        guard let fileName = item.subtitleFileName else { return nil }
        let url = downloadsDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
    
    func isDownloaded(tmdbId: Int, isMovie: Bool, seasonNumber: Int? = nil, episodeNumber: Int? = nil) -> Bool {
        let id: String
        if isMovie {
            id = "dl_movie_\(tmdbId)"
        } else {
            id = "dl_ep_\(tmdbId)_s\(seasonNumber ?? 0)_e\(episodeNumber ?? 0)"
        }
        return downloads.first(where: { $0.id == id && $0.status == .completed }) != nil
    }
    
    func isDownloading(tmdbId: Int, isMovie: Bool, seasonNumber: Int? = nil, episodeNumber: Int? = nil) -> Bool {
        let id: String
        if isMovie {
            id = "dl_movie_\(tmdbId)"
        } else {
            id = "dl_ep_\(tmdbId)_s\(seasonNumber ?? 0)_e\(episodeNumber ?? 0)"
        }
        return downloads.first(where: { $0.id == id && ($0.status == .downloading || $0.status == .queued) }) != nil
    }
    
    func downloadItem(tmdbId: Int, isMovie: Bool, seasonNumber: Int? = nil, episodeNumber: Int? = nil) -> DownloadItem? {
        let id: String
        if isMovie {
            id = "dl_movie_\(tmdbId)"
        } else {
            id = "dl_ep_\(tmdbId)_s\(seasonNumber ?? 0)_e\(episodeNumber ?? 0)"
        }
        return downloads.first(where: { $0.id == id })
    }

    func completedDownloadItem(tmdbId: Int, isMovie: Bool, seasonNumber: Int? = nil, episodeNumber: Int? = nil) -> DownloadItem? {
        guard let item = downloadItem(
            tmdbId: tmdbId,
            isMovie: isMovie,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber
        ),
              item.status == .completed,
              localFileURL(for: item) != nil else {
            return nil
        }
        return item
    }
    
    /// Total storage used by downloads
    func calculateStorageUsed() -> Int64 {
        var total: Int64 = 0
        for item in downloads where item.status == .completed {
            if let fileName = item.localFileName {
                let url = downloadsDirectory.appendingPathComponent(fileName)
                if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int64 {
                    total += size
                }
            }
        }
        return total
    }

    private func effectiveHeaders(_ headers: [String: String], for url: URL) -> [String: String] {
        CloudflareBypassManager.shared.headersByApplyingCachedBypass(headers, for: url)
    }

    private func headerValue(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private func cloudflareHeaderRefreshChanged(base: [String: String], effective: [String: String]) -> Bool {
        headerValue("Cookie", in: base) != headerValue("Cookie", in: effective)
            || headerValue("User-Agent", in: base) != headerValue("User-Agent", in: effective)
    }

    private func effectiveSubtitleHeaders(for item: DownloadItem, subtitleURL: URL, streamURL: URL) -> [String: String] {
        let streamHost = streamURL.host?.lowercased()
        let subtitleHost = subtitleURL.host?.lowercased()
        let baseHeaders: [String: String]

        if let subtitleHeaders = item.subtitleHeaders {
            baseHeaders = subtitleHeaders
        } else if streamHost != nil, streamHost == subtitleHost {
            baseHeaders = item.headers
        } else {
            baseHeaders = [:]
        }

        return effectiveHeaders(baseHeaders, for: subtitleURL)
    }

    private func downloadBodyPreview(from location: URL, maxBytes: Int = 1_000_000) -> String {
        guard let handle = try? FileHandle(forReadingFrom: location) else { return "" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func challengeFailureMessage(for response: HTTPURLResponse, body: String) -> String? {
        let headers = CloudflareBypassManager.headersDictionary(from: response)
        if CloudflareBypassManager.isChallengeResponse(status: response.statusCode, body: body, headers: headers) {
            return "Cloudflare verification required. Open the source once and try again."
        }

        if !(200...299).contains(response.statusCode) {
            return "HTTP \(response.statusCode) while downloading"
        }

        return nil
    }
    
    // MARK: - Queue Processing
    
    private func processQueue() {
        let currentlyDownloading = downloads.filter { $0.status == .downloading }.count
        var slotsAvailable = maxConcurrentDownloads - currentlyDownloading
        
        guard slotsAvailable > 0 else { return }
        
        let queued = downloads.filter { $0.status == .queued }

        for item in queued {
            guard slotsAvailable > 0 else { break }

            if item.isHLS {
                if activeHLSDownloaders.count >= maxConcurrentHLSDownloads {
                    setQueuedMessage(id: item.id, message: "Waiting to package HLS")
                    continue
                }

                if let delayReason = hlsStartDelayReason() {
                    setQueuedMessage(id: item.id, message: delayReason)
                    Logger.shared.log("Delaying HLS packaging for \(item.displayTitle): \(delayReason)", type: "Download")
                    continue
                }
            }

            clearQueuedMessage(id: item.id)
            startDownload(item)
            slotsAvailable -= 1
        }
    }
    
    private func startDownload(_ item: DownloadItem) {
        guard let url = URL(string: item.streamURL) else {
            markFailed(id: item.id, error: "Invalid stream URL")
            return
        }
        
        // Route HLS streams to the guarded TS packager so VLC/mpv playback stays compatible.
        if item.isHLS {
            if let delayReason = hlsStartDelayReason() {
                setQueuedMessage(id: item.id, message: delayReason)
                Logger.shared.log("HLS queued instead of starting: \(delayReason)", type: "Download")
                return
            }
            startHLSDownload(item)
            return
        }
        
        let effectiveHeaders = effectiveHeaders(item.headers, for: url)
        let refreshedCloudflareHeaders = cloudflareHeaderRefreshChanged(base: item.headers, effective: effectiveHeaders)

        var request = URLRequest(url: url)
        for (key, value) in effectiveHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let task: URLSessionDownloadTask
        if let resumeData = resumeDataStore[item.id], !refreshedCloudflareHeaders {
            task = backgroundSession.downloadTask(withResumeData: resumeData)
            resumeDataStore.removeValue(forKey: item.id)
        } else {
            if resumeDataStore.removeValue(forKey: item.id) != nil, refreshedCloudflareHeaders {
                Logger.shared.log("Restarting download with refreshed Cloudflare headers: \(item.displayTitle)", type: "Download")
            }
            task = backgroundSession.downloadTask(with: request)
        }
        
        task.taskDescription = item.id
        activeTasks[item.id] = task
        
        if let index = downloads.firstIndex(where: { $0.id == item.id }) {
            DispatchQueue.main.async {
                self.downloads[index].status = .downloading
                if refreshedCloudflareHeaders {
                    self.downloads[index].progress = 0
                    self.downloads[index].downloadedBytes = 0
                    self.downloads[index].totalBytes = 0
                }
                self.saveDownloads()
            }
        }
        
        task.resume()
        
        // Also download subtitle if available
        if let subtitleURLString = item.subtitleURL, let subtitleURL = URL(string: subtitleURLString) {
            let subtitleHeaders = effectiveSubtitleHeaders(for: item, subtitleURL: subtitleURL, streamURL: url)
            downloadSubtitle(for: item.id, from: subtitleURL, headers: subtitleHeaders)
        }
        
        Logger.shared.log("Started download: \(item.displayTitle)", type: "Download")
    }
    
    private func startHLSDownload(_ item: DownloadItem) {
        guard let url = URL(string: item.streamURL) else {
            markFailed(id: item.id, error: "Invalid stream URL")
            return
        }

        if backgroundHLSPipelineEnabled {
            Logger.shared.log("Background HLS experiment enabled; using guarded single-lane TS packager", type: "Download")
        }
        
        let fileName = "\(item.id).ts"
        let destURL = downloadsDirectory.appendingPathComponent(fileName)

        let resumeSegment = item.hlsResumeSegmentIndex ?? 0
        let resumeBytes = item.hlsResumeByteCount ?? 0
        let pinnedVariant = item.hlsVariantURL.flatMap { URL(string: $0) }
        let expectedTotal = item.hlsTotalSegments ?? 0
        let refreshedHeaders = effectiveHeaders(item.headers, for: url)

        let downloader = HLSDownloader(
            streamURL: url,
            headers: refreshedHeaders,
            destinationURL: destURL,
            downloadId: item.id,
            resumeFromSegment: resumeSegment,
            resumeByteCount: resumeBytes,
            pinnedVariantURL: pinnedVariant,
            expectedTotalSegments: expectedTotal
        )

        downloader.onVariantResolved = { [weak self] variantURL, totalSegments in
            guard let self = self else { return }
            if let index = self.downloads.firstIndex(where: { $0.id == item.id }) {
                self.downloads[index].hlsVariantURL = variantURL.absoluteString
                self.downloads[index].hlsTotalSegments = totalSegments
                self.saveDownloads()
            }
        }

        downloader.onCheckpoint = { [weak self] segmentsWritten, byteCount in
            guard let self = self else { return }
            guard let index = self.downloads.firstIndex(where: { $0.id == item.id }),
                  self.downloads[index].status == .downloading else { return }
            self.downloads[index].hlsResumeSegmentIndex = segmentsWritten
            self.downloads[index].hlsResumeByteCount = byteCount
            self.downloads[index].downloadedBytes = byteCount
            // In-memory state is always current for instant pause/resume; throttle the
            // disk write to a couple of seconds. On a hard kill we lose at most the last
            // throttle window, and the partial is truncated back to the saved checkpoint.
            let now = Date()
            if let last = self.lastHLSCheckpointSave[item.id], now.timeIntervalSince(last) < 2.0 {
                return
            }
            self.lastHLSCheckpointSave[item.id] = now
            self.saveDownloads()
        }

        downloader.onProgress = { [weak self] progress in
            guard let self = self else { return }
            if let index = self.downloads.firstIndex(where: { $0.id == item.id }),
               self.downloads[index].status == .downloading {
                self.downloads[index].progress = progress
            }
        }
        
        downloader.onCompletion = { [weak self] result in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.activeHLSDownloaders.removeValue(forKey: item.id)

                switch result {
                case .success(let fileURL):
                    if let index = self.downloads.firstIndex(where: { $0.id == item.id }) {
                        self.downloads[index].status = .completed
                        self.downloads[index].progress = 1.0
                        self.downloads[index].localFileName = fileName
                        self.downloads[index].dateCompleted = Date()
                        
                        if let attrs = try? self.fileManager.attributesOfItem(atPath: fileURL.path),
                           let size = attrs[.size] as? Int64 {
                            self.downloads[index].totalBytes = size
                            self.downloads[index].downloadedBytes = size
                        }

                        // Checkpoint no longer needed once the file is finalized.
                        self.downloads[index].hlsResumeSegmentIndex = nil
                        self.downloads[index].hlsResumeByteCount = nil

                        self.saveDownloads()
                    }
                    self.lastHLSCheckpointSave.removeValue(forKey: item.id)
                    self.processQueue()
                    Logger.shared.log("HLS download completed: \(item.displayTitle) -> \(fileName)", type: "Download")

                case .failure(let error):
                    if let hlsError = error as? HLSError {
                        switch hlsError {
                        case .cancelled:
                            self.handleCancelledHLSDownload(id: item.id)
                            Logger.shared.log("HLS download cancelled: \(item.displayTitle)", type: "Download")
                        case .backgroundTimeExpired:
                            self.requeueInterruptedHLSDownload(id: item.id, message: "Waiting for app to reopen")
                            Logger.shared.log("HLS background time expired for \(item.displayTitle)", type: "Download")
                        case .systemBackoff(let reason):
                            self.requeueInterruptedHLSDownload(id: item.id, message: reason)
                            Logger.shared.log("HLS packaging paused for \(item.displayTitle): \(reason)", type: "Download")
                        default:
                            self.markFailed(id: item.id, error: error.localizedDescription)
                        }
                    } else {
                        self.markFailed(id: item.id, error: error.localizedDescription)
                    }
                }
            }
        }
        
        activeHLSDownloaders[item.id] = downloader
        
        if let index = downloads.firstIndex(where: { $0.id == item.id }) {
            DispatchQueue.main.async {
                self.downloads[index].status = .downloading
                // Only zero progress on a genuine fresh start. When resuming we keep the
                // checkpointed progress/bytes so the bar doesn't snap back to zero.
                if resumeSegment == 0 {
                    self.downloads[index].progress = 0
                    self.downloads[index].downloadedBytes = 0
                    self.downloads[index].totalBytes = 0
                }
                self.saveDownloads()
            }
        }

        downloader.start()
        
        // Also download subtitle if available
        if let subtitleURLString = item.subtitleURL, let subtitleURL = URL(string: subtitleURLString) {
            let subtitleHeaders = effectiveSubtitleHeaders(for: item, subtitleURL: subtitleURL, streamURL: url)
            downloadSubtitle(for: item.id, from: subtitleURL, headers: subtitleHeaders)
        }
        
        Logger.shared.log("Started HLS download: \(item.displayTitle)", type: "Download")
    }

    private func hlsStartDelayReason() -> String? {
        #if canImport(UIKit)
        if !backgroundHLSPipelineEnabled && UIApplication.shared.applicationState != .active {
            return "Waiting for app to reopen"
        }

        let thermalState = ProcessInfo.processInfo.thermalState
        if thermalState == .serious || thermalState == .critical {
            return "Paused for thermal state"
        }

        let device = UIDevice.current
        if device.batteryState == .unplugged && device.batteryLevel >= 0 && device.batteryLevel < 0.15 {
            return "Paused for low battery"
        }
        #endif

        if let freeBytes = availableDownloadCapacity(), freeBytes < minimumFreeBytesForHLS {
            return "Paused for low disk space"
        }

        return nil
    }

    private func availableDownloadCapacity() -> Int64? {
        do {
            let values = try downloadsDirectory.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])

            if let importantUsage = values.volumeAvailableCapacityForImportantUsage {
                return importantUsage
            }
            if let capacity = values.volumeAvailableCapacity {
                return Int64(capacity)
            }
        } catch {
            Logger.shared.log("Could not read free disk space for HLS: \(error.localizedDescription)", type: "Download")
        }

        return nil
    }

    private func setQueuedMessage(id: String, message: String) {
        DispatchQueue.main.async {
            guard let index = self.downloads.firstIndex(where: { $0.id == id }),
                  self.downloads[index].status == .queued,
                  self.downloads[index].error != message else { return }
            self.downloads[index].error = message
            self.saveDownloads()
        }
    }

    private func clearQueuedMessage(id: String) {
        DispatchQueue.main.async {
            guard let index = self.downloads.firstIndex(where: { $0.id == id }),
                  self.downloads[index].error != nil else { return }
            self.downloads[index].error = nil
            self.saveDownloads()
        }
    }
    
    /// Known video file extensions that VLC/mpv can play
    private static let knownVideoExtensions: Set<String> = [
        "mp4", "mkv", "webm", "mov", "avi", "wmv", "flv", "ts", "m2ts",
        "mpg", "mpeg", "ogv", "3gp", "m4v", "vob", "divx", "asf", "rm",
        "rmvb", "f4v", "mts"
    ]
    
    /// Known subtitle file extensions supported by the players
    private static let knownSubtitleExtensions: Set<String> = [
        "srt", "vtt", "ass", "ssa", "sub", "idx", "sup", "smi", "mks", "dfxp", "ttml"
    ]
    
    private func downloadSubtitle(for downloadId: String, from url: URL, headers: [String: String]) {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let subtitleTask = URLSession.shared.downloadTask(with: request) { [weak self] tempURL, response, error in
            guard let self = self, let tempURL = tempURL, error == nil else { return }

            if let httpResponse = response as? HTTPURLResponse {
                let body = self.downloadBodyPreview(from: tempURL)
                if let message = self.challengeFailureMessage(for: httpResponse, body: body) {
                    Logger.shared.log("Subtitle download skipped for \(downloadId): \(message)", type: "Download")
                    return
                }
            }
            
            // Determine subtitle extension from URL, Content-Type, or default to srt
            var ext = url.pathExtension.lowercased()
            if ext.isEmpty || !Self.knownSubtitleExtensions.contains(ext) {
                // Try Content-Type header
                if let httpResp = response as? HTTPURLResponse,
                   let contentType = httpResp.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                    if contentType.contains("vtt") || contentType.contains("webvtt") {
                        ext = "vtt"
                    } else if contentType.contains("ass") || contentType.contains("ssa") {
                        ext = "ass"
                    } else if contentType.contains("subrip") {
                        ext = "srt"
                    } else {
                        ext = "srt"
                    }
                } else {
                    ext = "srt"
                }
            }
            let fileName = "\(downloadId)_sub.\(ext)"
            let destURL = self.downloadsDirectory.appendingPathComponent(fileName)
            
            try? self.fileManager.removeItem(at: destURL)
            do {
                try self.fileManager.moveItem(at: tempURL, to: destURL)
                DispatchQueue.main.async {
                    if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                        self.downloads[index].subtitleFileName = fileName
                        self.saveDownloads()
                    }
                }
                Logger.shared.log("Downloaded subtitle for \(downloadId)", type: "Download")
            } catch {
                Logger.shared.log("Failed to save subtitle for \(downloadId): \(error)", type: "Download")
            }
        }
        subtitleTask.resume()
    }

    private func handleCancelledHLSDownload(id: String) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else {
            processQueue()
            return
        }

        if downloads[index].status == .downloading {
            downloads[index].status = .paused
        }

        saveDownloads()
        processQueue()
    }

    private func requeueInterruptedHLSDownload(id: String, message: String) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else {
            processQueue()
            return
        }

        if downloads[index].status == .downloading || downloads[index].status == .queued {
            downloads[index].status = .queued
            downloads[index].error = message
        }

        saveDownloads()
        processQueue()
    }
    
    private func markFailed(id: String, error: String) {
        activeTasks.removeValue(forKey: id)
        DispatchQueue.main.async {
            if let index = self.downloads.firstIndex(where: { $0.id == id }) {
                self.downloads[index].status = .failed
                self.downloads[index].error = error
                self.saveDownloads()
                self.processQueue()
            }
        }
        Logger.shared.log("Download failed: \(id) - \(error)", type: "Download")
    }
    
    private func resumeInterruptedDownloads() {
        for (index, item) in downloads.enumerated() where item.status == .downloading {
            DispatchQueue.main.async {
                self.downloads[index].status = .queued
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.processQueue()
        }
    }
    
    // MARK: - Orphan Cleanup
    
    /// Removes any files in the downloads directory that are not referenced by a tracked download.
    /// This catches files left behind by interrupted deletions, crashes, or code bugs.
    private func cleanOrphanedFiles() {
        let dir = downloadsDirectory
        guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        
        // Build set of all file names currently tracked
        var trackedFileNames = Set<String>()
        trackedFileNames.insert(".downloads_metadata.json")
        for item in downloads {
            if let f = item.localFileName { trackedFileNames.insert(f) }
            if let s = item.subtitleFileName { trackedFileNames.insert(s) }
            // Preserve in-progress HLS partials so paused/interrupted downloads can resume.
            if item.isHLS && item.status != .completed {
                trackedFileNames.insert(".\(item.id).ts.partial")
            }
        }
        
        var removedCount = 0
        var freedBytes: Int64 = 0
        for fileURL in contents {
            let name = fileURL.lastPathComponent
            if !trackedFileNames.contains(name) {
                if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                   let size = attrs[.size] as? Int64 {
                    freedBytes += size
                }
                try? fileManager.removeItem(at: fileURL)
                removedCount += 1
            }
        }
        
        if removedCount > 0 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            Logger.shared.log("Cleaned \(removedCount) orphaned file(s), freed \(formatter.string(fromByteCount: freedBytes))", type: "Download")
        }
    }
    
    // MARK: - Persistence
    
    private func saveDownloads() {
        // Capture the current downloads array on the calling thread (main) to avoid
        // a data race when encoding on the background write queue.
        let snapshot = self.downloads
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: self.persistenceURL, options: .atomic)
            } catch {
                Logger.shared.log("Failed to save downloads: \(error)", type: "Download")
            }
        }
    }
    
    private func loadDownloads() {
        guard fileManager.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            let loaded = try JSONDecoder().decode([DownloadItem].self, from: data)
            // Set synchronously so that cleanOrphanedFiles() and resumeInterruptedDownloads()
            // see the correct data immediately after this call.
            self.downloads = loaded
        } catch {
            Logger.shared.log("Failed to load downloads: \(error)", type: "Download")
        }
    }
}

// MARK: - URLSession Delegate

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let downloadId = downloadTask.taskDescription else { return }

        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            let body = downloadBodyPreview(from: location)
            if let message = challengeFailureMessage(for: httpResponse, body: body) {
                markFailed(id: downloadId, error: message)
                return
            }
        }
        
        // Determine file extension from response MIME type or URL
        let ext: String
        let urlExt = (downloadTask.currentRequest?.url?.pathExtension ?? downloadTask.originalRequest?.url?.pathExtension ?? "").lowercased()
        if let mimeType = downloadTask.response?.mimeType?.lowercased() {
            switch mimeType {
            // Video formats
            case "video/mp4":                                       ext = "mp4"
            case "video/x-matroska":                                ext = "mkv"
            case "video/webm":                                      ext = "webm"
            case "video/quicktime":                                  ext = "mov"
            case "video/x-msvideo":                                  ext = "avi"
            case "video/x-ms-wmv":                                   ext = "wmv"
            case "video/x-flv", "video/flv":                         ext = "flv"
            case "video/mp2t", "video/m2ts", "video/vnd.dlna.mpeg-tts": ext = "ts"
            case "video/3gpp":                                       ext = "3gp"
            case "video/ogg":                                        ext = "ogv"
            case "video/mpeg":                                       ext = "mpg"
            // HLS manifests
            case "application/x-mpegurl", "application/vnd.apple.mpegurl": ext = "m3u8"
            // Generic binary - trust the URL extension if it's a known video format
            case "application/octet-stream":
                ext = Self.knownVideoExtensions.contains(urlExt) ? urlExt : (urlExt.isEmpty ? "mp4" : urlExt)
            default:
                // Unknown MIME - prefer URL extension if it's a known format
                ext = Self.knownVideoExtensions.contains(urlExt) ? urlExt : "mp4"
            }
        } else {
            ext = Self.knownVideoExtensions.contains(urlExt) ? urlExt : (urlExt.isEmpty ? "mp4" : urlExt)
        }
        
        let fileName = "\(downloadId).\(ext)"
        let destURL = downloadsDirectory.appendingPathComponent(fileName)
        
        try? fileManager.removeItem(at: destURL)
        
        do {
            try fileManager.moveItem(at: location, to: destURL)
            
            DispatchQueue.main.async {
                if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                    self.downloads[index].status = .completed
                    self.downloads[index].progress = 1.0
                    self.downloads[index].localFileName = fileName
                    self.downloads[index].dateCompleted = Date()
                    
                    // Get final file size
                    if let attrs = try? self.fileManager.attributesOfItem(atPath: destURL.path),
                       let size = attrs[.size] as? Int64 {
                        self.downloads[index].totalBytes = size
                        self.downloads[index].downloadedBytes = size
                    }
                    
                    self.saveDownloads()
                    self.activeTasks.removeValue(forKey: downloadId)
                    self.processQueue()
                }
            }
            
            Logger.shared.log("Download completed: \(downloadId) -> \(fileName)", type: "Download")
        } catch {
            markFailed(id: downloadId, error: "Failed to save file: \(error.localizedDescription)")
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let downloadId = downloadTask.taskDescription else { return }
        
        // Throttle progress updates to max every 0.5 seconds to reduce UI churn
        let now = Date()
        if let lastUpdate = lastProgressUpdate[downloadId],
           now.timeIntervalSince(lastUpdate) < 0.5 {
            return
        }
        lastProgressUpdate[downloadId] = now
        
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        
        DispatchQueue.main.async {
            if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                self.downloads[index].progress = progress
                self.downloads[index].downloadedBytes = totalBytesWritten
                self.downloads[index].totalBytes = totalBytesExpectedToWrite
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadId = task.taskDescription else { return }
        
        if let error = error as NSError? {
            // Don't mark as failed if user cancelled
            if error.code == NSURLErrorCancelled {
                return
            }
            markFailed(id: downloadId, error: error.localizedDescription)
        }
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Re-attach custom headers that get stripped on redirect by background sessions
        guard let downloadId = task.taskDescription,
              let item = downloads.first(where: { $0.id == downloadId }) else {
            completionHandler(request)
            return
        }
        
        var updatedRequest = request
        let targetURL = updatedRequest.url ?? URL(string: item.streamURL)
        let refreshedHeaders = targetURL.map { effectiveHeaders(item.headers, for: $0) } ?? item.headers
        for (key, value) in refreshedHeaders {
            let lowerKey = key.lowercased()
            if lowerKey == "cookie" || lowerKey == "user-agent" {
                updatedRequest.setValue(value, forHTTPHeaderField: key)
            } else if updatedRequest.value(forHTTPHeaderField: key) == nil {
                updatedRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        completionHandler(updatedRequest)
    }
}
