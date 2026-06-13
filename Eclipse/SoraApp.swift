//
//  SoraApp.swift
//  Sora
//
//  Created by Francesco on 12/08/25.
//

import SwiftUI
#if !os(tvOS)
import Nuke
#endif

class AppDelegate: NSObject, UIApplicationDelegate {
#if !os(tvOS)
    static var orientationLock: UIInterfaceOrientationMask = .all

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
#endif

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        if identifier == "app.eclipse.soupy.downloads" {
            DownloadManager.shared.backgroundCompletionHandler = completionHandler
        }
    }
}

@main
struct SoraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = Settings()
    @StateObject private var theme = EclipseTheme.shared
    @StateObject private var moduleManager = ModuleManager.shared
    @StateObject private var favouriteManager = FavouriteManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var startupReady = false
    @State private var startupFallbackScheduled = false
    @State private var showSplash = true
    @AppStorage("hideSplashScreen") private var hideSplashScreen = false
    private let startupFallbackDelay: TimeInterval = 20

#if !os(tvOS)
    @AppStorage("showKanzen") private var showKanzen: Bool = false
    let kanzen = KanzenEngine();
#endif

    init() {
        CrashReportManager.shared.start()
        GitHubReleaseChecker.registerDefaults()
        ExperimentalFeatureState.configureLaunchState()
#if !os(tvOS)
        ReaderImagePipelineConfigurator.configureIfNeeded()
#endif

        // Check and auto-clear cache on app startup if threshold exceeded
        DispatchQueue.global(qos: .background).async {
            CacheManager.shared.checkAndAutoClearIfNeeded()
        }
        // Initialize download manager early to reconnect background session
        _ = DownloadManager.shared
#if !os(tvOS)
        // Initialize Reader downloads early so interrupted Kanzen queues are recovered separately.
        Task { @MainActor in
            _ = ReaderDownloadManager.shared
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
#if os(tvOS)
                ContentView(onStartupReady: markStartupReady)
                    .onAppear { scheduleStartupFallback() }
#else
                if showKanzen {
                    if ExperimentalFeatureState.isEnabledAtLaunch {
                        ExperimentalKanzenMenu(onStartupReady: markStartupReady)
                            .environmentObject(settings)
                            .environmentObject(theme)
                            .environmentObject(moduleManager)
                            .environmentObject(favouriteManager)
                            .environment(\.managedObjectContext, favouriteManager.container.viewContext)
                            .accentColor(settings.effectiveAccentColor)
                            .onAppear { scheduleStartupFallback() }
                    } else {
                        KanzenMenu(onStartupReady: markStartupReady)
                            .environmentObject(settings)
                            .environmentObject(theme)
                            .environmentObject(moduleManager)
                            .environmentObject(favouriteManager)
                            .environment(\.managedObjectContext, favouriteManager.container.viewContext)
                            .accentColor(settings.effectiveAccentColor)
                            .onAppear { scheduleStartupFallback() }
                    }
                } else {
                    if ExperimentalFeatureState.isEnabledAtLaunch {
                        ExperimentalContentView(onStartupReady: markStartupReady)
                            .environmentObject(theme)
                            .onAppear { scheduleStartupFallback() }
                    } else {
                        ContentView(onStartupReady: markStartupReady)
                            .environmentObject(theme)
                            .onAppear { scheduleStartupFallback() }
                    }
                }
#endif

                if showSplash && !hideSplashScreen {
                    SplashScreenView(isFinished: $startupReady) {
                        showSplash = false
                    }
                        .ignoresSafeArea()
                        .zIndex(1)
                }
            }
#if os(iOS)
            .onAppear {
                ExperimentalCloudSyncManager.shared.syncOnActivationIfNeeded(reason: "launch")
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    ExperimentalCloudSyncManager.shared.syncOnActivationIfNeeded(reason: "active")
                }
            }
#endif
        }
    }

    private func markStartupReady() {
        guard !startupReady else { return }
        startupReady = true
    }

    private func scheduleStartupFallback() {
        guard !startupFallbackScheduled else { return }
        startupFallbackScheduled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + startupFallbackDelay) {
            markStartupReady()
        }
    }
}

#if !os(tvOS)
private enum ReaderImagePipelineConfigurator {
    private static var didConfigure = false

    static func configureIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        DataLoader.sharedUrlCache.diskCapacity = 0
        DataLoader.sharedUrlCache.memoryCapacity = 0

        let pipeline = ImagePipeline {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil

            let dataCache = try? DataCache(name: "app.eclipse.soupy.reader.datacache")
            dataCache?.sizeLimit = 500 * 1024 * 1024

            let imageCache = Nuke.ImageCache()
            imageCache.costLimit = 100 * 1024 * 1024

            $0.dataCache = dataCache
            $0.imageCache = imageCache
            $0.dataLoader = DataLoader(configuration: configuration)
            $0.dataCachePolicy = .storeOriginalData
            $0.isStoringPreviewsInMemoryCache = false
        }

        ImagePipeline.shared = pipeline
        ReaderLogger.shared.log("Configured reader image pipeline cache data=500MB image=100MB", type: "ReaderPerf")
    }
}
#endif
