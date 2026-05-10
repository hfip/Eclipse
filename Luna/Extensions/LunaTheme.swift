//
//  LunaTheme.swift
//  Luna
//
//  Theme system with customizable gradient colors
//

import SwiftUI

enum AtmosphereStyle: String, CaseIterable, Identifiable {
    case gradient
    case solid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gradient: return "Gradient"
        case .solid: return "Solid Color"
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

class LunaTheme: ObservableObject {
    static let shared = LunaTheme()
    
    // MARK: - Persisted Settings
    
    @Published var settingsGradientColor: Color {
        didSet { saveColor(settingsGradientColor, key: "lunaThemeGradientColor") }
    }

    @Published var atmosphereStyle: AtmosphereStyle {
        didSet { UserDefaults.standard.set(atmosphereStyle.rawValue, forKey: "atmosphereStyle") }
    }

    @Published var atmosphereSolidColorSource: AtmosphereSolidColorSource {
        didSet { UserDefaults.standard.set(atmosphereSolidColorSource.rawValue, forKey: "atmosphereSolidColorSource") }
    }

    @Published var atmosphereSolidColor: Color {
        didSet { saveColor(atmosphereSolidColor, key: "atmosphereSolidColor") }
    }
    
    // MARK: - Constants
    
    let cardCornerRadius: CGFloat = 16
    let backgroundBase = Color(red: 0.08, green: 0.08, blue: 0.08)
    let cardBackground = Color.white.opacity(0.08)
    let separatorColor = Color.white.opacity(0.12)
    let sectionHeaderColor = Color.white.opacity(0.5)
    
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
        self.settingsGradientColor = Self.gradientPresets[0].color
        self.settingsGradientColor = loadColor(key: "lunaThemeGradientColor") ?? Self.gradientPresets[0].color
        let styleRaw = UserDefaults.standard.string(forKey: "atmosphereStyle") ?? AtmosphereStyle.gradient.rawValue
        self.atmosphereStyle = AtmosphereStyle(rawValue: styleRaw) ?? .gradient
        let sourceRaw = UserDefaults.standard.string(forKey: "atmosphereSolidColorSource") ?? AtmosphereSolidColorSource.dominant.rawValue
        self.atmosphereSolidColorSource = AtmosphereSolidColorSource(rawValue: sourceRaw) ?? .dominant
        self.atmosphereSolidColor = loadColor(key: "atmosphereSolidColor") ?? Self.gradientPresets[0].color
    }

    func atmosphereColor(dominant: Color) -> Color {
        atmosphereSolidColorSource == .custom ? atmosphereSolidColor : dominant
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
    
    private func loadColor(key: String) -> Color? {
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
    func lunaBackground() -> some View {
        self.background(LunaTheme.shared.backgroundBase.ignoresSafeArea())
    }
    
    /// Apply the gradient background used in Settings screens
    func lunaGradientBackground() -> some View {
        self.modifier(LunaAutoGradientModifier())
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
    func lunaHideScrollBackground() -> some View {
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
    func lunaDarkToolbar() -> some View {
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

    /// Apply Luna styling to any List-based settings sub-view:
    /// gradient background, transparent list style, dark toolbar
    func lunaSettingsStyle() -> some View {
        self
            .lunaHideScrollBackground()
            .lunaGradientBackground()
            .lunaDarkToolbar()
    }

    /// Hide list row separators where supported (no-op on tvOS).
    @ViewBuilder
    func lunaHideListRowSeparator() -> some View {
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

private struct LunaAutoGradientModifier: ViewModifier {
    @State private var scrollOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: "lunaGradientScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
            .background(
                SettingsGradientBackground(scrollOffset: scrollOffset)
                    .ignoresSafeArea()
            )
    }
}
