//
//  EclipseTheme.swift
//  Eclipse
//
//  Theme system with customizable gradient colors
//

import SwiftUI

enum AtmosphereStyle: String, CaseIterable, Identifiable {
    case gradient
    case multiGradient
    case aurora
    case ember
    case solid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gradient: return "Gradient"
        case .multiGradient: return "Multi Gradient"
        case .aurora: return "Aurora"
        case .ember: return "Ember"
        case .solid: return "Solid Color"
        }
    }

    var isMultiGradient: Bool {
        switch self {
        case .multiGradient, .aurora, .ember:
            return true
        case .gradient, .solid:
            return false
        }
    }
}

enum AtmosphereSolidColorSource: String, CaseIterable, Identifiable {
    case dominant
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dominant: return "Poster Dominant"
        case .custom: return "Custom Color"
        }
    }
}

enum HeroBannerBehavior: String, CaseIterable, Identifiable {
    case `static`
    case carousel
    case launch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .static: return "Static"
        case .carousel: return "Carousel"
        case .launch: return "Change on App Launch"
        }
    }
}

class EclipseTheme: ObservableObject {
    static let shared = EclipseTheme()
    
    // MARK: - Persisted Settings

    @Published var globalAppearanceEnabled: Bool {
        didSet { UserDefaults.standard.set(globalAppearanceEnabled, forKey: "readerGlobalAppearanceEnabled") }
    }
    
    @Published var settingsGradientColor: Color {
        didSet { saveColor(settingsGradientColor, key: "eclipseThemeGradientColor") }
    }

    @Published var readerSettingsGradientColor: Color {
        didSet { saveColor(readerSettingsGradientColor, key: "readerThemeGradientColor") }
    }

    @Published var atmosphereStyle: AtmosphereStyle {
        didSet { UserDefaults.standard.set(atmosphereStyle.rawValue, forKey: "atmosphereStyle") }
    }

    @Published var readerAtmosphereStyle: AtmosphereStyle {
        didSet { UserDefaults.standard.set(readerAtmosphereStyle.rawValue, forKey: "readerAtmosphereStyle") }
    }

    @Published var atmosphereSolidColorSource: AtmosphereSolidColorSource {
        didSet { UserDefaults.standard.set(atmosphereSolidColorSource.rawValue, forKey: "atmosphereSolidColorSource") }
    }

    @Published var readerAtmosphereSolidColorSource: AtmosphereSolidColorSource {
        didSet { UserDefaults.standard.set(readerAtmosphereSolidColorSource.rawValue, forKey: "readerAtmosphereSolidColorSource") }
    }

    @Published var atmosphereSolidColor: Color {
        didSet { saveColor(atmosphereSolidColor, key: "atmosphereSolidColor") }
    }

    @Published var readerAtmosphereSolidColor: Color {
        didSet { saveColor(readerAtmosphereSolidColor, key: "readerAtmosphereSolidColor") }
    }
    
    // MARK: - Constants
    
    let cardCornerRadius: CGFloat = 16

    var backgroundBase: Color {
        #if !os(tvOS)
        if ExperimentalFeatureState.isEnabledAtLaunch {
            return Color(red: 0.070, green: 0.060, blue: 0.095)
        }
        #endif
        return Color(red: 0.08, green: 0.08, blue: 0.08)
    }

    var cardBackground: Color {
        #if !os(tvOS)
        if ExperimentalFeatureState.isEnabledAtLaunch {
            return Color(red: 0.12, green: 0.105, blue: 0.17).opacity(0.72)
        }
        #endif
        return Color.white.opacity(0.08)
    }

    var separatorColor: Color {
        #if !os(tvOS)
        if ExperimentalFeatureState.isEnabledAtLaunch {
            return Color.white.opacity(0.10)
        }
        #endif
        return Color.white.opacity(0.12)
    }

    var sectionHeaderColor: Color {
        #if !os(tvOS)
        if ExperimentalFeatureState.isEnabledAtLaunch {
            return Color.white.opacity(0.58)
        }
        #endif
        return Color.white.opacity(0.5)
    }
    
    // MARK: - Presets
    
    static let gradientPresets: [(name: String, color: Color)] = [
        ("Purple", Color(red: 0.25, green: 0.12, blue: 0.45)),
        ("Blue", Color(red: 0.10, green: 0.15, blue: 0.40)),
        ("Teal", Color(red: 0.08, green: 0.28, blue: 0.30)),
        ("Red", Color(red: 0.38, green: 0.10, blue: 0.12)),
        ("Green", Color(red: 0.10, green: 0.28, blue: 0.14))
    ]
    
    // MARK: - Init
    
