//
//  MainMenu.swift
//  Luna
//
//  Created by Dawud Osman on 17/11/2025.
//

import SwiftUI

#if !os(tvOS)
struct KanzenMenu: View {
    let kanzen = KanzenEngine()
    private let onStartupReady: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var moduleManager: ModuleManager
    @AppStorage("showKanzen") private var showKanzen: Bool = false

    init(onStartupReady: @escaping () -> Void = {}) {
        self.onStartupReady = onStartupReady
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 0.92)
        appearance.shadowColor = .clear
        let normalAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.gray]
        let selectedAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white]
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttrs
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttrs
        appearance.stackedLayoutAppearance.normal.iconColor = .gray
        appearance.stackedLayoutAppearance.selected.iconColor = .white
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    var body: some View {
        TabView {
            KanzenHomeView(onStartupReady: onStartupReady)
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            KanzenLibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            KanzenGlobalSearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            KanzenHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            KanzenSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .environmentObject(kanzen)
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    showKanzen = false
                }
            } label: {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .applyLiquidGlassBackground(cornerRadius: 22)
            }
            .accessibilityLabel("Switch to Media Mode")
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            .padding(.trailing, 16)
            .padding(.top, 8)
        }
        .task {
            await moduleManager.autoUpdateModulesIfNeeded()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task {
                    await moduleManager.autoUpdateModulesIfNeeded()
                }
            }
        }
    }
}
#endif
