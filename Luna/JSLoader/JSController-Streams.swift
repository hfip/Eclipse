//
//  JSLoader-Streams.swift
//  Sora
//
//  Created by Francesco on 07/08/25.
//

import JavaScriptCore

extension JSController {
    func fetchStreamUrlJS(episodeUrl: String, softsub: Bool = false, module: Service, completion: @escaping ((streams: [String]?, subtitles: [String]?,sources: [[String:Any]]? )) -> Void) {
        let operation = beginServiceOperation(service: module, operation: "extractStreamUrl", primaryURL: episodeUrl)

        if let exception = context.exception {
            Logger.shared.log("Service stream JavaScript exception service=\(module.metadata.sourceName): \(exception)", type: "Error")
            endServiceOperation(operation, reason: "exception")
            completion((nil, nil,nil))
            return
        }
        
        guard let extractStreamUrlFunction = context.objectForKeyedSubscript("extractStreamUrl") else {
            Logger.shared.log("No JavaScript function extractStreamUrl found service=\(module.metadata.sourceName)", type: "Error")
            endServiceOperation(operation, reason: "missing-function")
            completion((nil, nil,nil))
            return
        }
        
        let promiseValue = extractStreamUrlFunction.call(withArguments: [episodeUrl])
        guard let promise = promiseValue else {
            Logger.shared.log("extractStreamUrl did not return a Promise service=\(module.metadata.sourceName)", type: "Error")
            endServiceOperation(operation, reason: "invalid-promise")
            completion((nil, nil,nil))
            return
        }
        
        let thenBlock: @convention(block) (JSValue) -> Void = { [weak self] result in
            guard let self else { return }
            
            if result.isNull || result.isUndefined {
                Logger.shared.log("Received null or undefined stream result service=\(module.metadata.sourceName)", type: "Error")
                self.endServiceOperation(operation, reason: "empty-result")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            if let resultString = result.toString(), resultString == "[object Promise]" {
                Logger.shared.log("Received Promise object instead of resolved stream value service=\(module.metadata.sourceName)", type: "Error")
                self.endServiceOperation(operation, reason: "promise-object")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            guard let jsonString = result.toString() else {
                Logger.shared.log("Failed to convert stream JSValue to string service=\(module.metadata.sourceName)", type: "Error")
                self.endServiceOperation(operation, reason: "invalid-result")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            guard let data = jsonString.data(using: .utf8) else {
                Logger.shared.log("Failed to convert stream string to data service=\(module.metadata.sourceName)", type: "Error")
                self.endServiceOperation(operation, reason: "invalid-data")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    var streamUrls: [String]? = nil
                    var subtitleUrls: [String]? = nil
                    var streamUrlsAndHeaders : [[String:Any]]? = nil
                    
                    if let streamSources = json["streams"] as? [[String:Any]] {
                        streamUrlsAndHeaders = streamSources
                        Logger.shared.log("Found \(streamSources.count) streams and headers service=\(module.metadata.sourceName)", type: "Stream")
                        self.logStreamSourceDiagnostics(streamSources, serviceName: module.metadata.sourceName)
                    } else if let streamSource = json["stream"] as? [String:Any] {
                        streamUrlsAndHeaders = [streamSource]
                        Logger.shared.log("Found single stream with headers service=\(module.metadata.sourceName)", type: "Stream")
                        self.logStreamSourceDiagnostics([streamSource], serviceName: module.metadata.sourceName)
                    } else if let streamsArray = json["streams"] as? [String] {
                        streamUrls = streamsArray
                        Logger.shared.log("Found \(streamsArray.count) streams service=\(module.metadata.sourceName)", type: "Stream")
                        self.logPlainStreamDiagnostics(streamsArray, serviceName: module.metadata.sourceName)
                    } else if let streamUrl = json["stream"] as? String {
                        streamUrls = [streamUrl]
                        Logger.shared.log("Found single stream service=\(module.metadata.sourceName)", type: "Stream")
                        self.logPlainStreamDiagnostics([streamUrl], serviceName: module.metadata.sourceName)
                    }
                    
                    if let subsArray = json["subtitles"] as? [String] {
                        subtitleUrls = subsArray
                        Logger.shared.log("Found \(subsArray.count) subtitle tracks service=\(module.metadata.sourceName)", type: "Stream")
                    } else if let subtitleUrl = json["subtitles"] as? String {
                        subtitleUrls = [subtitleUrl]
                        Logger.shared.log("Found single subtitle track service=\(module.metadata.sourceName)", type: "Stream")
                    }
                    
                    Logger.shared.log("Service stream extraction completed service=\(module.metadata.sourceName) plainStreams=\(streamUrls?.count ?? 0) structuredSources=\(streamUrlsAndHeaders?.count ?? 0) subtitles=\(subtitleUrls?.count ?? 0)", type: "Stream")
                    self.endServiceOperation(operation, reason: "resolved")
                    DispatchQueue.main.async {
                        completion((streamUrls, subtitleUrls, streamUrlsAndHeaders))
                    }
                    return
                }
                
                if let streamsArray = try JSONSerialization.jsonObject(with: data, options: []) as? [String] {
                    Logger.shared.log("Starting multi-stream with \(streamsArray.count) sources service=\(module.metadata.sourceName)", type: "Stream")
                    self.endServiceOperation(operation, reason: "resolved-array")
                    DispatchQueue.main.async { completion((streamsArray, nil, nil)) }
                    return
                }
            } catch {
                Logger.shared.log("Stream JSON parsing error service=\(module.metadata.sourceName): \(error.localizedDescription)", type: "Error")
            }
            
            Logger.shared.log("Starting stream from raw string service=\(module.metadata.sourceName) target=\(ServiceSandboxState.redactedURL(jsonString))", type: "Stream")
            self.endServiceOperation(operation, reason: "raw-string")
            DispatchQueue.main.async {
                completion(([jsonString], nil, nil))
            }
        }
        
        let catchBlock: @convention(block) (JSValue) -> Void = { error in
            let errorMessage = error.toString() ?? "Unknown JavaScript error"
            Logger.shared.log("Stream promise rejected service=\(module.metadata.sourceName): \(errorMessage)", type: "Error")
            self.endServiceOperation(operation, reason: "rejected")
            DispatchQueue.main.async {
                completion((nil, nil, nil))
            }
        }
        
        let thenFunction = JSValue(object: thenBlock, in: context)
        let catchFunction = JSValue(object: catchBlock, in: context)
        
        guard let thenFunction = thenFunction, let catchFunction = catchFunction else {
            Logger.shared.log("Failed to create JSValue objects for stream Promise handling service=\(module.metadata.sourceName)", type: "Error")
            endServiceOperation(operation, reason: "handler-create-failed")
            completion((nil, nil, nil))
            return
        }
        
        promise.invokeMethod("then", withArguments: [thenFunction])
        promise.invokeMethod("catch", withArguments: [catchFunction])
    }

    private func logStreamSourceDiagnostics(_ sources: [[String: Any]], serviceName: String) {
        let summaries = sources.enumerated().prefix(8).map { index, source in
            streamSourceDiagnosticSummary(source, index: index)
        }.joined(separator: " || ")
        Logger.shared.log("Service stream diagnostics service=\(serviceName) sourceCount=\(sources.count) \(summaries)", type: "StreamDiagnostics")
    }

    private func logPlainStreamDiagnostics(_ urls: [String], serviceName: String) {
        let summaries = urls.enumerated().prefix(8).map { index, urlString in
            plainStreamDiagnosticSummary(urlString, index: index)
        }.joined(separator: " || ")
        Logger.shared.log("Service stream diagnostics service=\(serviceName) sourceCount=\(urls.count) \(summaries)", type: "StreamDiagnostics")
    }

    private func streamSourceDiagnosticSummary(_ source: [String: Any], index: Int) -> String {
        let urlString = firstStringValue(in: source, keys: ["url", "file", "src", "link", "stream"])
        let name = firstStringValue(in: source, keys: ["name", "title", "label", "quality"]) ?? "nil"
        let headerKeys = ((source["headers"] as? [String: Any]) ?? (source["headers"] as? [String: String])?.mapValues { $0 as Any } ?? [:])
            .keys
            .sorted()
            .joined(separator: ",")
        let summary = urlString.map { plainStreamDiagnosticSummary($0, index: index) } ?? "#\(index) url=nil"
        return "\(summary) name=\(name) headerKeys=[\(headerKeys)]"
    }

    private func plainStreamDiagnosticSummary(_ urlString: String, index: Int) -> String {
        guard let url = URL(string: urlString) else {
            return "#\(index) url=invalid"
        }
        let ext = url.pathExtension.isEmpty ? "none" : url.pathExtension
        let tail = url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
        return "#\(index) host=\(url.host ?? "nil") ext=\(ext) tail=\(tail)"
    }

    private func firstStringValue(in source: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = source[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
