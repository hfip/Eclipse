import Combine
import Foundation

#if os(tvOS)
import FakeWebKit
#else
import WebKit
#endif

#if os(iOS)
import SwiftUI
import UIKit
#endif

enum CloudflareBypassError: Error {
    case timeout
}

extension Notification.Name {
    static let cloudflareBypassSolved = Notification.Name("CloudflareBypassSolved")
}

final class CloudflareBypassManager: ObservableObject {
    static let shared = CloudflareBypassManager()

    @Published private(set) var activeBypassWebView: WKWebView?
    @Published private(set) var pendingVerificationURL: URL?

    private struct CachedBypass: Codable {
        let cookieHeader: String
        let userAgent: String
        let expires: Date
    }

    private enum Keys {
        static let persistedCache = "serviceCloudflareBypassCache"
    }

    private let lock = NSLock()
    private var cache: [String: CachedBypass] = [:]
    private var inProgressHosts: Set<String> = []
    private var bypassWebViews: [String: WKWebView] = [:]

    private init() {
        loadPersistedCache()
    }

    func applyCachedBypass(to request: inout URLRequest, for url: URL) {
        guard let host = normalizedHost(from: url),
              let entry = cachedEntry(for: host) else { return }

        let existingCookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
        let mergedCookie = mergeCookieHeaders(existingCookie, entry.cookieHeader)
        request.setValue(mergedCookie, forHTTPHeaderField: "Cookie")

        if !entry.userAgent.isEmpty {
            request.setValue(entry.userAgent, forHTTPHeaderField: "User-Agent")
        }

        Logger.shared.log(
            "CloudflareBypass: applied cached session host=\(host) cachedCookies=\(cookiePairCount(in: entry.cookieHeader)) mergedWithExisting=\(!existingCookie.isEmpty) userAgent=\(!entry.userAgent.isEmpty)",
            type: "Service"
        )
    }

    func headersByApplyingCachedBypass(_ headers: [String: String], for url: URL) -> [String: String] {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        applyCachedBypass(to: &request, for: url)
        return request.allHTTPHeaderFields ?? headers
    }

    func fullCookieHeader(for host: String) -> String? {
        cachedEntry(for: normalizedHost(host))?.cookieHeader
    }

    func bypassUserAgent(for host: String) -> String? {
        let userAgent = cachedEntry(for: normalizedHost(host))?.userAgent ?? ""
        return userAgent.isEmpty ? nil : userAgent
    }

    func store(cookieHeader: String, userAgent: String, for host: String) {
        let normalizedHost = normalizedHost(host)
        guard !cookieHeader.isEmpty else { return }

        lock.lock()
        cache[normalizedHost] = CachedBypass(
            cookieHeader: cookieHeader,
            userAgent: userAgent,
            expires: Date().addingTimeInterval(3600)
        )
        lock.unlock()

        persistCache()
        Logger.shared.log(
            "CloudflareBypass: stored solved session host=\(normalizedHost) cookies=\(cookiePairCount(in: cookieHeader)) userAgent=\(!userAgent.isEmpty) ttlSeconds=3600",
            type: "Service"
        )
        NotificationCenter.default.post(name: .cloudflareBypassSolved, object: normalizedHost)
    }

    @MainActor
    func flagPendingVerification(for url: URL) {
        guard let host = normalizedHost(from: url) else { return }
        removeCachedEntry(for: host)
        pendingVerificationURL = url
        Logger.shared.log(
            "CloudflareBypass: pending manual verification host=\(host)",
            type: "Service"
        )
    }

