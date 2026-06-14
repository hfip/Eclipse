//
//  Settings.swift
//  Eclipse
//
//  Created by Dawud Osman on 17/11/2025.
//
import SwiftUI
#if canImport(Network)
import Network
#endif
// helper Class & Enums
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    
    var id: String { self.rawValue }
}

enum MediaDetailElement: String, CaseIterable, Identifiable {
    case actions
    case overview
    case details
    case cast
    case ratingNotes
    case traktComments
    case episodes

    var id: String { rawValue }

    static let orderStorageKey = "mediaDetailElementOrder"
    static let hiddenStorageKey = "mediaDetailHiddenElements"
    static let legacyShowCastStorageKey = "showCastSection"

    static let defaultOrder: [MediaDetailElement] = [
        .overview,
        .actions,
        .details,
        .cast,
        .ratingNotes,
        .traktComments,
        .episodes
    ]

    var displayName: String {
        switch self {
        case .actions:
            return "Actions"
        case .overview:
            return "Overview"
        case .details:
            return "Details"
        case .cast:
            return "Cast"
        case .ratingNotes:
            return "Rating & Notes"
        case .traktComments:
            return "Trakt Reviews"
        case .episodes:
            return "Episodes"
        }
    }

    var settingsDescription: String {
        switch self {
        case .actions:
            return "Play, download, save, and collection controls."
        case .overview:
            return "Synopsis text for the title."
        case .details:
            return "Runtime, genres, dates, status, and ratings."
        case .cast:
            return "Principal cast list."
        case .ratingNotes:
            return "Your star rating, notes, and tracker sync shortcuts."
        case .traktComments:
            return "Community reviews and comments from Trakt."
        case .episodes:
            return "Seasons, specials, and episode list for series."
        }
    }

    var appliesToMovies: Bool {
        self != .episodes
    }

    var appliesToSeries: Bool {
        true
    }

    static var defaultOrderRawValue: String {
        rawValue(for: defaultOrder)
    }

    static func rawValue(for elements: [MediaDetailElement]) -> String {
        elements.map(\.rawValue).joined(separator: ",")
    }

