//
//  PassivePreviewTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Synchronization
import Testing
@testable import Thaw
import ThawAXCore

@MainActor
@Suite("Passive previews reuse cached glyphs")
struct PassivePreviewTests {
    @Test("Opening a preview preserves cached images and failed reads without starting capture", arguments: [true, false])
    func openingDoesNotCapture(onlyMissing: Bool) async throws {
        let probes = Mutex(0)
        let cache = MenuBarItemImageCache(screenIsLocked: {
            probes.withLock { $0 += 1 }
            return true
        })
        // Keep this regression independent of the user's on-disk cache.
        cache.hasLoadedFromDisk = true
        let tag = MenuBarItemTag(namespace: .string("com.example.hidden"), title: "Item-0", instanceIndex: 0)
        let context = try #require(CGContext(
            data: nil,
            width: 24,
            height: 24,
            bitsPerComponent: 8,
            bytesPerRow: 96,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        let image = try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: 1)
        #expect(!MenuBarItemImageCache.shouldCaptureInitialPreview(cachedImage: image, wasAttempted: false))
        #expect(!MenuBarItemImageCache.shouldCaptureInitialPreview(cachedImage: image, wasAttempted: true))
        cache.setCapture(image, for: tag)
        cache.failedCapturesLock.withLock {
            $0[tag] = .init(tag: tag, failureCount: 2, lastFailureTime: .now)
        }

        await cache.prewarmConcealedImages(
            sections: [.hidden, .alwaysHidden],
            onlyMissingImages: onlyMissing
        )

        #expect(probes.withLock { $0 } == 0)
        #expect(cache.capturesByTag[tag] == image)
        #expect(cache.failedCapturesLock.withLock { $0[tag]?.failureCount } == 2)
        #expect(!cache.isConcealedPrewarmRunning)
    }

    @Test("An explicit preview refresh still reaches capture admission")
    func explicitRefreshCanCapture() async {
        let probes = Mutex(0)
        let cache = MenuBarItemImageCache(screenIsLocked: {
            probes.withLock { $0 += 1 }
            // Stop at admission without accessing the real screen or permissions.
            return true
        })
        cache.hasLoadedFromDisk = true

        await cache.prewarmConcealedImages(
            sections: [.hidden],
            allowTemporaryReveal: true
        )

        #expect(probes.withLock { $0 } == 1)
    }

    @Test("A missing preview is attempted only once, even after a failed capture")
    func firstCaptureOnly() {
        #expect(MenuBarItemImageCache.shouldCaptureInitialPreview(cachedImage: nil, wasAttempted: false))
        #expect(!MenuBarItemImageCache.shouldCaptureInitialPreview(cachedImage: nil, wasAttempted: true))
    }

    @Test("Stable stale AX frames do not prove that a revealed icon is drawable")
    func hostMustDrawTheSameOwnerAtTheSamePosition() {
        let bounds = CGRect(x: 900, y: 4.5, width: 24, height: 24)
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.hidden"), title: "Item-0", instanceIndex: 0),
            windowID: 1, ownerPID: 42, sourcePID: 43, bounds: bounds, title: "Item-0", isOnScreen: true
        )
        #expect(!MenuBarItemImageCache.isSeatedForPreview(item, drawn: nil))
        #expect(!MenuBarItemImageCache.isSeatedForPreview(item, drawn: []))
        #expect(!MenuBarItemImageCache.isSeatedForPreview(item, drawn: [.init(ownerPID: 42, frame: bounds)]))
        #expect(!MenuBarItemImageCache.isSeatedForPreview(item, drawn: [
            .init(ownerPID: 43, frame: bounds.offsetBy(dx: 40, dy: 0)),
        ]))
        #expect(MenuBarItemImageCache.isSeatedForPreview(item, drawn: [
            .init(ownerPID: 43, frame: CGRect(x: 900, y: 0, width: 24, height: 33)),
        ]))
    }
}
