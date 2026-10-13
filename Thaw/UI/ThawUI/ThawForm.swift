//
//  ThawForm.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

struct ThawForm<Content: View>: View {
    /// How the form's content is measured against the detail pane's width.
    enum ReadingWidth {
        /// Width beyond SettingsDetailLayout.columnMaxWidth becomes symmetric
        /// gutters.
        case column
        /// The pane's full width, for inherently wide content such as the
        /// layout editor's drag rows.
        case full

        /// Quantize the gutter without storing geometry in view state.
        func gutter(for width: CGFloat) -> CGFloat {
            guard self == .column else { return 0 }
            let overflow = width - (SettingsDetailLayout.titleHorizontalInset * 2)
                - SettingsDetailLayout.columnMaxWidth
            return max(0, (overflow / 16).rounded(.down) * 8)
        }
    }

    @Environment(\.settingsPaneTitle) private var settingsPaneTitle

    private let readingWidth: ReadingWidth
    private let content: Content

    init(readingWidth: ReadingWidth = .column, @ViewBuilder content: () -> Content) {
        self.readingWidth = readingWidth
        self.content = content()
    }

    var body: some View {
        // The Form scrolls full-width so the scrollbar tracks the window edge;
        // reading width comes from gutters, not a narrower scroll view.
        VStack(alignment: .leading, spacing: 0) {
            if let settingsPaneTitle {
                // Settings passes nil and draws its own header; this is for
                // hosts like the What's New window.
                Text(settingsPaneTitle)
                    .font(ThawType.display)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, SettingsDetailLayout.titleTopInset)
                    .padding(.horizontal, SettingsDetailLayout.titleHorizontalInset)
                    .padding(.bottom, 12)
            }

            // The viewport supplies its width in the same layout pass. A
            // background preference followed by a State write scheduled an
            // extra view update even when the gutter stayed unchanged.
            GeometryReader { proxy in
                Form {
                    content
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .scrollEdgeEffectHidden()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentMargins(.horizontal, readingWidth.gutter(for: proxy.size.width), for: .scrollContent)
                .contentMargins(.vertical, 8, for: .scrollContent)
            }
        }
        .focusSection()
        .accessibilityElement(children: .contain)
    }
}
