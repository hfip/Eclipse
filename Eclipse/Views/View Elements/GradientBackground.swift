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
    
    var body: some View {
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
        dominantColor ?? theme.scopedGradientColor()
    }

    var body: some View {
        GeometryReader { geo in
            let h = max(geo.size.height * 1.6, geo.size.height + 1)
            ZStack {
                theme.backgroundBase

                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.08, green: 0.10, blue: 0.15), location: 0.0),
                        .init(color: accent.opacity(0.42), location: 0.18),
                        .init(color: Color(red: 0.27, green: 0.24, blue: 0.48), location: 0.48),
                        .init(color: Color(red: 0.22, green: 0.14, blue: 0.23), location: 0.78),
                        .init(color: theme.backgroundBase, location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: h)
                .offset(y: -scrollOffset * 0.10)

                RadialGradient(
                    colors: [
                        accent.opacity(0.35),
                        Color(red: 0.18, green: 0.20, blue: 0.43).opacity(0.22),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: max(geo.size.width, geo.size.height) * 0.92
                )

                LinearGradient(
                    colors: [.black.opacity(0.18), .clear, .black.opacity(0.22)],
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

    init(cornerRadius: CGFloat = 30, @ViewBuilder content: () -> Content) {
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
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)

            content
        }
    }
}

struct ExperimentalCircleButton: View {
    let systemName: String
    var size: CGFloat = 58
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.36, weight: .semibold))
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
                        .frame(minWidth: 72)
                        .padding(.vertical, 10)
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
                ExperimentalCircleButton(systemName: "magnifyingglass", size: 64, action: searchAction)
            }

            if let settingsAction {
                ExperimentalCircleButton(systemName: "gearshape.fill", size: 54, action: settingsAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }
}
#endif
