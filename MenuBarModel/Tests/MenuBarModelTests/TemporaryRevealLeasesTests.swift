//
//  TemporaryRevealLeasesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

/// Capture, clicks and alerts reveal the same item; none may conceal it out
/// from under another.
@Suite("Temporary reveal leases")
struct TemporaryRevealLeasesTests {
    private static let wifi = "menuBarAgent:com.apple.menuextra.wifi"
    private static let start = ContinuousClock.now

    @Test("A lone hold conceals on release")
    func loneHoldConceals() {
        var leases = TemporaryRevealLeases()
        leases.hold(Self.wifi)
        #expect(leases.release(Self.wifi, now: Self.start) == .conceal(count: 1))
        #expect(!leases.isHeld(Self.wifi, now: Self.start))
    }

    @Test("A capture finishing does not conceal an item another caller still holds")
    func overlappingHoldsWaitForTheLast() {
        var leases = TemporaryRevealLeases()
        leases.hold(Self.wifi) // capture
        leases.hold(Self.wifi) // click
        #expect(leases.release(Self.wifi, now: Self.start) == .deferred(until: nil))
        #expect(leases.isHeld(Self.wifi, now: Self.start))
        // The last holder issues both conceals, keeping calls paired.
        #expect(leases.release(Self.wifi, now: Self.start) == .conceal(count: 2))
    }

    @Test("A hold released during an interval show waits for the interval")
    func intervalShowOutlastsHold() {
        var leases = TemporaryRevealLeases()
        let deadline = Self.start + .seconds(5)
        leases.hold(Self.wifi) // capture
        leases.show(Self.wifi, until: deadline) // user clicked the item open
        #expect(leases.release(Self.wifi, now: Self.start + .seconds(1)) == .deferred(until: deadline))
        #expect(leases.settle(Self.wifi, now: deadline) == .conceal(count: 1))
    }

    @Test("Settling with nothing pending conceals nothing")
    func settleWithoutPendingIsNoOp() {
        var leases = TemporaryRevealLeases()
        leases.show(Self.wifi, until: Self.start + .seconds(5))
        #expect(leases.settle(Self.wifi, now: Self.start + .seconds(6)) == .conceal(count: 0))
    }

    @Test("Items are independent")
    func itemsAreIndependent() {
        var leases = TemporaryRevealLeases()
        leases.hold(Self.wifi)
        leases.hold("menuBarAgent:com.apple.menuextra.clock")
        #expect(leases.release(Self.wifi, now: Self.start) == .conceal(count: 1))
    }
}
