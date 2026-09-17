//
//  DesignTokens.swift
//  BRB
//
//  Single source of truth for native-feeling layout values.
//  Settings tabs share these; Onboarding intentionally stays roomier
//  (see DS.wizardOuterPad); Veil is fullscreen and only shares
//  button metrics via DS.Veil.
//

import SwiftUI

enum DS {
    // MARK: - Spacing scale
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 20

    // MARK: - Padding
    /// Standard outer padding for all settings tabs.
    static let outerPad: CGFloat = 20
    /// Roomier outer padding for the onboarding wizard (intentional).
    static let wizardOuterPad: CGFloat = 24
    /// Roomier outer spacing for the onboarding wizard (intentional).
    static let wizardSpacing: CGFloat = 24
    /// Standard inner card padding.
    static let cardPad: CGFloat = 14
    /// Compact inner padding (nested rows, banners).
    static let compactPad: CGFloat = 10
    /// Banner padding.
    static let bannerPad: CGFloat = 8

    // MARK: - Radius (native)
    static let radius: CGFloat = 8

    // MARK: - Backgrounds
    static var cardBg: Color {
        // Single card background; emphasis variant below for hero status cards.
        Color.secondary.opacity(0.06)
    }

    static func emphasisBg() -> Color {
        Color.secondary.opacity(0.08)
    }

    // MARK: - Window
    static let windowWidth: CGFloat = 640
    static let windowHeight: CGFloat = 520
    /// Industry-standard control center maximum dimensions (prevents awkward stretching on wide displays).
    static let windowMaxWidth: CGFloat = 960
    static let windowMaxHeight: CGFloat = 760

    // MARK: - Device cards (Nearby grid)
    static let deviceArtSize: CGFloat = 64
    static let deviceGridSpacing: CGFloat = 12

    // MARK: - Veil (fullscreen exception: dark aesthetic stays,
    // only internal button metrics are normalised)
    enum Veil {
        static let btnHPad: CGFloat = 22
        static let btnVPad: CGFloat = 10
        static let helpSize: CGFloat = 12
    }
}

/// Single native banner used for all status/notice rows.
/// Replaces ad-hoc purple/orange/blue/green pills and banners.
struct DSBanner: View {
    var icon: String
    var text: String
    var tint: Color

    init(icon: String, text: String, tint: Color) {
        self.icon = icon
        self.text = text
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: DS.spacingSM) {
            Image(systemName: icon)
                .foregroundColor(tint)
            Text(text)
                .font(.caption.bold())
                .foregroundColor(.secondary)
        }
        .padding(DS.bannerPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1))
        .cornerRadius(DS.radius)
    }
}

/// Single pill badge for compact inline status (e.g. Pinned, Suppression).
struct DSPill: View {
    var text: String
    var tint: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15))
            .foregroundColor(tint)
            .clipShape(Capsule())
    }
}
