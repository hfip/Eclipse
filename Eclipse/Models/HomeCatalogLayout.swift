//
//  HomeCatalogLayout.swift
//  Sora
//
//  Per-catalog overrides for home shelf orientation and size.
//  Global orientation/size continue to live in the existing
//  `experimentalHomeCardShape` / `experimentalMediaCardScale` defaults; this
//  store only holds the per-catalog deltas that override the global values.
//

import Foundation
import Combine

/// Per-catalog orientation choice. `.global` defers to the global Card Shape.
enum CatalogOrientationOverride: String, Codable, CaseIterable, Identifiable {
    case global
    case automatic
    case landscape
    case poster

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .global: return "Global"
        case .automatic: return "Automatic"
        case .landscape: return "Landscape"
        case .poster: return "Poster"
        }
    }

    /// The concrete card shape this override maps to, or `nil` to follow the global setting.
    var cardShape: ExperimentalHomeCardShape? {
        switch self {
        case .global: return nil
        case .automatic: return .automatic
        case .landscape: return .landscape
        case .poster: return .poster
        }
    }

    init(cardShape: ExperimentalHomeCardShape) {
        switch cardShape {
        case .automatic: self = .automatic
        case .landscape: self = .landscape
        case .poster: self = .poster
        }
    }
}

/// A single catalog's layout override. Empty fields (`.global` / `nil`) follow the global values.
struct CatalogLayoutOverride: Codable, Equatable {
    var orientation: CatalogOrientationOverride = .global
    /// Absolute card-size scale that replaces the global scale for this catalog. `nil` = follow global.
    var sizeScale: Double? = nil

    var isEmpty: Bool { orientation == .global && sizeScale == nil }

    static let empty = CatalogLayoutOverride()
}

/// Persists per-catalog layout overrides as a JSON dictionary keyed by `catalog.id`.
/// Mirrors the JSON-in-UserDefaults pattern used by the manga catalog managers.
final class HomeCatalogLayoutStore: ObservableObject {
    static let shared = HomeCatalogLayoutStore()

    static let storageKey = "homeCatalogLayoutOverrides"

    /// Allowed per-catalog (and global) size-scale range. Kept in sync with
    /// `ExperimentalVisualTuning.sanitizedMediaCardScale`.
    static let sizeRange: ClosedRange<Double> = 0.75...1.35

    @Published private var overrides: [String: CatalogLayoutOverride]

    private let userDefaults: UserDefaults

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.overrides = Self.load(from: userDefaults)
    }

    // MARK: - Reads

    func override(for id: String) -> CatalogLayoutOverride {
        overrides[id] ?? .empty
    }

    func hasOverride(for id: String) -> Bool {
        guard let value = overrides[id] else { return false }
        return !value.isEmpty
    }

    // MARK: - Writes

    func setOrientation(_ orientation: CatalogOrientationOverride, for id: String) {
        var value = override(for: id)
        value.orientation = orientation
        store(value, for: id)
    }

    func setSizeScale(_ scale: Double?, for id: String) {
        var value = override(for: id)
        if let scale {
            value.sizeScale = min(max(scale, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        } else {
            value.sizeScale = nil
        }
        store(value, for: id)
    }

    func reset(id: String) {
        guard overrides[id] != nil else { return }
        overrides.removeValue(forKey: id)
        persist()
    }

    func resetAll() {
        guard !overrides.isEmpty else { return }
        overrides.removeAll()
        persist()
    }

    /// Re-reads overrides from persistent storage. Call after a backup restore writes the
    /// underlying UserDefaults key directly.
    func reloadFromStorage() {
        let loaded = Self.load(from: userDefaults)
        if Thread.isMainThread {
            overrides = loaded
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.overrides = loaded
            }
        }
    }

    // MARK: - Storage

    private func store(_ value: CatalogLayoutOverride, for id: String) {
        if value.isEmpty {
            overrides.removeValue(forKey: id)
        } else {
            overrides[id] = value
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(overrides) {
            userDefaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func load(from userDefaults: UserDefaults) -> [String: CatalogLayoutOverride] {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: CatalogLayoutOverride].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
