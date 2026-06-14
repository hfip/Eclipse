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
    
    @ViewBuilder
    var body: some View {
#if !os(tvOS)
        if ExperimentalFeatureState.isEnabledAtLaunch {
            ExperimentalGradientBackground(
                dominantColor: theme.scopedGradientColor(),
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
        dominantColor ?? Color(red: 0.56, green: 0.39, blue: 0.94)
    }

    var body: some View {
        GeometryReader { geo in
            let h = max(geo.size.height * 1.65, geo.size.height + 1)
            ZStack {
                Color(red: 0.055, green: 0.050, blue: 0.090)

                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.04, green: 0.07, blue: 0.12), location: 0.00),
                        .init(color: Color(red: 0.15, green: 0.10, blue: 0.24), location: 0.20),
                        .init(color: Color(red: 0.32, green: 0.25, blue: 0.57), location: 0.46),
                        .init(color: Color(red: 0.22, green: 0.15, blue: 0.28), location: 0.68),
                        .init(color: Color(red: 0.06, green: 0.06, blue: 0.10), location: 1.00)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: h)
                .offset(y: -scrollOffset * 0.10)

                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.05, green: 0.66, blue: 0.78).opacity(0.40), location: 0.02),
                        .init(color: Color(red: 0.35, green: 0.24, blue: 0.86).opacity(0.30), location: 0.33),
                        .init(color: Color(red: 0.84, green: 0.28, blue: 0.54).opacity(0.24), location: 0.64),
                        .init(color: Color(red: 0.95, green: 0.55, blue: 0.22).opacity(0.14), location: 0.95)
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .blendMode(.screen)
                .offset(y: -scrollOffset * 0.055)

                AngularGradient(
                    colors: [
                        Color(red: 0.11, green: 0.72, blue: 0.72).opacity(0.26),
                        accent.opacity(0.34),
                        Color(red: 0.82, green: 0.22, blue: 0.58).opacity(0.24),
                        Color(red: 0.36, green: 0.30, blue: 0.77).opacity(0.30),
                        Color(red: 0.11, green: 0.72, blue: 0.72).opacity(0.26)
                    ],
                    center: UnitPoint(x: 0.48, y: 0.34)
                )
                .scaleEffect(1.7)
                .blur(radius: 42)
                .opacity(0.68)
                .blendMode(.screen)

                LinearGradient(
                    colors: [
                        accent.opacity(0.24),
                        .clear,
                        Color(red: 0.05, green: 0.30, blue: 0.34).opacity(0.22)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(y: -scrollOffset * 0.03)

                LinearGradient(
                    colors: [
                        .black.opacity(0.08),
                        .clear,
                        .black.opacity(0.30)
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