    func recoverChallengedRequest(
        for url: URL,
        method: String,
        body: Data?,
        extraHeaders: [String: String],
        allowRedirects: Bool
    ) async -> (data: Data, response: HTTPURLResponse)? {
        Logger.shared.log(
            "CloudflareBypass: recovery requested host=\(redactedHost(url)) method=\(method) bodyBytes=\(body?.count ?? 0) extraHeaders=\(extraHeaders.count) redirects=\(allowRedirects)",
            type: "Service"
        )

        if let recovered = await retryWithSolvedSession(
            for: url,
            method: method,
            body: body,
            extraHeaders: extraHeaders,
            allowRedirects: allowRedirects
        ) {
            Logger.shared.log(
                "CloudflareBypass: recovered with existing solved session host=\(redactedHost(url)) status=\(recovered.response.statusCode) bytes=\(recovered.data.count)",
                type: "Service"
            )
            return recovered
        }

        Logger.shared.log(
            "CloudflareBypass: opening verification flow host=\(redactedHost(url))",
            type: "Service"
        )
        do {
            try await triggerBypass(for: url)
        } catch {
            await flagPendingVerification(for: url)
            Logger.shared.log("CloudflareBypass: verification failed host=\(redactedHost(url)) error=\(error)", type: "Error")
            return nil
        }

        let recovered = await retryWithSolvedSession(
            for: url,
            method: method,
            body: body,
            extraHeaders: extraHeaders,
            allowRedirects: allowRedirects
        )

        if recovered == nil {
            await flagPendingVerification(for: url)
            Logger.shared.log(
                "CloudflareBypass: recovery unavailable after verification host=\(redactedHost(url))",
                type: "Service"
            )
        } else if let recovered {
            Logger.shared.log(
                "CloudflareBypass: recovered after verification host=\(redactedHost(url)) status=\(recovered.response.statusCode) bytes=\(recovered.data.count)",
                type: "Service"
            )
        }
        return recovered
    }

