//
//  GradientBackground.swift
//  Eclipse
//
//  Gradient background for Settings screens
//

import SwiftUI

// MARK: - Scroll Offset Tracking

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum ExperimentalMediaDesignPreset: String, CaseIterable, Identifiable {
    static let storageKey = "experimentalMediaDesignPreset"

    case cinematic
    case balanced
    case compact

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cinematic: return "Cinematic"
        case .balanced: return "Balanced"
        case .compact: return "Compact"
        }
    }

    static var defaultValue: ExperimentalMediaDesignPreset { .cinematic }

    static var current: ExperimentalMediaDesignPreset {
        let rawValue = UserDefaults.standard.string(forKey: storageKey)
        return ExperimentalMediaDesignPreset(rawValue: rawValue ?? "") ?? defaultValue
    }
}

enum ExperimentalHeroBleedLevel: String, CaseIterable, Identifiable {
    static let storageKey = "experimentalHeroBleedLevel"

    case soft
    case standard
    case strong

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .soft: return "Soft"
        case .standard: return "Standard"
        case .strong: return "Strong"
        }
    }

    var strengthMultiplier: Double {
        switch self {
        case .soft: return 0.72
        case .standard: return 1.0
        case .strong: return 1.24
        }
    }

    static var defaultValue: ExperimentalHeroBleedLevel { .standard }

    static var current: ExperimentalHeroBleedLevel {
        let rawValue = UserDefaults.standard.string(forKey: storageKey)
        return ExperimentalHeroBleedLevel(rawValue: rawValue ?? "") ?? defaultValue
    }
}

enum ExperimentalHomeCardShape: String, CaseIterable, Identifiable {
    static let storageKey = "experimentalHomeCardShape"

    case automatic
    case landscape
    case poster

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .landscape: return "Landscape"
        case .poster: return "Poster"
        }
    }

    static var defaultValue: ExperimentalHomeCardShape { .automatic }

    static var current: ExperimentalHomeCardShape {
        let rawValue = UserDefaults.standard.string(forKey: storageKey)
        return ExperimentalHomeCardShape(rawValue: rawValue ?? "") ?? defaultValue
    }
}

enum ExperimentalMultiGradientPalette: String, CaseIterable, Identifiable {
    static let storageKey = "experimentalMultiGradientPalette"

    case eclipse
    case nocturne
    case velvet
    case auroraMuted

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eclipse: return "Eclipse"
        case .nocturne: return "Nocturne"
        case .velvet: return "Velvet"
        case .auroraMuted: return "Muted Aurora"
        }
    }

    static var defaultValue: ExperimentalMultiGradientPalette { .eclipse }

    static var current: ExperimentalMultiGradientPalette {
        let rawValue = UserDefaults.standard.string(forKey: storageKey)
        return ExperimentalMultiGradientPalette(rawValue: rawValue ?? "") ?? defaultValue
    }
}

struct ExperimentalMediaDesignMetrics {
    let preset: ExperimentalMediaDesignPreset
    let heroBleedLevel: ExperimentalHeroBleedLevel
    let cardShape: ExperimentalHomeCardShape

    var homeHeroHeightRatio: CGFloat {
        switch preset {
        case .cinematic: return 0.86
        case .balanced: return 0.78
        case .compact: return 0.68
        }
    }

    var detailHeroHeightRatio: CGFloat {
        switch preset {
        case .cinematic: return 0.90
        case .balanced: return 0.80
        case .compact: return 0.70
        }
    }

    var heroBleedDistance: CGFloat {
        switch preset {
        case .cinematic: return 560
        case .balanced: return 440
        case .compact: return 320
        }
    }

    var heroWashStrength: Double {
        let base: Double
        switch preset {
        case .cinematic: base = 0.94
        case .balanced: base = 0.76
        case .compact: base = 0.58
        }
        return base * heroBleedLevel.strengthMultiplier
    }

    var contentTopOverlap: CGFloat {
        switch preset {
        case .cinematic: return 34
        case .balanced: return 22
        case .compact: return 10
        }
    }

    var sectionSpacing: CGFloat {
        switch preset {
        case .cinematic: return 30
        case .balanced: return 24
        case .compact: return 18
        }
    }