    static func rawValue(for hiddenElements: Set<MediaDetailElement>) -> String {
        defaultOrder
            .filter { hiddenElements.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    static func orderedElements(from rawValue: String?) -> [MediaDetailElement] {
        var result: [MediaDetailElement] = []
        let rawItems = rawValue?
            .split(separator: ",")
            .map { String($0) } ?? []

        for rawItem in rawItems {
            guard let element = MediaDetailElement(rawValue: rawItem),
                  !result.contains(element) else { continue }
            result.append(element)
        }

        for element in defaultOrder where !result.contains(element) {
            result.append(element)
        }

        return result
    }

    static func orderedElements(defaults: UserDefaults = .standard) -> [MediaDetailElement] {
        orderedElements(from: defaults.string(forKey: orderStorageKey))
    }

    static func hiddenElements(from rawValue: String?, legacyShowCastSection: Bool = true) -> Set<MediaDetailElement> {
        var hidden = Set(
            (rawValue ?? "")
                .split(separator: ",")
                .compactMap { MediaDetailElement(rawValue: String($0)) }
        )

        if (rawValue ?? "").isEmpty, !legacyShowCastSection {
            hidden.insert(.cast)
        }

        return hidden
    }

    static func hiddenElements(defaults: UserDefaults = .standard) -> Set<MediaDetailElement> {
        hiddenElements(
            from: defaults.string(forKey: hiddenStorageKey),
            legacyShowCastSection: defaults.object(forKey: legacyShowCastStorageKey) as? Bool ?? true
        )
    }

    static func isVisible(
        _ element: MediaDetailElement,
        hiddenRawValue: String?,
        legacyShowCastSection: Bool = true
    ) -> Bool {
        !hiddenElements(from: hiddenRawValue, legacyShowCastSection: legacyShowCastSection).contains(element)
    }

    static func saveOrder(_ elements: [MediaDetailElement], defaults: UserDefaults = .standard) {
        defaults.set(rawValue(for: elements), forKey: orderStorageKey)
    }

    static func saveHiddenElements(_ hiddenElements: Set<MediaDetailElement>, defaults: UserDefaults = .standard) {
        defaults.set(rawValue(for: hiddenElements), forKey: hiddenStorageKey)
        defaults.set(!hiddenElements.contains(.cast), forKey: legacyShowCastStorageKey)
    }
}

enum ReaderDetailElement: String, CaseIterable, Identifiable {
    case overview
    case tags
    case ratingNotes
    case chapters

    var id: String { rawValue }

    static let orderStorageKey = "readerDetailElementOrder"
    static let hiddenStorageKey = "readerDetailHiddenElements"

    static let defaultOrder: [ReaderDetailElement] = [
        .overview,
        .tags,
        .ratingNotes,
        .chapters
    ]

    var displayName: String {
        switch self {
        case .overview:
            return "Overview"
        case .tags:
            return "Tags"
        case .ratingNotes:
            return "Rating & Notes"
        case .chapters:
            return "Chapters"
        }
    }

    var settingsDescription: String {
        switch self {
        case .overview:
            return "Synopsis text for the title."
        case .tags:
            return "Genres, tags, and source categories."
        case .ratingNotes:
            return "Your private star rating and reader notes."
        case .chapters:
            return "Source chapter list, language picker, and reading controls."
        }
    }

    static var defaultOrderRawValue: String {
        rawValue(for: defaultOrder)
    }

    static func rawValue(for elements: [ReaderDetailElement]) -> String {
        elements.map(\.rawValue).joined(separator: ",")
    }

    static func rawValue(for hiddenElements: Set<ReaderDetailElement>) -> String {
        defaultOrder
            .filter { hiddenElements.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    static func orderedElements(from rawValue: String?) -> [ReaderDetailElement] {
        var result: [ReaderDetailElement] = []
        let rawItems = rawValue?
            .split(separator: ",")
            .map { String($0) } ?? []

        for rawItem in rawItems {
            guard let element = ReaderDetailElement(rawValue: rawItem),
                  !result.contains(element) else { continue }
            result.append(element)
        }

        for element in defaultOrder where !result.contains(element) {
            result.append(element)
        }

        return result
    }

    static func orderedElements(defaults: UserDefaults = .standard) -> [ReaderDetailElement] {
        orderedElements(from: defaults.string(forKey: orderStorageKey))
    }

    static func hiddenElements(from rawValue: String?) -> Set<ReaderDetailElement> {
        Set(
            (rawValue ?? "")
                .split(separator: ",")
                .compactMap { ReaderDetailElement(rawValue: String($0)) }
        )
    }

    static func hiddenElements(defaults: UserDefaults = .standard) -> Set<ReaderDetailElement> {
        hiddenElements(from: defaults.string(forKey: hiddenStorageKey))
    }

    static func isVisible(_ element: ReaderDetailElement, hiddenRawValue: String?) -> Bool {
        !hiddenElements(from: hiddenRawValue).contains(element)
    }

    static func saveOrder(_ elements: [ReaderDetailElement], defaults: UserDefaults = .standard) {
        defaults.set(rawValue(for: elements), forKey: orderStorageKey)
    }

    static func saveHiddenElements(_ hiddenElements: Set<ReaderDetailElement>, defaults: UserDefaults = .standard) {
        defaults.set(rawValue(for: hiddenElements), forKey: hiddenStorageKey)
    }
}

enum MPVRenderBackend: String, CaseIterable, Identifiable {
    case openGL = "opengl"
    case metal = "metal"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openGL:
            return "OpenGL"
        case .metal:
            return "Metal"
        }
    }

    static let defaultBackend: MPVRenderBackend = .openGL
}

enum MPVMetalQualityProfile: String, CaseIterable, Identifiable {
    case auto = "auto"
    case balanced = "balanced"
    case lowHeat = "lowHeat"
    case sharp = "sharp"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return "Auto (Let Eclipse decide for your device)"
        case .balanced:
            return "Balanced"
        case .lowHeat:
            return "Low Heat"
        case .sharp:
            return "Sharp"
        }
    }

    var settingsDescription: String {
        switch self {
        case .auto:
            return "Keeps MoltenVK inline playback full quality and lets Eclipse lower PiP pacing if iOS reports serious thermal pressure."
        case .balanced:
            return "Keeps inline Metal full quality with standard PiP frame pacing."
        case .lowHeat:
            return "Keeps inline Metal full quality and lowers PiP frame pacing to reduce heat."
        case .sharp:
            return "Keeps inline Metal and PiP bridge quality as high as possible at higher power cost."
        }
    }

    static let defaultProfile: MPVMetalQualityProfile = .auto
}

struct MPVRenderBackendSupport {
    static let bundledMPVKitVersion = "0.41.0-eclipse-metal.1"
    static let bundledMPVKitRevision = "6b33a15f6d943d33505e26b66acc715870336c74"
    static let bundledMPVKitSupportsMoltenVKInlineRendering = true
    static let metalRendererEnabled = true

