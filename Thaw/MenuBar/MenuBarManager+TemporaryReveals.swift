//
//  MenuBarManager+TemporaryReveals.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Every temporary reveal goes through here, so a caller conceals only its
/// own reveal. See TemporaryRevealLeases.
extension MenuBarManager {
    /// Reveals identifier until the matching releaseTemporaryReveal(_:on:).
    ///
    /// - Parameter controller: The controller to reveal through; nil for the
    ///   live one. Callers handed a controller pass it on.
    func holdTemporaryReveal(_ identifier: String, on controller: (any MenuBarSectionControlling)? = nil) {
        temporaryRevealLeases.hold(Self.leaseKey(identifier))
        (controller ?? sectionController).revealItemTemporarily(identifier)
    }

    /// Ends one hold. The item is concealed once no other caller holds it and
    /// no interval show is still running.
    func releaseTemporaryReveal(_ identifier: String, on controller: (any MenuBarSectionControlling)? = nil) {
        let key = Self.leaseKey(identifier)
        apply(temporaryRevealLeases.release(key), to: identifier, key: key, controller: controller ?? sectionController)
    }

    /// Reveals identifier for the temporary-show interval.
    func showTemporarily(_ identifier: String, on controller: (any MenuBarSectionControlling)? = nil) {
        let controller = controller ?? sectionController
        let interval = appState?.settings.general.tempShowInterval ?? Defaults.DefaultValue.tempShowInterval
        temporaryRevealLeases.show(Self.leaseKey(identifier), until: .now + .seconds(interval))
        controller.revealItemTemporarily(identifier)
        controller.scheduleTemporaryItemConceal(identifier)
    }

    private func apply(
        _ release: TemporaryRevealLeases.Release,
        to identifier: String,
        key: String,
        controller: any MenuBarSectionControlling
    ) {
        switch release {
        case let .conceal(count):
            for _ in 0 ..< count {
                controller.concealTemporarilyRevealedItem(identifier)
            }
        case .deferred(until: nil):
            // The last holder's release settles it.
            break
        case let .deferred(until: deadline?):
            Task { @MainActor [weak self] in
                try? await Task.sleep(until: deadline)
                guard let self else { return }
                apply(temporaryRevealLeases.settle(key), to: identifier, key: key, controller: controller)
            }
        }
    }

    private static func leaseKey(_ identifier: String) -> String {
        MenuBarItemTag.canonicalPersistentIdentifier(identifier)
    }
}
