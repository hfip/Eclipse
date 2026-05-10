//
//  AlternativeUIView.swift
//  Sora
//
//  Created by Francesco on 20/08/25.
//

import SwiftUI

struct AlternativeUIView: View {
    @AppStorage("seasonMenu") private var useSeasonMenu = false
    @AppStorage("horizontalEpisodeList") private var horizontalEpisodeList = false
    @AppStorage("useClassicScheduleUI") private var useClassicScheduleUI = false
    @AppStorage("showCastSection") private var showCastSection = true
    @AppStorage("heroBannerCatalogId") private var heroBannerCatalogId = "trending"
    @AppStorage("heroBannerBehavior") private var heroBannerBehavior = HeroBannerBehavior.static.rawValue
    
    @StateObject private var accentColorManager = AccentColorManager.shared
    @StateObject private var catalogManager = CatalogManager.shared
    @ObservedObject private var theme = LunaTheme.shared
    
    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accent Color")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("This affects buttons, links, and other interactive elements.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
#if !os(tvOS)
                    ColorPicker("", selection: $accentColorManager.currentAccentColor)
                        .onChangeComp(of: accentColorManager.currentAccentColor) { _, newColor in
                            accentColorManager.saveAccentColor(newColor)
                        }
#endif
                }
            } header: {
                Text("Interface")
            }
            .background(LunaScrollTracker())
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Settings Theme Color")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Changes the gradient background color in Settings screens.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    HStack(spacing: 12) {
                        ForEach(LunaTheme.gradientPresets, id: \.name) { preset in
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    theme.settingsGradientColor = preset.color
                                }
                            } label: {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white, lineWidth: colorsMatch(preset.color, theme.settingsGradientColor) ? 2.5 : 0)
                                    )
                                    .scaleEffect(colorsMatch(preset.color, theme.settingsGradientColor) ? 1.15 : 1.0)
                                    .animation(.easeInOut(duration: 0.2), value: theme.settingsGradientColor)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Spacer()
                        
#if !os(tvOS)
                        ColorPicker("", selection: $theme.settingsGradientColor)
                            .labelsHidden()
#endif
                    }
                }
            } header: {
                Text("Settings Theme")
            }
            
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Cast Section")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Show cast rows on media detail pages.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Toggle("", isOn: $showCastSection)
                        .tint(accentColorManager.currentAccentColor)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Alternative Season Menu")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Use dropdown menu instead of horizontal scroll for seasons")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $useSeasonMenu)
                        .tint(accentColorManager.currentAccentColor)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Horizontal Episode list ")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Use Horizontal list instead of vertical episode list")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $horizontalEpisodeList)
                        .tint(accentColorManager.currentAccentColor)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Classic Schedule Layout")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Use the original full schedule list instead of the compact day picker.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Toggle("", isOn: $useClassicScheduleUI)
                        .tint(accentColorManager.currentAccentColor)
                }
            } header: {
                Text("DISPLAY OPTIONS")
            } footer: {
                Text("Classic schedule keeps the old all-days list. The alternative season menu uses a dropdown instead of a horizontal scroll for selecting seasons.")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hero Banner Catalogue")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Choose the home catalogue used for the large banner.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Picker("", selection: $heroBannerCatalogId) {
                        ForEach(catalogManager.catalogs.sorted { $0.order < $1.order }) { catalog in
                            Text(catalog.name).tag(catalog.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hero Banner Behavior")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Control when the banner changes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Picker("", selection: $heroBannerBehavior) {
                        ForEach(HeroBannerBehavior.allCases) { behavior in
                            Text(behavior.displayName).tag(behavior.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Hero Banner")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Atmosphere Style")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Choose the app background atmosphere.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Picker("", selection: $theme.atmosphereStyle) {
                        ForEach(AtmosphereStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if theme.atmosphereStyle == .solid {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Solid Color Source")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("Use poster color where available, or a custom color everywhere.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Picker("", selection: $theme.atmosphereSolidColorSource) {
                            ForEach(AtmosphereSolidColorSource.allCases) { source in
                                Text(source.displayName).tag(source)
                            }
                        }
                        .pickerStyle(.menu)
                    }

#if !os(tvOS)
                    if theme.atmosphereSolidColorSource == .custom {
                        ColorPicker("Custom Atmosphere Color", selection: $theme.atmosphereSolidColor)
                    }
#endif
                }
            } header: {
                Text("Atmosphere")
            } footer: {
                Text("Gradient keeps the current default look. Solid Color replaces the gradient atmosphere with the poster's dominant color or your chosen color.")
            }
        }
        .navigationTitle("Appearance")
        .lunaSettingsStyle()
    }
    
    private func colorsMatch(_ a: Color, _ b: Color) -> Bool {
        let uiA = UIColor(a)
        let uiB = UIColor(b)
        var rA: CGFloat = 0, gA: CGFloat = 0, bA: CGFloat = 0, aA: CGFloat = 0
        var rB: CGFloat = 0, gB: CGFloat = 0, bB: CGFloat = 0, aB: CGFloat = 0
        uiA.getRed(&rA, green: &gA, blue: &bA, alpha: &aA)
        uiB.getRed(&rB, green: &gB, blue: &bB, alpha: &aB)
        return abs(rA - rB) < 0.02 && abs(gA - gB) < 0.02 && abs(bA - bB) < 0.02
    }
}
