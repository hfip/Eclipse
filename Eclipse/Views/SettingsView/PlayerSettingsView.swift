//
//  PlayerSettingsView.swift
//  Sora
//
//  Created by Francesco on 19/09/25.
//

import SwiftUI

enum ExternalPlayer: String, CaseIterable, Identifiable {
    case none = "Default"
    case infuse = "Infuse"
    case vlc = "VLC"
    case outPlayer = "OutPlayer"
    case nPlayer = "nPlayer"
    case senPlayer = "SenPlayer"
    case tracy = "TracyPlayer"
    case vidHub = "VidHub"

    var id: String { rawValue }

    func schemeURL(for urlString: String) -> URL? {
        let url = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString
        switch self {
        case .infuse:
            return URL(string: "infuse://x-callback-url/play?url=\(url)")
        case .vlc:
            return URL(string: "vlc://\(url)")
        case .outPlayer:
            return URL(string: "outplayer://\(url)")
        case .nPlayer:
            return URL(string: "nplayer-\(url)")
        case .senPlayer:
            return URL(string: "senplayer://x-callback-url/play?url=\(url)")
        case .tracy:
            return URL(string: "tracy://open?url=\(url)")
        case .vidHub:
            return URL(string: "open-vidhub://x-callback-url/open?url=\(url)")
        case .none:
            return nil
        }
    }
}

enum InAppPlayer: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case mpv = "mpv"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mpv:
            return "MPV"
        case .normal:
            return "Normal AVPlayer (Not recommended)"
        }
    }
}

final class PlayerSettingsStore: ObservableObject {
    @Published var defaultPlaybackSpeed: Double {
        didSet { UserDefaults.standard.set(defaultPlaybackSpeed, forKey: "defaultPlaybackSpeed") }
    }

    @Published var holdSpeed: Double {
        didSet { UserDefaults.standard.set(holdSpeed, forKey: "holdSpeedPlayer") }
    }

    @Published var externalPlayer: ExternalPlayer {
        didSet { UserDefaults.standard.set(externalPlayer.rawValue, forKey: "externalPlayer") }
    }

    @Published var landscapeOnly: Bool {
        didSet { UserDefaults.standard.set(landscapeOnly, forKey: "alwaysLandscape") }
    }

    @Published var inAppPlayer: InAppPlayer {
        didSet { UserDefaults.standard.set(inAppPlayer.rawValue, forKey: "inAppPlayer") }
    }

    @Published var preferDownloadedMedia: Bool {
        didSet { UserDefaults.standard.set(preferDownloadedMedia, forKey: "preferDownloadedMedia") }
    }

    @Published var aniSkipAutoSkip: Bool {
        didSet { UserDefaults.standard.set(aniSkipAutoSkip, forKey: "aniSkipAutoSkip") }
    }

    @Published var aniSkipEnabled: Bool {
        didSet { UserDefaults.standard.set(aniSkipEnabled, forKey: "aniSkipEnabled") }
    }

    @Published var introDBEnabled: Bool {
        didSet { UserDefaults.standard.set(introDBEnabled, forKey: "introDBEnabled") }
    }

    @Published var introDBAppEnabled: Bool {
        didSet { UserDefaults.standard.set(introDBAppEnabled, forKey: "introDBAppEnabled") }
    }

    @Published var skip85sEnabled: Bool {
        didSet { UserDefaults.standard.set(skip85sEnabled, forKey: "skip85sEnabled") }
    }

    @Published var skip85sAlwaysVisible: Bool {
        didSet { UserDefaults.standard.set(skip85sAlwaysVisible, forKey: "skip85sAlwaysVisible") }
    }

    @Published var showNextEpisodeButton: Bool {
        didSet { UserDefaults.standard.set(showNextEpisodeButton, forKey: "showNextEpisodeButton") }
    }

    @Published var showEpisodeBrowserButton: Bool {
        didSet { UserDefaults.standard.set(showEpisodeBrowserButton, forKey: "showEpisodeBrowserButton") }
    }

    @Published var showNextEpisodePosterButton: Bool {
        didSet { UserDefaults.standard.set(showNextEpisodePosterButton, forKey: "showNextEpisodePosterButton") }
    }

    @Published var nextEpisodeThreshold: Double {
        didSet { UserDefaults.standard.set(nextEpisodeThreshold, forKey: "nextEpisodeThreshold") }
    }

    @Published var playerBrightnessGestureEnabled: Bool {
        didSet { UserDefaults.standard.set(playerBrightnessGestureEnabled, forKey: "playerBrightnessGestureEnabled") }
    }

    @Published var playerVolumeGestureEnabled: Bool {
        didSet { UserDefaults.standard.set(playerVolumeGestureEnabled, forKey: "playerVolumeGestureEnabled") }
    }

    @Published var playerTwoFingerTapPlayPauseEnabled: Bool {
        didSet { UserDefaults.standard.set(playerTwoFingerTapPlayPauseEnabled, forKey: "playerTwoFingerTapPlayPauseEnabled") }
    }

    @Published var playerCenterTapPlayPauseEnabled: Bool {
        didSet { UserDefaults.standard.set(playerCenterTapPlayPauseEnabled, forKey: "playerCenterTapPlayPauseEnabled") }
    }

    @Published var playerDoubleTapSeekEnabled: Bool {
        didSet { UserDefaults.standard.set(playerDoubleTapSeekEnabled, forKey: "playerDoubleTapSeekEnabled") }
    }

    @Published var playerDoubleTapSeekSeconds: Double {
        didSet { UserDefaults.standard.set(playerDoubleTapSeekSeconds, forKey: "playerDoubleTapSeekSeconds") }
    }

