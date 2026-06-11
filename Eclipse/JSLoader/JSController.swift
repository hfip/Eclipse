//
//  JSController.swift
//  Sora
//
//  Created by Francesco on 07/08/25.
//

import SwiftUI
import JavaScriptCore

struct ServiceSandboxOperation {
    let id: UUID
    let serviceName: String
    let operation: String
    let primaryURL: String?
}

final class ServiceSandboxState {
    private let lock = NSLock()
    private var currentOperation: ServiceSandboxOperation?
    private var loadingServiceName: String?

    func beginLoading(serviceName: String?) {
        lock.lock()
        loadingServiceName = serviceName
        lock.unlock()
    }

    func endLoading() {
        lock.lock()
        loadingServiceName = nil
        lock.unlock()
    }

    func beginOperation(serviceName: String, operation: String, primaryURL: String? = nil) -> ServiceSandboxOperation {
        let op = ServiceSandboxOperation(
            id: UUID(),
            serviceName: serviceName,
            operation: operation,
            primaryURL: primaryURL
        )
        lock.lock()
        currentOperation = op
        lock.unlock()
        Logger.shared.log("Service operation started service=\(serviceName) operation=\(operation) target=\(Self.redactedURL(primaryURL))", type: "Service")
        return op
    }

    func endOperation(_ operation: ServiceSandboxOperation, reason: String) {
        lock.lock()
        let shouldEnd = currentOperation?.id == operation.id
        if shouldEnd {
            currentOperation = nil
        }
        lock.unlock()
        if shouldEnd {
            Logger.shared.log("Service operation ended service=\(operation.serviceName) operation=\(operation.operation) reason=\(reason)", type: "Service")
        }
    }

    func contextLabel() -> String {
        lock.lock()
        let operation = currentOperation
        let loadingName = loadingServiceName
        lock.unlock()

        if let operation {
            return "service=\(operation.serviceName) operation=\(operation.operation)"
        }
        if let loadingName {
            return "service=\(loadingName) operation=loadScript"
        }
        return "service=unknown operation=none"
    }

    func allowServiceNetworkRequest(api: String, urlString: String) -> ServiceSandboxOperation? {
        lock.lock()
        let operation = currentOperation
        let loadingName = loadingServiceName
        lock.unlock()

        guard let operation else {
            let serviceName = loadingName ?? "unknown"
            Logger.shared.log("Service sandbox blocked network request outside user operation service=\(serviceName) api=\(api) target=\(Self.redactedURL(urlString))", type: "ServiceSandbox")
            return nil
        }

        if Self.isBlockedTrackingURL(urlString) {
            Logger.shared.log("Service sandbox blocked tracking request service=\(operation.serviceName) operation=\(operation.operation) api=\(api) target=\(Self.redactedURL(urlString))", type: "ServiceSandbox")
            return nil
        }

        Logger.shared.log("Service network request service=\(operation.serviceName) operation=\(operation.operation) api=\(api) target=\(Self.redactedURL(urlString))", type: "Service")
        return operation
    }

    static func redactedURL(_ value: String?) -> String {
        guard let value, let url = URL(string: value) else {
            return value?.isEmpty == false ? "invalid-url" : "nil"
        }

        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = url.path.isEmpty ? "/" : url.path
        return components.string ?? "\(url.scheme ?? "unknown")://\(url.host ?? "unknown")"
    }

    static func hostDescription(_ value: String?) -> String {
        guard let value, let host = URL(string: value)?.host else { return "nil" }
        return host
    }

    static func isBlockedTrackingURL(_ value: String?) -> Bool {
        guard let value,
              let url = URL(string: value),
              let host = url.host?.lowercased() else {
            return false
        }

        let blockedSuffixes = [
            "google-analytics.com",
            "googletagmanager.com",
            "doubleclick.net",
            "googlesyndication.com",
            "facebook.net",
            "facebook.com",
            "mixpanel.com",
            "segment.io",
            "segment.com",
            "amplitude.com",
            "appsflyer.com",
            "branch.io",
            "hotjar.com",
            "clarity.ms",
            "scorecardresearch.com",
            "quantserve.com",
            "newrelic.com",
            "sentry.io",
            "datadoghq-browser-agent.com"
        ]

        if blockedSuffixes.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return true
        }

        let blockedHostTokens = ["analytics", "telemetry", "metrics", "tracking", "tracker", "beacon"]
        return blockedHostTokens.contains(where: host.contains)
    }
}

class JSController: NSObject, ObservableObject {
    static let shared = JSController()
    var context: JSContext
    private let sandbox = ServiceSandboxState()
    
    override init() {
        self.context = JSContext()
        super.init()
        setupContext()
    }
    
    func setupContext() {
        context.setupJavaScriptEnvironment(sandbox: sandbox)
    }
    
    func loadScript(_ script: String, service: Service? = nil) {
        // Clean up old context
        context.exception = nil
        
        // Create fresh context
        context = JSContext()
        context.setupJavaScriptEnvironment(sandbox: sandbox)
        sandbox.beginLoading(serviceName: service?.metadata.sourceName)
        context.evaluateScript(script)
        if let exception = context.exception {
            Logger.shared.log("Error loading service script \(sandbox.contextLabel()): \(exception)", type: "Error")
        }
        sandbox.endLoading()
    }

    func beginServiceOperation(service: Service, operation: String, primaryURL: String? = nil) -> ServiceSandboxOperation {
        sandbox.beginOperation(
            serviceName: service.metadata.sourceName,
            operation: operation,
            primaryURL: primaryURL
        )
    }

    func endServiceOperation(_ operation: ServiceSandboxOperation, reason: String) {
        sandbox.endOperation(operation, reason: reason)
    }
}