    var cardRadius: CGFloat {
        switch preset {
        case .cinematic: return 20
        case .balanced: return 18
        case .compact: return 16
        }
    }

    var glassOpacity: Double {
        switch preset {
        case .cinematic: return 0.72
        case .balanced: return 0.64
        case .compact: return 0.56
        }
    }

    var heroBottomFadeHeight: CGFloat {
        switch preset {
        case .cinematic: return 520
        case .balanced: return 420
        case .compact: return 320
        }
    }

    var scrollOffsetThreshold: CGFloat {
        switch preset {
        case .cinematic: return 18
        case .balanced: return 20
        case .compact: return 24
        }
    }

    func homeHeroHeight(screenHeight: CGFloat, isIPad: Bool) -> CGFloat {
        if isIPad {
            switch preset {
            case .cinematic: return 780
            case .balanced: return 720
            case .compact: return 640
            }
        }
        let minimum: CGFloat = preset == .compact ? 560 : 640
        let maximum: CGFloat = preset == .cinematic ? 820 : 760
        return min(max(screenHeight * homeHeroHeightRatio, minimum), maximum)
    }

    func detailHeroHeight(screenHeight: CGFloat, isIPad: Bool) -> CGFloat {
        if isIPad {
            switch preset {
            case .cinematic: return 760
            case .balanced: return 700
            case .compact: return 620
            }
        }
        let minimum: CGFloat = preset == .compact ? 560 : 650
        let maximum: CGFloat = preset == .cinematic ? 850 : 780
        return min(max(screenHeight * detailHeroHeightRatio, minimum), maximum)
    }

    func landscapeCardSize(isIPad: Bool) -> CGSize {
        if isIPad {
            switch preset {
            case .cinematic: return CGSize(width: 330, height: 186)
            case .balanced: return CGSize(width: 300, height: 169)
            case .compact: return CGSize(width: 270, height: 152)
            }
        }
        switch preset {
        case .cinematic: return CGSize(width: 186, height: 105)
        case .balanced: return CGSize(width: 174, height: 98)
        case .compact: return CGSize(width: 162, height: 91)
        }
    }

    func posterCardSize(isIPad: Bool) -> CGSize {
        if isIPad {
            switch preset {
            case .cinematic: return CGSize(width: 156, height: 234)
            case .balanced: return CGSize(width: 142, height: 213)
            case .compact: return CGSize(width: 128, height: 192)
            }
        }
        switch preset {
        case .cinematic: return CGSize(width: 116, height: 174)
        case .balanced: return CGSize(width: 108, height: 162)
        case .compact: return CGSize(width: 100, height: 150)
        }
    }

    static var current: ExperimentalMediaDesignMetrics {
        ExperimentalMediaDesignMetrics(
            preset: ExperimentalMediaDesignPreset.current,
            heroBleedLevel: ExperimentalHeroBleedLevel.current,
            cardShape: ExperimentalHomeCardShape.current
        )
    }
}

struct SettingsGradientBackground: View {
    @ObservedObject private var theme = EclipseTheme.shared
    var scrollOffset: CGFloat = 0
    
    // The gradient is taller than the screen and physically offset upward
    // as the user scrolls, so the color band visibly moves with the content.
    private var gradientOffset: CGFloat {
        -scrollOffset * 0.35
    }
    
    @ViewBuilder
    var body: some View {
#if !os(tvOS)
        let style = theme.scopedAtmosphereStyle()
        if style.isMultiGradient {
            ExperimentalGradientBackground(
                dominantColor: theme.scopedGradientColor(),
                scrollOffset: scrollOffset,
                style: style
            )
        } else {
            legacyBackground
        }
#else
        legacyBackground
#endif
    }

