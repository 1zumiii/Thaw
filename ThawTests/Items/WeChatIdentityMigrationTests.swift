//
//  WeChatIdentityMigrationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
struct WeChatIdentityMigrationTests {
    @Test("Unread-count aliases merge before snapshots load, preserving the most concealed placement")
    func migratesAliases() throws {
        let suite = "WeChatMigration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let count = "com.tencent.xinWeChat: 2"
        let unnamed = "com.tencent.xinWeChat:Item-0"
        let canonical = "com.tencent.xinWeChat:Item"
        defaults.set([count, unnamed, "notion.id:Item-0"], forKey: "MenuBarItemManager.knownItemIdentifiers")
        defaults.set([
            "alwaysHidden": [count], "hidden": [unnamed, "notion.id:Item-0"],
        ], forKey: "MenuBarItemManager.savedSectionOrder")
        defaults.set([count: "com.tencent.xinWeChat", unnamed: "com.tencent.xinWeChat"], forKey: "MenuBarConcealBundleIDMap")
        let snapshots: [String: [String: Any]] = [
            count: ["tag": ["title": " 2", "instanceIndex": 0], "windowID": 22],
            unnamed: ["tag": ["title": "Item-0", "instanceIndex": 0], "windowID": 11],
            "notion.id:Item-0": ["title": "Item-0", "windowID": 33],
        ]
        try defaults.set(JSONSerialization.data(withJSONObject: snapshots), forKey: "MenuBarConcealSnapshots")

        WeChatIdentityMigration.apply(to: defaults)

        #expect(defaults.stringArray(forKey: "MenuBarItemManager.knownItemIdentifiers") == [canonical, "notion.id:Item-0"])
        let order = try #require(defaults.dictionary(forKey: "MenuBarItemManager.savedSectionOrder") as? [String: [String]])
        #expect(order["alwaysHidden"] == [canonical])
        #expect(order["hidden"] == ["notion.id:Item-0"])
        let snapshotData = try #require(defaults.data(forKey: "MenuBarConcealSnapshots"))
        let migrated = try #require(JSONSerialization.jsonObject(with: snapshotData) as? [String: [String: Any]])
        #expect(migrated.count == 2)
        #expect(migrated[canonical]?["windowID"] as? Int == 22)
        #expect((migrated[canonical]?["tag"] as? [String: Any])?["title"] as? String == "Item")
        #expect(migrated["notion.id:Item-0"]?["windowID"] as? Int == 33)
        let first = defaults.data(forKey: "MenuBarConcealSnapshots")
        WeChatIdentityMigration.apply(to: defaults)
        #expect(defaults.data(forKey: "MenuBarConcealSnapshots") == first)
    }
}
