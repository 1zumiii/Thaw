//
//  TemporaryRevealLeases.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Who holds a temporarily revealed item, so one caller's conceal cannot cut
/// short another's reveal.
///
/// Glyph capture, clicks, alert reveals and app triggers reveal the same item
/// by the same identifier. Without ownership, a capture finishing conceals an
/// item the user just clicked open, and a failed click conceals an item a
/// capture is photographing.
///
/// Every reveal is still forwarded and every conceal still issued, so the
/// calls stay paired whatever the section controller does with them. Only the
/// timing changes: a conceal waits until no other holder remains and no
/// interval show is running.
public struct TemporaryRevealLeases: Sendable {
    /// What the caller must do with a released hold.
    public enum Release: Equatable, Sendable {
        /// Issue this many conceals now: the item is free.
        case conceal(count: Int)
        /// Others still hold the item; the conceal is kept for later. A
        /// deadline means an interval show ends then: settle again at that time.
        case deferred(until: ContinuousClock.Instant?)
    }

    private var holds: [String: Int] = [:]
    private var shownUntil: [String: ContinuousClock.Instant] = [:]
    private var pendingConceals: [String: Int] = [:]

    public init() {}

    /// Records a hold on identifier. The caller reveals the item as before.
    public mutating func hold(_ identifier: String) {
        holds[identifier, default: 0] += 1
    }

    /// Records that identifier is shown until deadline by an interval show,
    /// whose own scheduled conceal the section controller issues.
    public mutating func show(_ identifier: String, until deadline: ContinuousClock.Instant) {
        shownUntil[identifier] = max(shownUntil[identifier] ?? deadline, deadline)
    }

    /// Releases one hold on identifier.
    public mutating func release(
        _ identifier: String,
        now: ContinuousClock.Instant = .now
    ) -> Release {
        if let count = holds[identifier] {
            holds[identifier] = count > 1 ? count - 1 : nil
        }
        pendingConceals[identifier, default: 0] += 1
        return settle(identifier, now: now)
    }

    /// Re-checks identifier after an interval show's deadline.
    public mutating func settle(
        _ identifier: String,
        now: ContinuousClock.Instant = .now
    ) -> Release {
        guard let pending = pendingConceals[identifier], pending > 0 else {
            return .conceal(count: 0)
        }
        if holds[identifier] != nil {
            return .deferred(until: nil)
        }
        if let deadline = shownUntil[identifier] {
            guard deadline <= now else { return .deferred(until: deadline) }
            shownUntil[identifier] = nil
        }
        pendingConceals[identifier] = nil
        return .conceal(count: pending)
    }

    /// Whether anyone holds identifier or shows it for an interval.
    public func isHeld(_ identifier: String, now: ContinuousClock.Instant = .now) -> Bool {
        holds[identifier] != nil || (shownUntil[identifier].map { $0 > now } ?? false)
    }
}
