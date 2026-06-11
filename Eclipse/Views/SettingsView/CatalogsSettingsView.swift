//
//  CatalogsSettingsView.swift
//  Eclipse
//
//  Created by Soupy-dev
//

import SwiftUI

struct CatalogsSettingsView: View {
    @ObservedObject private var catalogManager = CatalogManager.shared
    @StateObject private var accentColorManager = AccentColorManager.shared
    @State private var editMode = EditMode.active
    
    var body: some View {
        List {
            Section {
                ForEach(catalogManager.catalogs.indices, id: \.self) { index in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(catalogManager.catalogs[index].name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            HStack(spacing: 6) {
                                Text(sourceText(for: catalogManager.catalogs[index]))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if catalogManager.catalogs[index].displayStyle != .standard {
                                    Text("\u{00B7} \(catalogManager.catalogs[index].displayStyle.rawValue.capitalized)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { catalogManager.catalogs[index].isEnabled },
                            set: { _ in catalogManager.toggleCatalog(id: catalogManager.catalogs[index].id) }
                        ))
                        .tint(accentColorManager.currentAccentColor)
                    }
                }
                .onMove(perform: catalogManager.moveCatalog)
            } header: {
                Text("Content Catalogs")
            } footer: {
                Text("Enable/disable content catalogs and drag to reorder them. The order here determines the order on your home screen. Stremio catalog addons may reduce performance or have visual inconsistencies.")
            }
            .background(EclipseScrollTracker())
        }
        .navigationTitle("Catalogs")
        .eclipseSettingsStyle()
        .environment(\.editMode, $editMode)
    }

    private func sourceText(for catalog: Catalog) -> String {
        if catalog.source == .stremio,
           let addonName = catalog.stremioAddonName,
           !addonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Source: Stremio · \(addonName)"
        }
        return "Source: \(catalog.source.rawValue)"
    }
}