    private var legacyBackground: some View {
        GeometryReader { geo in
            let h = geo.size.height * 2.5
            let gradientColor = theme.scopedGradientColor()
            if theme.scopedAtmosphereStyle() == .solid {
                theme.scopedAtmosphereColor(dominant: gradientColor)
                    .frame(height: h)
            } else {
                LinearGradient(
                    stops: [
                        .init(color: theme.backgroundBase, location: 0.0),
                        .init(color: gradientColor.opacity(0.6), location: 0.15),
                        .init(color: gradientColor.opacity(0.3), location: 0.35),
                        .init(color: theme.backgroundBase, location: 0.6)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: h)
                .offset(y: gradientOffset)
            }
        }
        .clipped()
    }
}

/// Drop inside any scrollable container (ScrollView/List content)
/// to emit scroll offset for gradient tracking.
struct EclipseScrollTracker: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ScrollOffsetPreferenceKey.self,
                value: -geo.frame(in: .named("eclipseGradientScroll")).origin.y
            )
        }
        .frame(height: 0)
    }
}

struct GlobalGradientBackground: View {
    @ObservedObject private var theme = EclipseTheme.shared
    var overrideColor: Color? = nil
    var scrollOffset: CGFloat = 0
    
    private var gradientColor: Color {
        overrideColor ?? theme.scopedGradientColor()
    }
    
    private var gradientOffset: CGFloat {
        -scrollOffset * 0.15
    }
    
    @ViewBuilder
    var body: some View {
#if !os(tvOS)
        let style = theme.scopedAtmosphereStyle()
        if style.isMultiGradient {
            ExperimentalGradientBackground(dominantColor: overrideColor, scrollOffset: scrollOffset, style: style)
        } else {
            legacyBackground
        }
#else
        legacyBackground
#endif
    }

    private var legacyBackground: some View {
        GeometryReader { geo in
            let h = geo.size.height * 5.0
            if theme.scopedAtmosphereStyle() == .solid {
                theme.scopedAtmosphereColor(dominant: gradientColor)
                    .frame(height: h)
            } else {
                LinearGradient(
                    stops: [
                        .init(color: theme.backgroundBase, location: 0.0),
                        .init(color: gradientColor.opacity(0.7), location: 0.06),
                        .init(color: gradientColor.opacity(0.4), location: 0.15),
                        .init(color: gradientColor.opacity(0.15), location: 0.3),
                        .init(color: gradientColor.opacity(0.05), location: 0.5),
                        .init(color: theme.backgroundBase, location: 0.7)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: h)
                .offset(y: gradientOffset)
            }
        }
        .clipped()
    }
}

struct HeroBleedGradientBackground: View {
    var dominantColor: Color
    var scrollOffset: CGFloat
    var heroHeight: CGFloat
    var fadeDistance: CGFloat
    var bleedStrength: Double
    var style: AtmosphereStyle

    private var fadeProgress: Double {
        guard fadeDistance > 0 else { return 1 }
        let rawProgress = Double(max(0, min(scrollOffset / fadeDistance, 1)))
        return rawProgress * rawProgress * (3 - 2 * rawProgress)
    }

    private var activeStrength: Double {
        max(0, bleedStrength * (1 - fadeProgress))
    }

    @ViewBuilder
    private var baseBackground: some View {
        GlobalGradientBackground(scrollOffset: scrollOffset)
    }

