//
//  GlassCardGroup.swift
//  Eclipse
//
//  Translucent glass card group container with thin separators
//

import SwiftUI

// MARK: - Glass Card Group

struct GlassCardGroup<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .background(cardBackground)
    }

    @ViewBuilder
    private var cardBackground: some View {
#if !os(tvOS)
        if ExperimentalFeatureState.isEnabledAtLaunch {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.13, blue: 0.22).opacity(0.88),
                            Color(red: 0.09, green: 0.09, blue: 0.15).opacity(0.78)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.54, green: 0.44, blue: 0.95).opacity(0.38),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color(red: 0.05, green: 0.03, blue: 0.12).opacity(0.30), radius: 14, x: 0, y: 8)
        } else {
            legacyCardBackground
        }
#else
        legacyCardBackground
#endif
    }

    private var legacyCardBackground: some View {
        RoundedRectangle(cornerRadius: EclipseTheme.shared.cardCornerRadius, style: .continuous)
            .fill(EclipseTheme.shared.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: EclipseTheme.shared.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
    }
}

// MARK: - Settings Row

struct GlassSettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let trailing: Trailing
    
    init(
        icon: String,
        iconColor: Color = .white,
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.trailing = trailing()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            settingsIcon
            
            Text(title)
                .font(rowTitleFont)
                .foregroundColor(.white)
            
            Spacer()
            
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, rowVerticalPadding)
        .contentShape(Rectangle())
    }

    private var iconSize: CGFloat {
        ExperimentalFeatureState.isEnabledAtLaunch ? 16 : 15
    }

    private var iconFrame: CGFloat {
        ExperimentalFeatureState.isEnabledAtLaunch ? 36 : 32
    }

    @ViewBuilder
    private var settingsIcon: some View {
        if ExperimentalFeatureState.isEnabledAtLaunch {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: iconFrame, height: iconFrame)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    iconColor.opacity(0.82),
                                    Color.white.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                )
        } else {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: iconFrame, height: iconFrame)
                .background(iconColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var rowTitleFont: Font {
        ExperimentalFeatureState.isEnabledAtLaunch ? .body.weight(.medium) : .body
    }

    private var rowVerticalPadding: CGFloat {
        ExperimentalFeatureState.isEnabledAtLaunch ? 12 : 13
    }
}

// Convenience for NavigationLink rows with chevron
extension GlassSettingsRow where Trailing == AnyView {
    init(icon: String, iconColor: Color = .white, title: String) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.trailing = AnyView(
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.3))
        )
    }
}

// MARK: - Glass Section

struct GlassSection<Content: View>: View {
    let header: String?
    let content: Content
    
    init(header: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header = header {
                Text(header)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(EclipseTheme.shared.sectionHeaderColor)
                    .padding(.horizontal, 18)
            }
            
            GlassCardGroup {
                content
            }
            .padding(.horizontal, 14)
        }
    }
}

// MARK: - Glass Divider

struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(EclipseTheme.shared.separatorColor)
            .frame(height: 0.5)
            .padding(.leading, 54)
    }
}
