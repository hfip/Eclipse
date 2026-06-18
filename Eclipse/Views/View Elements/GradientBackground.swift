//
//  GradientBackground.swift
//  Eclipse
//
//  Gradient background for Settings screens
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

struct ExperimentalVisualTuning {
    static let heroHeightScaleKey = "experimentalHeroHeightScale"
    static let heroBleedStrengthKey = "experimentalHeroBleedStrength"
    static let heroFadeDistanceScaleKey = "experimentalHeroFadeDistanceScale"
    static let sectionSpacingScaleKey = "experimentalSectionSpacingScale"
    static let cardRadiusScaleKey = "experimentalCardRadiusScale"
    static let mediaCardScaleKey = "experimentalMediaCardScale"
    static let glassStrengthKey = "experimentalGlassStrength"
    static let gradientBaseDarknessKey = "experimentalGradientBaseDarkness"
    static let gradientAccentIntensityKey = "experimentalGradientAccentIntensity"
    static let gradientScrollMotionKey = "experimentalGradientScrollMotion"
    static let gradientUseCustomColorsKey = "experimentalGradientUseCustomColors"
    static let gradientColorAKey = "experimentalGradientColorA"
    static let gradientColorBKey = "experimentalGradientColorB"
    static let gradientColorCKey = "experimentalGradientColorC"

    static let defaultHeroHeightScale = 1.0
    static let defaultHeroBleedStrength = 1.0
    static let defaultHeroFadeDistanceScale = 1.0
    static let defaultSectionSpacingScale = 1.0
    static let defaultCardRadiusScale = 1.0
    static let defaultMediaCardScale = 1.0
    static let defaultGlassStrength = 1.0
    static let defaultGradientBaseDarkness = 1.0
    static let defaultGradientAccentIntensity = 1.0
    static let defaultGradientScrollMotion = 1.0

    var heroHeightScale: Double
    var heroBleedStrength: Double
    var heroFadeDistanceScale: Double
    var sectionSpacingScale: Double
    var cardRadiusScale: Double
    var mediaCardScale: Double
    var glassStrength: Double
    var gradientBaseDarkness: Double
    var gradientAccentIntensity: Double
    var gradientScrollMotion: Double
    var gradientUseCustomColors: Bool
    var gradientColorA: Color?
    var gradientColorB: Color?
    var gradientColorC: Color?

    static var current: ExperimentalVisualTuning {
        let defaults = UserDefaults.standard
        return ExperimentalVisualTuning(
            heroHeightScale: sanitizedHeroHeightScale(defaults.doubleValue(forKey: heroHeightScaleKey, defaultValue: defaultHeroHeightScale)),
            heroBleedStrength: sanitizedHeroBleedStrength(defaults.doubleValue(forKey: heroBleedStrengthKey, defaultValue: defaultHeroBleedStrength)),
            heroFadeDistanceScale: sanitizedHeroFadeDistanceScale(defaults.doubleValue(forKey: heroFadeDistanceScaleKey, defaultValue: defaultHeroFadeDistanceScale)),
            sectionSpacingScale: sanitizedSectionSpacingScale(defaults.doubleValue(forKey: sectionSpacingScaleKey, defaultValue: defaultSectionSpacingScale)),
            cardRadiusScale: sanitizedCardRadiusScale(defaults.doubleValue(forKey: cardRadiusScaleKey, defaultValue: defaultCardRadiusScale)),
            mediaCardScale: sanitizedMediaCardScale(defaults.doubleValue(forKey: mediaCardScaleKey, defaultValue: defaultMediaCardScale)),
            glassStrength: sanitizedGlassStrength(defaults.doubleValue(forKey: glassStrengthKey, defaultValue: defaultGlassStrength)),
            gradientBaseDarkness: sanitizedGradientBaseDarkness(defaults.doubleValue(forKey: gradientBaseDarknessKey, defaultValue: defaultGradientBaseDarkness)),
            gradientAccentIntensity: sanitizedGradientAccentIntensity(defaults.doubleValue(forKey: gradientAccentIntensityKey, defaultValue: defaultGradientAccentIntensity)),
            gradientScrollMotion: sanitizedGradientScrollMotion(defaults.doubleValue(forKey: gradientScrollMotionKey, defaultValue: defaultGradientScrollMotion)),
            gradientUseCustomColors: defaults.bool(forKey: gradientUseCustomColorsKey),
            gradientColorA: loadColor(key: gradientColorAKey),
            gradientColorB: loadColor(key: gradientColorBKey),
            gradientColorC: loadColor(key: gradientColorCKey)
        )
    }

