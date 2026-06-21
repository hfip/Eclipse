import Foundation
import JavaScriptCore

class KanzenRunnerController {
    private let moduleRunner: KanzenModuleRunner
    init(moduleRunner: KanzenModuleRunner) {
        self.moduleRunner = moduleRunner
    }

    private func parseArrayOfDictionaries(from jsValue: JSValue?) -> [[String: Any]]? {
        guard let jsValue else { return nil }

        if let result = jsValue.toArray() as? [[String: Any]] {
            return result
        }

        if let dictionary = jsValue.toDictionary() as? [String: Any] {
            for key in ["sections", "items", "results", "data", "home", "catalogs", "filters", "filterGroups", "groups"] {
                if let result = dictionary[key] as? [[String: Any]] {
                    return result
                }
                if let result = dictionary[key] as? [Any] {
                    return result.compactMap { $0 as? [String: Any] }
                }
            }
        }

        if jsValue.isString,
           let jsonString = jsValue.toString(),
           let data = jsonString.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) {
            if let result = parsed as? [[String: Any]] {
                return result
            }
            if let dictionary = parsed as? [String: Any] {
                for key in ["sections", "items", "results", "data", "home", "catalogs", "filters", "filterGroups", "groups"] {
                    if let result = dictionary[key] as? [[String: Any]] {
                        return result
                    }
                    if let result = dictionary[key] as? [Any] {
                        return result.compactMap { $0 as? [String: Any] }
                    }
                }
            }
        }