    private init() {
        let styleRaw = UserDefaults.standard.string(forKey: "atmosphereStyle") ?? Self.defaultAtmosphereStyle.rawValue
        let sourceRaw = UserDefaults.standard.string(forKey: "atmosphereSolidColorSource") ?? AtmosphereSolidColorSource.dominant.rawValue
        let readerStyleRaw = UserDefaults.standard.string(forKey: "readerAtmosphereStyle") ?? styleRaw
        let readerSourceRaw = UserDefaults.standard.string(forKey: "readerAtmosphereSolidColorSource") ?? sourceRaw

        self.globalAppearanceEnabled = UserDefaults.standard.object(forKey: "readerGlobalAppearanceEnabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "readerGlobalAppearanceEnabled")
        self.settingsGradientColor = Self.loadColor(key: "eclipseThemeGradientColor") ?? Self.gradientPresets[0].color
        self.readerSettingsGradientColor = Self.loadColor(key: "readerThemeGradientColor") ?? Self.loadColor(key: "eclipseThemeGradientColor") ?? Self.gradientPresets[0].color
        self.atmosphereStyle = AtmosphereStyle(rawValue: styleRaw) ?? .gradient
        self.readerAtmosphereStyle = AtmosphereStyle(rawValue: readerStyleRaw) ?? .gradient
        self.atmosphereSolidColorSource = AtmosphereSolidColorSource(rawValue: sourceRaw) ?? .dominant
        self.readerAtmosphereSolidColorSource = AtmosphereSolidColorSource(rawValue: readerSourceRaw) ?? .dominant
        self.atmosphereSolidColor = Self.loadColor(key: "atmosphereSolidColor") ?? Self.gradientPresets[0].color
        self.readerAtmosphereSolidColor = Self.loadColor(key: "readerAtmosphereSolidColor") ?? Self.loadColor(key: "atmosphereSolidColor") ?? Self.gradientPresets[0].color
    }

    private static var defaultAtmosphereStyle: AtmosphereStyle {
        #if !os(tvOS)
        return ExperimentalFeatureState.isEnabledAtLaunch ? .multiGradient : .gradient
        #else
        return .gradient
        #endif
    }

    func atmosphereColor(dominant: Color) -> Color {
        atmosphereSolidColorSource == .custom ? atmosphereSolidColor : dominant
    }

    func scopedGradientColor(isReaderMode: Bool? = nil) -> Color {
        let readerMode = isReaderMode ?? UserDefaults.standard.bool(forKey: "showKanzen")
        return readerMode && !globalAppearanceEnabled ? readerSettingsGradientColor : settingsGradientColor
    }

    func scopedAtmosphereStyle(isReaderMode: Bool? = nil) -> AtmosphereStyle {
        let readerMode = isReaderMode ?? UserDefaults.standard.bool(forKey: "showKanzen")
        return readerMode && !globalAppearanceEnabled ? readerAtmosphereStyle : atmosphereStyle
    }

    func scopedAtmosphereColor(dominant: Color, isReaderMode: Bool? = nil) -> Color {
        let readerMode = isReaderMode ?? UserDefaults.standard.bool(forKey: "showKanzen")
        if readerMode && !globalAppearanceEnabled {
            return readerAtmosphereSolidColorSource == .custom ? readerAtmosphereSolidColor : dominant
        }
        return atmosphereColor(dominant: dominant)
    }
    
    // MARK: - Persistence
    
    private func saveColor(_ color: Color, key: String) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: UIColor(color), requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            // Silently fail — default will be used next launch
        }
    }
    
    private static func loadColor(key: String) -> Color? {
        guard let data = UserDefaults.standard.data(forKey: key),
              !data.isEmpty else { return nil }
        do {
            if let uiColor = try NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) {
                return Color(uiColor)
            }
        } catch { }
        return nil
    }
}

// MARK: - View Modifiers

extension View {
    /// Apply the standard dark base background used across all screens
    @ViewBuilder
    func eclipseBackground() -> some View {
        self.background(
            GlobalGradientBackground()
                .ignoresSafeArea()
        )
    }
    
    /// Apply the gradient background used in Settings screens
    func eclipseGradientBackground() -> some View {
        self.modifier(EclipseAutoGradientModifier())
    }

    /// Apply the app-wide gradient used by Reader Mode/Kanzen shell screens.
    func kanzenGradientBackground(scrollOffset: CGFloat = 0) -> some View {
        self.background(
            GlobalGradientBackground(scrollOffset: scrollOffset)
                .ignoresSafeArea()
        )
    }
    
    /// Hide list/scroll-view chrome (iOS 16+, unavailable on tvOS)
    @ViewBuilder
    func eclipseHideScrollBackground() -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Dark toolbar color scheme (iOS 16+, unavailable on tvOS)
    @ViewBuilder
    func eclipseDarkToolbar() -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            self.toolbarColorScheme(.dark, for: .navigationBar)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Apply Eclipse styling to any List-based settings sub-view:
    /// gradient background, transparent list style, dark toolbar
    func eclipseSettingsStyle() -> some View {
        self
            .eclipseHideScrollBackground()
            .eclipseGradientBackground()
            .eclipseDarkToolbar()
    }

    /// Hide list row separators where supported (no-op on tvOS).
    @ViewBuilder
    func eclipseHideListRowSeparator() -> some View {
        #if os(iOS)
        if #available(iOS 15.0, *) {
            self.listRowSeparator(.hidden)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// MARK: - Auto-tracking gradient modifier

private struct EclipseAutoGradientModifier: ViewModifier {
    @State private var scrollOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: "eclipseGradientScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
            .background(
                SettingsGradientBackground(scrollOffset: scrollOffset)
                    .ignoresSafeArea()
            )
    }
}