    static func sanitizedHeroHeightScale(_ value: Double?) -> Double { clamp(value, defaultValue: defaultHeroHeightScale, range: 0.75...1.15) }
    static func sanitizedHeroBleedStrength(_ value: Double?) -> Double { clamp(value, defaultValue: defaultHeroBleedStrength, range: 0.0...1.5) }
    static func sanitizedHeroFadeDistanceScale(_ value: Double?) -> Double { clamp(value, defaultValue: defaultHeroFadeDistanceScale, range: 0.6...1.6) }
    static func sanitizedSectionSpacingScale(_ value: Double?) -> Double { clamp(value, defaultValue: defaultSectionSpacingScale, range: 0.75...1.35) }
    static func sanitizedCardRadiusScale(_ value: Double?) -> Double { clamp(value, defaultValue: defaultCardRadiusScale, range: 0.7...1.4) }
    static func sanitizedMediaCardScale(_ value: Double?) -> Double { clamp(value, defaultValue: defaultMediaCardScale, range: 0.85...1.2) }
    static func sanitizedGlassStrength(_ value: Double?) -> Double { clamp(value, defaultValue: defaultGlassStrength, range: 0.0...1.4) }
    static func sanitizedGradientBaseDarkness(_ value: Double?) -> Double { clamp(value, defaultValue: defaultGradientBaseDarkness, range: 0.7...1.3) }
    static func sanitizedGradientAccentIntensity(_ value: Double?) -> Double { clamp(value, defaultValue: defaultGradientAccentIntensity, range: 0.0...1.6) }
    static func sanitizedGradientScrollMotion(_ value: Double?) -> Double { clamp(value, defaultValue: defaultGradientScrollMotion, range: 0.0...1.4) }

    private static func clamp(_ value: Double?, defaultValue: Double, range: ClosedRange<Double>) -> Double {
        guard let value, value.isFinite else { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func saveColor(_ color: Color, key: String) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: UIColor(color), requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: key)
        } catch { }
    }

    static func loadColor(key: String) -> Color? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let color = loadColor(data: data) else {
            return nil
        }
        return color
    }

    static func loadColor(data: Data) -> Color? {
        guard !data.isEmpty,
              let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) else {
            return nil
        }
        return Color(uiColor)
    }

    static func colorData(_ color: Color) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: UIColor(color), requiringSecureCoding: true)
    }
}

private extension UserDefaults {
    func doubleValue(forKey key: String, defaultValue: Double) -> Double {
        object(forKey: key) == nil ? defaultValue : double(forKey: key)
    }
}

struct ExperimentalMediaDesignMetrics {
    let preset: ExperimentalMediaDesignPreset
    let heroBleedLevel: ExperimentalHeroBleedLevel
    let cardShape: ExperimentalHomeCardShape
    let tuning: ExperimentalVisualTuning

    init(
        preset: ExperimentalMediaDesignPreset,
        heroBleedLevel: ExperimentalHeroBleedLevel,
        cardShape: ExperimentalHomeCardShape,
        tuning: ExperimentalVisualTuning = .current
    ) {
        self.preset = preset
        self.heroBleedLevel = heroBleedLevel
        self.cardShape = cardShape
        self.tuning = tuning
    }

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
        let base: CGFloat
        switch preset {
        case .cinematic: base = 560
        case .balanced: base = 440
        case .compact: base = 320
        }
        return base * CGFloat(tuning.heroFadeDistanceScale)
    }

    var heroWashStrength: Double {
        let base: Double
        switch preset {
        case .cinematic: base = 0.94
        case .balanced: base = 0.76
        case .compact: base = 0.58
        }
        return base * heroBleedLevel.strengthMultiplier * tuning.heroBleedStrength
    }

    var contentTopOverlap: CGFloat {
        switch preset {
        case .cinematic: return 34
        case .balanced: return 22
        case .compact: return 10
        }
    }

    var sectionSpacing: CGFloat {
        let base: CGFloat
        switch preset {
        case .cinematic: base = 30
        case .balanced: base = 24
        case .compact: base = 18
        }
        return base * CGFloat(tuning.sectionSpacingScale)
    }

    var cardRadius: CGFloat {
        let base: CGFloat
        switch preset {
        case .cinematic: base = 20
        case .balanced: base = 18
        case .compact: base = 16
        }
        return base * CGFloat(tuning.cardRadiusScale)
    }

    var glassOpacity: Double {
        let base: Double
        switch preset {
        case .cinematic: base = 0.72
        case .balanced: base = 0.64
        case .compact: base = 0.56
        }
        return min(max(base * tuning.glassStrength, 0), 0.95)
    }

    var heroBottomFadeHeight: CGFloat {
        let base: CGFloat
        switch preset {
        case .cinematic: base = 520
        case .balanced: base = 420
        case .compact: base = 320
        }
        return base * CGFloat(tuning.heroFadeDistanceScale)
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
            let base: CGFloat
            switch preset {
            case .cinematic: base = 780
            case .balanced: base = 720
            case .compact: base = 640
            }
            return base * CGFloat(tuning.heroHeightScale)
        }
        let minimum: CGFloat = preset == .compact ? 560 : 640
        let maximum: CGFloat = preset == .cinematic ? 820 : 760
        return min(max(screenHeight * homeHeroHeightRatio * CGFloat(tuning.heroHeightScale), minimum), maximum)
    }

    func detailHeroHeight(screenHeight: CGFloat, isIPad: Bool) -> CGFloat {
        if isIPad {
            let base: CGFloat
            switch preset {
            case .cinematic: base = 760
            case .balanced: base = 700
            case .compact: base = 620
            }
            return base * CGFloat(tuning.heroHeightScale)
        }
        let minimum: CGFloat = preset == .compact ? 560 : 650
        let maximum: CGFloat = preset == .cinematic ? 850 : 780
        return min(max(screenHeight * detailHeroHeightRatio * CGFloat(tuning.heroHeightScale), minimum), maximum)
    }

    func landscapeCardSize(isIPad: Bool) -> CGSize {
        if isIPad {
            switch preset {
            case .cinematic: return scaled(CGSize(width: 330, height: 186))
            case .balanced: return scaled(CGSize(width: 300, height: 169))
            case .compact: return scaled(CGSize(width: 270, height: 152))
            }
        }
        switch preset {
        case .cinematic: return scaled(CGSize(width: 196, height: 110))
        case .balanced: return scaled(CGSize(width: 184, height: 104))
        case .compact: return scaled(CGSize(width: 168, height: 95))
        }
    }

    func posterCardSize(isIPad: Bool) -> CGSize {
        if isIPad {
            switch preset {
            case .cinematic: return scaled(CGSize(width: 156, height: 234))
            case .balanced: return scaled(CGSize(width: 142, height: 213))
            case .compact: return scaled(CGSize(width: 128, height: 192))
            }
        }
        switch preset {
        case .cinematic: return scaled(CGSize(width: 116, height: 174))
        case .balanced: return scaled(CGSize(width: 108, height: 162))
        case .compact: return scaled(CGSize(width: 100, height: 150))
        }
    }

    private func scaled(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width * CGFloat(tuning.mediaCardScale),
            height: size.height * CGFloat(tuning.mediaCardScale)
        )
    }

    static var current: ExperimentalMediaDesignMetrics {
        ExperimentalMediaDesignMetrics(
            preset: ExperimentalMediaDesignPreset.current,
            heroBleedLevel: ExperimentalHeroBleedLevel.current,
            cardShape: ExperimentalHomeCardShape.current,
            tuning: .current
        )
    }
}

