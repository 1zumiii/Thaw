//
//  EscapedConcealmentTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
struct EscapedConcealmentTests {
    private func item(_ title: String, pid: pid_t = 123) -> MenuBarItem {
        MenuBarItem(
            tag: .init(namespace: .string("notion.id"), title: title),
            windowID: CGWindowID(pid),
            ownerPID: pid,
            sourcePID: pid,
            // AX retains parked geometry even when the host draws the item.
            bounds: CGRect(x: -1, y: 970, width: 34, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("A concealed owner actually drawn by MenuBarAgent needs re-adoption")
    func exposedNotion() {
        let notion = item("Item-0")
        #expect(MenuBarItemManager.escapedConcealedItems(
            in: [notion], concealedIdentifiers: [notion.uniqueIdentifier], drawnOwners: [123]
        ).map(\.uniqueIdentifier) == [notion.uniqueIdentifier])
        #expect(MenuBarItemManager.escapedConcealedItems(
            in: [notion], concealedIdentifiers: [notion.uniqueIdentifier], drawnOwners: []
        ).isEmpty)
    }

    @Test("Intentional temporary reveals and a visible sibling are left alone")
    func intentionalVisibility() {
        let hidden = item("Hidden")
        let visible = item("Visible")
        #expect(MenuBarItemManager.escapedConcealedItems(
            in: [hidden], concealedIdentifiers: [], drawnOwners: [123]
        ).isEmpty)
        #expect(MenuBarItemManager.escapedConcealedItems(
            in: [hidden, visible], concealedIdentifiers: [hidden.uniqueIdentifier], drawnOwners: [123]
        ).isEmpty)
    }
}
