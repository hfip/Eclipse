//
//  MangaCatalogSettingsView.swift
//  Kanzen
//
//  Created by Eclipse on 2025.
//

import SwiftUI

#if !os(tvOS)
struct MangaCatalogSettingsView: View {
    @EnvironmentObject private var moduleManager: ModuleManager
    @StateObject private var aidokuManager = AidokuSourceManager.shared

    private var aidokuSources: [AidokuInstalledSource] {
        aidokuManager.installedSources
            .filter { aidokuManager.showMatureSources || !$0.isMature }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    var body: some View {
        List {
            Section(header: Text("Aidoku Home Sources"), footer: Text("Enabled Aidoku sources appear on Discover. Legacy JS modules stay available for compatibility, but they are not shown on the Home page because they do not provide home feeds.")) {
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
            .eclipseExperimentalSettingsRows()
            .background(EclipseScrollTracker())
        }
        .navigationTitle("Home Sources")
        .navigationBarTitleDisplayMode(.inline)
        .eclipseSettingsStyle()
        .toolbar {
            EditButton()
        }
    }
}
#endif
