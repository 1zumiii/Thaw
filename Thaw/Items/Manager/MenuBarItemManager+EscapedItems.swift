//
//  MenuBarItemManager+EscapedItems.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel

extension MenuBarItemManager {
    /// A fresh, seated item that the current restriction says is concealed
    /// needs re-adoption, not another layout assignment or synthetic drag.
    static func escapedConcealedItems(
        in items: [MenuBarItem],
        concealedIdentifiers: Set<String>,
        drawnOwners: Set<pid_t>
    ) -> [MenuBarItem] {
        let intentionallyVisibleOwners = Set(items.filter {
            !concealedIdentifiers.contains(MenuBarItemTag.canonicalPersistentIdentifier($0.uniqueIdentifier))
        }.map { $0.sourcePID ?? $0.ownerPID })
        return items.filter { item in
            !item.isControlItem && !item.tag.isSystemItem
                && concealedIdentifiers.contains(MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier))
                && drawnOwners.contains(item.sourcePID ?? item.ownerPID)
                && !intentionallyVisibleOwners.contains(item.sourcePID ?? item.ownerPID)
        }
    }

    @MainActor
    func reapplyEscapedConcealment() async {
        guard !Task.isCancelled, let appState, !appState.imageCache.isConcealedPrewarmRunning else { return }
        let controller = appState.menuBarManager.sectionController
        guard controller.isOperational, controller.revealedSection == nil,
              await !(menuOpenMonitor.isAnyMenuOpen()) else { return }
        guard let entries = await MenuBarItemAXProvider.drawnBarConcurrent() else { return }
        let screens = NSScreen.screens.map(\.cgFrame)
        let drawnOwners = Set(entries.filter {
            MenuBarItemGeometry.barScreen(holding: $0.frame, among: screens) != nil
        }.map(\.ownerPID))
        // Intentional per-item reveals are excluded by the controller's effective set.
        let escaped = Self.escapedConcealedItems(
            in: managedItems,
            concealedIdentifiers: controller.effectivelyConcealedIdentifiers,
            drawnOwners: drawnOwners
        )
        guard !escaped.isEmpty else { return }
        Self.diagLog.info("Reapplying concealment for exposed items: \(escaped.map(\.uniqueIdentifier))")
        controller.refresh(forceRestrictionPulse: false, forceReapply: true)
    }
}
