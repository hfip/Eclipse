//
//  MangaCatalogManager.swift
//  Kanzen
//
//  Created by Luna on 2025.
//

import Foundation
import Combine
import SwiftUI

enum MangaHomeSourceKind: String, Codable {
    case aidoku
    case legacyModule
}

struct MangaHomeSource: Identifiable, Equatable {
    let id: String
    let name: String
    let iconURL: String
    let kind: MangaHomeSourceKind
    let aidokuSource: AidokuInstalledSource?
    let module: ModuleDataContainer?
    var isEnabled: Bool
    var order: Int

    var isAidoku: Bool { kind == .aidoku }
    var isLegacyModule: Bool { kind == .legacyModule }

    var sourceId: String? {
        aidokuSource?.id
    }

    var moduleUUID: UUID? {
        module?.id
    }

    static func aidoku(_ source: AidokuInstalledSource, order: Int) -> MangaHomeSource {
        MangaHomeSource(
            id: "aidoku:\(source.id)",
            name: source.name,
            iconURL: source.iconURLString,
            kind: .aidoku,
            aidokuSource: source,
            module: nil,
            isEnabled: source.isEnabled,
            order: order
        )
    }

    static func legacyModule(_ module: ModuleDataContainer, preference: MangaHomeSourcePreference, orderOffset: Int) -> MangaHomeSource {
        MangaHomeSource(
            id: "module:\(module.id.uuidString)",
            name: module.moduleData.sourceName,
            iconURL: module.moduleData.iconURL,
            kind: .legacyModule,
            aidokuSource: nil,
            module: module,
            isEnabled: preference.isEnabled,
            order: orderOffset + preference.order
        )
    }
}

struct MangaHomeSourcePreference: Codable {
    var isEnabled: Bool
    var order: Int
}

final class MangaHomeSourceManager: ObservableObject {
    static let shared = MangaHomeSourceManager()

    @Published private var legacyPreferences: [String: MangaHomeSourcePreference] = [:]

    private let storageKey = "kanzenLegacyHomeSourcePreferences"

    private init() {
        loadPreferences()
    }

    func refreshSources(from modules: [ModuleDataContainer]) {
        reconcile(modules: legacyMangaModules(from: modules))
    }

    func allSources(
        aidokuManager: AidokuSourceManager = .shared,
        modules: [ModuleDataContainer],
        includeDisabledAidoku: Bool = true
    ) -> [MangaHomeSource] {
        let aidokuMetadata = includeDisabledAidoku
            ? aidokuManager.installedSources.filter { aidokuManager.showMatureSources || !$0.isMature }
            : aidokuManager.enabledSources()

        let aidokuSources = aidokuMetadata
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .enumerated()
            .map { index, source in
                MangaHomeSource.aidoku(source, order: index)
            }

        let legacySources = legacySources(from: modules, orderOffset: aidokuSources.count)
        return aidokuSources + legacySources
    }

    func enabledSources(
        aidokuManager: AidokuSourceManager = .shared,
        modules: [ModuleDataContainer]
    ) -> [MangaHomeSource] {
        allSources(aidokuManager: aidokuManager, modules: modules, includeDisabledAidoku: false)
            .filter(\.isEnabled)
    }

    func legacySources(from modules: [ModuleDataContainer], orderOffset: Int = 0) -> [MangaHomeSource] {
        let sourceModules = legacyMangaModules(from: modules)

        return sourceModules.map { module in
            let key = module.id.uuidString
            let preference = legacyPreferences[key] ?? MangaHomeSourcePreference(
                isEnabled: true,
                order: defaultOrder(for: module, in: sourceModules)
            )

            return MangaHomeSource.legacyModule(module, preference: preference, orderOffset: orderOffset)
        }
        .sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func toggleLegacySource(id: String) {
        let key = normalizedLegacyKey(id)
        var preference = legacyPreferences[key] ?? MangaHomeSourcePreference(
            isEnabled: true,
            order: legacyPreferences.count
        )
        preference.isEnabled.toggle()
        legacyPreferences[key] = preference
        savePreferences()
    }

    func moveLegacySource(from offsets: IndexSet, to destination: Int, modules: [ModuleDataContainer]) {
        var orderedIds = legacySources(from: modules).compactMap(\.moduleUUID).map(\.uuidString)
        orderedIds.move(fromOffsets: offsets, toOffset: destination)

        for (index, id) in orderedIds.enumerated() {
            var preference = legacyPreferences[id] ?? MangaHomeSourcePreference(isEnabled: true, order: index)
            preference.order = index
            legacyPreferences[id] = preference
        }

        savePreferences()
    }

    private func legacyMangaModules(from modules: [ModuleDataContainer]) -> [ModuleDataContainer] {
        modules.filter { $0.moduleData.novel != true }
    }

    private func reconcile(modules: [ModuleDataContainer]) {
        let validIds = Set(modules.map { $0.id.uuidString })
        var changed = false

        for key in legacyPreferences.keys where !validIds.contains(key) {
            legacyPreferences.removeValue(forKey: key)
            changed = true
        }

        for (index, module) in modules.enumerated() {
            let key = module.id.uuidString
            if legacyPreferences[key] == nil {
                legacyPreferences[key] = MangaHomeSourcePreference(isEnabled: true, order: index)
                changed = true
            }
        }

        if changed {
            savePreferences()
        }
    }

    private func defaultOrder(for module: ModuleDataContainer, in modules: [ModuleDataContainer]) -> Int {
        modules.firstIndex(where: { $0.id == module.id }) ?? legacyPreferences.count
    }

    private func normalizedLegacyKey(_ id: String) -> String {
        id.replacingOccurrences(of: "module:", with: "")
    }

    private func loadPreferences() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String: MangaHomeSourcePreference].self, from: data)
        else {
            if let oldData = UserDefaults.standard.data(forKey: "kanzenHomeSourcePreferences"),
               let oldDecoded = try? JSONDecoder().decode([String: MangaHomeSourcePreference].self, from: oldData) {
                legacyPreferences = oldDecoded
            }
            return
        }

        legacyPreferences = decoded
    }

    private func savePreferences() {
        if let data = try? JSONEncoder().encode(legacyPreferences) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        objectWillChange.send()
    }
}
