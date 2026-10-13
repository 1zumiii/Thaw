//
//  DownstreamUpdatePolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
struct DownstreamUpdatePolicyTests {
    @Test func officialUpdatesRemainDisabled() {
        #expect(!Constants.supportsSparkleUpdates)
        let manager = UpdatesManager()
        manager.automaticallyChecksForUpdates = true
        manager.automaticallyDownloadsUpdates = true
        manager.startUpdaterIfNeeded()
        #expect(!manager.automaticallyChecksForUpdates)
        #expect(!manager.automaticallyDownloadsUpdates)
        #expect(!manager.canCheckForUpdates)
    }

    @Test func bundleIdentifiesTheCustomBuildWithoutAnOfficialFeed() {
        #expect(Constants.versionString.contains("-custom."))
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") == nil)
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool == false)
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool == false)
    }
}
