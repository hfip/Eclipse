//
//  Settings.swift
//  Eclipse
//
//  Created by Dawud Osman on 17/11/2025.
//
import SwiftUI
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
            return "Keeps Metal sample-buffer playback at full frame quality and only changes pacing if iOS reports serious thermal pressure."
        case .balanced:
            return "Keeps full-size sample buffers with standard frame pacing."
        case .lowHeat:
            return "Keeps full-size sample buffers and lowers only PiP frame pacing to reduce heat."
        case .sharp:
            return "Keeps full-size sample buffers for the cleanest image at higher power cost."
        }
    }

    static let defaultProfile: MPVMetalQualityProfile = .auto
}

struct MPVRenderBackendSupport {
    static let bundledMPVKitVersion = "0.41.0"
    static let bundledMPVKitRevision = "3257830892c6b8cf44e0007aca2a4cef8064bc90"
    static let bundledMPVKitSupportsMoltenVKInlineRendering = true
    static let metalRendererEnabled = false

    #if ECLIPSE_MPVKIT_FORK_EXPOSES_METAL_SAMPLE_BUFFER_PIP
    static let forkExposesMetalSampleBufferPictureInPicture = true
    #else
    static let forkExposesMetalSampleBufferPictureInPicture = false
    #endif

    #if ECLIPSE_MPVKIT_METAL_SAMPLE_BUFFER_PIP_IMPLEMENTED
    static let eclipseImplementsMetalSampleBufferPictureInPicture = true
    #else
    static let eclipseImplementsMetalSampleBufferPictureInPicture = false
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

    static var metalSampleBufferPictureInPictureAvailable: Bool {
        bundledMPVKitSupportsMoltenVKInlineRendering
            && forkExposesMetalSampleBufferPictureInPicture
            && eclipseImplementsMetalSampleBufferPictureInPicture
    }

    static var metalIsFullySupported: Bool {
        metalRendererEnabled && metalSampleBufferPictureInPictureAvailable
    }

    static var diagnosticsSummary: String {
        [
            "mpvKit=\(bundledMPVKitVersion)",
            "revision=\(bundledMPVKitRevision)",
            "moltenVKInline=\(bundledMPVKitSupportsMoltenVKInlineRendering)",
            "forkMetalSampleBufferPiP=\(forkExposesMetalSampleBufferPictureInPicture)",
            "eclipseMetalPiP=\(eclipseImplementsMetalSampleBufferPictureInPicture)",
            "metalRendererEnabled=\(metalRendererEnabled)",
            "bitmapSubsAllowed=\(metalBitmapSubtitlesAllowed)",
            "bitmapSubsValidated=\(metalBitmapSubtitlesValidated)",
            "liveQuality=\(metalLiveQualityReconfigurationAvailable)"
        ].joined(separator: " ")
    }

    static var settingsDescription: String {
        if metalIsFullySupported {
            return "Applies to the next player session. Metal sample-buffer playback is experimental in this build; switch back to OpenGL if a stream misbehaves."
        }
        if !metalRendererEnabled {
            return "Applies to the next player session. OpenGL is active in this build."
        }
        return "Applies to the next player session. OpenGL is active in this build; Metal is remembered but falls back until the MPVKit fork exposes full sample-buffer PiP."
    }

    static var settingsStatusLine: String {
        if metalIsFullySupported {
            return "Metal backend: experimental sample-buffer PiP available"
        }
        if !metalRendererEnabled {
            return "Metal backend: hidden in this build"
        }
        return "Metal backend: waiting for MPVKit fork sample-buffer PiP"
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
        guard forkExposesMetalSampleBufferPictureInPicture else {
            return "MPVKit \(bundledMPVKitVersion) bundled in this build does not expose Metal sample-buffer PiP frames"
        }
        guard eclipseImplementsMetalSampleBufferPictureInPicture else {
            return "Eclipse Metal sample-buffer PiP adapter is not enabled in this build"
        }
        return nil
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
