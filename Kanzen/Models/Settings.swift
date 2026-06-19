//
//  Settings.swift
//  Eclipse
//
//  Created by Dawud Osman on 17/11/2025.
//
import SwiftUI
#if canImport(CryptoKit)
import CryptoKit
#endif
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
    case stills
    case trailers

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
        .episodes,
        .stills,
        .trailers
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
        case .stills:
            return "Stills"
        case .trailers:
            return "Trailers"
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
        case .stills:
            return "Backdrop stills and gallery images."
        case .trailers:
            return "Trailer and teaser cards."
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

    static let defaultBackend: MPVRenderBackend = .metal
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
            return "Starts sharp and automatically lowers Metal resolution, frame pacing, and high-bit-depth HDR work when the device gets hot, then restores quality as it cools."
        case .balanced:
            return "Caps Metal/sample-buffer output below native 4K while preserving high-bit-depth HDR for lower heat with minimal visible softening."
        case .lowHeat:
            return "Caps Metal/sample-buffer output aggressively and disables high-bit-depth HDR to minimize heat and power use; video looks softer."
        case .sharp:
            return "Allows full-resolution Metal output and high-bit-depth HDR for maximum fidelity at higher power cost."
        }
    }

    static let defaultProfile: MPVMetalQualityProfile = .auto
}

/// Controls how the Metal/gpu-next renderer treats HDR (HDR10/HLG/Dolby Vision P8) content.
enum MPVHDRMode: String, CaseIterable, Identifiable {
    /// Pass HDR through to the display when it has EDR headroom; tone-map to SDR otherwise.
    case auto
    /// Always request HDR/EDR output for HDR content, regardless of display detection.
    case hdr
    /// Always tone-map HDR down to SDR for a consistent look across every display.
    case sdr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .hdr: return "Always HDR"
        case .sdr: return "Always SDR"
        }
    }

    var settingsDescription: String {
        switch self {
        case .auto:
            return "Outputs true HDR on HDR-capable displays and cleanly tone-maps to SDR everywhere else. Recommended."
        case .hdr:
            return "Always sends HDR content to the display as HDR. May look washed out or too dark on non-HDR screens."
        case .sdr:
            return "Always tone-maps HDR content down to SDR for a consistent picture on any display."
        }
    }

    static let defaultMode: MPVHDRMode = .auto
}

