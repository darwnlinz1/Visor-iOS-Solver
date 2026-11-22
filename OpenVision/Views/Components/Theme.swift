// OpenVision - Theme.swift
// App-wide visual theme and design tokens (PLAN.md §4.5, T6.1): emerald-on-black assistant aesthetic.

import SwiftUI

enum Theme {
    // MARK: - Core accent (emerald)

    static let accent = Color(red: 0.16, green: 0.85, blue: 0.47)        // ~#29D978
    static let accentBright = Color(red: 0.45, green: 0.96, blue: 0.58)  // ~#73F594
    static let accentDeep = Color(red: 0.04, green: 0.55, blue: 0.30)    // ~#0A8C4D
    static let accentMuted = Color(red: 0.16, green: 0.85, blue: 0.47).opacity(0.16)
    static let glow = Color(red: 0.22, green: 0.95, blue: 0.52)

    // MARK: - Backgrounds & Surfaces

    static let bg = Color(red: 0.02, green: 0.03, blue: 0.025)
    static let bgElevated = Color(red: 0.07, green: 0.09, blue: 0.08)
    static let bgCard = Color(red: 0.08, green: 0.105, blue: 0.09)
    static let bgCardHighlight = Color(red: 0.08, green: 0.20, blue: 0.13)
    static let bgElevatedStroke = Color.white.opacity(0.09)
    static let glass = Color.white.opacity(0.05)

    // MARK: - Text

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.42)
    static let heading = Color(red: 0.62, green: 0.98, blue: 0.66)

    // MARK: - Gradients

    static var buttonGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.34, green: 0.96, blue: 0.58), Color(red: 0.10, green: 0.78, blue: 0.42)],
            startPoint: .top, endPoint: .bottom
        )
    }

    static var ringGradient: AngularGradient {
        AngularGradient(
            colors: [accentBright, accent, accentDeep, accent, accentBright],
            center: .center
        )
    }

    static var loopGradient: LinearGradient {
        LinearGradient(
            colors: [accentBright, glow, accent.opacity(0.35)],
            startPoint: .leading, endPoint: .trailing
        )
    }

    static func glowGradient(_ opacity: Double = 0.9) -> RadialGradient {
        RadialGradient(
            colors: [glow.opacity(opacity), accent.opacity(opacity * 0.35), .clear],
            center: .center, startRadius: 0, endRadius: 220
        )
    }

    // MARK: - Semantic status colors

    static let success = accent
    static let danger = Color(red: 0.96, green: 0.30, blue: 0.30)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let info = Color(red: 0.36, green: 0.76, blue: 0.98)
    static let inactive = Color.white.opacity(0.4)

    // MARK: - Layout Tokens (T6.1)

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let chip: CGFloat = 12
        static let row: CGFloat = 14
        static let card: CGFloat = 18
        static let composer: CGFloat = 24
    }

    enum Typography {
        static let screenTitle: Font = .title2.weight(.bold)
        static let cardTitle: Font = .subheadline.weight(.semibold)
        static let body: Font = .callout
        static let math: Font = .system(.body, design: .rounded)
        static let caption: Font = .caption
        static let badge: Font = .caption2.weight(.semibold)
    }
}
