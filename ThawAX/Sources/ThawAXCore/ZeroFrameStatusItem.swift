//
//  ZeroFrameStatusItem.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import CoreGraphics

/// Little Snitch 6.5 can publish a real AXMenuBarItem with no frame attribute or a zero frame.
/// Its MenuBarAgent wrapper still carries geometry while the icon is drawn.
public enum ZeroFrameStatusItem {
    public static let bundleID = "at.obdev.littlesnitch.agent"

    public static func matches(bundleIdentifier: String?, role: String?, frame: CGRect?, childCount: Int) -> Bool {
        bundleIdentifier == bundleID && role == kAXMenuBarItemRole && (frame == nil || frame == .zero) && childCount == 1
    }

    /// No positional guess when an owner has several seats or its seat cannot be read.
    /// Zero retains the proven item in inventory while hidden, without authorizing a coordinate click or drag.
    public static func frame(ownerPID: pid_t, maximumHeight: CGFloat, entries: [MenuBarAgentWindow.Entry]?) -> CGRect {
        let owned = entries?.filter { $0.ownerPID == ownerPID } ?? []
        guard owned.count == 1, let frame = owned.first?.frame,
              frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0, frame.height <= maximumHeight
        else { return .zero }
        return frame
    }
}

public extension AXPrimitives {
    /// Normal AX items retain the usual panel/height filter. Only the verified
    /// single, frameless Little Snitch status item may use its host's bounds.
    static func inventoryItemFrame(
        _ reported: CGRect?,
        bundleIdentifier: String?,
        role: String?,
        childCount: Int,
        ownerPID: pid_t,
        maximumHeight: CGFloat,
        hostedEntries: () -> [MenuBarAgentWindow.Entry]? = { menuBarAgentWindowEntries() }
    ) -> CGRect? {
        if ZeroFrameStatusItem.matches(bundleIdentifier: bundleIdentifier, role: role, frame: reported, childCount: childCount) {
            return ZeroFrameStatusItem.frame(ownerPID: ownerPID, maximumHeight: maximumHeight, entries: hostedEntries())
        }
        guard let reported else { return nil }
        return itemFrame(reported, maximumHeight: maximumHeight)
    }
}