    @Published var playerOpenSubtitlesEnabled: Bool {
        didSet { UserDefaults.standard.set(playerOpenSubtitlesEnabled, forKey: "playerOpenSubtitlesEnabled") }
    }

    @Published var playerOpenSubtitlesAutoFallbackEnabled: Bool {
        didSet { UserDefaults.standard.set(playerOpenSubtitlesAutoFallbackEnabled, forKey: "playerOpenSubtitlesAutoFallbackEnabled") }
    }

    @Published var mpvForegroundFPS: Int {
        didSet { UserDefaults.standard.set(mpvForegroundFPS == 60 ? 60 : 30, forKey: "mpvForegroundFPS") }
    }

    @Published var mpvRenderBackend: MPVRenderBackend {
        didSet { UserDefaults.standard.set(mpvRenderBackend.rawValue, forKey: "mpvRenderBackend") }
    }

    @Published var mpvMetalQualityProfile: MPVMetalQualityProfile {
        didSet { UserDefaults.standard.set(mpvMetalQualityProfile.rawValue, forKey: "mpvMetalQualityProfile") }
    }

    @Published var mpvAppExitPictureInPictureEnabled: Bool {
        didSet { UserDefaults.standard.set(mpvAppExitPictureInPictureEnabled, forKey: "mpvAppExitPictureInPictureEnabled") }
    }

    @Published var experimentalMPVPreloadEnabled: Bool {
        didSet { UserDefaults.standard.set(experimentalMPVPreloadEnabled, forKey: ExperimentalFeatureState.mpvPreloadEnabledKey) }
    }

    @Published var experimentalMPVSmoothTransitionEnabled: Bool {
        didSet { UserDefaults.standard.set(experimentalMPVSmoothTransitionEnabled, forKey: ExperimentalFeatureState.mpvSmoothTransitionEnabledKey) }
    }

    @Published var experimentalMPVPreloadCellularEnabled: Bool {
        didSet { UserDefaults.standard.set(experimentalMPVPreloadCellularEnabled, forKey: ExperimentalFeatureState.mpvPreloadCellularEnabledKey) }
    }

    @Published var experimentalMPVPreloadWifiLimitMB: Int {
        didSet { UserDefaults.standard.set(max(32, min(experimentalMPVPreloadWifiLimitMB, 2048)), forKey: ExperimentalFeatureState.mpvPreloadWifiLimitMBKey) }
    }

    @Published var experimentalMPVPreloadCellularLimitMB: Int {
        didSet { UserDefaults.standard.set(max(8, min(experimentalMPVPreloadCellularLimitMB, 256)), forKey: ExperimentalFeatureState.mpvPreloadCellularLimitMBKey) }
    }

    @Published var experimentalMPVShowRemainingTime: Bool {
        didSet { UserDefaults.standard.set(experimentalMPVShowRemainingTime, forKey: ExperimentalFeatureState.mpvShowRemainingTimeKey) }
    }

    @Published var experimentalMPVPreciseProgress: Bool {
        didSet { UserDefaults.standard.set(experimentalMPVPreciseProgress, forKey: ExperimentalFeatureState.mpvPreciseProgressKey) }
    }

    @Published var experimentalMPVIgnoreSpecialSubtitleStyles: Bool {
        didSet { UserDefaults.standard.set(experimentalMPVIgnoreSpecialSubtitleStyles, forKey: ExperimentalFeatureState.mpvIgnoreSpecialSubtitleStylesKey) }
    }

