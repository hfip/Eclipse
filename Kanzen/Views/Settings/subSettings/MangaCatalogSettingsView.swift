//
//  MangaCatalogSettingsView.swift
//  Kanzen
//
//  Created by Luna on 2025.
//

import SwiftUI

#if !os(tvOS)
struct MangaCatalogSettingsView: View {
    @EnvironmentObject private var moduleManager: ModuleManager
    @StateObject private var sourceManager = MangaHomeSourceManager.shared
    @StateObject private var aidokuManager = AidokuSourceManager.shared

    private var aidokuSources: [AidokuInstalledSource] {
        aidokuManager.installedSources
            .filter { aidokuManager.showMatureSources || !$0.isMature }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private var legacySources: [MangaHomeSource] {
        sourceManager.legacySources(from: moduleManager.modules)
    }

    var body: some View {
        List {
            Section(header: Text("Aidoku Home Sources"), footer: Text("Enabled Aidoku sources appear first on Discover and Search.")) {
                if aidokuSources.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "shippingbox")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Aidoku sources installed")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        NavigationLink(destination: AidokuSourcesSettingsView().environmentObject(moduleManager)) {
                            Text("Manage Aidoku Sources")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    ForEach(aidokuSources) { source in
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: source.iconURLString)) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Image(systemName: "shippingbox")
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(source.isEnabled ? .primary : .secondary)
                                Text(source.languages.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { source.isEnabled },
                                set: { _ in aidokuManager.toggle(source) }
                            ))
                            .labelsHidden()
                        }
                    }
                    .onMove { from, to in
                        aidokuManager.move(from: from, to: to)
                    }
                }
            }
            .background(LunaScrollTracker())

            Section(header: Text("Legacy JS Module Sources"), footer: Text("Legacy JS sources remain available for compatibility and appear after Aidoku sources.")) {
                if legacySources.isEmpty {
                    Text("No legacy manga modules installed")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(legacySources) { source in
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: source.iconURL)) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Image(systemName: "puzzlepiece.extension")
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(source.isEnabled ? .primary : .secondary)
                                Text(source.module?.moduleData.language ?? "Legacy")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { source.isEnabled },
                                set: { _ in sourceManager.toggleLegacySource(id: source.id) }
                            ))
                            .labelsHidden()
                        }
                    }
                    .onMove { from, to in
                        sourceManager.moveLegacySource(from: from, to: to, modules: moduleManager.modules)
                    }
                }
            }
            .background(LunaScrollTracker())
        }
        .navigationTitle("Home Sources")
        .navigationBarTitleDisplayMode(.inline)
        .lunaSettingsStyle()
        .toolbar {
            EditButton()
        }
        .onAppear {
            sourceManager.refreshSources(from: moduleManager.modules)
        }
    }
}
#endif
