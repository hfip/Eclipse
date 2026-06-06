//
//  kanzenSettings.swift
//  Kanzen
//
//  Created by Dawud Osman on 16/05/2025.
//

import SwiftUI

#if !os(tvOS)
struct KanzenSettingsView: View {
    @EnvironmentObject var moduleManager: ModuleManager
    @AppStorage("showKanzen") private var showKanzen: Bool = false
    @State private var autoUpdateModules = ModuleManager.isAutoUpdateEnabled
    @AppStorage("kanzenAutoMode") private var autoModeEnabled: Bool = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("General")) {
                    NavigationLink(destination: KanzenGeneralSettingsView()) {
                        Text("Preferences")
                    }
                    NavigationLink(destination: AidokuSourcesSettingsView().environmentObject(moduleManager)) {
                        Text("Aidoku Sources")
                    }
                    NavigationLink(destination: MangaCatalogSettingsView().environmentObject(moduleManager)) {
                        Text("Home Sources")
                    }
                }
                .background(LunaScrollTracker())

                Section(
                    header: Text("Legacy JS Modules"),
                    footer: Text("Auto Mode only applies to legacy Kanzen JS modules. Aidoku sources are used directly.")
                ) {
                    NavigationLink(destination: KanzenModuleView().environmentObject(moduleManager)) {
                        Text("Manage Legacy Modules")
                    }
                    Toggle("Auto-Update Modules", isOn: $autoUpdateModules)
                        .onChange(of: autoUpdateModules) { newValue in
                            ModuleManager.isAutoUpdateEnabled = newValue
                        }
                    Toggle("Auto Mode", isOn: $autoModeEnabled)
                }

                Section(header: Text("Activity")) {
                    NavigationLink(destination: ReaderLoggerView()) {
                        Text("Reader Logs")
                    }
                }

                Section(header: Text("Others")) {
                    Text("Switch to Eclipse")
                        .onTapGesture {
                            showKanzen = false
                        }
                }
            }
            .navigationTitle("Settings")
            .lunaSettingsStyle()
        }
    }
}
#endif