        return nil
    }
    
    func loadScript(_script: String, isNovel: Bool = false) throws
    {
        try moduleRunner.loadScript(_script, isNovel: isNovel)
    }
    
    func extractImages(params:Any,completion: @escaping ([String]?) -> Void)
    {
        moduleRunner.extractImages(params: params)
        {
            jsResult, error in
            guard let jsValue = jsResult else {
                completion(nil)
                return
            }

            if let result = jsValue.toArray() as? [String] {
                completion(result)
                return
            }

            // Novel modules may return a JSON string
            if jsValue.isString, let jsonString = jsValue.toString(),
               let data = jsonString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String] {
                completion(parsed)
                return
            }

            completion(nil)
        }
    }

    func homeSections(page: Int = 0, completion: @escaping ([[String: Any]]?) -> Void) {
        moduleRunner.homeSections(page: page) { jsResult, error in
            if let error {
                ReaderLogger.shared.log("RunnerController.homeSections: \(error.localizedDescription)", type: "Error")
                completion(nil)
                return
            }

            completion(self.parseArrayOfDictionaries(from: jsResult))
        }
    }

    func homeSectionItems(sectionId: String, page: Int = 0, completion: @escaping ([[String: Any]]?) -> Void) {
        moduleRunner.homeSectionItems(sectionId: sectionId, page: page) { jsResult, error in
            if let error {
                ReaderLogger.shared.log("RunnerController.homeSectionItems: \(error.localizedDescription)", type: "Error")
                completion(nil)
                return
            }

            completion(self.parseArrayOfDictionaries(from: jsResult))
        }
    }

    func searchFilters(completion: @escaping ([[String: Any]]?) -> Void) {
        moduleRunner.searchFilters { jsResult, error in
            if let error {
                ReaderLogger.shared.log("RunnerController.searchFilters: \(error.localizedDescription)", type: "Error")
                completion(nil)
                return
            }

            completion(self.parseArrayOfDictionaries(from: jsResult))
        }
    }

    func searchAdvanced(_input: String, filters: [String: Any], page: Int = 0, completion: @escaping ([[String: Any]]?) -> Void) {
        moduleRunner.searchResultsAdvanced(input: _input, filters: filters, page: page) { jsResult, error in
            if let error {
                ReaderLogger.shared.log("RunnerController.searchAdvanced: \(error.localizedDescription)", type: "Error")
                completion(nil)
                return
            }

            completion(self.parseArrayOfDictionaries(from: jsResult))
        }
    }
    
    func extractChapters(params:Any, completion: @escaping (Any?) -> Void )
    {
        ReaderLogger.shared.log("RunnerController.extractChapters: called with params=\(params)", type: "Debug")
        moduleRunner.extractChapters(params: params){
            jsResult, error in
            if let error = error {
                ReaderLogger.shared.log("RunnerController.extractChapters: JS error: \(error.localizedDescription)", type: "Error")
                completion(nil)
                return
            }
            guard let jsResult = jsResult else {
                ReaderLogger.shared.log("RunnerController.extractChapters: jsResult is nil", type: "Error")
                completion(nil)
                return
            }
            ReaderLogger.shared.log("RunnerController.extractChapters: jsResult isArray=\(jsResult.isArray), isObject=\(jsResult.isObject), isString=\(jsResult.isString), isUndefined=\(jsResult.isUndefined), isNull=\(jsResult.isNull)", type: "Debug")
            // Try dictionary first (Kanzen format: {language: [[name, [data...]]]})
            if let result = jsResult.toDictionary() as? [String:Any] {
                ReaderLogger.shared.log("RunnerController.extractChapters: parsed as dictionary with \(result.count) keys: \(Array(result.keys))", type: "Debug")
                completion(result)
                return
            }
            ReaderLogger.shared.log("RunnerController.extractChapters: toDictionary failed, trying toArray", type: "Debug")
            // Try array (Sora format: [{number, title, href}, ...])
            if let result = jsResult.toArray() as? [[String:Any]] {
                ReaderLogger.shared.log("RunnerController.extractChapters: parsed as array with \(result.count) elements", type: "Debug")
                if let first = result.first {
                    ReaderLogger.shared.log("RunnerController.extractChapters: first element keys: \(Array(first.keys))", type: "Debug")
                }
                completion(result)
                return
            }
            ReaderLogger.shared.log("RunnerController.extractChapters: toArray failed, trying JSON string", type: "Debug")
            // Try JSON string fallback
            if let jsonString = jsResult.toString() {
                ReaderLogger.shared.log("RunnerController.extractChapters: toString preview: \(jsonString.prefix(300))", type: "Debug")
                if let data = jsonString.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) {
                    ReaderLogger.shared.log("RunnerController.extractChapters: JSON parse succeeded, type=\(type(of: parsed))", type: "Debug")
                    completion(parsed)
                    return
                }
            }
            ReaderLogger.shared.log("RunnerController.extractChapters: all parsing failed, returning nil", type: "Error")
            completion(nil)
        }
    }
    
    func extractDetails(params:Any, completion: @escaping ([String:Any]?)-> Void)
    {
       
        moduleRunner.extractDetails(params: params)
        {
            jsResult, error in
            guard let jsValue = jsResult else {
                completion(nil)
                return
            }

            if let result = jsValue.toDictionary() as? [String:Any] {
                completion(result)
                return
            }

            // Novel modules may return a JSON string
            if jsValue.isString, let jsonString = jsValue.toString(),
               let data = jsonString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String:Any] {
                completion(parsed)
                return
            }

            completion(nil)
        }
    }
    
    func extractText(params:Any, completion: @escaping (String?) -> Void)
    {
        ReaderLogger.shared.log("RunnerController.extractText: called with params type=\(type(of: params)), value=\(params)", type: "Debug")
        moduleRunner.extractText(params: params)
        {
            jsResult, error in
            if let error = error {
                ReaderLogger.shared.log("RunnerController.extractText: error: \(error.localizedDescription)", type: "Error")
                completion(nil)
                return
            }
            guard let jsResult = jsResult else {
                ReaderLogger.shared.log("RunnerController.extractText: jsResult is nil", type: "Error")
                completion(nil)
                return
            }
            ReaderLogger.shared.log("RunnerController.extractText: isString=\(jsResult.isString), isUndefined=\(jsResult.isUndefined), isNull=\(jsResult.isNull)", type: "Debug")
            guard let result = jsResult.toString() else {
                ReaderLogger.shared.log("RunnerController.extractText: toString returned nil", type: "Error")
                completion(nil)
                return
            }
            let preview = result.prefix(200)
            ReaderLogger.shared.log("RunnerController.extractText: result length=\(result.count), preview=\(preview)", type: "Debug")
            completion(result)
        }
    }
    
    func searchInput(_input: String,page:Int = 0, completion: @escaping ([[String:Any]]?) -> Void)
    {
        moduleRunner.searchResults(input: _input,page: page)
        {
            jsResult,error in
            guard let jsValue = jsResult else {
                completion(nil)
                return
            }

            // If the Promise resolved with a JS array, convert directly
            if let result = jsValue.toArray() as? [[String:Any]] {
                completion(result)
                return
            }

            // Novel modules may return a JSON string instead of a JS array;
            // parse it in Swift so .toArray() isn't called on a primitive.
            if jsValue.isString, let jsonString = jsValue.toString(),
               let data = jsonString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String:Any]] {
                completion(parsed)
                return
            }

            completion(nil)
        }
    }
}
