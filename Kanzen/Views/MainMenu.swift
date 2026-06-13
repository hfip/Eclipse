//
//  MainMenu.swift
//  Eclipse
//
//  Created by Dawud Osman on 17/11/2025.
//

import SwiftUI

#if !os(tvOS)
enum KanzenRootTab: Hashable {
    case home
    case library
    case search
    case history
    case settings
}

struct KanzenModeSwitchButton: View {
    @AppStorage("showKanzen") private var showKanzen: Bool = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                showKanzen = false
            }
        } label: {
            Image(systemName: "play.rectangle.fill")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch to Media Mode")
    }
}

struct KanzenRootHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            trailing()

            KanzenModeSwitchButton()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

extension KanzenRootHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}

struct KanzenMenu: View {
    let kanzen = KanzenEngine()
    private let onStartupReady: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var moduleManager: ModuleManager
    @StateObject private var aidokuManager = AidokuSourceManager.shared
    @State private var selectedTab: KanzenRootTab = .home

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
        TabView(selection: $selectedTab) {
            KanzenHomeView(onStartupReady: onStartupReady)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(KanzenRootTab.home)

            KanzenLibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(KanzenRootTab.library)

            KanzenGlobalSearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(KanzenRootTab.search)

            KanzenHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(KanzenRootTab.history)

            KanzenSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(KanzenRootTab.settings)
        }
        .environmentObject(kanzen)
        .task {
            await moduleManager.autoUpdateModulesIfNeeded()
            await aidokuManager.autoUpdateInstalledSourcesIfNeeded(reason: "reader-open")
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task {
                    await moduleManager.autoUpdateModulesIfNeeded()
                    await aidokuManager.autoUpdateInstalledSourcesIfNeeded(reason: "reader-active")
                }
            }
        }
    }
}

private enum ExperimentalKanzenTab: Hashable {
    case home
    case library
    case history
}

struct ExperimentalKanzenMenu: View {
    let kanzen = KanzenEngine()
    private let onStartupReady: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var moduleManager: ModuleManager
    @StateObject private var aidokuManager = AidokuSourceManager.shared
    @State private var selectedTab: ExperimentalKanzenTab = .home
    @State private var showsSearch = false
    @State private var showsSettings = false

    init(onStartupReady: @escaping () -> Void = {}) {
        self.onStartupReady = onStartupReady
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ExperimentalGradientBackground()

            Group {
                switch selectedTab {
                case .home:
                    KanzenHomeView(onStartupReady: onStartupReady)
                case .library:
                    KanzenLibraryView()
                case .history:
                    KanzenHistoryView()
                }
            }
            .environmentObject(kanzen)
            .padding(.bottom, 84)

            experimentalControls
        }
        .sheet(isPresented: $showsSearch) {
            NavigationView {
                KanzenGlobalSearchView()
                    .environmentObject(kanzen)
            }
        }
        .sheet(isPresented: $showsSettings) {
            NavigationView {
                KanzenSettingsView()
                    .environmentObject(kanzen)
            }
        }
        .environmentObject(kanzen)
        .task {
            await moduleManager.autoUpdateModulesIfNeeded()
            await aidokuManager.autoUpdateInstalledSourcesIfNeeded(reason: "reader-open")
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task {
                    await moduleManager.autoUpdateModulesIfNeeded()
                    await aidokuManager.autoUpdateInstalledSourcesIfNeeded(reason: "reader-active")
                }
            }
        }
    }

    private var experimentalControls: some View {
        HStack(alignment: .bottom, spacing: 14) {
            ExperimentalFloatingTabBar(
                items: [
                    ExperimentalFloatingTabItem(id: .home, title: "Home", systemImage: "house.fill"),
                    ExperimentalFloatingTabItem(id: .library, title: "Library", systemImage: "books.vertical.fill"),
                    ExperimentalFloatingTabItem(id: .history, title: "History", systemImage: "clock.fill")
                ],
                selection: $selectedTab
            )

            Spacer(minLength: 10)

            HStack(spacing: 12) {
                ExperimentalCircleButton(systemName: "magnifyingglass") {
                    showsSearch = true
                }

                ExperimentalCircleButton(systemName: "gearshape.fill") {
                    showsSettings = true
                }

                KanzenModeSwitchButton()
                    .frame(width: 58, height: 58)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }
}
#endif