struct MPVRenderBackendSupport {
    static let bundledMPVKitVersion = "0.41.0-eclipse-metal.2"
    static let bundledMPVKitRevision = "80a278beba7e6a348cdb2269f4d9816b7a520038"
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
            "gpuSampleBufferPiP=\(sampleBufferPictureInPictureBridgeAvailable)",
            "metalRendererEnabled=\(metalRendererEnabled)",
            "bitmapSubsAllowed=\(metalBitmapSubtitlesAllowed)",
            "bitmapSubsValidated=\(metalBitmapSubtitlesValidated)",
            "liveQuality=\(metalLiveQualityReconfigurationAvailable)"
        ].joined(separator: " ")
    }

    static var settingsDescription: String {
        if metalIsFullySupported {
            return "Applies to the next player session. Metal is the default MPV renderer and uses MoltenVK inline playback with a GPU sample-buffer handoff for PiP; OpenGL remains the fallback."
        }
        if !metalRendererEnabled {
            return "Applies to the next player session. OpenGL is active in this build."
        }
        return "Applies to the next player session. Metal is remembered but falls back to OpenGL until the MoltenVK inline renderer is available."
    }

    static var settingsStatusLine: String {
        if metalIsFullySupported {
            return "Metal backend: MoltenVK inline renderer with GPU sample-buffer PiP handoff"
        }
        if !metalRendererEnabled {
            return "Metal backend: hidden in this build"
        }
        return "Metal backend: waiting for MoltenVK inline renderer"
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
    static let mpvPreloadAutoClearKey = "experimentalMPVPreloadAutoClear"
    static let mpvShowRemainingTimeKey = "experimentalMPVShowRemainingTime"
    static let mpvPreciseProgressKey = "experimentalMPVPreciseProgress"
    static let mpvIgnoreSpecialSubtitleStylesKey = "experimentalMPVIgnoreSpecialSubtitleStyles"
    static let iCloudSyncEnabledKey = "experimentalICloudSyncEnabled"

    static let mpvPreloadWifiDefaultLimitMB = 2048
    static let mpvPreloadCellularDefaultLimitMB = 500
    static let mpvPreloadWifiLimitRange = 32...2048
    static let mpvPreloadCellularLimitRange = 8...2048

    static func clampedMPVPreloadWifiLimitMB(_ value: Int) -> Int {
        max(mpvPreloadWifiLimitRange.lowerBound, min(value, mpvPreloadWifiLimitRange.upperBound))
    }

    static func clampedMPVPreloadCellularLimitMB(_ value: Int) -> Int {
        max(mpvPreloadCellularLimitRange.lowerBound, min(value, mpvPreloadCellularLimitRange.upperBound))
    }

    static func resolvedMPVPreloadWifiLimitMB(_ value: Int) -> Int {
        clampedMPVPreloadWifiLimitMB(value > 0 ? value : mpvPreloadWifiDefaultLimitMB)
    }

    static func resolvedMPVPreloadCellularLimitMB(_ value: Int) -> Int {
        clampedMPVPreloadCellularLimitMB(value > 0 ? value : mpvPreloadCellularDefaultLimitMB)
    }

    // Modern interface is the default. Use object(forKey:) so a fresh install
    // (key unset, before registerDefaults runs) still resolves to `true`.
    private(set) static var isEnabledAtLaunch: Bool = (UserDefaults.standard.object(forKey: enabledKey) as? Bool) ?? true

    static func configureLaunchState(defaults: UserDefaults = .standard) {
        registerDefaults(defaults: defaults)
        isEnabledAtLaunch = (defaults.object(forKey: enabledKey) as? Bool) ?? true
    }

    static func registerDefaults(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            enabledKey: true,
            mpvPreloadEnabledKey: true,
            mpvSmoothTransitionEnabledKey: true,
            mpvPreloadCellularEnabledKey: false,
            mpvPreloadWifiLimitMBKey: mpvPreloadWifiDefaultLimitMB,
            mpvPreloadCellularLimitMBKey: mpvPreloadCellularDefaultLimitMB,
            mpvPreloadAutoClearKey: true,
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

    static var isMetalMPVPlaybackDefault: Bool {
        guard isMPVPlaybackDefault else { return false }
        let raw = UserDefaults.standard.string(forKey: "mpvRenderBackend") ?? MPVRenderBackend.defaultBackend.rawValue
        let requested = MPVRenderBackend(rawValue: raw) ?? .defaultBackend
        return MPVRenderBackendSupport.effectiveBackend(requested: requested, hasMetalDevice: true) == .metal
    }

    static var mpvAdvancedPlaybackUnavailableReason: String? {
        let inApp = Settings.normalizedInAppPlayer(UserDefaults.standard.string(forKey: "inAppPlayer"))
        guard inApp == "mpv" else { return "mpv-not-default" }

        let external = UserDefaults.standard.string(forKey: "externalPlayer") ?? ""
        let usesInternalPlayer = external.isEmpty || external == "none" || external == "Default"
        guard usesInternalPlayer else { return "external-player-enabled" }

        let raw = UserDefaults.standard.string(forKey: "mpvRenderBackend") ?? MPVRenderBackend.defaultBackend.rawValue
        let requested = MPVRenderBackend(rawValue: raw) ?? .defaultBackend
        guard requested == .metal else { return "renderer-not-metal" }

        guard MPVRenderBackendSupport.effectiveBackend(requested: requested, hasMetalDevice: true) == .metal else {
            return MPVRenderBackendSupport.fallbackReason(requested: requested, hasMetalDevice: true) ?? "metal-renderer-unavailable"
        }

        return nil
    }

    static var isMPVAdvancedPlaybackAvailable: Bool {
        mpvAdvancedPlaybackUnavailableReason == nil
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
    private static let lastSeenRemoteModificationKey = "experimentalICloudSyncLastSeenRemoteModificationAt"
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
        syncSnapshot(reason: reason)
    }

    func syncSnapshot(reason: String = "manual") {
        runSyncTask(statusPrefix: "Synced") {
            try Self.reconcileSnapshot(reason: reason)
        }
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
        markRemoteSnapshotSeen(at: url, fallbackDate: Date())
        Logger.shared.log("Experimental iCloud snapshot pushed reason=\(reason) bytes=\(data.count)", type: "iCloud")
        return Date()
#else
        throw SyncError.unavailable
#endif
    }

    private static func reconcileSnapshot(reason: String) throws -> Date {
#if os(iOS)
        let url = try snapshotURL()
        if hasUnseenRemoteSnapshot(at: url) {
            Logger.shared.log("Experimental iCloud snapshot restoring newer remote reason=\(reason)", type: "iCloud")
            return try restoreRemoteSnapshot()
        }
        return try writeLocalSnapshot(reason: reason)
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
        markRemoteSnapshotSeen(at: url, fallbackDate: Date())
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

    private static func hasUnseenRemoteSnapshot(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let modificationDate = remoteModificationDate(at: url) else {
            return false
        }

        let lastSeen = UserDefaults.standard.double(forKey: lastSeenRemoteModificationKey)
        guard lastSeen > 0 else { return true }
        return modificationDate.timeIntervalSince1970 > lastSeen + 1
    }

    private static func markRemoteSnapshotSeen(at url: URL, fallbackDate: Date) {
        let modificationDate = remoteModificationDate(at: url) ?? fallbackDate
        UserDefaults.standard.set(modificationDate.timeIntervalSince1970, forKey: lastSeenRemoteModificationKey)
    }

    private static func remoteModificationDate(at url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
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

struct ExperimentalMPVPreloadCachedStarter {
    let data: Data
    let contentType: String?
    let totalLength: Int64?
    let statusCode: Int
    let isPlaylist: Bool
}

final class ExperimentalMPVPreloadManager {
    static let shared = ExperimentalMPVPreloadManager()

    private let fileManager = FileManager.default
    private let maxStarterBytes = 8 * 1024 * 1024
    private let maxStarterAge: TimeInterval = 30 * 60
    private let cacheKeyMigrationDefaultsKey = "experimentalMPVPreloadHashedCacheKeysMigrated"
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
        migrateLegacyCacheFileNamesIfNeeded()
        // Auto-clear (default ON): wipe any warmup starters left over from a previous app
        // session at startup, so the cache never accumulates across launches. Starters are
        // only useful within a session (30-minute TTL), so this never affects same-session
        // warmups. When disabled, the cache is still bounded by the size limit + TTL.
        if Self.autoClearEnabled {
            clearCache()
        }
    }

    static var autoClearEnabled: Bool {
        (UserDefaults.standard.object(forKey: ExperimentalFeatureState.mpvPreloadAutoClearKey) as? Bool) ?? true
    }

    var cacheSizeBytes: Int64 {
        directorySize(at: cacheDirectory)
    }

    func shouldUsePlaybackProxy(for url: URL) -> Bool {
        playbackProxySkipReason(for: url) == nil
    }

    func playbackProxySkipReason(for url: URL) -> String? {
        if let reason = ExperimentalFeatureState.mpvAdvancedPlaybackUnavailableReason {
            return reason
        }
        guard UserDefaults.standard.bool(forKey: ExperimentalFeatureState.mpvPreloadEnabledKey) else {
            return "warmup-disabled"
        }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return "non-http-url" }
        guard !isLoopbackURL(url) else { return "loopback-proxy-url" }
        let path = url.pathExtension.lowercased()
        return isWarmupCompatiblePathExtension(path) ? nil : "unsupported-extension-\(path.isEmpty ? "empty" : path)"
    }

    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        lock.lock()
        activeKeys.removeAll()
        lock.unlock()
    }

    func noteNextEpisodeCandidate(showId: Int, seasonNumber: Int, episodeNumber: Int) {
        if let reason = ExperimentalFeatureState.mpvAdvancedPlaybackUnavailableReason {
            Logger.shared.log(
                "MPV advanced smooth transition skipped show=\(showId) S\(seasonNumber)E\(episodeNumber) reason=\(reason)",
                type: "MPV"
            )
            return
        }
        guard UserDefaults.standard.bool(forKey: ExperimentalFeatureState.mpvSmoothTransitionEnabledKey) else {
            Logger.shared.log(
                "MPV advanced smooth transition skipped show=\(showId) S\(seasonNumber)E\(episodeNumber) reason=staging-disabled",
                type: "MPV"
            )
            return
        }
        Logger.shared.log(
            "MPV advanced smooth transition staged candidate show=\(showId) S\(seasonNumber)E\(episodeNumber)",
            type: "MPV"
        )
    }

    func prewarm(url: URL, headers: [String: String]?, label: String) {
        let safeLabel = label.isEmpty ? "unknown" : label
        let headerKeys = (headers ?? [:]).keys.sorted().joined(separator: ",")
        if let reason = ExperimentalFeatureState.mpvAdvancedPlaybackUnavailableReason {
            Logger.shared.log("MPV warmup skipped for \(safeLabel): \(reason)", type: "MPV")
            return
        }
        if let skipReason = preloadSkipReason(for: url) {
            Logger.shared.log("MPV warmup skipped for \(safeLabel): \(skipReason)", type: "MPV")
            return
        }

        if cachedStarter(for: url, headers: headers) != nil {
            Logger.shared.log("MPV warmup cache already ready for \(safeLabel) target=\(logURLSummary(url)) headerKeys=[\(headerKeys)]", type: "MPV")
            return
        }

        let key = cacheKey(for: url, headers: headers)
        lock.lock()
        if activeKeys.contains(key) {
            lock.unlock()
            Logger.shared.log("MPV warmup coalesced for \(safeLabel) target=\(logURLSummary(url)) headerKeys=[\(headerKeys)]", type: "MPV")
            return
        }
        activeKeys.insert(key)
        lock.unlock()

        Logger.shared.log("MPV warmup started for \(safeLabel) target=\(logURLSummary(url)) key=\(String(key.prefix(8))) headerKeys=[\(headerKeys)] limitBytes=\(currentCacheLimitBytes())", type: "MPV")

        Task.detached(priority: .utility) { [weak self] in
            defer {
                self?.lock.lock()
                self?.activeKeys.remove(key)
                self?.lock.unlock()
            }
            await self?.writeStarterCache(url: url, headers: headers, key: key, label: label)
        }
    }

    func cachedStarter(for url: URL, headers: [String: String]?) -> ExperimentalMPVPreloadCachedStarter? {
        let key = cacheKey(for: url, headers: headers)
        let dataURL = starterURL(forKey: key)
        let metadataURL = starterMetadataURL(forKey: key)

        guard let metadata = try? JSONDecoder().decode(StarterMetadata.self, from: Data(contentsOf: metadataURL)),
              Date().timeIntervalSince1970 - metadata.storedAt <= maxStarterAge,
              let data = try? Data(contentsOf: dataURL),
              !data.isEmpty,
              data.count == metadata.dataLength else {
            try? fileManager.removeItem(at: dataURL)
            try? fileManager.removeItem(at: metadataURL)
            return nil
        }

        return ExperimentalMPVPreloadCachedStarter(
            data: data,
            contentType: metadata.contentType,
            totalLength: metadata.totalLength,
            statusCode: metadata.statusCode,
            isPlaylist: metadata.isPlaylist
        )
    }

    func cachedStarter(for url: URL, headers: [String: String]?, waitUpTo timeout: TimeInterval) async -> ExperimentalMPVPreloadCachedStarter? {
        if let starter = cachedStarter(for: url, headers: headers) {
            return starter
        }

        guard timeout > 0 else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let starter = cachedStarter(for: url, headers: headers) {
                Logger.shared.log("MPV warmup cache became available target=\(logURLSummary(url)) waitMs=\(Int(timeout * 1000)) bytes=\(starter.data.count)", type: "MPV")
                return starter
            }
        }
        return nil
    }

    private func preloadSkipReason(for url: URL) -> String? {
        guard UserDefaults.standard.bool(forKey: ExperimentalFeatureState.mpvPreloadEnabledKey) else { return "warmup-disabled" }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return "non-http-url" }
        guard !isLoopbackURL(url) else { return "loopback-proxy-url" }
        guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return "low-power-mode" }
        guard ProcessInfo.processInfo.thermalState != .serious,
              ProcessInfo.processInfo.thermalState != .critical else { return "thermal-pressure" }
        guard freeDiskBytes() > 750 * 1024 * 1024 else { return "low-disk-space" }
        if let networkSkipReason = currentNetworkPreloadSkipReason() {
            return networkSkipReason
        }
        guard cacheSizeBytes < currentCacheLimitBytes() else { return "cache-limit-reached" }

        let path = url.pathExtension.lowercased()
        return isWarmupCompatiblePathExtension(path) ? nil : "unsupported-extension-\(path)"
    }

    private func isWarmupCompatiblePathExtension(_ path: String) -> Bool {
        path.isEmpty || [
            "m3u8",
            "m3u",
            "mp4",
            "m4v",
            "m4s",
            "mkv",
            "mov",
            "ts",
            "aac",
            "mp3"
        ].contains(path)
    }

    private func isLoopbackURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func currentNetworkPreloadSkipReason() -> String? {
#if canImport(Network)
        guard let currentPath else { return "network-path-pending" }
        guard currentPath.status == .satisfied else { return "network-unsatisfied" }
        if currentPath.usesInterfaceType(.cellular),
           !UserDefaults.standard.bool(forKey: ExperimentalFeatureState.mpvPreloadCellularEnabledKey) {
            return "cellular-disabled"
        }
#endif
        return nil
    }

    private func currentCacheLimitBytes() -> Int64 {
#if canImport(Network)
        if currentPath?.usesInterfaceType(.cellular) == true {
            let mb = UserDefaults.standard.integer(forKey: ExperimentalFeatureState.mpvPreloadCellularLimitMBKey)
            return Int64(ExperimentalFeatureState.resolvedMPVPreloadCellularLimitMB(mb)) * 1024 * 1024
        }
#endif
        let mb = UserDefaults.standard.integer(forKey: ExperimentalFeatureState.mpvPreloadWifiLimitMBKey)
        return Int64(ExperimentalFeatureState.resolvedMPVPreloadWifiLimitMB(mb)) * 1024 * 1024
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
                Logger.shared.log("MPV warmup skipped for \(label): empty-or-invalid-response target=\(logURLSummary(url))", type: "MPV")
                return
            }

            let contentType = http.value(forHTTPHeaderField: "Content-Type")
            let rangeInfo = parseContentRange(http.value(forHTTPHeaderField: "Content-Range"))
            let isPlaylist = isLikelyPlaylist(url: url, contentType: contentType)
            if isPlaylist {
                await writeHLSMediaStarterCache(playlistURL: url, data: data, headers: headers, label: label, depth: 0)
                return
            }

            let totalLength = rangeInfo?.totalLength
                ?? (http.expectedContentLength >= 0 ? http.expectedContentLength : nil)
            let isUsableRangeStarter = http.statusCode == 206 && rangeInfo?.start == 0
            guard isUsableRangeStarter else {
                Logger.shared.log("MPV warmup skipped for \(label): upstream-did-not-provide-usable-starter status=\(http.statusCode) range=\(http.value(forHTTPHeaderField: "Content-Range") ?? "nil") target=\(logURLSummary(url))", type: "MPV")
                return
            }

            let trimmed = data.count > maxStarterBytes ? data.prefix(maxStarterBytes) : data[...]
            let starterData = Data(trimmed)
            let target = starterURL(forKey: key)
            let metadata = StarterMetadata(
                statusCode: http.statusCode,
                contentType: contentType,
                totalLength: totalLength,
                isPlaylist: false,
                dataLength: starterData.count,
                storedAt: Date().timeIntervalSince1970
            )
            try starterData.write(to: target, options: .atomic)
            try JSONEncoder().encode(metadata).write(to: starterMetadataURL(forKey: key), options: .atomic)
            pruneCacheIfNeeded(limitBytes: currentCacheLimitBytes())
            Logger.shared.log("MPV warmup cached bytes=\(starterData.count) status=\(http.statusCode) playlist=false totalLength=\(totalLength.map(String.init) ?? "unknown") target=\(logURLSummary(url)) label=\(label)", type: "MPV")
        } catch {
            Logger.shared.log("MPV warmup skipped for \(label): \(error.localizedDescription) target=\(logURLSummary(url))", type: "MPV")
        }
    }

    private func writeHLSMediaStarterCache(
        playlistURL: URL,
        data: Data,
        headers: [String: String]?,
        label: String,
        depth: Int
    ) async {
        guard depth < 2 else {
            Logger.shared.log("MPV warmup skipped for \(label): hls-playlist-depth-limit target=\(logURLSummary(playlistURL))", type: "MPV")
            return
        }
        guard let text = String(data: data, encoding: .utf8) else {
            Logger.shared.log("MPV warmup skipped for \(label): hls-playlist-not-utf8 target=\(logURLSummary(playlistURL))", type: "MPV")
            return
        }

        let plan = hlsWarmupPlan(from: text, playlistURL: playlistURL)
        if let variantURL = plan.variantURL {
            do {
                let (variantData, response) = try await fetchHLSPlaylistData(url: variantURL, headers: headers)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      !variantData.isEmpty else {
                    Logger.shared.log("MPV warmup skipped for \(label): hls-variant-invalid target=\(logURLSummary(variantURL))", type: "MPV")
                    return
                }
                Logger.shared.log("MPV warmup HLS master selected variant target=\(logURLSummary(variantURL)) playlist=\(logURLSummary(playlistURL))", type: "MPV")
                await writeHLSMediaStarterCache(
                    playlistURL: variantURL,
                    data: variantData,
                    headers: headers,
                    label: "\(label) HLS variant",
                    depth: depth + 1
                )
            } catch {
                Logger.shared.log("MPV warmup skipped for \(label): hls-variant-fetch-failed error=\(error.localizedDescription) target=\(logURLSummary(variantURL))", type: "MPV")
            }
            return
        }

        let targets = hlsMediaWarmupTargets(mapURL: plan.mapURL, segmentURL: plan.segmentURL)
        guard !targets.isEmpty else {
            Logger.shared.log("MPV warmup skipped for \(label): hls-no-media-target playlist=\(logURLSummary(playlistURL))", type: "MPV")
            return
        }

        Logger.shared.log("MPV warmup HLS media targets count=\(targets.count) playlist=\(logURLSummary(playlistURL)) targets=[\(targets.map { logURLSummary($0) }.joined(separator: ","))]", type: "MPV")
        for target in targets {
            await writeStarterCache(
                url: target,
                headers: headers,
                key: cacheKey(for: target, headers: headers),
                label: "\(label) HLS media"
            )
        }
    }

    private func fetchHLSPlaylistData(url: URL, headers: [String: String]?) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18)
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return try await URLSession.shared.data(for: request)
    }

    private func pruneCacheIfNeeded(limitBytes: Int64) {
        let directory = cacheDirectory
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard var files = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )?.compactMap({ item -> (url: URL, size: Int64, modified: Date)? in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                return nil
            }
            return (url, Int64(fileSize), values.contentModificationDate ?? .distantPast)
        }) else {
            return
        }

        var total = files.reduce(Int64(0)) { $0 + $1.size }
        guard total > limitBytes else { return }

        files.sort { $0.modified < $1.modified }
        for file in files where total > limitBytes {
            try? fileManager.removeItem(at: file.url)
            total -= file.size
        }
    }

    private func cacheKey(for url: URL, headers: [String: String]?) -> String {
        let headerSignature = (headers ?? [:])
            .map { "\($0.key.lowercased()):\($0.value)" }
            .sorted()
            .joined(separator: "\n")
        let raw = Array("\(url.absoluteString)\n\(headerSignature)".utf8)
#if canImport(CryptoKit)
        return SHA256.hash(data: Data(raw)).map { String(format: "%02x", $0) }.joined()
#else
        let hash = fnv1a64(raw)
        return String(format: "%016llx", hash)
#endif
    }

    private func starterURL(forKey key: String) -> URL {
        cacheDirectory.appendingPathComponent(key).appendingPathExtension("starter")
    }

    private func starterMetadataURL(forKey key: String) -> URL {
        cacheDirectory.appendingPathComponent(key).appendingPathExtension("json")
    }

    private func logURLSummary(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.string ?? "\(url.scheme ?? "unknown")://\(url.host ?? "unknown")\(url.path)"
    }

    private func hlsWarmupPlan(from text: String, playlistURL: URL) -> HLSWarmupPlan {
        let baseURL = playlistURL.deletingLastPathComponent()
        var awaitingVariantURL = false
        var variantURL: URL?
        var mapURL: URL?
        var segmentURL: URL?

        for rawLine in text.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("#") {
                if trimmed.range(of: "#EXT-X-STREAM-INF", options: [.caseInsensitive]) != nil {
                    awaitingVariantURL = true
                } else if trimmed.range(of: "#EXT-X-MAP", options: [.caseInsensitive]) != nil,
                          mapURL == nil,
                          let reference = hlsURIAttribute(in: trimmed) {
                    mapURL = resolvedHLSURL(reference, baseURL: baseURL)
                }
                continue
            }

            if awaitingVariantURL {
                variantURL = resolvedHLSURL(trimmed, baseURL: baseURL)
                break
            }

            if segmentURL == nil {
                segmentURL = resolvedHLSURL(trimmed, baseURL: baseURL)
            }

            if mapURL != nil, segmentURL != nil {
                break
            }
        }

        return HLSWarmupPlan(variantURL: variantURL, mapURL: mapURL, segmentURL: segmentURL)
    }

    private func hlsURIAttribute(in line: String) -> String? {
        guard let keyRange = line.range(of: "URI=", options: [.caseInsensitive]) else { return nil }
        let valueStart = keyRange.upperBound
        guard valueStart < line.endIndex else { return nil }

        if line[valueStart] == "\"" {
            let contentStart = line.index(after: valueStart)
            guard contentStart <= line.endIndex,
                  let contentEnd = line[contentStart...].firstIndex(of: "\"") else {
                return nil
            }
            return String(line[contentStart..<contentEnd])
        }

        let valueEnd = line[valueStart...].firstIndex(of: ",") ?? line.endIndex
        let value = String(line[valueStart..<valueEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func resolvedHLSURL(_ reference: String, baseURL: URL) -> URL? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.lowercased().hasPrefix("data:"),
              let resolved = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL,
              let scheme = resolved.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return resolved
    }

    private func hlsMediaWarmupTargets(mapURL: URL?, segmentURL: URL?) -> [URL] {
        var seen = Set<String>()
        var targets: [URL] = []
        for url in [mapURL, segmentURL].compactMap({ $0 }) {
            let key = url.absoluteString
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            targets.append(url)
        }
        return targets
    }

    private func isLikelyPlaylist(url: URL, contentType: String?) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "m3u8" || ext == "m3u" {
            return true
        }
        let lower = contentType?.lowercased() ?? ""
        return lower.contains("mpegurl") || lower.contains("application/vnd.apple.mpegurl")
    }

    private func parseContentRange(_ value: String?) -> (start: Int64, end: Int64, totalLength: Int64?)? {
        guard let value else { return nil }
        let lower = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard lower.hasPrefix("bytes ") else { return nil }
        let rangeAndTotal = lower.dropFirst("bytes ".count).split(separator: "/", maxSplits: 1).map(String.init)
        guard rangeAndTotal.count == 2 else { return nil }
        let bounds = rangeAndTotal[0].split(separator: "-", maxSplits: 1).map(String.init)
        guard bounds.count == 2,
              let start = Int64(bounds[0]),
              let end = Int64(bounds[1]) else {
            return nil
        }
        let total = rangeAndTotal[1] == "*" ? nil : Int64(rangeAndTotal[1])
        return (start, end, total)
    }

    private func fnv1a64(_ bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }

    private func migrateLegacyCacheFileNamesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: cacheKeyMigrationDefaultsKey) else { return }
        try? fileManager.removeItem(at: cacheDirectory)
        UserDefaults.standard.set(true, forKey: cacheKeyMigrationDefaultsKey)
    }

    private struct StarterMetadata: Codable {
        let statusCode: Int
        let contentType: String?
        let totalLength: Int64?
        let isPlaylist: Bool
        let dataLength: Int
        let storedAt: TimeInterval
    }

    private struct HLSWarmupPlan {
        let variantURL: URL?
        let mapURL: URL?
        let segmentURL: URL?
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

    var mpvHDRMode: MPVHDRMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "mpvHDRMode")
                ?? MPVHDRMode.defaultMode.rawValue
            return MPVHDRMode(rawValue: raw) ?? .defaultMode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "mpvHDRMode")
        }
    }

    /// Whether the player may request multichannel (5.1/7.1) PCM output on routes that
    /// support it (USB-C/HDMI/AirPlay). Built-in speakers always remain stereo. Defaults on.
    var mpvSurroundSoundEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "mpvSurroundSoundEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "mpvSurroundSoundEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "mpvSurroundSoundEnabled")
        }
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