    func retryWithSolvedSession(
        for url: URL,
        method: String,
        body: Data?,
        extraHeaders: [String: String],
        allowRedirects: Bool
    ) async -> (data: Data, response: HTTPURLResponse)? {
        guard let host = normalizedHost(from: url) else {
            Logger.shared.log("CloudflareBypass: retry skipped because URL has no host", type: "Service")
            return nil
        }

        let sessionInfo: (cookieHeader: String, userAgent: String, source: String)?
        if let liveInfo = await liveBypassSessionInfo(for: host) {
            sessionInfo = (liveInfo.cookieHeader, liveInfo.userAgent, "liveWebView")
        } else if let entry = cachedEntry(for: host) {
            sessionInfo = (entry.cookieHeader, entry.userAgent, "cache")
        } else {
            sessionInfo = nil
        }

        guard let sessionInfo, !sessionInfo.cookieHeader.isEmpty else {
            Logger.shared.log("CloudflareBypass: no solved session available host=\(host)", type: "Service")
            return nil
        }

        Logger.shared.log(
            "CloudflareBypass: retrying challenged request host=\(host) source=\(sessionInfo.source) method=\(method) bodyBytes=\(body?.count ?? 0) cookies=\(cookiePairCount(in: sessionInfo.cookieHeader)) redirects=\(allowRedirects)",
            type: "Service"
        )

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in extraHeaders where !["cookie", "user-agent"].contains(key.lowercased()) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue(sessionInfo.cookieHeader, forHTTPHeaderField: "Cookie")
        if !sessionInfo.userAgent.isEmpty {
            request.setValue(sessionInfo.userAgent, forHTTPHeaderField: "User-Agent")
        }

        let session = URLSession.fetchData(allowRedirects: allowRedirects)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            if Self.isChallengeResponse(
                status: httpResponse.statusCode,
                body: bodyText,
                headers: Self.headersDictionary(from: httpResponse)
            ) {
                removeCachedEntry(for: host)
                Logger.shared.log(
                    "CloudflareBypass: solved session still challenged host=\(host) status=\(httpResponse.statusCode); cache cleared",
                    type: "Service"
                )
                return nil
            }
            Logger.shared.log(
                "CloudflareBypass: session retry succeeded host=\(redactedHost(url)) source=\(sessionInfo.source) status=\(httpResponse.statusCode) bytes=\(data.count)",
                type: "Service"
            )
            return (data, httpResponse)
        } catch {
            Logger.shared.log("CloudflareBypass: session retry failed host=\(redactedHost(url)) error=\(error.localizedDescription)", type: "Error")
            return nil
        }
    }

    @MainActor
    func triggerBypass(for url: URL) async throws {
        guard let host = normalizedHost(from: url) else { return }
        if cachedEntry(for: host) != nil {
            Logger.shared.log("CloudflareBypass: verification skipped because cache exists host=\(host)", type: "Service")
            return
        }

        if inProgressHosts.contains(host) {
            Logger.shared.log("CloudflareBypass: verification already in progress; waiting host=\(host)", type: "Service")
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if !inProgressHosts.contains(host) { return }
            }
            Logger.shared.log("CloudflareBypass: verification wait timed out host=\(host)", type: "Service")
            return
        }

        inProgressHosts.insert(host)
        defer { inProgressHosts.remove(host) }

        let webView = makeBypassWebView()
        let rootURL = URL(string: "\(url.scheme ?? "https")://\(host)/") ?? url
        Logger.shared.log("CloudflareBypass: verification web view opened host=\(host)", type: "Service")

        activeBypassWebView = webView
        #if os(iOS)
        CloudflareBypassWindowController.shared.show()
        #endif
        defer {
            activeBypassWebView = nil
            #if os(iOS)
            CloudflareBypassWindowController.shared.hide()
            #endif
        }

        webView.load(URLRequest(url: rootURL))
        Logger.shared.log("CloudflareBypass: verification web view loading host=\(host) root=\(rootURL.scheme ?? "https")://\(host)/", type: "Service")

        for _ in 0..<60 {
            try await Task.sleep(nanoseconds: 500_000_000)
            guard activeBypassWebView != nil else {
                Logger.shared.log("CloudflareBypass: verification cancelled host=\(host)", type: "Service")
                return
            }
            if let cookieHeader = await allCookiesHeader(for: host, in: webView),
               cookieHeader.lowercased().contains("cf_clearance=") {
                let userAgent = await userAgent(for: webView)
                Logger.shared.log(
                    "CloudflareBypass: clearance cookie observed host=\(host) cookies=\(cookiePairCount(in: cookieHeader)) userAgent=\(!userAgent.isEmpty)",
                    type: "Service"
                )
                store(cookieHeader: cookieHeader, userAgent: userAgent, for: host)
                bypassWebViews[host] = webView
                if pendingVerificationURL?.host?.lowercased() == host {
                    pendingVerificationURL = nil
                }
                Logger.shared.log("CloudflareBypass: verification solved host=\(host)", type: "Service")
                return
            }
        }

        Logger.shared.log("CloudflareBypass: verification timed out host=\(host)", type: "Service")
        throw CloudflareBypassError.timeout
    }

    @MainActor
    func cancelActiveBypass() {
        if let host = activeBypassWebView?.url?.host?.lowercased() ?? pendingVerificationURL?.host?.lowercased() {
            Logger.shared.log("CloudflareBypass: user cancelled verification host=\(host)", type: "Service")
        } else {
            Logger.shared.log("CloudflareBypass: user cancelled verification", type: "Service")
        }
        activeBypassWebView = nil
    }

    static func isChallengeResponse(status: Int, body: String, headers: [String: String] = [:]) -> Bool {
        let lowerBody = body.lowercased()
        if lowerBody.contains("challenges.cloudflare.com")
            || lowerBody.contains("__cf_chl_")
            || lowerBody.contains("cf-turnstile")
            || lowerBody.contains("challenge-platform")
            || lowerBody.contains("enable javascript and cookies")
            || lowerBody.contains("cloudflare ray id")
            || (lowerBody.contains("just a moment") && lowerBody.contains("cloudflare")) {
            return true
        }

        let lowerHeaders = headers.reduce(into: [String: String]()) { result, pair in
            result[pair.key.lowercased()] = pair.value.lowercased()
        }
        let server = lowerHeaders["server"] ?? ""
        let hasCloudflareHeader = server.contains("cloudflare") || lowerHeaders["cf-ray"] != nil
        return hasCloudflareHeader && [403, 429, 503].contains(status) && lowerBody.contains("<html")
    }

    static func headersDictionary(from response: HTTPURLResponse?) -> [String: String] {
        guard let response else { return [:] }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        return headers
    }

    @MainActor
    func captureSolvedCookies(from webView: WKWebView, for url: URL?) {
        guard let url, let host = normalizedHost(from: url) else { return }
        Task { @MainActor in
            guard let cookieHeader = await allCookiesHeader(for: host, in: webView),
                  cookieHeader.lowercased().contains("cf_clearance=") else { return }
            let resolvedUserAgent: String
            if let customUserAgent = webView.customUserAgent, !customUserAgent.isEmpty {
                resolvedUserAgent = customUserAgent
            } else {
                resolvedUserAgent = await userAgent(for: webView)
            }
            store(cookieHeader: cookieHeader, userAgent: resolvedUserAgent, for: host)
            bypassWebViews[host] = webView
            Logger.shared.log(
                "CloudflareBypass: captured solved cookies from web view host=\(host) cookies=\(cookiePairCount(in: cookieHeader)) userAgent=\(!resolvedUserAgent.isEmpty)",
                type: "Service"
            )
        }
    }

    private func cachedEntry(for host: String) -> CachedBypass? {
        lock.lock()
        let entry = cache[host]
        if let entry, entry.expires <= Date() {
            cache.removeValue(forKey: host)
            lock.unlock()
            persistCache()
            Logger.shared.log("CloudflareBypass: cached session expired host=\(host)", type: "Service")
            return nil
        }
        lock.unlock()
        return entry
    }

    private func removeCachedEntry(for host: String) {
        lock.lock()
        let removed = cache.removeValue(forKey: host) != nil
        lock.unlock()
        if removed {
            persistCache()
            Logger.shared.log("CloudflareBypass: removed cached session host=\(host)", type: "Service")
        }
    }

    private func persistCache() {
        lock.lock()
        let live = cache.filter { $0.value.expires > Date() }
        cache = live
        let data = try? JSONEncoder().encode(live)
        lock.unlock()

        if let data {
            UserDefaults.standard.set(data, forKey: Keys.persistedCache)
        }
    }

    private func loadPersistedCache() {
        guard let data = UserDefaults.standard.data(forKey: Keys.persistedCache),
              let decoded = try? JSONDecoder().decode([String: CachedBypass].self, from: data) else { return }
        cache = decoded.filter { $0.value.expires > Date() }
        Logger.shared.log("CloudflareBypass: loaded persisted sessions count=\(cache.count)", type: "Service")
    }

    @MainActor
    private func liveBypassSessionInfo(for host: String) async -> (cookieHeader: String, userAgent: String)? {
        guard let webView = bypassWebViews[host],
              let cookieHeader = await allCookiesHeader(for: host, in: webView),
              !cookieHeader.isEmpty else { return nil }
        return (cookieHeader, await userAgent(for: webView))
    }

    @MainActor
    private func makeBypassWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        #if !os(tvOS)
        config.websiteDataStore = .nonPersistent()
        #endif
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        #endif
        config.mediaTypesRequiringUserActionForPlayback = []
        return WKWebView(frame: .zero, configuration: config)
    }

    @MainActor
    private func allCookiesHeader(for host: String, in webView: WKWebView) async -> String? {
        #if os(tvOS)
        return nil
        #else
        return await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let hostCookies = cookies.filter { cookie in
                    let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                    return host == domain.lowercased() || host.hasSuffix("." + domain.lowercased())
                }
                let header = hostCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                continuation.resume(returning: header.isEmpty ? nil : header)
            }
        }
        #endif
    }

    @MainActor
    private func userAgent(for webView: WKWebView) async -> String {
        if let customUserAgent = webView.customUserAgent, !customUserAgent.isEmpty {
            return customUserAgent
        }
        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("navigator.userAgent") { result, _ in
                continuation.resume(returning: (result as? String) ?? "")
            }
        }
    }

    private func normalizedHost(from url: URL) -> String? {
        url.host?.lowercased()
    }

    private func normalizedHost(_ host: String) -> String {
        host.lowercased()
    }

    private func mergeCookieHeaders(_ existing: String, _ bypass: String) -> String {
        if existing.isEmpty { return bypass }
        if bypass.isEmpty { return existing }

        var merged = cookiePairs(from: existing)
        for bypassPair in cookiePairs(from: bypass) {
            if let index = merged.firstIndex(where: { $0.name == bypassPair.name }) {
                merged[index] = bypassPair
            } else {
                merged.append(bypassPair)
            }
        }
        return merged.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private func cookiePairs(from header: String) -> [(name: String, value: String)] {
        header.split(separator: ";").compactMap { part in
            let pieces = part.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard pieces.count == 2, !pieces[0].isEmpty else { return nil }
            return (name: pieces[0], value: pieces[1])
        }
    }

    private func cookiePairCount(in header: String) -> Int {
        cookiePairs(from: header).count
    }

    private func redactedHost(_ url: URL) -> String {
        normalizedHost(from: url) ?? "unknown-host"
    }
}

#if os(iOS)
private struct CloudflareBypassSheetView: View {
    @ObservedObject private var manager = CloudflareBypassManager.shared

    var body: some View {
        NavigationView {
            Group {
                if let webView = manager.activeBypassWebView {
                    CloudflareBypassWebView(webView: webView)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Security Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Task { @MainActor in
                            CloudflareBypassManager.shared.cancelActiveBypass()
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .background(Color(UIColor.systemBackground))
    }
}

private struct CloudflareBypassWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@MainActor
private final class CloudflareBypassWindowController {
    static let shared = CloudflareBypassWindowController()
    private var window: UIWindow?

    private init() {}

    func show() {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }

        let host = UIHostingController(rootView: CloudflareBypassSheetView())
        host.view.backgroundColor = UIColor.systemBackground

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
    }

    func hide() {
        window?.isHidden = true
        window = nil
    }
}
#endif
