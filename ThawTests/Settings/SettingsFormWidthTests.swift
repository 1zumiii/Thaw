//
//  SettingsFormWidthTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

@MainActor
struct SettingsFormWidthTests {
    private typealias Width = ThawForm<EmptyView>.ReadingWidth

    @Test("Narrow panes use all available width", arguments: [0.0, 560, 708, 804, 819])
    func narrowPane(width: Double) {
        #expect(Width.column.gutter(for: width) == 0)
    }

    @Test("Wide panes retain the reading column and symmetric quantized gutters")
    func widePane() {
        for width in stride(from: 820.0, through: 2400, by: 1) {
            let gutter = Width.column.gutter(for: width)
            let column = width - gutter * 2 - SettingsDetailLayout.titleHorizontalInset * 2
            #expect(column >= SettingsDetailLayout.columnMaxWidth)
            #expect(column < SettingsDetailLayout.columnMaxWidth + 16)
            #expect(gutter.truncatingRemainder(dividingBy: 8) == 0)
        }
    }

    @Test("The layout editor keeps its full width", arguments: [560.0, 820, 1018, 2400])
    func fullWidthEditor(width: Double) {
        #expect(Width.full.gutter(for: width) == 0)
    }
}