struct SettingsGradientBackground: View {
    @ObservedObject private var theme = EclipseTheme.shared
    
    @ViewBuilder
    var body: some View {
#if !os(tvOS)
        let style = theme.scopedAtmosphereStyle()
        if style.isMultiGradient {
            AtmosphereBackdrop(
                input: theme.atmosphereInput(dominant: nil, hasHeroBleed: false, heroHeight: 0, fadeDistance: 1),
                scrollOffset: 0
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
        -scrollOffset * 0.15 * CGFloat(ExperimentalVisualTuning.current.gradientScrollMotion)
    }
    
    @ViewBuilder
    var body: some View {
#if !os(tvOS)
        let style = theme.scopedAtmosphereStyle()
        if style.isMultiGradient {
            AtmosphereBackdrop(
                input: theme.atmosphereInput(dominant: overrideColor, hasHeroBleed: false, heroHeight: 0, fadeDistance: 1),
                scrollOffset: scrollOffset
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
            let safeStrength = min(max(activeStrength, 0), 1.5)

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
    @AppStorage(ExperimentalVisualTuning.gradientBaseDarknessKey) private var gradientBaseDarkness = ExperimentalVisualTuning.defaultGradientBaseDarkness
    @AppStorage(ExperimentalVisualTuning.gradientAccentIntensityKey) private var gradientAccentIntensity = ExperimentalVisualTuning.defaultGradientAccentIntensity
    @AppStorage(ExperimentalVisualTuning.gradientScrollMotionKey) private var gradientScrollMotion = ExperimentalVisualTuning.defaultGradientScrollMotion
    @AppStorage(ExperimentalVisualTuning.gradientUseCustomColorsKey) private var gradientUseCustomColors = false
    @AppStorage(ExperimentalVisualTuning.gradientColorAKey) private var gradientColorAData = Data()
    @AppStorage(ExperimentalVisualTuning.gradientColorBKey) private var gradientColorBData = Data()
    @AppStorage(ExperimentalVisualTuning.gradientColorCKey) private var gradientColorCData = Data()
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

    private var sanitizedBaseDarkness: Double {
        ExperimentalVisualTuning.sanitizedGradientBaseDarkness(gradientBaseDarkness)
    }

    private var sanitizedAccentIntensity: Double {
        ExperimentalVisualTuning.sanitizedGradientAccentIntensity(gradientAccentIntensity)
    }

    private var sanitizedScrollMotion: Double {
        ExperimentalVisualTuning.sanitizedGradientScrollMotion(gradientScrollMotion)
    }

    private var customGradientColors: [Color]? {
        guard gradientUseCustomColors,
              let first = ExperimentalVisualTuning.loadColor(data: gradientColorAData),
              let second = ExperimentalVisualTuning.loadColor(data: gradientColorBData),
              let third = ExperimentalVisualTuning.loadColor(data: gradientColorCData) else {
            return nil
        }
        return [first, second, third]
    }

    private var baseStops: [Gradient.Stop] {
        if let customGradientColors {
            return [
                .init(color: Color(red: 0.054, green: 0.048, blue: 0.066), location: 0.00),
                .init(color: customGradientColors[0].opacity(0.34), location: 0.24),
                .init(color: customGradientColors[1].opacity(0.30), location: 0.52),
                .init(color: customGradientColors[2].opacity(0.26), location: 0.76),
                .init(color: Color(red: 0.060, green: 0.052, blue: 0.070), location: 1.00)
            ]
        }

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
        if let customGradientColors {
            return [
                customGradientColors[0].opacity(0.24),
                accent.opacity(0.28),
                customGradientColors[1].opacity(0.24),
                customGradientColors[2].opacity(0.22),
                customGradientColors[0].opacity(0.24)
            ]
        }

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
                .offset(y: -scrollOffset * 0.10 * sanitizedScrollMotion)

                LinearGradient(
                    stops: washStops,
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .opacity(sanitizedAccentIntensity)
                .blendMode(.screen)
                .offset(y: -scrollOffset * 0.055 * sanitizedScrollMotion)

                RadialGradient(
                    colors: angularColors,
                    center: UnitPoint(x: 0.48, y: 0.34),
                    startRadius: 16,
                    endRadius: max(geo.size.width, geo.size.height) * 0.86
                )
                .opacity(0.54 * sanitizedAccentIntensity)
                .blendMode(.screen)

                LinearGradient(
                    colors: [
                        accent.opacity((resolvedStyle == .multiGradient ? 0.18 : 0.24) * sanitizedAccentIntensity),
                        .clear,
                        Color(red: 0.06, green: 0.24, blue: 0.26).opacity((resolvedStyle == .multiGradient ? 0.14 : 0.22) * sanitizedAccentIntensity)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(y: -scrollOffset * 0.03 * sanitizedScrollMotion)

                Color.black
                    .opacity(max(0, sanitizedBaseDarkness - 1) * 0.28)

                Color.white
                    .opacity(max(0, 1 - sanitizedBaseDarkness) * 0.06)
                    .blendMode(.screen)

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

#endif

// MARK: - Eclipse Design Tokens
//
// A single source of truth for spacing, radius, type, and shadow so every
// screen reads from the same scale instead of re-inventing values inline.

enum EclipseSpacing {
    static let xs: CGFloat = 6
    static let s: CGFloat = 10
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
}

enum EclipseRadius {
    /// The shared card radius, sourced from the active design metrics.
    static var card: CGFloat { ExperimentalMediaDesignMetrics.current.cardRadius }
    static let chip: CGFloat = 10
    static let control: CGFloat = 14
    static let hero: CGFloat = 20
}

enum EclipseType {
    static func screenTitle(_ pad: Bool = false) -> Font { .system(size: isIPad ? 34 : 28, weight: .heavy) }
    static var sectionHeader: Font { .system(size: isIPad ? 24 : 21, weight: .bold) }
    static var cardTitle: Font { .system(size: isIPad ? 19 : 17, weight: .semibold) }
    static var cardSubtitle: Font { .system(size: isIPad ? 15 : 14, weight: .regular) }
    static var badge: Font { .system(size: 11, weight: .bold) }
}

enum EclipseShadowTier {
    case subtle
    case standard
    case elevated
    case floating

    var radius: CGFloat {
        switch self {
        case .subtle: return 8
        case .standard: return 14
        case .elevated: return 18
        case .floating: return 26
        }
    }

    var yOffset: CGFloat {
        switch self {
        case .subtle: return 4
        case .standard: return 8
        case .elevated: return 10
        case .floating: return 14
        }
    }

    var opacity: Double {
        switch self {
        case .subtle: return 0.20
        case .standard: return 0.26
        case .elevated: return 0.30
        case .floating: return 0.34
        }
    }
}

extension View {
    /// Apply one of the four shared elevation tiers.
    func eclipseShadow(_ tier: EclipseShadowTier = .standard) -> some View {
        shadow(color: Color.black.opacity(tier.opacity), radius: tier.radius, x: 0, y: tier.yOffset)
    }
}

// MARK: - Modern Atmosphere System
//
// Replaces the broken multi-layer ExperimentalGradientBackground / HeroBleed
// stack with a single compositor (AtmosphereBackdrop) that renders the app
// gradient and the scroll-driven banner bleed in one coordinate space sharing
// one parallax offset, so they can never seam or produce bright spots.

extension Color {
    /// Scales a color for the Background Intensity control. `intensity == 1`
    /// returns the color unchanged; `< 1` darkens and `> 1` lifts it (clamped).
    func atmosphereScaled(_ intensity: Double) -> Color {
        guard intensity != 1.0 else { return self }
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        let f = CGFloat(intensity)
        return Color(
            red: Double(min(max(r * f, 0), 1)),
            green: Double(min(max(g * f, 0), 1)),
            blue: Double(min(max(b * f, 0), 1)),
            opacity: Double(a)
        )
        #else
        return self
        #endif
    }
}

/// A curated dark multi-gradient palette. Mesh colors are kept inside a tight
/// luminance band so the rendered background has no bright spots.
struct AtmospherePalette: Equatable {
    let id: String
    let displayName: String
    /// 12 colors, row-major 3 columns × 4 rows, for the iOS 18 MeshGradient.
    let mesh: [Color]
    /// Vertical stops for the iOS 15–17 fallback (top → bottom).
    let verticalStops: [Gradient.Stop]
    /// Soft top wash for the fallback's top-anchored radial.
    let topWash: Color

    func meshColors(intensity: Double) -> [Color] {
        intensity == 1.0 ? mesh : mesh.map { $0.atmosphereScaled(intensity) }
    }

    func scaledVerticalStops(intensity: Double) -> [Gradient.Stop] {
        intensity == 1.0 ? verticalStops : verticalStops.map {
            Gradient.Stop(color: $0.color.atmosphereScaled(intensity), location: $0.location)
        }
    }
}

enum AtmospherePaletteID: String, CaseIterable, Identifiable {
    case midnightPurple
    case nocturne
    case velvet
    case mutedAurora
    case custom

    var id: String { rawValue }
    static var defaultValue: AtmospherePaletteID { .midnightPurple }

    var displayName: String {
        switch self {
        case .midnightPurple: return "Midnight Purple"
        case .nocturne: return "Nocturne"
        case .velvet: return "Velvet"
        case .mutedAurora: return "Muted Aurora"
        case .custom: return "Custom"
        }
    }

    static func from(_ raw: String?) -> AtmospherePaletteID {
        AtmospherePaletteID(rawValue: raw ?? "") ?? .defaultValue
    }
}

enum AppearancePalettes {
    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    // Purple-dominant but genuinely multi-hued: indigo, violet, magenta and
    // blue blend together so it reads as a multi-gradient, not flat purple.
    static let midnightPurple = AtmospherePalette(
        id: "midnightPurple", displayName: "Midnight Purple",
        mesh: [
            c(0.105, 0.070, 0.210), c(0.165, 0.085, 0.235), c(0.085, 0.090, 0.240),
            c(0.195, 0.082, 0.215), c(0.180, 0.110, 0.300), c(0.095, 0.110, 0.285),
            c(0.150, 0.080, 0.215), c(0.130, 0.100, 0.270), c(0.080, 0.100, 0.235),
            c(0.065, 0.052, 0.110), c(0.078, 0.060, 0.130), c(0.055, 0.055, 0.105)
        ],
        verticalStops: [
            .init(color: c(0.130, 0.085, 0.235), location: 0.0),
            .init(color: c(0.175, 0.105, 0.285), location: 0.40),
            .init(color: c(0.070, 0.058, 0.120), location: 1.0)
        ],
        topWash: c(0.42, 0.22, 0.58)
    )

    // Blue-dominant with teal and indigo accents.
    static let nocturne = AtmospherePalette(
        id: "nocturne", displayName: "Nocturne",
        mesh: [
            c(0.060, 0.095, 0.205), c(0.080, 0.125, 0.255), c(0.060, 0.105, 0.225),
            c(0.072, 0.150, 0.270), c(0.100, 0.165, 0.320), c(0.070, 0.135, 0.300),
            c(0.060, 0.120, 0.235), c(0.090, 0.140, 0.295), c(0.070, 0.105, 0.260),
            c(0.048, 0.060, 0.120), c(0.058, 0.072, 0.140), c(0.044, 0.058, 0.110)
        ],
        verticalStops: [
            .init(color: c(0.078, 0.125, 0.255), location: 0.0),
            .init(color: c(0.095, 0.155, 0.305), location: 0.40),
            .init(color: c(0.050, 0.062, 0.125), location: 1.0)
        ],
        topWash: c(0.20, 0.42, 0.62)
    )

    // Wine / magenta dominant with violet accents.
    static let velvet = AtmospherePalette(
        id: "velvet", displayName: "Velvet",
        mesh: [
            c(0.165, 0.060, 0.140), c(0.205, 0.080, 0.180), c(0.140, 0.070, 0.165),
            c(0.225, 0.080, 0.205), c(0.245, 0.105, 0.260), c(0.165, 0.085, 0.225),
            c(0.185, 0.070, 0.180), c(0.165, 0.095, 0.245), c(0.125, 0.075, 0.190),
            c(0.085, 0.050, 0.105), c(0.095, 0.062, 0.125), c(0.072, 0.050, 0.100)
        ],
        verticalStops: [
            .init(color: c(0.205, 0.080, 0.180), location: 0.0),
            .init(color: c(0.235, 0.100, 0.250), location: 0.40),
            .init(color: c(0.082, 0.052, 0.105), location: 1.0)
        ],
        topWash: c(0.55, 0.20, 0.46)
    )

    // Teal / green dominant drifting into violet.
    static let mutedAurora = AtmospherePalette(
        id: "mutedAurora", displayName: "Muted Aurora",
        mesh: [
            c(0.050, 0.130, 0.140), c(0.070, 0.165, 0.180), c(0.065, 0.125, 0.205),
            c(0.072, 0.185, 0.200), c(0.095, 0.205, 0.240), c(0.110, 0.140, 0.265),
            c(0.075, 0.155, 0.205), c(0.095, 0.165, 0.250), c(0.110, 0.120, 0.265),
            c(0.048, 0.072, 0.115), c(0.058, 0.090, 0.135), c(0.052, 0.072, 0.120)
        ],
        verticalStops: [
            .init(color: c(0.070, 0.165, 0.185), location: 0.0),
            .init(color: c(0.100, 0.185, 0.245), location: 0.40),
            .init(color: c(0.050, 0.072, 0.120), location: 1.0)
        ],
        topWash: c(0.16, 0.52, 0.54)
    )

    static func base(for id: AtmospherePaletteID) -> AtmospherePalette {
        switch id {
        case .midnightPurple: return midnightPurple
        case .nocturne: return nocturne
        case .velvet: return velvet
        case .mutedAurora: return mutedAurora
        case .custom: return midnightPurple
        }
    }

    static func resolved(id: AtmospherePaletteID, customColors: [Color]) -> AtmospherePalette {
        id == .custom ? custom(customColors) : base(for: id)
    }

    static func custom(_ colors: [Color]) -> AtmospherePalette {
        let a = colors.indices.contains(0) ? colors[0] : c(0.16, 0.12, 0.20)
        let b = colors.indices.contains(1) ? colors[1] : c(0.26, 0.16, 0.34)
        let cc = colors.indices.contains(2) ? colors[2] : c(0.20, 0.12, 0.16)
        let aD = a.atmosphereScaled(0.5)
        let bMid = b.atmosphereScaled(0.62)
        let bD = b.atmosphereScaled(0.5)
        let cD = cc.atmosphereScaled(0.46)
        let deep = c(0.058, 0.050, 0.080)
        return AtmospherePalette(
            id: "custom", displayName: "Custom",
            mesh: [
                aD, a.atmosphereScaled(0.56), aD,
                bD, bMid, bD,
                cD, cc.atmosphereScaled(0.52), cD,
                deep, deep, deep
            ],
            verticalStops: [
                .init(color: aD, location: 0.0),
                .init(color: bMid, location: 0.42),
                .init(color: deep, location: 1.0)
            ],
            topWash: a
        )
    }
}

/// Persistence keys, clamps and one-time legacy migration for the appearance
/// controls. Values are owned here and persisted by EclipseTheme.
enum AppearanceConfig {
    static let paletteKey = "appearancePalette"
    static let bleedStrengthKey = "appearanceBleedStrength"
    static let backgroundIntensityKey = "appearanceBackgroundIntensity"
    static let motionKey = "appearanceMotion"
    static let customColorsKey = "appearanceCustomColors"
    static let readerPaletteKey = "readerAppearancePalette"
    static let readerBleedStrengthKey = "readerAppearanceBleedStrength"
    static let readerBackgroundIntensityKey = "readerAppearanceBackgroundIntensity"
    static let readerMotionKey = "readerAppearanceMotion"
    static let readerCustomColorsKey = "readerAppearanceCustomColors"
    private static let migratedKey = "appearanceMigratedV1"

    static let defaultBleedStrength = 1.0
    static let defaultBackgroundIntensity = 1.0
    static let defaultMotion = 1.0

    static let bleedRange: ClosedRange<Double> = 0.0...1.2
    static let intensityRange: ClosedRange<Double> = 0.6...1.3
    static let motionRange: ClosedRange<Double> = 0.0...1.2

    static func clampBleed(_ v: Double) -> Double { v.isFinite ? min(max(v, bleedRange.lowerBound), bleedRange.upperBound) : defaultBleedStrength }
    static func clampIntensity(_ v: Double) -> Double { v.isFinite ? min(max(v, intensityRange.lowerBound), intensityRange.upperBound) : defaultBackgroundIntensity }
    static func clampMotion(_ v: Double) -> Double { v.isFinite ? min(max(v, motionRange.lowerBound), motionRange.upperBound) : defaultMotion }

    static let defaultCustomColors: [Color] = [
        Color(red: 0.16, green: 0.12, blue: 0.20),
        Color(red: 0.26, green: 0.16, blue: 0.34),
        Color(red: 0.20, green: 0.12, blue: 0.16)
    ]

    static func encodeColors(_ colors: [Color]) -> Data? {
        #if canImport(UIKit)
        let uiColors = colors.map { UIColor($0) }
        return try? NSKeyedArchiver.archivedData(withRootObject: uiColors, requiringSecureCoding: true)
        #else
        return nil
        #endif
    }

    static func decodeColors(_ data: Data?) -> [Color]? {
        #if canImport(UIKit)
        guard let data, !data.isEmpty,
              let uiColors = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: UIColor.self, from: data),
              !uiColors.isEmpty else { return nil }
        return uiColors.map { Color($0) }
        #else
        return nil
        #endif
    }

    /// Map the previous experimental tuning keys onto the new appearance model
    /// once, so upgrading users keep their look.
    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)

        if defaults.object(forKey: paletteKey) == nil,
           let oldPalette = defaults.string(forKey: "experimentalMultiGradientPalette") {
            let mapped: String
            switch oldPalette {
            case "eclipse": mapped = AtmospherePaletteID.midnightPurple.rawValue
            case "nocturne": mapped = AtmospherePaletteID.nocturne.rawValue
            case "velvet": mapped = AtmospherePaletteID.velvet.rawValue
            case "auroraMuted": mapped = AtmospherePaletteID.mutedAurora.rawValue
            default: mapped = AtmospherePaletteID.midnightPurple.rawValue
            }
            defaults.set(mapped, forKey: paletteKey)
        }

        if defaults.object(forKey: bleedStrengthKey) == nil,
           defaults.object(forKey: "experimentalHeroBleedStrength") != nil {
            defaults.set(clampBleed(defaults.double(forKey: "experimentalHeroBleedStrength")), forKey: bleedStrengthKey)
        }

        if defaults.object(forKey: backgroundIntensityKey) == nil,
           let darkness = defaults.object(forKey: "experimentalGradientBaseDarkness") as? Double {
            defaults.set(clampIntensity(darkness), forKey: backgroundIntensityKey)
        }

        if defaults.object(forKey: motionKey) == nil,
           defaults.object(forKey: "experimentalGradientScrollMotion") != nil {
            defaults.set(clampMotion(defaults.double(forKey: "experimentalGradientScrollMotion")), forKey: motionKey)
        }

        if defaults.bool(forKey: "experimentalGradientUseCustomColors"),
           defaults.string(forKey: paletteKey) != AtmospherePaletteID.custom.rawValue {
            let a = ExperimentalVisualTuning.loadColor(key: "experimentalGradientColorA")
            let b = ExperimentalVisualTuning.loadColor(key: "experimentalGradientColorB")
            let cc = ExperimentalVisualTuning.loadColor(key: "experimentalGradientColorC")
            if let a, let b, let cc, let data = encodeColors([a, b, cc]) {
                defaults.set(data, forKey: customColorsKey)
                defaults.set(AtmospherePaletteID.custom.rawValue, forKey: paletteKey)
            }
        }
    }
}

enum AtmosphereBackgroundMode: Equatable {
    case multiGradient
    case classicGradient
    case solid
}

/// Everything required to render an atmosphere. A value type so SwiftUI can
/// diff it cheaply and EclipseTheme can build it for any screen.
struct AtmosphereInput: Equatable {
    var mode: AtmosphereBackgroundMode
    var palette: AtmospherePalette
    var classicColor: Color
    var baseColor: Color
    var dominant: Color?
    var hasHeroBleed: Bool
    var heroHeight: CGFloat
    var fadeDistance: CGFloat
    var bleedStrength: Double
    var backgroundIntensity: Double
    var motion: Double
}

struct AtmosphereBackdrop: View {
    var input: AtmosphereInput
    var scrollOffset: CGFloat = 0

    private var fadeProgress: Double {
        guard input.fadeDistance > 0 else { return 1 }
        let t = Double(max(0, min(scrollOffset / input.fadeDistance, 1)))
        return t * t * (3 - 2 * t)
    }

    private var bleedAlpha: Double {
        guard input.hasHeroBleed, input.dominant != nil else { return 0 }
        return max(0, input.bleedStrength * (1 - fadeProgress))
    }

    private var parallax: CGFloat {
        -scrollOffset * 0.06 * CGFloat(max(0, input.motion))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AtmosphereBaseLayer(input: input, size: geo.size)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .offset(y: parallax)

                if let dominant = input.dominant, bleedAlpha > 0.001 {
                    AtmosphereBleedLayer(
                        color: dominant,
                        alpha: bleedAlpha,
                        heroHeight: input.heroHeight,
                        containerSize: geo.size
                    )
                    .offset(y: parallax)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipped()
        .animation(.easeInOut(duration: 0.35), value: input.dominant)
    }
}

private struct AtmosphereBaseLayer: View {
    let input: AtmosphereInput
    let size: CGSize

    @ViewBuilder
    var body: some View {
        switch input.mode {
        case .solid:
            input.classicColor
        case .classicGradient:
            classicGradient
        case .multiGradient:
            AtmosphereMeshLayer(palette: input.palette, intensity: input.backgroundIntensity, size: size)
        }
    }

    private var classicGradient: some View {
        let accent = input.classicColor.atmosphereScaled(input.backgroundIntensity)
        return LinearGradient(
            stops: [
                .init(color: input.baseColor, location: 0.0),
                .init(color: accent.opacity(0.70), location: 0.08),
                .init(color: accent.opacity(0.35), location: 0.22),
                .init(color: input.baseColor, location: 0.55),
                .init(color: input.baseColor, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct AtmosphereMeshLayer: View {
    let palette: AtmospherePalette
    let intensity: Double
    let size: CGSize

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, tvOS 18.0, macOS 15.0, *) {
            MeshGradient(
                width: 3,
                height: 4,
                points: AtmosphereMeshLayer.points,
                colors: palette.meshColors(intensity: intensity)
            )
        } else {
            AtmosphereFallbackLayer(palette: palette, intensity: intensity, size: size)
        }
    }

    static let points: [SIMD2<Float>] = [
        SIMD2<Float>(0.0, 0.0), SIMD2<Float>(0.5, 0.0), SIMD2<Float>(1.0, 0.0),
        SIMD2<Float>(0.0, 0.33), SIMD2<Float>(0.46, 0.30), SIMD2<Float>(1.0, 0.34),
        SIMD2<Float>(0.0, 0.66), SIMD2<Float>(0.54, 0.70), SIMD2<Float>(1.0, 0.66),
        SIMD2<Float>(0.0, 1.0), SIMD2<Float>(0.5, 1.0), SIMD2<Float>(1.0, 1.0)
    ]
}

private struct AtmosphereFallbackLayer: View {
    let palette: AtmospherePalette
    let intensity: Double
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                stops: palette.scaledVerticalStops(intensity: intensity),
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [palette.topWash.atmosphereScaled(intensity).opacity(0.16), .clear],
                center: UnitPoint(x: 0.5, y: 0.0),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.95
            )
        }
    }
}

private struct AtmosphereBleedLayer: View {
    let color: Color
    let alpha: Double
    let heroHeight: CGFloat
    let containerSize: CGSize

    var body: some View {
        // The hero image is opaque and covers the top, so hold the bleed at
        // near-full strength through the hero, then fade it out over the tail
        // below — that is the part that actually reads as "color bleeding down".
        let tail = max(containerSize.height * 0.55, 220)
        let h = max(heroHeight + tail, 1)
        let holdEnd = min(max(heroHeight / h, 0.05), 0.9)
        return LinearGradient(
            stops: [
                .init(color: color.opacity(0.95 * alpha), location: 0.0),
                .init(color: color.opacity(0.88 * alpha), location: holdEnd * 0.7),
                .init(color: color.opacity(0.72 * alpha), location: holdEnd),
                .init(color: color.opacity(0.40 * alpha), location: holdEnd + (1 - holdEnd) * 0.35),
                .init(color: color.opacity(0.14 * alpha), location: holdEnd + (1 - holdEnd) * 0.70),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: h)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Scroll-attached hero banner bleed
//
// The banner's dominant color is rendered as a top-anchored background INSIDE
// the scroll content (not the fixed backdrop), so it stays glued to the hero:
// it holds near-opaque through the hero region — matching the hero image's own
// bottom fade so the two meet with no seam — then fades to clear over a tail
// below. Because it lives in the scroll content it scrolls up and off together
// with the hero, revealing the fixed app gradient underneath. That reveal IS
// the "overpowered by the app gradient" handoff, and because it rides the
// native scroll it needs no scroll-offset plumbing, so it can never freeze
// mid-fade the way a fixed, alpha-faded layer can.
struct HeroBannerBleed: View {
    var color: Color
    var heroHeight: CGFloat
    var tail: CGFloat
    var strength: Double

    var body: some View {
        let h = max(heroHeight + tail, 1)
        let hold = min(max(heroHeight / h, 0.05), 0.92)
        let s = max(0, strength)
        return LinearGradient(
            stops: [
                .init(color: color.opacity(min(1, 1.00 * s)), location: 0.0),
                .init(color: color.opacity(min(1, 0.97 * s)), location: hold * 0.86),
                .init(color: color.opacity(min(1, 0.95 * s)), location: hold),
                .init(color: color.opacity(0.52 * s), location: hold + (1 - hold) * 0.30),
                .init(color: color.opacity(0.24 * s), location: hold + (1 - hold) * 0.56),
                .init(color: color.opacity(0.07 * s), location: hold + (1 - hold) * 0.82),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: h)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Attaches a scroll-following banner bleed to the top of scroll content.
    /// Pass `color == nil` (e.g. a near-black poster, via
    /// `EclipseTheme.usableDominant`) to render nothing, so the app gradient
    /// shows through unmuddied.
    @ViewBuilder
    func heroBannerBleed(color: Color?, heroHeight: CGFloat, tail: CGFloat, strength: Double) -> some View {
        if let color, strength > 0.001, heroHeight > 0 {
            background(alignment: .top) {
                HeroBannerBleed(color: color, heroHeight: heroHeight, tail: tail, strength: strength)
            }
        } else {
            self
        }
    }
}