    private static func migratedBool(genericKey: String, legacyKey: String, defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: genericKey) == nil {
            let value = UserDefaults.standard.object(forKey: legacyKey) as? Bool ?? defaultValue
            UserDefaults.standard.set(value, forKey: genericKey)
            return value
        }
        return UserDefaults.standard.bool(forKey: genericKey)
    }

    private static func migratedDouble(genericKey: String, legacyKey: String, defaultValue: Double) -> Double {
        if UserDefaults.standard.object(forKey: genericKey) == nil {
            let value = UserDefaults.standard.double(forKey: legacyKey)
            let resolved = value > 0 ? value : defaultValue
            UserDefaults.standard.set(resolved, forKey: genericKey)
            return resolved
        }
        let value = UserDefaults.standard.double(forKey: genericKey)
        return value > 0 ? value : defaultValue
    }

    init() {
        let savedDefaultSpeed = UserDefaults.standard.double(forKey: "defaultPlaybackSpeed")
        self.defaultPlaybackSpeed = savedDefaultSpeed > 0 ? savedDefaultSpeed : 1.0

        let savedSpeed = UserDefaults.standard.double(forKey: "holdSpeedPlayer")
        self.holdSpeed = savedSpeed > 0 ? savedSpeed : 2.0

        let raw = UserDefaults.standard.string(forKey: "externalPlayer") ?? ExternalPlayer.none.rawValue
        self.externalPlayer = ExternalPlayer(rawValue: raw) ?? .none

        self.landscapeOnly = UserDefaults.standard.bool(forKey: "alwaysLandscape")

        let inAppRaw = UserDefaults.standard.string(forKey: "inAppPlayer") ?? InAppPlayer.mpv.rawValue
        let normalizedInAppRaw = Settings.normalizedInAppPlayer(inAppRaw)
        if normalizedInAppRaw != inAppRaw {
            UserDefaults.standard.set(normalizedInAppRaw, forKey: "inAppPlayer")
        }
        self.inAppPlayer = InAppPlayer(rawValue: normalizedInAppRaw) ?? .mpv

        self.preferDownloadedMedia = UserDefaults.standard.bool(forKey: "preferDownloadedMedia")

        self.aniSkipAutoSkip = UserDefaults.standard.bool(forKey: "aniSkipAutoSkip")

        if UserDefaults.standard.object(forKey: "aniSkipEnabled") == nil {
            self.aniSkipEnabled = true
        } else {
            self.aniSkipEnabled = UserDefaults.standard.bool(forKey: "aniSkipEnabled")
        }

        if UserDefaults.standard.object(forKey: "introDBEnabled") == nil {
            self.introDBEnabled = true
        } else {
            self.introDBEnabled = UserDefaults.standard.bool(forKey: "introDBEnabled")
        }

        if UserDefaults.standard.object(forKey: "introDBAppEnabled") == nil {
            self.introDBAppEnabled = true
        } else {
            self.introDBAppEnabled = UserDefaults.standard.bool(forKey: "introDBAppEnabled")
        }

        self.skip85sEnabled = UserDefaults.standard.bool(forKey: "skip85sEnabled")
        self.skip85sAlwaysVisible = UserDefaults.standard.bool(forKey: "skip85sAlwaysVisible")

        // Default to true if key has never been set
        if UserDefaults.standard.object(forKey: "showNextEpisodeButton") == nil {
            self.showNextEpisodeButton = true
        } else {
            self.showNextEpisodeButton = UserDefaults.standard.bool(forKey: "showNextEpisodeButton")
        }

        if UserDefaults.standard.object(forKey: "showEpisodeBrowserButton") == nil {
            let legacy = UserDefaults.standard.object(forKey: "showVLCEpisodeBrowserButton") as? Bool ?? true
            UserDefaults.standard.set(legacy, forKey: "showEpisodeBrowserButton")
            self.showEpisodeBrowserButton = legacy
        } else {
            self.showEpisodeBrowserButton = UserDefaults.standard.bool(forKey: "showEpisodeBrowserButton")
        }

        self.showNextEpisodePosterButton = UserDefaults.standard.bool(forKey: "showNextEpisodePosterButton")

        let savedThreshold = UserDefaults.standard.double(forKey: "nextEpisodeThreshold")
        self.nextEpisodeThreshold = savedThreshold > 0 ? savedThreshold : 0.90

        self.playerBrightnessGestureEnabled = Self.migratedBool(genericKey: "playerBrightnessGestureEnabled", legacyKey: "vlcBrightnessGestureEnabled", defaultValue: false)
        self.playerVolumeGestureEnabled = Self.migratedBool(genericKey: "playerVolumeGestureEnabled", legacyKey: "vlcVolumeGestureEnabled", defaultValue: false)

        if UserDefaults.standard.object(forKey: "playerTwoFingerTapPlayPauseEnabled") == nil {
            if let legacy = UserDefaults.standard.object(forKey: "mpvTwoFingerTapEnabled") as? Bool {
                UserDefaults.standard.set(legacy, forKey: "playerTwoFingerTapPlayPauseEnabled")
                self.playerTwoFingerTapPlayPauseEnabled = legacy
            } else {
                UserDefaults.standard.set(true, forKey: "playerTwoFingerTapPlayPauseEnabled")
                self.playerTwoFingerTapPlayPauseEnabled = true
            }
        } else {
            self.playerTwoFingerTapPlayPauseEnabled = UserDefaults.standard.bool(forKey: "playerTwoFingerTapPlayPauseEnabled")
        }

        if UserDefaults.standard.object(forKey: "playerCenterTapPlayPauseEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "playerCenterTapPlayPauseEnabled")
            self.playerCenterTapPlayPauseEnabled = true
        } else {
            self.playerCenterTapPlayPauseEnabled = UserDefaults.standard.bool(forKey: "playerCenterTapPlayPauseEnabled")
        }

        self.playerDoubleTapSeekEnabled = Self.migratedBool(genericKey: "playerDoubleTapSeekEnabled", legacyKey: "vlcDoubleTapSeekEnabled", defaultValue: true)
        self.playerDoubleTapSeekSeconds = Self.migratedDouble(genericKey: "playerDoubleTapSeekSeconds", legacyKey: "vlcDoubleTapSeekSeconds", defaultValue: 10.0)
        self.playerOpenSubtitlesEnabled = Self.migratedBool(genericKey: "playerOpenSubtitlesEnabled", legacyKey: "vlcOpenSubtitlesEnabled", defaultValue: false)
        self.playerOpenSubtitlesAutoFallbackEnabled = Self.migratedBool(genericKey: "playerOpenSubtitlesAutoFallbackEnabled", legacyKey: "vlcOpenSubtitlesAutoFallbackEnabled", defaultValue: true)

        self.mpvForegroundFPS = UserDefaults.standard.integer(forKey: "mpvForegroundFPS") == 60 ? 60 : 30
        let backendRaw = UserDefaults.standard.string(forKey: "mpvRenderBackend") ?? MPVRenderBackend.defaultBackend.rawValue
        self.mpvRenderBackend = MPVRenderBackend(rawValue: backendRaw) ?? .defaultBackend
        let metalQualityRaw = UserDefaults.standard.string(forKey: "mpvMetalQualityProfile") ?? MPVMetalQualityProfile.defaultProfile.rawValue
        self.mpvMetalQualityProfile = MPVMetalQualityProfile(rawValue: metalQualityRaw) ?? .defaultProfile
        self.mpvAppExitPictureInPictureEnabled = UserDefaults.standard.bool(forKey: "mpvAppExitPictureInPictureEnabled")

        ExperimentalFeatureState.registerDefaults()
        self.experimentalMPVPreloadEnabled = UserDefaults.standard.bool(forKey: ExperimentalFeatureState.mpvPreloadEnabledKey)
        self.experimentalMPVSmoothTransitionEnabled = UserDefaults.standard.bool(forKey: ExperimentalFeatureState.mpvSmoothTransitionEnabledKey)
        self.experimentalMPVPreloadCellularEnabled = UserDefaults.standard.bool(forKey: ExperimentalFeatureState.mpvPreloadCellularEnabledKey)
        let wifiLimit = UserDefaults.standard.integer(forKey: ExperimentalFeatureState.mpvPreloadWifiLimitMBKey)
        self.experimentalMPVPreloadWifiLimitMB = wifiLimit > 0 ? wifiLimit : 256
        let cellularLimit = UserDefaults.standard.integer(forKey: ExperimentalFeatureState.mpvPreloadCellularLimitMBKey)
        self.experimentalMPVPreloadCellularLimitMB = cellularLimit > 0 ? cellularLimit : 32
        self.experimentalMPVShowRemainingTime = UserDefaults.standard.bool(forKey: ExperimentalFeatureState.mpvShowRemainingTimeKey)
        self.experimentalMPVPreciseProgress = UserDefaults.standard.bool(forKey: ExperimentalFeatureState.mpvPreciseProgressKey)
        self.experimentalMPVIgnoreSpecialSubtitleStyles = UserDefaults.standard.bool(forKey: ExperimentalFeatureState.mpvIgnoreSpecialSubtitleStylesKey)
    }
}