    #if ECLIPSE_MPVKIT_MOLTENVK_INLINE_RENDERER
    static let moltenVKInlineRendererAvailable = true
    #else
    static let moltenVKInlineRendererAvailable = false
    #endif

    #if ECLIPSE_MPVKIT_SAMPLE_BUFFER_PIP_BRIDGE
    static let sampleBufferPictureInPictureBridgeAvailable = true
    #else
    static let sampleBufferPictureInPictureBridgeAvailable = false
    #endif

    #if ECLIPSE_MPVKIT_METAL_BITMAP_SUBTITLES_VALIDATED
    static let metalBitmapSubtitlesValidated = true
    #else
    static let metalBitmapSubtitlesValidated = false
    #endif
    static let metalBitmapSubtitlesAllowed = true

    #if ECLIPSE_MPVKIT_METAL_LIVE_QUALITY_RECONFIGURE
    static let metalLiveQualityReconfigurationAvailable = true
    #else
    static let metalLiveQualityReconfigurationAvailable = false
    #endif

    static var moltenVKMetalBackendAvailable: Bool {
        bundledMPVKitSupportsMoltenVKInlineRendering
            && moltenVKInlineRendererAvailable
            && sampleBufferPictureInPictureBridgeAvailable
    }

    static var metalIsFullySupported: Bool {
        metalRendererEnabled && moltenVKMetalBackendAvailable
    }

    static var diagnosticsSummary: String {
        [
            "mpvKit=\(bundledMPVKitVersion)",
            "revision=\(bundledMPVKitRevision)",
            "moltenVKInline=\(bundledMPVKitSupportsMoltenVKInlineRendering)",
            "inlineRenderer=\(moltenVKInlineRendererAvailable)",
            "pipBridge=\(sampleBufferPictureInPictureBridgeAvailable)",
            "metalRendererEnabled=\(metalRendererEnabled)",
            "bitmapSubsAllowed=\(metalBitmapSubtitlesAllowed)",
            "bitmapSubsValidated=\(metalBitmapSubtitlesValidated)",
            "liveQuality=\(metalLiveQualityReconfigurationAvailable)"
        ].joined(separator: " ")
    }

    static var settingsDescription: String {
        if metalIsFullySupported {
            return "Applies to the next player session. Metal uses MPV MoltenVK inline playback with a sample-buffer bridge for PiP; OpenGL remains the fallback."
        }
        if !metalRendererEnabled {
            return "Applies to the next player session. OpenGL is active in this build."
        }
        return "Applies to the next player session. Metal is remembered but falls back to OpenGL until the MoltenVK inline renderer and PiP bridge are available."
    }

    static var settingsStatusLine: String {
        if metalIsFullySupported {
            return "Metal backend: MoltenVK inline renderer with sample-buffer PiP"
        }
        if !metalRendererEnabled {
            return "Metal backend: hidden in this build"
        }
        return "Metal backend: waiting for MoltenVK inline renderer and PiP bridge"
    }

    static func effectiveBackend(requested: MPVRenderBackend, hasMetalDevice: Bool) -> MPVRenderBackend {
        guard requested == .metal else { return .openGL }
        guard hasMetalDevice, metalIsFullySupported else { return .openGL }
        return .metal
    }

    static func fallbackReason(requested: MPVRenderBackend, hasMetalDevice: Bool) -> String? {
        guard requested == .metal else { return nil }
        guard metalRendererEnabled else { return "Metal renderer hidden in this build" }
        guard hasMetalDevice else { return "Metal device unavailable" }
        guard moltenVKInlineRendererAvailable else {
            return "MPVKit \(bundledMPVKitVersion) bundled in this build does not expose the MoltenVK inline renderer path"
        }
        guard sampleBufferPictureInPictureBridgeAvailable else {
            return "Eclipse sample-buffer PiP bridge is not enabled in this build"
        }
        return nil
    }
}

enum ExperimentalFeatureState {
    static let enabledKey = "experimentalFeaturesEnabled"
    static let lastChangedAtKey = "experimentalFeaturesLastChangedAt"

