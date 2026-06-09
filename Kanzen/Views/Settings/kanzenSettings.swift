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
    @State private var autoUpdateModules = ModuleManager.isAutoUpdateEnabled
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    KanzenRootHeader("Settings")
                        .padding(.horizontal, -20)

                    GlassSection(header: "General") {
                        VStack(spacing: 0) {
                            NavigationLink(destination: KanzenGeneralSettingsView()) {
                                GlassSettingsRow(icon: "paintbrush.fill", iconColor: .purple, title: "Appearance")
                            }
                            .buttonStyle(.plain)

                            GlassDivider()

                            NavigationLink(destination: AidokuSourcesSettingsView().environmentObject(moduleManager)) {
                                GlassSettingsRow(icon: "shippingbox.fill", iconColor: .orange, title: "Aidoku Sources")
                            }
                            .buttonStyle(.plain)

                            GlassDivider()

                            NavigationLink(destination: MangaCatalogSettingsView().environmentObject(moduleManager)) {
                                GlassSettingsRow(icon: "slider.horizontal.3", iconColor: .green, title: "Home Sources")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    GlassSection(header: "Legacy JS Modules") {
                        VStack(spacing: 0) {
                            NavigationLink(destination: KanzenModuleView().environmentObject(moduleManager)) {
                                GlassSettingsRow(icon: "puzzlepiece.extension.fill", iconColor: .cyan, title: "Manage Legacy Modules")
                            }
                            .buttonStyle(.plain)

                            GlassDivider()

                            GlassSettingsRow(icon: "arrow.triangle.2.circlepath", iconColor: .teal, title: "Auto-Update Legacy Modules") {
                                Toggle("", isOn: $autoUpdateModules)
                                    .labelsHidden()
                                    .onChange(of: autoUpdateModules) { newValue in
                                        ModuleManager.isAutoUpdateEnabled = newValue
                                    }
                            }
                        }
                    }

                    GlassSection(header: "Activity") {
                        NavigationLink(destination: ReaderLoggerView()) {
                            GlassSettingsRow(icon: "doc.text.fill", iconColor: .yellow, title: "Reader Logs")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 32)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: -geo.frame(in: .named("kanzenSettingsScroll")).origin.y
                        )
                    }
                )
            }
            .coordinateSpace(name: "kanzenSettingsScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
            .background(GlobalGradientBackground(scrollOffset: scrollOffset).ignoresSafeArea())
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
#endif
