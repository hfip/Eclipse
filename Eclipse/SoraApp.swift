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

    @State private var startupReady = false
    @State private var startupFallbackScheduled = false
    @State private var showSplash = true
    private let startupFallbackDelay: TimeInterval = 3

#if !os(tvOS)
    @AppStorage("showKanzen") private var showKanzen: Bool = false
#endif

    init() {
        CrashReportManager.shared.start()
        GitHubReleaseChecker.registerDefaults()
#if !os(tvOS)
        ReaderImagePipelineConfigurator.configureIfNeeded()
#endif

        // Check and auto-clear cache on app startup if threshold exceeded
        DispatchQueue.global(qos: .background).async {
            CacheManager.shared.checkAndAutoClearIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
#if os(tvOS)
                ContentView(onStartupReady: markStartupReady)
                    .onAppear { scheduleStartupFallback() }
#else
                if showKanzen {
                    KanzenMenu(onStartupReady: markStartupReady)
                        .environmentObject(settings)
                        .environmentObject(theme)
                        .accentColor(settings.effectiveAccentColor)
                        .onAppear { scheduleStartupFallback() }
                } else {
                    ContentView(onStartupReady: markStartupReady)
                        .environmentObject(theme)
                        .onAppear { scheduleStartupFallback() }
                }
#endif

                if showSplash {
                    SplashScreenView(isFinished: $startupReady) {
                        showSplash = false
                    }
                        .ignoresSafeArea()
                        .zIndex(1)
                }
            }
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
