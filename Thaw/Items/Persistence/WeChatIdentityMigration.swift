//
//  WeChatIdentityMigration.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Runs before the runtime loads snapshots, so old unread-count aliases
/// cannot reintroduce extra items beside the newly canonical live item.
@MainActor
enum WeChatIdentityMigration {
    private nonisolated static let prefix = "com.tencent.xinWeChat:"

    private nonisolated static func key(_ identifier: String) -> String {
        identifier.hasPrefix(prefix) ? MenuBarItemTag.canonicalPersistentIdentifier(identifier) : identifier
    }

    static func apply(to defaults: UserDefaults = .standard) {
        let knownKey = "MenuBarItemManager.knownItemIdentifiers"
        if let known = defaults.stringArray(forKey: knownKey) {
            var seen = Set<String>()
            defaults.set(known.map(key).filter { seen.insert($0).inserted }, forKey: knownKey)
        }
        migrateOrder(in: defaults)
        let bundleKey = "MenuBarConcealBundleIDMap"
        if let bundles = defaults.dictionary(forKey: bundleKey) as? [String: String] {
            let canonical = bundles.reduce(into: [String: String]()) { result, pair in
                result[key(pair.key)] = pair.value
            }
            if canonical != bundles {
                defaults.set(canonical, forKey: bundleKey)
            }
        }
        migrateSnapshots(in: defaults)
    }

    private static func migrateOrder(in defaults: UserDefaults) {
        let storageKey = "MenuBarItemManager.savedSectionOrder"
        guard var order = defaults.dictionary(forKey: storageKey) as? [String: [String]] else { return }
        var seen = Set<String>()
        // Preserve the most concealed placement if aliases disagree.
        for section in ["alwaysHidden", "hidden", "visible"] {
            order[section] = order[section]?.compactMap { identifier in
                guard identifier.hasPrefix(prefix) else { return identifier }
                let canonical = key(identifier)
                return seen.insert(canonical).inserted ? canonical : nil
            }
        }
        defaults.set(order, forKey: storageKey)
    }

    private static func migrateSnapshots(in defaults: UserDefaults) {
        let storageKey = "MenuBarConcealSnapshots"
        guard let data = defaults.data(forKey: storageKey),
              let snapshots = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else { return }
        var migrated = [String: [String: Any]]()
        // Prefer an already migrated entry, then a named live snapshot over
        // an old unnamed fallback. The order must not depend on Dictionary iteration.
        let keys = snapshots.keys.sorted {
            func rank(_ value: String) -> Int {
                if value == key(value) {
                    return 0
                }
                return value.hasSuffix(":Item-0") ? 2 : 1
            }
            return rank($0) == rank($1) ? $0 < $1 : rank($0) < rank($1)
        }
        for identifier in keys {
            let canonical = key(identifier)
            guard migrated[canonical] == nil, var snapshot = snapshots[identifier] else { continue }
            if identifier.hasPrefix(prefix), var tag = snapshot["tag"] as? [String: Any] {
                tag["title"] = MenuBarItemTag.volatileTitlePlaceholder
                snapshot["tag"] = tag
            }
            migrated[canonical] = snapshot
        }
        guard let encoded = try? JSONSerialization.data(withJSONObject: migrated, options: [.sortedKeys]),
              encoded != data
        else { return }
        defaults.set(encoded, forKey: storageKey)
    }
}
