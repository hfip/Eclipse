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
            if ExperimentalFeatureState.isEnabledAtLaunch {
                Image(systemName: "play.rectangle.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .applyLiquidGlassBackground(
                        cornerRadius: 21,
                        glassTint: Color.white.opacity(0.04)
                    )
            } else {
                Image(systemName: "play.rectangle.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
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
                .font(ExperimentalFeatureState.isEnabledAtLaunch ? .system(size: isIPad ? 42 : 34, weight: .heavy) : .largeTitle)
                .fontWeight(ExperimentalFeatureState.isEnabledAtLaunch ? .heavy : .bold)
                .foregroundColor(ExperimentalFeatureState.isEnabledAtLaunch ? .white : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            trailing()

            KanzenModeSwitchButton()
        }
        .padding(.horizontal, 20)
        .padding(.top, ExperimentalFeatureState.isEnabledAtLaunch ? 16 : 10)
        .padding(.bottom, ExperimentalFeatureState.isEnabledAtLaunch ? 8 : 2)
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

#endif
