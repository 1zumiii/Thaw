//
//  ZeroFrameStatusItemTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import CoreGraphics
import Testing
@testable import ThawAXCore

struct ZeroFrameStatusItemTests {
    private let seat = CGRect(x: 1200, y: 0, width: 26, height: 33)

    private func resolve(
        bundle: String? = ZeroFrameStatusItem.bundleID,
        role: String? = kAXMenuBarItemRole,
        reported: CGRect? = .zero,
        childCount: Int = 1,
        entries: [MenuBarAgentWindow.Entry]? = nil
    ) -> CGRect? {
        AXPrimitives.inventoryItemFrame(
            reported,
            bundleIdentifier: bundle,
            role: role,
            childCount: childCount,
            ownerPID: 42,
            maximumHeight: 40,
            hostedEntries: { entries }
        )
    }

    @Test func recoversOnlyTheMatchingOwnersSeat() {
        let other = MenuBarAgentWindow.Entry(ownerPID: 7, frame: CGRect(x: 10, y: 0, width: 20, height: 33))
        #expect(resolve(entries: [other, .init(ownerPID: 42, frame: seat)]) == seat)
    }

    @Test func hiddenItemKeepsItsIdentityWithoutInventingGeometry() {
        #expect(resolve(entries: []) == .zero)
        #expect(resolve(entries: nil) == .zero)
        #expect(resolve(entries: [.init(ownerPID: 7, frame: seat)]) == .zero)
    }

    @Test func neverChoosesBetweenSeveralSeatsForTheSameOwner() {
        #expect(resolve(entries: [.init(ownerPID: 42, frame: seat), .init(ownerPID: 42, frame: seat)]) == .zero)
    }

    @Test func missingFrameAttributeStillRecoversTheProvenStatusItem() {
        #expect(resolve(reported: nil, entries: [.init(ownerPID: 42, frame: seat)]) == seat)
        #expect(resolve(reported: nil) == .zero)
        #expect(resolve(bundle: "com.example.App", reported: nil) == nil)
        #expect(resolve(role: nil, reported: nil) == nil)
    }

    @Test func refusesUnknownAppsAndNonStatusRoots() {
        #expect(resolve(bundle: "com.example.App") == nil)
        #expect(resolve(role: kAXMenuRole) == nil)
        #expect(resolve(childCount: 2) == nil)
        #expect(resolve(childCount: 0) == nil)
    }

    @Test func invalidHostFramesCannotBecomeClickTargets() {
        for frame in [CGRect.zero, CGRect(x: 0, y: 0, width: 300, height: 400), CGRect.infinite] {
            #expect(resolve(entries: [.init(ownerPID: 42, frame: frame)]) == .zero)
        }
    }

    @Test func ordinaryGeometryDoesNotQueryTheHost() {
        let result = AXPrimitives.inventoryItemFrame(
            seat,
            bundleIdentifier: ZeroFrameStatusItem.bundleID,
            role: kAXMenuBarItemRole,
            childCount: 1,
            ownerPID: 42,
            maximumHeight: 40,
            hostedEntries: { Issue.record("Valid geometry must not trigger a host read"); return nil }
        )
        #expect(result == seat)
    }

    @Test func stillRejectsPopovers() {
        #expect(resolve(reported: CGRect(x: 100, y: 33, width: 300, height: 400)) == nil)
    }
}
