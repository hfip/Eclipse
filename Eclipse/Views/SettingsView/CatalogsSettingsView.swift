import SwiftUI

struct CatalogsSettingsView: View {
    @ObservedObject private var catalogManager = CatalogManager.shared
    @ObservedObject private var trackerManager = TrackerManager.shared
    @StateObject private var accentColorManager = AccentColorManager.shared
    @State private var editMode = EditMode.active
    
    var body: some View {
        List {
            Section {
                ForEach(catalogManager.visibleCatalogs) { catalog in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(catalog.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            HStack(spacing: 6) {
                                Text(sourceText(for: catalog))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if catalogManager.isCatalogLockedByPerformanceMode(catalog) {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                if catalog.displayStyle != .standard {
                                    Text("\u{00B7} \(displayStyleText(for: catalog.displayStyle))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { catalogManager.isCatalogEffectivelyEnabled(catalog) },
                            set: { _ in catalogManager.toggleCatalog(id: catalog.id) }
                        ))
                        .tint(accentColorManager.currentAccentColor)
                    }
                }
                .onMove(perform: catalogManager.moveVisibleCatalog)
            } header: {
                Text("Content Catalogs")
            } footer: {
                Text("Enable/disable content catalogs and drag to reorder them. The order here determines the order on your home screen. Stremio catalog addons may reduce performance or have visual inconsistencies. Trakt catalogs appear after Trakt is connected.")
            }
            .eclipseExperimentalSettingsRows()
            .background(EclipseScrollTracker())
        }
        .navigationTitle("Catalogs")
        .eclipseSettingsStyle()
        .environment(\.editMode, $editMode)
    }

    private func sourceText(for catalog: Catalog) -> String {
        if catalogManager.isCatalogLockedByPerformanceMode(catalog) {
            return "Source: Performance Mode - AniList locked"
        }
        if catalog.source == .stremio,
           let addonName = catalog.stremioAddonName,
           !addonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Source: Stremio · \(addonName)"
        }
        if catalog.source == .trakt,
           let listIdentifier = catalog.traktListDisplayIdentifier {
            let mediaType = Catalog.normalizedTraktListMediaType(catalog.traktListMediaType) == "movies" ? "Movies" : "Shows"
            return "Source: Trakt - List \(listIdentifier) - \(mediaType)"
        }
        if catalog.id == Catalog.traktContinueWatchingCatalogId {
            return "Source: Trakt - Continue Watching"
        }
        return "Source: \(catalog.source.rawValue)"
    }

    private func displayStyleText(for style: Catalog.CatalogDisplayStyle) -> String {
        switch style {
        case .continueWatching:
            return "Playback"
        default:
            return style.rawValue.capitalized
        }
    }
}
