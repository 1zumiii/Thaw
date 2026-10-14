//
//  MenuBarItemImageCache+InitialPreviews.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel

extension MenuBarItemImageCache {
    /// Retry transient misses while the same reveal is held. Cancellation or
    /// a layout change does not consume an item's one initial capture session.
    @MainActor
    func captureInitialPreviewBatch(
        _ batch: [MenuBarItem],
        displayID: CGDirectDisplayID,
        admittedDisplayID: CGDirectDisplayID?,
        scale: CGFloat,
        missPolicy: RevealMissPolicy,
        appState: AppState,
        sources: RevealCaptureSources
    ) async -> Bool {
        var pending = batch
        for _ in 0 ..< 3 {
            let revealed = await sources.settledItems(pending)
            guard !Task.isCancelled, !skipCaptureWhileScreenLocked("capture reveal completed") else { return false }
            if !revealed.isEmpty {
                await sources.renderSettle()
                guard !Task.isCancelled, !skipCaptureWhileScreenLocked("settled capture batch") else { return false }

                // A restriction rebuild moves the generation during reveal.
                // Admit after settling; later moves still reject the screenshot.
                let admission = CapturePublicationPolicy.admit(
                    layout: appState.itemManager.layoutPublication,
                    displayID: admittedDisplayID
                )
                guard publicationRejection(
                    of: admission, appState: appState, ignoreRecentMove: true, isRecapturePass: false
                ) == nil else { return false }

                let result = await axBoundsCapture(
                    revealed.map { (item: $0.live, bounds: $0.live.bounds) },
                    scale: scale,
                    displayID: displayID,
                    validateFreshBounds: true,
                    concealedIdentifiers: [],
                    using: sources.reader
                )
                guard commitRevealedBatch(
                    result,
                    revealed: revealed,
                    admission: admission,
                    missPolicy: missPolicy,
                    appState: appState
                ) else { return false }
            }
            guard !Task.isCancelled, !skipCaptureWhileScreenLocked("completed capture attempt") else { return false }
            pending = pending.filter { item in
                guard let capture = image(for: item.tag) else { return true }
                return !Self.isTrustedGlyph(capture)
            }
            if pending.isEmpty {
                break
            }
        }

        initialPreviewCaptureAttempts.formUnion(batch.map(\.tag.tagIdentifier))
        exhaustedInitialPreviews.subtract(batch.map(\.tag.tagIdentifier))
        if !pending.isEmpty {
            exhaustedInitialPreviews.formUnion(pending.map(\.tag.tagIdentifier))
            Self.diagLog.warning("Initial preview capture exhausted: \(pending.map(\.uniqueIdentifier))")
        }
        return true
    }

    /// Lets items whose initial capture was exhausted try one more session,
    /// after a change that can explain the miss (a display change, a
    /// screen-recording grant).
    ///
    /// Each item gets this once per run, so an item that can never be
    /// captured does not reveal again on every change. Items that captured
    /// successfully are never touched.
    @MainActor
    func retryExhaustedInitialPreviews(reason: String) {
        let eligible = exhaustedInitialPreviews.subtracting(retriedInitialPreviews)
        guard !eligible.isEmpty else { return }
        initialPreviewCaptureAttempts.subtract(eligible)
        exhaustedInitialPreviews.subtract(eligible)
        retriedInitialPreviews.formUnion(eligible)
        Self.diagLog.info("Allowing one more initial capture for \(eligible.sorted()) (\(reason))")
    }
}