    var body: some View {
        GeometryReader { geo in
            let bleedHeight = max(heroHeight + fadeDistance, geo.size.height * 0.72)
            let safeStrength = min(max(activeStrength, 0), 1.35)

            ZStack(alignment: .top) {
                baseBackground

                LinearGradient(
                    stops: [
                        .init(color: dominantColor.opacity(0.82 * safeStrength), location: 0.00),
                        .init(color: dominantColor.opacity(0.66 * safeStrength), location: 0.24),
                        .init(color: dominantColor.opacity(0.38 * safeStrength), location: 0.54),
                        .init(color: dominantColor.opacity(0.15 * safeStrength), location: 0.80),
                        .init(color: .clear, location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: bleedHeight)
                .offset(y: -scrollOffset * 0.08)

                RadialGradient(
                    colors: [
                        dominantColor.opacity(0.34 * safeStrength),
                        dominantColor.opacity(0.13 * safeStrength),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.18),
                    startRadius: 10,
                    endRadius: max(geo.size.width, bleedHeight) * 0.72
                )
                .frame(height: bleedHeight)
                .blendMode(style.isMultiGradient ? .screen : .normal)

                LinearGradient(
                    colors: [
                        .black.opacity(0.06),
                        .clear,
                        .black.opacity(0.18 * (1 - fadeProgress))
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: bleedHeight)
            }
        }
        .clipped()
    }
}

#if !os(tvOS)
struct ExperimentalGradientBackground: View {
    @ObservedObject private var theme = EclipseTheme.shared
    @AppStorage(ExperimentalMultiGradientPalette.storageKey) private var multiGradientPaletteRaw = ExperimentalMultiGradientPalette.defaultValue.rawValue
    var dominantColor: Color? = nil
    var scrollOffset: CGFloat = 0
    var style: AtmosphereStyle = .multiGradient

    private var accent: Color {
        dominantColor ?? Color(red: 0.25, green: 0.21, blue: 0.34)
    }

    private var palette: ExperimentalMultiGradientPalette {
        ExperimentalMultiGradientPalette(rawValue: multiGradientPaletteRaw) ?? .defaultValue
    }

    private var resolvedStyle: AtmosphereStyle {
        style.isMultiGradient ? style : .multiGradient
    }

    private var baseStops: [Gradient.Stop] {
        switch resolvedStyle {
        case .aurora:
            return [
                .init(color: Color(red: 0.05, green: 0.10, blue: 0.14), location: 0.00),
                .init(color: Color(red: 0.08, green: 0.25, blue: 0.26), location: 0.22),
                .init(color: Color(red: 0.22, green: 0.21, blue: 0.46), location: 0.48),
                .init(color: Color(red: 0.18, green: 0.12, blue: 0.27), location: 0.72),
                .init(color: Color(red: 0.07, green: 0.06, blue: 0.10), location: 1.00)
            ]
        case .ember:
            return [
                .init(color: Color(red: 0.11, green: 0.08, blue: 0.10), location: 0.00),
                .init(color: Color(red: 0.29, green: 0.15, blue: 0.16), location: 0.24),
                .init(color: Color(red: 0.48, green: 0.31, blue: 0.20), location: 0.50),
                .init(color: Color(red: 0.23, green: 0.16, blue: 0.27), location: 0.76),
                .init(color: Color(red: 0.08, green: 0.06, blue: 0.09), location: 1.00)
            ]
        case .multiGradient, .gradient, .solid:
            switch palette {
            case .eclipse:
                return [
                    .init(color: Color(red: 0.070, green: 0.062, blue: 0.090), location: 0.00),
                    .init(color: Color(red: 0.105, green: 0.086, blue: 0.130), location: 0.24),
                    .init(color: Color(red: 0.165, green: 0.126, blue: 0.188), location: 0.50),
                    .init(color: Color(red: 0.145, green: 0.094, blue: 0.124), location: 0.74),
                    .init(color: Color(red: 0.074, green: 0.064, blue: 0.088), location: 1.00)
                ]
            case .nocturne:
                return [
                    .init(color: Color(red: 0.052, green: 0.058, blue: 0.078), location: 0.00),
                    .init(color: Color(red: 0.078, green: 0.100, blue: 0.126), location: 0.24),
                    .init(color: Color(red: 0.114, green: 0.118, blue: 0.166), location: 0.50),
                    .init(color: Color(red: 0.118, green: 0.084, blue: 0.126), location: 0.74),
                    .init(color: Color(red: 0.058, green: 0.056, blue: 0.074), location: 1.00)
                ]
            case .velvet:
                return [
                    .init(color: Color(red: 0.080, green: 0.058, blue: 0.082), location: 0.00),
                    .init(color: Color(red: 0.132, green: 0.082, blue: 0.112), location: 0.24),
                    .init(color: Color(red: 0.170, green: 0.112, blue: 0.158), location: 0.50),
                    .init(color: Color(red: 0.112, green: 0.088, blue: 0.150), location: 0.74),
                    .init(color: Color(red: 0.068, green: 0.058, blue: 0.080), location: 1.00)
                ]
            case .auroraMuted:
                return [
                    .init(color: Color(red: 0.052, green: 0.076, blue: 0.086), location: 0.00),
                    .init(color: Color(red: 0.070, green: 0.124, blue: 0.126), location: 0.24),
                    .init(color: Color(red: 0.112, green: 0.112, blue: 0.168), location: 0.50),
                    .init(color: Color(red: 0.126, green: 0.092, blue: 0.136), location: 0.74),
                    .init(color: Color(red: 0.058, green: 0.060, blue: 0.078), location: 1.00)
                ]
            }
        }
    }

    private var washStops: [Gradient.Stop] {
        switch resolvedStyle {
        case .aurora:
            return [
                .init(color: Color(red: 0.08, green: 0.80, blue: 0.72).opacity(0.36), location: 0.02),
                .init(color: Color(red: 0.28, green: 0.38, blue: 0.92).opacity(0.28), location: 0.34),
                .init(color: Color(red: 0.78, green: 0.30, blue: 0.72).opacity(0.22), location: 0.68),
                .init(color: Color(red: 0.92, green: 0.64, blue: 0.28).opacity(0.12), location: 0.95)
            ]
        case .ember:
            return [
                .init(color: Color(red: 0.94, green: 0.54, blue: 0.18).opacity(0.30), location: 0.02),
                .init(color: Color(red: 0.82, green: 0.24, blue: 0.40).opacity(0.24), location: 0.34),
                .init(color: Color(red: 0.35, green: 0.26, blue: 0.84).opacity(0.22), location: 0.68),
                .init(color: Color(red: 0.07, green: 0.62, blue: 0.72).opacity(0.12), location: 0.95)
            ]
        case .multiGradient, .gradient, .solid:
            switch palette {
            case .eclipse:
                return [
                    .init(color: Color(red: 0.06, green: 0.30, blue: 0.30).opacity(0.18), location: 0.04),
                    .init(color: Color(red: 0.28, green: 0.20, blue: 0.40).opacity(0.18), location: 0.34),
                    .init(color: Color(red: 0.38, green: 0.14, blue: 0.22).opacity(0.14), location: 0.68),
                    .init(color: Color(red: 0.48, green: 0.30, blue: 0.16).opacity(0.10), location: 0.96)
                ]
            case .nocturne:
                return [
                    .init(color: Color(red: 0.08, green: 0.26, blue: 0.34).opacity(0.16), location: 0.04),
                    .init(color: Color(red: 0.18, green: 0.22, blue: 0.42).opacity(0.16), location: 0.38),
                    .init(color: Color(red: 0.28, green: 0.16, blue: 0.30).opacity(0.12), location: 0.72)
                ]
            case .velvet:
                return [
                    .init(color: Color(red: 0.38, green: 0.14, blue: 0.24).opacity(0.18), location: 0.04),
                    .init(color: Color(red: 0.30, green: 0.18, blue: 0.42).opacity(0.16), location: 0.40),
                    .init(color: Color(red: 0.54, green: 0.28, blue: 0.16).opacity(0.10), location: 0.88)
                ]
            case .auroraMuted:
                return [
                    .init(color: Color(red: 0.08, green: 0.42, blue: 0.36).opacity(0.16), location: 0.04),
                    .init(color: Color(red: 0.24, green: 0.28, blue: 0.50).opacity(0.16), location: 0.44),
                    .init(color: Color(red: 0.46, green: 0.22, blue: 0.38).opacity(0.11), location: 0.88)
                ]
            }
        }
    }

    private var angularColors: [Color] {
        switch resolvedStyle {
        case .aurora:
            return [
                Color(red: 0.08, green: 0.84, blue: 0.70).opacity(0.28),
                accent.opacity(0.30),
                Color(red: 0.56, green: 0.26, blue: 0.88).opacity(0.26),
                Color(red: 0.10, green: 0.46, blue: 0.62).opacity(0.30),
                Color(red: 0.08, green: 0.84, blue: 0.70).opacity(0.28)
            ]
        case .ember:
            return [
                Color(red: 0.96, green: 0.54, blue: 0.20).opacity(0.28),
                accent.opacity(0.30),
                Color(red: 0.80, green: 0.22, blue: 0.42).opacity(0.24),
                Color(red: 0.28, green: 0.26, blue: 0.70).opacity(0.26),
                Color(red: 0.96, green: 0.54, blue: 0.20).opacity(0.28)
            ]
        case .multiGradient, .gradient, .solid:
            return [
                Color(red: 0.07, green: 0.34, blue: 0.36).opacity(0.12),
                accent.opacity(0.16),
                Color(red: 0.38, green: 0.15, blue: 0.27).opacity(0.12),
                Color(red: 0.24, green: 0.22, blue: 0.44).opacity(0.14),
                Color(red: 0.07, green: 0.34, blue: 0.36).opacity(0.12)
            ]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let h = max(geo.size.height * 1.65, geo.size.height + 1)
            ZStack {
                Color(red: 0.068, green: 0.060, blue: 0.088)

                LinearGradient(
                    stops: baseStops,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: h)
                .offset(y: -scrollOffset * 0.10)

                LinearGradient(
                    stops: washStops,
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .blendMode(.screen)
                .offset(y: -scrollOffset * 0.055)

                RadialGradient(
                    colors: angularColors,
                    center: UnitPoint(x: 0.48, y: 0.34),
                    startRadius: 16,
                    endRadius: max(geo.size.width, geo.size.height) * 0.86
                )
                .opacity(0.54)
                .blendMode(.screen)

                LinearGradient(
                    colors: [
                        accent.opacity(resolvedStyle == .multiGradient ? 0.18 : 0.24),
                        .clear,
                        Color(red: 0.06, green: 0.24, blue: 0.26).opacity(resolvedStyle == .multiGradient ? 0.14 : 0.22)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(y: -scrollOffset * 0.03)

                LinearGradient(
                    colors: [
                        .black.opacity(resolvedStyle == .multiGradient ? 0.10 : 0.08),
                        .clear,
                        .black.opacity(resolvedStyle == .multiGradient ? 0.34 : 0.30)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .clipped()
    }
}

struct ExperimentalCard<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.13, blue: 0.23).opacity(0.82),
                                Color(red: 0.09, green: 0.09, blue: 0.14).opacity(0.74)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.16),
                                        Color(red: 0.58, green: 0.42, blue: 1.0).opacity(0.34),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color(red: 0.10, green: 0.05, blue: 0.20).opacity(0.38), radius: 22, x: 0, y: 12)
            )
    }
}

struct ExperimentalSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)

            content
        }
    }
}

struct ExperimentalCircleButton: View {
    let systemName: String
    var size: CGFloat = 44
    var isSelected: Bool = false
    var accessibilityLabel: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isSelected
                                    ? [
                                        Color(red: 0.42, green: 0.34, blue: 0.78).opacity(0.80),
                                        Color(red: 0.12, green: 0.11, blue: 0.20).opacity(0.90)
                                    ]
                                    : [
                                        Color(red: 0.10, green: 0.10, blue: 0.16).opacity(0.86),
                                        Color.black.opacity(0.42)
                                    ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected ? Color(red: 0.50, green: 0.42, blue: 0.92).opacity(0.70) : Color.white.opacity(0.14),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.24), radius: 16, x: 0, y: 10)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }
}

struct ExperimentalFloatingTabItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let systemImage: String
}

struct ExperimentalFloatingTabBar<ID: Hashable>: View {
    let items: [ExperimentalFloatingTabItem<ID>]
    @Binding var selection: ID
    var searchItemID: ID? = nil
    var searchAction: (() -> Void)?
    var trailingSystemImage: String? = nil
    var trailingAccessibilityLabel: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(items) { item in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            selection = item.id
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                            Text(item.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundColor(.white)
                        .frame(minWidth: 48)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 1)
                        .background(
                            Capsule()
                                .fill(
                                    selection == item.id
                                        ? Color.white.opacity(0.20)
                                        : Color.clear
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.10, green: 0.10, blue: 0.17).opacity(0.92),
                                Color.black.opacity(0.46)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color(red: 0.43, green: 0.35, blue: 0.82).opacity(0.52), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.26), radius: 20, x: 0, y: 12)
            )

            if let searchAction {
                ExperimentalCircleButton(
                    systemName: "magnifyingglass",
                    size: 50,
                    isSelected: searchItemID.map { $0 == selection } ?? false,
                    accessibilityLabel: "Search",
                    action: searchAction
                )
            }

            if let trailingSystemImage, let trailingAction {
                ExperimentalCircleButton(
                    systemName: trailingSystemImage,
                    size: 44,
                    accessibilityLabel: trailingAccessibilityLabel,
                    action: trailingAction
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
#endif