    static let mpvPreloadEnabledKey = "experimentalMPVPreloadEnabled"
    static let mpvSmoothTransitionEnabledKey = "experimentalMPVSmoothTransitionEnabled"
    static let mpvPreloadCellularEnabledKey = "experimentalMPVPreloadCellularEnabled"
    static let mpvPreloadWifiLimitMBKey = "experimentalMPVPreloadWifiLimitMB"
    static let mpvPreloadCellularLimitMBKey = "experimentalMPVPreloadCellularLimitMB"
    static let mpvShowRemainingTimeKey = "experimentalMPVShowRemainingTime"
    static let mpvPreciseProgressKey = "experimentalMPVPreciseProgress"
    static let mpvIgnoreSpecialSubtitleStylesKey = "experimentalMPVIgnoreSpecialSubtitleStyles"
    static let iCloudSyncEnabledKey = "experimentalICloudSyncEnabled"

    private(set) static var isEnabledAtLaunch: Bool = UserDefaults.standard.bool(forKey: enabledKey)

    static func configureLaunchState(defaults: UserDefaults = .standard) {
        registerDefaults(defaults: defaults)
        isEnabledAtLaunch = defaults.bool(forKey: enabledKey)
    }

    static func registerDefaults(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            enabledKey: false,
            mpvPreloadEnabledKey: true,
            mpvSmoothTransitionEnabledKey: true,
            mpvPreloadCellularEnabledKey: false,
            mpvPreloadWifiLimitMBKey: 256,
            mpvPreloadCellularLimitMBKey: 32,
            mpvShowRemainingTimeKey: true,
            mpvPreciseProgressKey: true,
            mpvIgnoreSpecialSubtitleStylesKey: false,
            iCloudSyncEnabledKey: false
        ])
    }

    static var currentStoredValue: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setStoredValue(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastChangedAtKey)
    }

    static var isMPVPlaybackDefault: Bool {
        let inApp = Settings.normalizedInAppPlayer(UserDefaults.standard.string(forKey: "inAppPlayer"))
        let external = UserDefaults.standard.string(forKey: "externalPlayer") ?? ""
        let usesInternalPlayer = external.isEmpty || external == "none" || external == "Default"
        return inApp == "mpv" && usesInternalPlayer
    }

    static var isMPVAdvancedPlaybackAvailable: Bool {
        isMPVPlaybackDefault
    }

    static var canUseExperimentalMPVPlayback: Bool {
        isMPVAdvancedPlaybackAvailable
    }
}

struct ExperimentalCloudSyncAvailability {
    let isAvailable: Bool
    let statusTitle: String
    let statusMessage: String

    static var current: ExperimentalCloudSyncAvailability {
#if os(iOS)
        if FileManager.default.ubiquityIdentityToken != nil {
            return ExperimentalCloudSyncAvailability(
                isAvailable: true,
                statusTitle: "iCloud Available",
                statusMessage: "This build has access to the signed-in iCloud account. Eclipse will sync only personal state and safe source definitions when enabled."
            )
        }
#endif
        return ExperimentalCloudSyncAvailability(
            isAvailable: false,
            statusTitle: "Unavailable in This Build",
            statusMessage: "iCloud requires the app entitlement. Sideloaded builds stay local-only; TestFlight builds can enable this once the entitlement is present."
        )
    }
}

@MainActor
final class ExperimentalCloudSyncManager: ObservableObject {
    static let shared = ExperimentalCloudSyncManager()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastStatusMessage: String = ""
    @Published private(set) var lastSyncDate: Date?

    private static let snapshotFileName = "EclipseExperimentalSync.json"
    private var lastAutomaticSync: Date?

    private init() {}

    func syncOnActivationIfNeeded(reason: String) {
        guard ExperimentalFeatureState.isEnabledAtLaunch,
              UserDefaults.standard.bool(forKey: ExperimentalFeatureState.iCloudSyncEnabledKey) else {
            return
        }

        if let lastAutomaticSync,
           Date().timeIntervalSince(lastAutomaticSync) < 300 {
            return
        }

        lastAutomaticSync = Date()
        pushLocalSnapshot(reason: reason)
    }

    func pushLocalSnapshot(reason: String = "manual") {
        runSyncTask(statusPrefix: "Synced") {
            try Self.writeLocalSnapshot(reason: reason)
        }
    }

    func restoreRemoteSnapshot() {
        runSyncTask(statusPrefix: "Restored") {
            try Self.restoreRemoteSnapshot()
        }
    }