struct PlayerSettingsView: View {
    @StateObject private var accentColorManager = AccentColorManager.shared
    @StateObject private var store = PlayerSettingsStore()
    @Environment(\.dismiss) private var dismiss
    @State private var subtitleTextColorName: String = "White"
    @State private var subtitleStrokeColorName: String = "Black"
    @State private var subtitleStrokeWidth: Double = 1.0
    @State private var subtitleFontSizePresetName: String = "Medium"
    @State private var subtitleVerticalOffset: Double = -6.0
    @State private var expandedGroups: Set<String> = []
    private let playbackSpeedOptions: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    private let doubleTapSeekOptions: [Double] = [5, 10, 15, 20, 30, 45, 60]
    private let mpvForegroundFPSOptions: [Int] = [30, 60]

    private var accent: Color { accentColorManager.currentAccentColor }

    private var selectedMPVRendererIsMetal: Bool {
        MPVRenderBackendSupport.effectiveBackend(requested: store.mpvRenderBackend, hasMetalDevice: true) == .metal
    }

    private var canUseMetalMPVAdvancedSettings: Bool {
        store.inAppPlayer == .mpv
            && store.externalPlayer == .none
            && selectedMPVRendererIsMetal
    }

    private var mpvAdvancedRequirementMessage: String {
        if store.inAppPlayer != .mpv {
            return "MPV advanced features require MPV as the default in-app player."
        }
        if store.externalPlayer != .none {
            return "MPV advanced features require external playback set to Default."
        }
        if store.mpvRenderBackend != .metal {
            return "MPV advanced features require the Metal MPV renderer."
        }
        if !MPVRenderBackendSupport.metalIsFullySupported {
            return "MPV advanced features require the bundled Metal renderer."
        }
        return "MPV advanced features require the Metal MPV renderer."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                // MARK: - Default Player
                VStack(spacing: 8) {
                    GlassSection(header: "Default Player") {
                        VStack(spacing: 0) {
                            GlassDetailRow(title: "Default Playback Speed", subtitle: "Speed used when a video starts.") {
                                Picker("", selection: $store.defaultPlaybackSpeed) {
                                    ForEach(playbackSpeedOptions, id: \.self) { speed in
                                        Text(formatSpeed(speed)).tag(speed)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.white.opacity(0.7))
                            }

#if !os(tvOS)
                            GlassDivider(leadingInset: 16)
                            GlassDetailRow(title: String(format: "Hold Speed: %.1fx", store.holdSpeed), subtitle: "Value of long-press speed playback in the player.") {
                                Stepper("", value: $store.holdSpeed, in: 0.1...3, step: 0.1)
                                    .labelsHidden()
                            }
#endif

                            GlassDivider(leadingInset: 16)
                            GlassDetailRow(title: "Force Landscape", subtitle: "Force landscape orientation in the video player.") {
                                Toggle("", isOn: $store.landscapeOnly)
                                    .labelsHidden()
                                    .tint(accent)
                            }
                        }
                    }
                    .disabled(store.externalPlayer != .none)

                    GlassSectionFooter("This setting works exclusively with the Default media player.")
                }

                // MARK: - Media Player
                GlassSection(header: "Media Player") {
                    VStack(spacing: 0) {
                        GlassDetailRow(title: "Media Player", subtitle: "The app must be installed and accept the provided scheme.") {
                            Picker("", selection: $store.externalPlayer) {
                                ForEach(ExternalPlayer.allCases) { player in
                                    Text(player.rawValue).tag(player)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white.opacity(0.7))
                        }

                        GlassDivider(leadingInset: 16)

                        GlassDetailRow(title: "In-App Player", subtitle: "Select the internal player software.") {
                            Picker("", selection: $store.inAppPlayer) {
                                ForEach(InAppPlayer.allCases) { p in
                                    Text(p.displayName).tag(p)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white.opacity(0.7))
                        }

                        GlassDivider(leadingInset: 16)

                        GlassDetailRow(title: "Prefer Downloaded Episodes", subtitle: "When a matching download exists, play it from detail pages instead of streaming.") {
                            Toggle("", isOn: $store.preferDownloadedMedia)
                                .labelsHidden()
                                .tint(accent)
                        }
                    }
                }

                // MARK: - MPV Player
                if store.inAppPlayer == .mpv {
                    VStack(spacing: 8) {
                        GlassSection(header: "MPV Player") {
                            VStack(spacing: 0) {
                                subtitleDefaultsGroup
                                GlassDivider()
                                subtitleAppearanceGroup
                                GlassDivider()
                                mpvRenderingGroup
                                GlassDivider()
                                gesturesGroup
                                GlassDivider()
                                openSubtitlesGroup
                                GlassDivider()
                                skipSegmentsGroup
                                GlassDivider()
                                if canUseMetalMPVAdvancedSettings {
                                    experimentalMPVDisclosure
                                } else {
                                    HStack(spacing: 10) {
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(.white.opacity(0.5))
                                        Text(mpvAdvancedRequirementMessage)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.5))
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                GlassDivider()
                                nextEpisodeGroup
                            }
                        }
                        GlassSectionFooter("In-app playback, subtitle, and gesture settings.")
                    }
                } else {
                    VStack(spacing: 8) {
                        GlassSection(header: "MPV Advanced Features") {
                            HStack(spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.white.opacity(0.5))
                                Text("Requires Metal MPV")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        GlassSectionFooter("Select MPV, keep external playback set to Default, and use the Metal renderer to enable MPV advanced playback features.")
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
            .background(EclipseScrollTracker())
        }
        .navigationTitle("Media Player")
        .background(SettingsGradientBackground().ignoresSafeArea())
        .eclipseDarkToolbar()
        .onAppear {
            refreshPlayerSubtitleStyleStateFromDefaults()
        }
    }

    // MARK: - MPV disclosure groups

    @ViewBuilder
    private var subtitleDefaultsGroup: some View {
        disclosureHeader("Subtitle Defaults", icon: "captions.bubble", iconColor: .blue, key: "subDefaults")
        if isExpanded("subDefaults") {
            GlassDivider(leadingInset: 16)
            settingsToggleRow(
                title: "Enable Subtitles by Default",
                detail: "Automatically load and display subtitles when available.",
                binding: Binding(
                    get: { UserDefaults.standard.bool(forKey: "enableSubtitlesByDefault") },
                    set: { UserDefaults.standard.set($0, forKey: "enableSubtitlesByDefault") }
                )
            )

            GlassDivider(leadingInset: 16)

            NavigationLink(destination: PlayerLanguageSelectionView(
                title: "Default Subtitle Language",
                selectedLanguage: Binding(
                    get: { UserDefaults.standard.string(forKey: "defaultSubtitleLanguage") ?? "eng" },
                    set: { UserDefaults.standard.set($0, forKey: "defaultSubtitleLanguage") }
                )
            )) {
                GlassDetailRow(title: "Default Subtitle Language", subtitle: "Language preference for subtitles.") {
                    valueChevron(getLanguageName(UserDefaults.standard.string(forKey: "defaultSubtitleLanguage") ?? "eng"))
                }
            }
            .buttonStyle(.plain)

            GlassDivider(leadingInset: 16)

            NavigationLink(destination: PlayerLanguageSelectionView(
                title: "Preferred Anime Audio",
                selectedLanguage: Binding(
                    get: { UserDefaults.standard.string(forKey: "preferredAnimeAudioLanguage") ?? "jpn" },
                    set: { UserDefaults.standard.set($0, forKey: "preferredAnimeAudioLanguage") }
                )
            )) {
                GlassDetailRow(title: "Preferred Anime Audio", subtitle: "Audio language for anime content.") {
                    valueChevron(getLanguageName(UserDefaults.standard.string(forKey: "preferredAnimeAudioLanguage") ?? "jpn"))
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var subtitleAppearanceGroup: some View {
        disclosureHeader("Subtitle Appearance", icon: "textformat.size", iconColor: .purple, key: "subAppearance")
        if isExpanded("subAppearance") {
            GlassDivider(leadingInset: 16)
            GlassDetailRow(title: "Subtitle Text Color", subtitle: "Default color for in-app subtitle rendering.") {
                Picker("", selection: subtitleTextColorBinding) {
                    ForEach(subtitleTextColorOptions.map(\.name), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white.opacity(0.7))
            }

            GlassDivider(leadingInset: 16)
            GlassDetailRow(title: "Subtitle Stroke Color", subtitle: "Outline color for in-app subtitle rendering.") {
                Picker("", selection: subtitleStrokeColorBinding) {
                    ForEach(subtitleStrokeColorOptions.map(\.name), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white.opacity(0.7))
            }

            GlassDivider(leadingInset: 16)
            GlassDetailRow(title: String(format: "Subtitle Stroke Width: %.1f", subtitleStrokeWidthBinding.wrappedValue), subtitle: "Outline thickness for in-app subtitle rendering.") {
#if os(tvOS)
                Picker("", selection: subtitleStrokeWidthBinding) {
                    Text("0.0").tag(0.0)
                    Text("0.5").tag(0.5)
                    Text("1.0").tag(1.0)
                    Text("1.5").tag(1.5)
                    Text("2.0").tag(2.0)
                }
                .pickerStyle(.menu)
                .tint(.white.opacity(0.7))
#else
                Stepper("", value: subtitleStrokeWidthBinding, in: 0.0...2.0, step: 0.5)
                    .labelsHidden()
#endif
            }

            GlassDivider(leadingInset: 16)
            GlassDetailRow(title: "Subtitle Font Size", subtitle: "Named size presets for in-app subtitle rendering.") {
                Picker("", selection: subtitleFontSizePresetBinding) {
                    ForEach(subtitleFontSizeOptions.map(\.name), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white.opacity(0.7))
            }

            GlassDivider(leadingInset: 16)
            GlassDetailRow(title: String(format: "Subtitle Vertical Offset: %.0f", subtitleVerticalOffsetBinding.wrappedValue), subtitle: "Numeric offset for subtitle height. Higher values place subtitles lower on screen.") {
#if os(tvOS)
                Picker("", selection: subtitleVerticalOffsetBinding) {
                    ForEach(Array(stride(from: -24, through: 24, by: 2)), id: \.self) { value in
                        Text("\(value)").tag(Double(value))
                    }
                }
                .pickerStyle(.menu)
                .tint(.white.opacity(0.7))
#else
                Stepper("", value: subtitleVerticalOffsetBinding, in: -24...24, step: 1)
                    .labelsHidden()
#endif
            }

            GlassDivider(leadingInset: 16)
            Button(action: resetPlayerSubtitleStyleDefaults) {
                GlassDetailRow(icon: "arrow.counterclockwise", iconColor: .orange, title: "Reset Subtitle Style", subtitle: "Restore default subtitle text color, stroke, width, and font size.") {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var mpvRenderingGroup: some View {
        disclosureHeader("MPV Rendering", icon: "display", iconColor: .cyan, key: "rendering")
        if isExpanded("rendering") {
            GlassDivider(leadingInset: 16)
            if MPVRenderBackendSupport.metalIsFullySupported {
                GlassDetailRow(title: "Render Backend", subtitle: "\(MPVRenderBackendSupport.settingsDescription)\n\(MPVRenderBackendSupport.settingsStatusLine)") {
                    Picker("", selection: $store.mpvRenderBackend) {
                        ForEach(MPVRenderBackend.allCases) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white.opacity(0.7))
                }

                GlassDivider(leadingInset: 16)
                GlassDetailRow(title: "Metal Quality", subtitle: store.mpvMetalQualityProfile.settingsDescription) {
                    Picker("", selection: $store.mpvMetalQualityProfile) {
                        ForEach(MPVMetalQualityProfile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white.opacity(0.7))
                }

                GlassDivider(leadingInset: 16)
            }

            GlassDetailRow(title: "Inline Frame Rate", subtitle: "Most media will look normal in 30 fps, but in the rare case of 60fps media, switch this to 60 fps.") {
                Picker("", selection: $store.mpvForegroundFPS) {
                    ForEach(mpvForegroundFPSOptions, id: \.self) { fps in
                        Text("\(fps) fps").tag(fps)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white.opacity(0.7))
            }

            GlassDivider(leadingInset: 16)
            settingsToggleRow(
                title: "PiP When Leaving App",
                detail: "Automatically start Picture in Picture when MPV playback moves to the background.",
                binding: $store.mpvAppExitPictureInPictureEnabled
            )
        }
    }

    @ViewBuilder
    private var gesturesGroup: some View {
        disclosureHeader("Playback Gestures", icon: "hand.draw", iconColor: .green, key: "gestures")
        if isExpanded("gestures") {
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Brightness Gesture", detail: "Use a left-side vertical drag for screen brightness.", binding: $store.playerBrightnessGestureEnabled)
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Volume Gesture", detail: "Use a right-side vertical drag for system volume.", binding: $store.playerVolumeGestureEnabled)
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Two-Finger Play/Pause", detail: "Toggle play and pause with a two-finger tap.", binding: $store.playerTwoFingerTapPlayPauseEnabled)
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Center-Tap Play/Pause", detail: "Tap the center of the video to play or pause without opening controls.", binding: $store.playerCenterTapPlayPauseEnabled)
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Double-Tap Seek", detail: "Double-tap the left or right side of the video to seek.", binding: $store.playerDoubleTapSeekEnabled)
            GlassDivider(leadingInset: 16)
            GlassDetailRow(title: "Seek Amount", subtitle: "Seek \(Int(store.playerDoubleTapSeekSeconds)) seconds with skip buttons, PiP, and double-tap when enabled.") {
#if os(tvOS)
                Picker("", selection: $store.playerDoubleTapSeekSeconds) {
                    ForEach(doubleTapSeekOptions, id: \.self) { seconds in
                        Text("\(Int(seconds))s").tag(seconds)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white.opacity(0.7))
#else
                Stepper("", value: $store.playerDoubleTapSeekSeconds, in: 5...60, step: 5)
                    .labelsHidden()
#endif
            }
        }
    }

    @ViewBuilder
    private var openSubtitlesGroup: some View {
        disclosureHeader("OpenSubtitles", icon: "globe", iconColor: .indigo, key: "openSubs")
        if isExpanded("openSubs") {
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "OpenSubtitles", detail: "Enable subtitle search through the Stremio OpenSubtitles v3 add-on.", binding: $store.playerOpenSubtitlesEnabled)

            if store.playerOpenSubtitlesEnabled {
                GlassDivider(leadingInset: 16)
                settingsToggleRow(title: "Use as Auto Fallback", detail: "When auto subtitles are on, search OpenSubtitles if the selected language is missing locally.", binding: $store.playerOpenSubtitlesAutoFallbackEnabled)
            }
        }
    }

    @ViewBuilder
    private var skipSegmentsGroup: some View {
        disclosureHeader("Skip Segments", icon: "forward.fill", iconColor: .pink, key: "skip")
        if isExpanded("skip") {
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "AniSkip", detail: "Fetch skip segments from AniSkip for anime content.", binding: $store.aniSkipEnabled)
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "TheIntroDB", detail: "Fetch skip segments from TheIntroDB for all content.", binding: $store.introDBEnabled)
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "IntroDB", detail: "Fetch skip segments from introdb.app using IMDb IDs when other skip sources return nothing.", binding: $store.introDBAppEnabled)
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Auto Skip", detail: "Automatically skip intros, outros, recaps, and previews when detected. A skip button is always shown regardless of this setting.", binding: $store.aniSkipAutoSkip)
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Skip 85s Fallback", detail: "Show a skip 85 seconds button when no skip data is returned for the current episode.", binding: $store.skip85sEnabled)
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Always Show Skip 85s", detail: "Keep the Skip 85s button visible even when skip segments are available.", binding: $store.skip85sAlwaysVisible)
        }
    }

    @ViewBuilder
    private var nextEpisodeGroup: some View {
        disclosureHeader("Next Episode", icon: "forward.end.fill", iconColor: .yellow, key: "nextEp")
        if isExpanded("nextEp") {
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Episode Browser Button", detail: "Show the episode drawer button over the player.", binding: $store.showEpisodeBrowserButton)
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Show Next Episode Button", detail: "Display a button near the end of an episode to quickly open stream search for the next episode.", binding: $store.showNextEpisodeButton)

            if store.showNextEpisodeButton {
                GlassDivider(leadingInset: 16)
                settingsToggleRow(title: "Use Episode Poster", detail: "Show the next episode image, number, and title when available.", binding: $store.showNextEpisodePosterButton)

                GlassDivider(leadingInset: 16)
                GlassDetailRow(title: "Appearance Threshold", subtitle: "How far into the episode (%) before the button appears. Default is 90%.") {
                    HStack(spacing: 8) {
                        Text("\(Int(store.nextEpisodeThreshold * 100))%")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
#if os(tvOS)
                        Picker("", selection: $store.nextEpisodeThreshold) {
                            ForEach(Array(stride(from: 0.50, through: 0.99, by: 0.05)), id: \.self) { value in
                                Text("\(Int(value * 100))%").tag(value)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.white.opacity(0.7))
#else
                        Stepper("", value: $store.nextEpisodeThreshold, in: 0.50...0.99, step: 0.05)
                            .labelsHidden()
#endif
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func isExpanded(_ key: String) -> Bool {
        expandedGroups.contains(key)
    }

    private func toggleGroup(_ key: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedGroups.contains(key) {
                expandedGroups.remove(key)
            } else {
                expandedGroups.insert(key)
            }
        }
    }

    private func disclosureHeader(_ title: String, icon: String, iconColor: Color, key: String) -> some View {
        Button {
            toggleGroup(key)
        } label: {
            GlassDetailRow(icon: icon, iconColor: iconColor, title: title) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .rotationEffect(.degrees(isExpanded(key) ? 90 : 0))
            }
        }
        .buttonStyle(.plain)
    }

    private func valueChevron(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    private func getLanguageName(_ code: String) -> String {
        let languages: [String: String] = [
            "eng": "English",
            "jpn": "Japanese",
            "zho": "Chinese",
            "kor": "Korean",
            "spa": "Spanish",
            "fra": "French",
            "deu": "German",
            "ita": "Italian",
            "por": "Portuguese",
            "rus": "Russian"
        ]
        return languages[code] ?? code.uppercased()
    }

    private func formatSpeed(_ speed: Double) -> String {
        let oneDecimal = (speed * 10).rounded() / 10
        if abs(speed - oneDecimal) < 0.001 {
            return String(format: "%.1fx", speed)
        }
        return String(format: "%.2fx", speed)
    }

    private func settingsToggleRow(title: String, detail: String, binding: Binding<Bool>) -> some View {
        GlassDetailRow(title: title, subtitle: detail) {
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(accentColorManager.currentAccentColor)
        }
    }

    @ViewBuilder
    private var experimentalMPVDisclosure: some View {
        disclosureHeader("MPV Advanced", icon: "sparkles", iconColor: .purple, key: "experimental")
        if isExpanded("experimental") {
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Stream Warmup Cache", detail: "Route compatible HTTP streams through a cache-aware MPV proxy that can reuse starter bytes for faster retries and reloads.", binding: $store.experimentalMPVPreloadEnabled)
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Next Episode Staging", detail: "Pre-resolve the next episode preview near the end of MPV playback. Stream selection still uses the normal next-episode flow.", binding: $store.experimentalMPVSmoothTransitionEnabled)
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Allow Cellular Warmup", detail: "Keep off for sideloaded or metered setups unless you explicitly want small stream warmups on cellular.", binding: $store.experimentalMPVPreloadCellularEnabled)
            GlassDivider(leadingInset: 16)
            GlassDetailRow(title: "Wi-Fi Cache Limit", subtitle: "\(store.experimentalMPVPreloadWifiLimitMB) MB for MPV stream warmup cache.") {
                Stepper("", value: $store.experimentalMPVPreloadWifiLimitMB, in: 32...2048, step: 32)
                    .labelsHidden()
            }
            GlassDivider(leadingInset: 16)
            GlassDetailRow(title: "Cellular Cache Limit", subtitle: "\(store.experimentalMPVPreloadCellularLimitMB) MB for MPV stream warmup cache.") {
                Stepper("", value: $store.experimentalMPVPreloadCellularLimitMB, in: 8...256, step: 8)
                    .labelsHidden()
            }
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Show Remaining Time", detail: "Use remaining time in MPV player controls where supported.", binding: $store.experimentalMPVShowRemainingTime)
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Precise Progress Adjustment", detail: "Use finer slider updates for MPV progress adjustments.", binding: $store.experimentalMPVPreciseProgress)
            GlassDivider(leadingInset: 16)
            settingsToggleRow(title: "Ignore Special Subtitle Styles", detail: "Prefer app subtitle styling over embedded ASS effects when MPV exposes compatible tracks.", binding: $store.experimentalMPVIgnoreSpecialSubtitleStyles)
        }
    }

    private var subtitleTextColorOptions: [(name: String, color: UIColor)] {
        [("White", .white), ("Yellow", .yellow), ("Cyan", .cyan), ("Green", .green), ("Magenta", .magenta)]
    }

    private var subtitleStrokeColorOptions: [(name: String, color: UIColor)] {
        [("Black", .black), ("Dark Gray", .darkGray), ("White", .white), ("None", .clear)]
    }

    private var subtitleTextColorBinding: Binding<String> {
        Binding(
            get: { subtitleTextColorName },
            set: { selectedName in
                subtitleTextColorName = selectedName
                if let selected = subtitleTextColorOptions.first(where: { $0.name == selectedName })?.color {
                    saveSubtitleColor(selected, forKey: "subtitles_foregroundColor")
                }
            }
        )
    }

    private var subtitleStrokeColorBinding: Binding<String> {
        Binding(
            get: { subtitleStrokeColorName },
            set: { selectedName in
                subtitleStrokeColorName = selectedName
                if let selected = subtitleStrokeColorOptions.first(where: { $0.name == selectedName })?.color {
                    saveSubtitleColor(selected, forKey: "subtitles_strokeColor")
                }
            }
        )
    }

    private var subtitleStrokeWidthBinding: Binding<Double> {
        Binding(
            get: { subtitleStrokeWidth },
            set: {
                subtitleStrokeWidth = $0
                UserDefaults.standard.set($0, forKey: "subtitles_strokeWidth")
            }
        )
    }

    private var subtitleFontSizeOptions: [(name: String, size: Double)] {
        [
            ("Very Small", 20.0),
            ("Small", 24.0),
            ("Medium", 30.0),
            ("Large", 34.0),
            ("Extra Large", 38.0),
            ("Huge", 42.0),
            ("Extra Huge", 46.0)
        ]
    }

    private var subtitleFontSizePresetBinding: Binding<String> {
        Binding(
            get: { subtitleFontSizePresetName },
            set: { selectedName in
                subtitleFontSizePresetName = selectedName
                if let selected = subtitleFontSizeOptions.first(where: { $0.name == selectedName }) {
                    UserDefaults.standard.set(selected.size, forKey: "subtitles_fontSize")
                }
            }
        )
    }

    private var subtitleVerticalOffsetBinding: Binding<Double> {
        Binding(
            get: { subtitleVerticalOffset },
            set: { selectedValue in
                subtitleVerticalOffset = selectedValue
                UserDefaults.standard.set(selectedValue, forKey: "playerSubtitleOverlayBottomConstant")
            }
        )
    }

    private func loadSubtitleColor(forKey key: String, defaultColor: UIColor) -> UIColor {
        guard let data = UserDefaults.standard.data(forKey: key),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) else {
            return defaultColor
        }
        return color
    }

    private func saveSubtitleColor(_ color: UIColor, forKey key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func resetPlayerSubtitleStyleDefaults() {
        saveSubtitleColor(.white, forKey: "subtitles_foregroundColor")
        saveSubtitleColor(.black, forKey: "subtitles_strokeColor")
        UserDefaults.standard.set(1.0, forKey: "subtitles_strokeWidth")
        UserDefaults.standard.set(30.0, forKey: "subtitles_fontSize")
        UserDefaults.standard.set(-6.0, forKey: "playerSubtitleOverlayBottomConstant")
        refreshPlayerSubtitleStyleStateFromDefaults()
    }

    private func refreshPlayerSubtitleStyleStateFromDefaults() {
        let textColor = loadSubtitleColor(forKey: "subtitles_foregroundColor", defaultColor: .white)
        subtitleTextColorName = subtitleTextColorOptions.first(where: { $0.color.isEqual(textColor) })?.name ?? "White"

        let strokeColor = loadSubtitleColor(forKey: "subtitles_strokeColor", defaultColor: .black)
        subtitleStrokeColorName = subtitleStrokeColorOptions.first(where: { $0.color.isEqual(strokeColor) })?.name ?? "Black"

        let savedStrokeWidth = UserDefaults.standard.double(forKey: "subtitles_strokeWidth")
        subtitleStrokeWidth = savedStrokeWidth >= 0 ? savedStrokeWidth : 1.0

        let savedFontSize = UserDefaults.standard.double(forKey: "subtitles_fontSize")
        let resolvedFontSize = savedFontSize > 0 ? savedFontSize : 30.0
        if let exact = subtitleFontSizeOptions.first(where: { abs($0.size - resolvedFontSize) < 0.01 }) {
            subtitleFontSizePresetName = exact.name
        } else {
            let nearest = subtitleFontSizeOptions.min(by: { abs($0.size - resolvedFontSize) < abs($1.size - resolvedFontSize) })
            subtitleFontSizePresetName = nearest?.name ?? "Medium"
        }

        if UserDefaults.standard.object(forKey: "playerSubtitleOverlayBottomConstant") == nil,
           UserDefaults.standard.object(forKey: "vlcSubtitleOverlayBottomConstant") != nil {
            UserDefaults.standard.set(UserDefaults.standard.double(forKey: "vlcSubtitleOverlayBottomConstant"), forKey: "playerSubtitleOverlayBottomConstant")
        }
        let savedBottomConstant = UserDefaults.standard.double(forKey: "playerSubtitleOverlayBottomConstant")
        subtitleVerticalOffset = UserDefaults.standard.object(forKey: "playerSubtitleOverlayBottomConstant") != nil ? savedBottomConstant : -6.0
    }
}
