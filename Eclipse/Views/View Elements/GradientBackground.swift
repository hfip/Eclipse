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

struct SettingsGradientBackground: View {
    @ObservedObject private var theme = EclipseTheme.shared
    var scrollOffset: CGFloat = 0
    
    // The gradient is taller than the screen and physically offset upward
    // as the user scrolls, so the color band visibly moves with the content.
    private var gradientOffset: CGFloat {
        -scrollOffset * 0.35
    }
    
    var body: some View {
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
        if ExperimentalFeatureState.isEnabledAtLaunch {
            ExperimentalGradientBackground(dominantColor: overrideColor, scrollOffset: scrollOffset)
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

#if !os(tvOS)
struct ExperimentalGradientBackground: View {
    @ObservedObject private var theme = EclipseTheme.shared
    var dominantColor: Color? = nil
    var scrollOffset: CGFloat = 0

    private var accent: Color {
        dominantColor ?? Color(red: 0.50, green: 0.36, blue: 0.76)
    }

    var body: some View {
        GeometryReader { geo in
            let h = max(geo.size.height * 1.45, geo.size.height + 1)
            let longestSide = max(geo.size.width, geo.size.height)
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.11)

                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.06, green: 0.08, blue: 0.12), location: 0.00),
                        .init(color: Color(red: 0.14, green: 0.12, blue: 0.22), location: 0.22),
                        .init(color: Color(red: 0.24, green: 0.20, blue: 0.42), location: 0.46),
                        .init(color: Color(red: 0.19, green: 0.12, blue: 0.19), location: 0.74),
                        .init(color: Color(red: 0.07, green: 0.07, blue: 0.11), location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: h)
                .offset(y: -scrollOffset * 0.08)

                RadialGradient(
                    colors: [
                        Color(red: 0.10, green: 0.24, blue: 0.34).opacity(0.46),
                        Color(red: 0.12, green: 0.17, blue: 0.32).opacity(0.24),
                        .clear
                    ],
                    center: UnitPoint(x: 0.88, y: 0.05),
                    startRadius: 0,
                    endRadius: longestSide * 0.82
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.47, green: 0.28, blue: 0.58).opacity(0.42),
                        accent.opacity(0.20),
                        .clear
                    ],
                    center: UnitPoint(x: 0.18, y: 0.38),
                    startRadius: 20,
                    endRadius: longestSide * 0.78
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.48, green: 0.22, blue: 0.18).opacity(0.24),
                        Color(red: 0.22, green: 0.12, blue: 0.18).opacity(0.14),
                        .clear
                    ],
                    center: UnitPoint(x: 0.82, y: 0.82),
                    startRadius: 0,
                    endRadius: longestSide * 0.72
                )

                LinearGradient(
                    colors: [
                        .black.opacity(0.10),
                        .clear,
                        .black.opacity(0.24)
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
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.16).opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
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
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.30))
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
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
    var searchAction: (() -> Void)?
    var settingsAction: (() -> Void)?

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
                        .frame(minWidth: 58)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selection == item.id ? Color.white.opacity(0.18) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.34))
                    .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
            )

            if let searchAction {
                ExperimentalCircleButton(systemName: "magnifyingglass", size: 52, action: searchAction)
            }

            if let settingsAction {
                ExperimentalCircleButton(systemName: "gearshape.fill", size: 44, action: settingsAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
#endif