    private func runSyncTask(statusPrefix: String, operation: @escaping () throws -> Date) {
        guard !isSyncing else { return }
        guard ExperimentalFeatureState.isEnabledAtLaunch,
              UserDefaults.standard.bool(forKey: ExperimentalFeatureState.iCloudSyncEnabledKey) else {
            lastStatusMessage = "Enable experimental iCloud sync first."
            return
        }
        guard ExperimentalCloudSyncAvailability.current.isAvailable else {
            lastStatusMessage = ExperimentalCloudSyncAvailability.current.statusMessage
            return
        }

        isSyncing = true
        Task {
            do {
                let date = try operation()
                self.lastSyncDate = date
                self.lastStatusMessage = "\(statusPrefix) \(Self.relativeSyncTime(for: date))"
                self.isSyncing = false
            } catch {
                self.lastStatusMessage = error.localizedDescription
                self.isSyncing = false
            }
        }
    }

    private static func writeLocalSnapshot(reason: String) throws -> Date {
#if os(iOS)
        let url = try snapshotURL()
        guard let data = BackupManager.shared.createExperimentalCloudSnapshotData() else {
            throw SyncError.snapshotEncodingFailed
        }
        try data.write(to: url, options: .atomic)
        Logger.shared.log("Experimental iCloud snapshot pushed reason=\(reason) bytes=\(data.count)", type: "iCloud")
        return Date()
#else
        throw SyncError.unavailable
#endif
    }

    private static func restoreRemoteSnapshot() throws -> Date {
#if os(iOS)
        let url = try snapshotURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SyncError.noSnapshot
        }
        let data = try Data(contentsOf: url)
        guard BackupManager.shared.restoreExperimentalCloudSnapshot(from: data) else {
            throw SyncError.snapshotRestoreFailed
        }
        Logger.shared.log("Experimental iCloud snapshot restored bytes=\(data.count)", type: "iCloud")
        return Date()
#else
        throw SyncError.unavailable
#endif
    }

#if os(iOS)
    private static func snapshotURL() throws -> URL {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw SyncError.unavailable
        }

        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents.appendingPathComponent(snapshotFileName)
    }
#endif

    private static func relativeSyncTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private enum SyncError: LocalizedError {
        case unavailable
        case noSnapshot
        case snapshotEncodingFailed
        case snapshotRestoreFailed

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "iCloud is unavailable for this build or account."
            case .noSnapshot:
                return "No iCloud snapshot was found."
            case .snapshotEncodingFailed:
                return "Could not prepare a safe iCloud snapshot."
            case .snapshotRestoreFailed:
                return "Could not restore the iCloud snapshot."
            }
        }
    }
}

final class ExperimentalMPVPreloadManager {
    static let shared = ExperimentalMPVPreloadManager()

    private let fileManager = FileManager.default
    private let maxStarterBytes = 8 * 1024 * 1024
    private var activeKeys = Set<String>()
    private let lock = NSLock()
#if canImport(Network)
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "dev.soupy.eclipse.experimental-mpv-preload.path")
    private var currentPath: NWPath?
#endif

    var cacheDirectory: URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("ExperimentalMPVPreload", isDirectory: true)
    }

    private init() {
#if canImport(Network)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.currentPath = path
        }
        pathMonitor.start(queue: pathQueue)
