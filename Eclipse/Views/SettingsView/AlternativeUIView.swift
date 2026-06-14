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
    @AppStorage("heroBannerCatalogId") private var heroBannerCatalogId = "trending"
    @AppStorage("heroBannerBehavior") private var heroBannerBehavior = HeroBannerBehavior.static.rawValue
    @AppStorage(ExperimentalMediaDesignPreset.storageKey) private var experimentalDesignPreset = ExperimentalMediaDesignPreset.defaultValue.rawValue
    @AppStorage(ExperimentalHeroBleedLevel.storageKey) private var experimentalHeroBleedLevel = ExperimentalHeroBleedLevel.defaultValue.rawValue
    @AppStorage(ExperimentalHomeCardShape.storageKey) private var experimentalHomeCardShape = ExperimentalHomeCardShape.defaultValue.rawValue
    @AppStorage(ExperimentalMultiGradientPalette.storageKey) private var experimentalMultiGradientPalette = ExperimentalMultiGradientPalette.defaultValue.rawValue
    
    @StateObject private var accentColorManager = AccentColorManager.shared
    @StateObject private var catalogManager = CatalogManager.shared
    @ObservedObject private var theme = EclipseTheme.shared
    @State private var mediaDetailElements = MediaDetailElement.orderedElements()
    @State private var hiddenMediaDetailElements = MediaDetailElement.hiddenElements()
    
    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Global Appearance")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Share appearance changes between media and reader mode.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Toggle("", isOn: $theme.globalAppearanceEnabled)
                        .tint(accentColorManager.currentAccentColor)
                }

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
            .background(EclipseScrollTracker())
            
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
                        ForEach(EclipseTheme.gradientPresets, id: \.name) { preset in
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
                experimentalDesignPickerRow(
                    title: "Design Preset",
                    description: "Controls experimental hero scale, section spacing, cards, and glass.",
                    selection: $experimentalDesignPreset,
                    values: ExperimentalMediaDesignPreset.allCases.map { ($0.rawValue, $0.displayName) }
                )

                experimentalDesignPickerRow(
                    title: "Hero Bleed",
                    description: "Controls how strongly poster color washes into the page.",
                    selection: $experimentalHeroBleedLevel,
                    values: ExperimentalHeroBleedLevel.allCases.map { ($0.rawValue, $0.displayName) }
                )

                experimentalDesignPickerRow(
                    title: "Card Shape",
                    description: "Controls whether home shelves prefer backdrop or poster art.",
                    selection: $experimentalHomeCardShape,
                    values: ExperimentalHomeCardShape.allCases.map { ($0.rawValue, $0.displayName) }
                )

                experimentalDesignPickerRow(
                    title: "Multi Gradient Palette",
                    description: "Controls the regular background once the hero color fades out.",
                    selection: $experimentalMultiGradientPalette,
                    values: ExperimentalMultiGradientPalette.allCases.map { ($0.rawValue, $0.displayName) }
                )
            } header: {
                Text("Experimental Design")
            } footer: {
                Text("Applies to the Experimental UI only. Hero Bleed controls poster color wash; Multi Gradient Palette controls the background that takes over while scrolling.")
            }

            Section {
                ForEach(mediaDetailElements) { element in
                    mediaDetailElementRow(element)
                }
                .onMove(perform: moveMediaDetailElements)

                Button(action: resetMediaDetailElements) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reset Media Detail Layout")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("Restore the default order and visibility.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(accentColorManager.currentAccentColor)
                    }
                }
            } header: {
                Text("Media Detail Page")
            } footer: {
                Text("Drag rows to change their order. Hidden rows will not appear on media detail pages. Episodes only appear for series.")
            }
            .environment(\.editMode, .constant(.active))

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Alternative Season Menu")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Use dropdown menus instead of horizontal scrolls for seasons, specials, and OVAs.")
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
                Text("Classic schedule keeps the old all-days list. The alternative season menu uses dropdowns instead of horizontal scrolls for selecting seasons, specials, and OVAs.")
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
                Text("Gradient keeps the classic poster-colored look. Multi Gradient, Aurora, and Ember use layered palettes that blend with poster colors as you scroll. Solid Color replaces the gradient atmosphere with the poster's dominant color or your chosen color.")
            }
        }
        .navigationTitle("Appearance")
        .eclipseSettingsStyle()
        .onAppear(perform: reloadMediaDetailElements)
    }

    private func experimentalDesignPickerRow(
        title: String,
        description: String,
        selection: Binding<String>,
        values: [(String, String)]
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Picker("", selection: selection) {
                ForEach(values, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func mediaDetailElementRow(_ element: MediaDetailElement) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(element.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(element.settingsDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)

                Text(hiddenMediaDetailElements.contains(element) ? "Hidden" : "Visible")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { !hiddenMediaDetailElements.contains(element) },
                set: { setMediaDetailElement(element, visible: $0) }
            ))
            .labelsHidden()
            .tint(accentColorManager.currentAccentColor)
        }
        .padding(.vertical, 4)
    }

    private func reloadMediaDetailElements() {
        mediaDetailElements = MediaDetailElement.orderedElements()
        hiddenMediaDetailElements = MediaDetailElement.hiddenElements()
    }

    private func moveMediaDetailElements(from source: IndexSet, to destination: Int) {
        mediaDetailElements.move(fromOffsets: source, toOffset: destination)
        MediaDetailElement.saveOrder(mediaDetailElements)
    }

    private func setMediaDetailElement(_ element: MediaDetailElement, visible: Bool) {
        if visible {
            hiddenMediaDetailElements.remove(element)
        } else {
            hiddenMediaDetailElements.insert(element)
        }
        MediaDetailElement.saveHiddenElements(hiddenMediaDetailElements)
    }

    private func resetMediaDetailElements() {
        mediaDetailElements = MediaDetailElement.defaultOrder
        hiddenMediaDetailElements = []
        MediaDetailElement.saveOrder(mediaDetailElements)
        MediaDetailElement.saveHiddenElements(hiddenMediaDetailElements)
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