#endif
    }

    var cacheSizeBytes: Int64 {
        directorySize(at: cacheDirectory)
    }

    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        lock.lock()
        activeKeys.removeAll()
        lock.unlock()
    }

    func noteNextEpisodeCandidate(showId: Int, seasonNumber: Int, episodeNumber: Int) {
        guard ExperimentalFeatureState.isMPVAdvancedPlaybackAvailable,
              UserDefaults.standard.bool(forKey: ExperimentalFeatureState.mpvSmoothTransitionEnabledKey) else {
            return
        }
        Logger.shared.log(
            "MPV advanced smooth transition staged candidate show=\(showId) S\(seasonNumber)E\(episodeNumber)",
            type: "MPV"
        )
    }

    func prewarm(url: URL, headers: [String: String]?, label: String) {
        guard ExperimentalFeatureState.isMPVAdvancedPlaybackAvailable,
              UserDefaults.standard.bool(forKey: ExperimentalFeatureState.mpvPreloadEnabledKey),
              shouldPreload(url: url) else {
            return
        }

        let key = cacheKey(for: url)
        lock.lock()
        if activeKeys.contains(key) {
            lock.unlock()
            return
        }
        activeKeys.insert(key)
        lock.unlock()

        Task.detached(priority: .utility) { [weak self] in
            defer {
                self?.lock.lock()
                self?.activeKeys.remove(key)
                self?.lock.unlock()
            }
            await self?.writeStarterCache(url: url, headers: headers, key: key, label: label)
        }
    }

    private func shouldPreload(url: URL) -> Bool {
        guard url.scheme == "http" || url.scheme == "https" else { return false }
        guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return false }
        guard ProcessInfo.processInfo.thermalState != .serious,
              ProcessInfo.processInfo.thermalState != .critical else { return false }
        guard freeDiskBytes() > 750 * 1024 * 1024 else { return false }
        guard respectsCurrentNetworkPolicy() else { return false }
        guard cacheSizeBytes < currentCacheLimitBytes() else { return false }

        let path = url.pathExtension.lowercased()
        return path == "m3u8" || path == "mp4" || path == "mkv" || path == "mov" || path.isEmpty
    }

    private func respectsCurrentNetworkPolicy() -> Bool {
#if canImport(Network)
        if currentPath?.usesInterfaceType(.cellular) == true {
            return UserDefaults.standard.bool(forKey: ExperimentalFeatureState.mpvPreloadCellularEnabledKey)
        }
#endif
        return true
    }

    private func currentCacheLimitBytes() -> Int64 {
#if canImport(Network)
        if currentPath?.usesInterfaceType(.cellular) == true {
            let mb = UserDefaults.standard.integer(forKey: ExperimentalFeatureState.mpvPreloadCellularLimitMBKey)
            return Int64(max(8, mb)) * 1024 * 1024
        }
#endif
        let mb = UserDefaults.standard.integer(forKey: ExperimentalFeatureState.mpvPreloadWifiLimitMBKey)
        return Int64(max(32, mb)) * 1024 * 1024
    }

    private func writeStarterCache(url: URL, headers: [String: String]?, key: String, label: String) async {
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18)
            headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            if url.pathExtension.lowercased() != "m3u8" {
                request.setValue("bytes=0-\(maxStarterBytes - 1)", forHTTPHeaderField: "Range")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty else {
                return
            }

            let trimmed = data.count > maxStarterBytes ? data.prefix(maxStarterBytes) : data[...]
            let target = cacheDirectory.appendingPathComponent(key).appendingPathExtension("starter")
            try Data(trimmed).write(to: target, options: .atomic)
            Logger.shared.log("MPV advanced preload cached \(data.count) bytes for \(label)", type: "MPV")
        } catch {
            Logger.shared.log("MPV advanced preload skipped for \(label): \(error.localizedDescription)", type: "MPV")
        }
    }

    private func cacheKey(for url: URL) -> String {
        let raw = url.absoluteString.data(using: .utf8) ?? Data()
        return raw.map { String(format: "%02x", $0) }.joined().prefix(96).description
    }

    private func directorySize(at url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }
            total += Int64(fileSize)
        }
        return total
    }

    private func freeDiskBytes() -> Int64 {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let values = try? caches.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

class Settings: ObservableObject {
    static let shared = Settings()
    
    @Published var accentColor: Color {
        didSet {
            saveAccentColor(accentColor)
        }
    }
    @Published var readerAccentColor: Color {
        didSet {
            saveReaderAccentColor(readerAccentColor)
        }
    }
    @Published var selectedAppearance: Appearance {
        didSet {
            UserDefaults.standard.set(selectedAppearance.rawValue, forKey: "selectedAppearance")
            updateAppearance()
        }
    }
    @Published var readerSelectedAppearance: Appearance {
        didSet {
            UserDefaults.standard.set(readerSelectedAppearance.rawValue, forKey: "readerSelectedAppearance")
            updateAppearance()
        }
    }

    var effectiveAccentColor: Color {
        UserDefaults.standard.bool(forKey: "showKanzen") && !EclipseTheme.shared.globalAppearanceEnabled ? readerAccentColor : accentColor
    }

    var effectiveAppearance: Appearance {
        UserDefaults.standard.bool(forKey: "showKanzen") && !EclipseTheme.shared.globalAppearanceEnabled ? readerSelectedAppearance : selectedAppearance
    }
    
    // In-App Player Settings
    private func migratedBool(genericKey: String, legacyKey: String, defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: genericKey) == nil {
            let value = UserDefaults.standard.object(forKey: legacyKey) as? Bool ?? defaultValue
            UserDefaults.standard.set(value, forKey: genericKey)
            return value
        }
        return UserDefaults.standard.bool(forKey: genericKey)
    }

    private func migratedDouble(genericKey: String, legacyKey: String, defaultValue: Double) -> Double {
        if UserDefaults.standard.object(forKey: genericKey) == nil {
            let value = UserDefaults.standard.double(forKey: legacyKey)
            let resolved = value > 0 ? value : defaultValue
            UserDefaults.standard.set(resolved, forKey: genericKey)
            return resolved
        }
        let value = UserDefaults.standard.double(forKey: genericKey)
        return value > 0 ? value : defaultValue
    }

    static func normalizedInAppPlayer(_ rawValue: String?) -> String {
        rawValue == "VLC" ? "mpv" : (rawValue ?? "mpv")
    }

    var enableSubtitlesByDefault: Bool {
        get { UserDefaults.standard.bool(forKey: "enableSubtitlesByDefault") }
        set { UserDefaults.standard.set(newValue, forKey: "enableSubtitlesByDefault") }
    }
    
    var defaultSubtitleLanguage: String {
        get { UserDefaults.standard.string(forKey: "defaultSubtitleLanguage") ?? "eng" }
        set { UserDefaults.standard.set(newValue, forKey: "defaultSubtitleLanguage") }
    }
    
    var preferredAnimeAudioLanguage: String {
        get { UserDefaults.standard.string(forKey: "preferredAnimeAudioLanguage") ?? "jpn" }
        set { UserDefaults.standard.set(newValue, forKey: "preferredAnimeAudioLanguage") }
    }

    var playerBrightnessGestureEnabled: Bool {
        get { migratedBool(genericKey: "playerBrightnessGestureEnabled", legacyKey: "vlcBrightnessGestureEnabled", defaultValue: false) }
        set { UserDefaults.standard.set(newValue, forKey: "playerBrightnessGestureEnabled") }
    }

    var playerVolumeGestureEnabled: Bool {
        get { migratedBool(genericKey: "playerVolumeGestureEnabled", legacyKey: "vlcVolumeGestureEnabled", defaultValue: false) }
        set { UserDefaults.standard.set(newValue, forKey: "playerVolumeGestureEnabled") }
    }

    var playerTwoFingerTapPlayPauseEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "playerTwoFingerTapPlayPauseEnabled") == nil {
                if let legacyValue = UserDefaults.standard.object(forKey: "mpvTwoFingerTapEnabled") as? Bool {
                    UserDefaults.standard.set(legacyValue, forKey: "playerTwoFingerTapPlayPauseEnabled")
                    return legacyValue
                }
                UserDefaults.standard.set(true, forKey: "playerTwoFingerTapPlayPauseEnabled")
            }
            return UserDefaults.standard.bool(forKey: "playerTwoFingerTapPlayPauseEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "playerTwoFingerTapPlayPauseEnabled") }
    }

    var defaultPlaybackSpeed: Double {
        get {
            let savedSpeed = UserDefaults.standard.double(forKey: "defaultPlaybackSpeed")
            return savedSpeed > 0 ? savedSpeed : 1.0
        }
        set { UserDefaults.standard.set(newValue, forKey: "defaultPlaybackSpeed") }
    }

    var playerDoubleTapSeekEnabled: Bool {
        get { migratedBool(genericKey: "playerDoubleTapSeekEnabled", legacyKey: "vlcDoubleTapSeekEnabled", defaultValue: true) }
        set { UserDefaults.standard.set(newValue, forKey: "playerDoubleTapSeekEnabled") }
    }

    var playerDoubleTapSeekSeconds: Double {
        get { migratedDouble(genericKey: "playerDoubleTapSeekSeconds", legacyKey: "vlcDoubleTapSeekSeconds", defaultValue: 10.0) }
        set { UserDefaults.standard.set(newValue, forKey: "playerDoubleTapSeekSeconds") }
    }

    var playerOpenSubtitlesEnabled: Bool {
        get { migratedBool(genericKey: "playerOpenSubtitlesEnabled", legacyKey: "vlcOpenSubtitlesEnabled", defaultValue: false) }
        set { UserDefaults.standard.set(newValue, forKey: "playerOpenSubtitlesEnabled") }
    }

    var playerOpenSubtitlesAutoFallbackEnabled: Bool {
        get { migratedBool(genericKey: "playerOpenSubtitlesAutoFallbackEnabled", legacyKey: "vlcOpenSubtitlesAutoFallbackEnabled", defaultValue: true) }
        set { UserDefaults.standard.set(newValue, forKey: "playerOpenSubtitlesAutoFallbackEnabled") }
    }

    var playerPerformanceOverlayEnabled: Bool {
        get { false }
        set { UserDefaults.standard.set(false, forKey: "playerPerformanceOverlayEnabled") }
    }

    var mpvForegroundFPS: Int {
        get {
            UserDefaults.standard.integer(forKey: "mpvForegroundFPS") == 60 ? 60 : 30
        }
        set {
            UserDefaults.standard.set(newValue == 60 ? 60 : 30, forKey: "mpvForegroundFPS")
        }
    }

    var mpvRenderBackend: MPVRenderBackend {
        get {
            let raw = UserDefaults.standard.string(forKey: "mpvRenderBackend")
                ?? MPVRenderBackend.defaultBackend.rawValue
            let requested = MPVRenderBackend(rawValue: raw) ?? .defaultBackend
            return MPVRenderBackendSupport.effectiveBackend(requested: requested, hasMetalDevice: true)
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "mpvRenderBackend")
        }
    }

    var mpvMetalQualityProfile: MPVMetalQualityProfile {
        get {
            let raw = UserDefaults.standard.string(forKey: "mpvMetalQualityProfile")
                ?? MPVMetalQualityProfile.defaultProfile.rawValue
            return MPVMetalQualityProfile(rawValue: raw) ?? .defaultProfile
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "mpvMetalQualityProfile")
        }
    }

    var mpvAppExitPictureInPictureEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "mpvAppExitPictureInPictureEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "mpvAppExitPictureInPictureEnabled") }
    }

    var smartInAppPlayerChoosingEnabled: Bool {
        get { false }
        set { UserDefaults.standard.set(false, forKey: "smartInAppPlayerChoosingEnabled") }
    }

    var playerSubtitleAppearanceEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "playerSubtitleAppearanceEnabled") == nil {
                let legacy = UserDefaults.standard.object(forKey: "enableVLCSubtitleEditMenu") as? Bool ?? true
                UserDefaults.standard.set(legacy, forKey: "playerSubtitleAppearanceEnabled")
                return legacy
            }
            return UserDefaults.standard.bool(forKey: "playerSubtitleAppearanceEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "playerSubtitleAppearanceEnabled") }
    }
    
    enum PlayerChoice: String {
        case mpv
    }
    
    var playerChoice: PlayerChoice {
        get {
            let normalized = Self.normalizedInAppPlayer(UserDefaults.standard.string(forKey: "inAppPlayer"))
            if normalized != UserDefaults.standard.string(forKey: "inAppPlayer") {
                UserDefaults.standard.set(normalized, forKey: "inAppPlayer")
            }
            return .mpv
        }
        set {
            UserDefaults.standard.set("mpv", forKey: "inAppPlayer")
        }
    }
    
    init() {
        let resolvedAccentColor: Color
        if let colorData = UserDefaults.standard.data(forKey: "accentColor"),
           let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
            resolvedAccentColor = Color(uiColor)
        } else {
            resolvedAccentColor = .accentColor
        }
        self.accentColor = resolvedAccentColor
        if let colorData = UserDefaults.standard.data(forKey: "readerAccentColor"),
           let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
            self.readerAccentColor = Color(uiColor)
        } else {
            self.readerAccentColor = resolvedAccentColor
        }
        let resolvedAppearance: Appearance
        if let appearanceRawValue = UserDefaults.standard.string(forKey: "selectedAppearance"),
           let appearance = Appearance(rawValue: appearanceRawValue) {
            resolvedAppearance = appearance
        } else {
            resolvedAppearance = .system
        }
        self.selectedAppearance = resolvedAppearance
        if let appearanceRawValue = UserDefaults.standard.string(forKey: "readerSelectedAppearance"),
           let appearance = Appearance(rawValue: appearanceRawValue) {
            self.readerSelectedAppearance = appearance
        } else {
            self.readerSelectedAppearance = resolvedAppearance
        }
        updateAppearance()
    }
    
    private func saveAccentColor(_ color: Color) {
        
        let uiColor = UIColor(color)
        do {
            let colorData = try NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: false)
            UserDefaults.standard.set(colorData, forKey: "accentColor")
        } catch {
            ReaderLogger.shared.log("Failed to save accent color: \(error.localizedDescription)")
        }
    }

    private func saveReaderAccentColor(_ color: Color) {
        let uiColor = UIColor(color)
        do {
            let colorData = try NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: false)
            UserDefaults.standard.set(colorData, forKey: "readerAccentColor")
        } catch {
            ReaderLogger.shared.log("Failed to save reader accent color: \(error.localizedDescription)")
        }
    }
    
    func updateAppearance() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        switch effectiveAppearance {
        case .system:
            windowScene.windows.first?.overrideUserInterfaceStyle = .unspecified
        case .light:
            windowScene.windows.first?.overrideUserInterfaceStyle = .light
        case .dark:
            windowScene.windows.first?.overrideUserInterfaceStyle = .dark
        }
    }
}
