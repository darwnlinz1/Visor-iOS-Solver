// Reybain - Theme.swift
// iOS 26 Liquid Glass & Apple Intelligence OLED design tokens (iOS 17–26 safe).

import SwiftUI

enum Theme {
    // MARK: - Core Brand & Apple Intelligence Iridescent Accents

    static let accent = Color(red: 0.220, green: 0.741, blue: 0.973)            // #38BDF8 Optical Cyan
    static let accentBright = Color(red: 0.490, green: 0.827, blue: 0.988)      // #7DD3FC Prism Ice
    static let accentDeep = Color(red: 0.310, green: 0.275, blue: 0.898)        // #4F46E5 Electric Indigo
    static let accentMuted = Color(red: 0.220, green: 0.741, blue: 0.973).opacity(0.15)
    static let glow = Color(red: 0.388, green: 0.400, blue: 0.945)              // #6366F1 Ambient Indigo

    static let iridescentCyan = Color(red: 0.220, green: 0.851, blue: 1.000)    // #38D9FF
    static let iridescentIndigo = Color(red: 0.388, green: 0.400, blue: 0.945)  // #6366F1
    static let iridescentViolet = Color(red: 0.659, green: 0.333, blue: 0.969)  // #A855F7
    static let iridescentMagenta = Color(red: 0.925, green: 0.282, blue: 0.600) // #EC4899

    /// Ordered spectrum for Apple Intelligence borders, SwirlOrb, and live audio waveforms.
    static let intelligenceColors: [Color] = [
        iridescentCyan,
        iridescentIndigo,
        iridescentViolet,
        iridescentMagenta,
        iridescentIndigo,
        iridescentCyan
    ]

    // MARK: - OLED Obsidian Backgrounds & Elevation Tiers

    static let bg = Color(red: 0.020, green: 0.024, blue: 0.039)                // #05060A OLED Obsidian
    static let bgSurface = Color(red: 0.039, green: 0.051, blue: 0.086)         // #0A0D16 Tier 1
    static let bgCard = Color(red: 0.055, green: 0.071, blue: 0.114)            // #0E121D Tier 2 Editorial Card
    static let bgElevated = Color(red: 0.078, green: 0.098, blue: 0.157)        // #141928 Tier 3 Elevated Surface
    static let bgCardHighlight = Color(red: 0.086, green: 0.133, blue: 0.235)   // #16223C Active Selection Tint
    static let bgElevatedStroke = Color.white.opacity(0.10)
    static let glass = Color(red: 0.071, green: 0.090, blue: 0.149).opacity(0.58)
    static let glassFill = glass
    static let glassHighlight = Color.white.opacity(0.08)

    // MARK: - Specular Rim Colors (Liquid Glass Edge Catchlights)

    static let specularTop = Color.white.opacity(0.28)
    static let specularMid = Color(red: 0.62, green: 0.77, blue: 1.00).opacity(0.12)
    static let specularBottom = Color.white.opacity(0.04)
    static let glassSpecularTop = specularTop
    static let glassSpecularMid = specularMid

    // MARK: - Typography Ink (WCAG AA/AAA on Obsidian)

    static let textPrimary = Color(red: 0.961, green: 0.969, blue: 0.980)       // #F5F7FA
    static let textSecondary = Color(red: 0.639, green: 0.682, blue: 0.761)     // #A3AEC2
    static let textTertiary = Color(red: 0.494, green: 0.541, blue: 0.639)      // #7E8AA3
    static let heading = Color(red: 0.796, green: 0.902, blue: 1.000)           // #CBE6FF
    static let ctaForeground = Color.white

    // MARK: - Gradients

    /// Primary interactive CTA fill (pairs with `Theme.ctaForeground` / `.white`).
    static var buttonGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.231, green: 0.435, blue: 0.961), // #3B6FF5 Sapphire
                Color(red: 0.486, green: 0.302, blue: 1.000)  // #7C4DFF Violet
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Subtle user chat bubble fill (elevated sapphire glass, pairs with `Theme.textPrimary`).
    static var userBubbleGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.145, green: 0.220, blue: 0.431).opacity(0.92), // Deep Sapphire
                Color(red: 0.196, green: 0.165, blue: 0.392).opacity(0.92)  // Deep Indigo-Violet
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Liquid Glass specular hairline rim (light catches top-leading glass curvature).
    static var specularRimGradient: LinearGradient {
        LinearGradient(
            colors: [specularTop, specularMid, specularBottom, specularMid.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Horizontal iridescent sheen for waveforms, progress bars, and active accents.
    static var intelligenceLinear: LinearGradient {
        LinearGradient(
            colors: [iridescentCyan, iridescentIndigo, iridescentViolet, iridescentMagenta],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var ringGradient: AngularGradient {
        AngularGradient(
            colors: intelligenceColors,
            center: .center
        )
    }

    static var loopGradient: LinearGradient {
        LinearGradient(
            colors: [iridescentCyan, iridescentIndigo, iridescentViolet, iridescentMagenta.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func glowGradient(_ opacity: Double = 0.85) -> RadialGradient {
        RadialGradient(
            colors: [
                iridescentCyan.opacity(opacity * 0.65),
                iridescentIndigo.opacity(opacity * 0.42),
                iridescentViolet.opacity(opacity * 0.18),
                .clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: 220
        )
    }

    // MARK: - Semantic Status Colors

    static let success = Color(red: 0.204, green: 0.827, blue: 0.600)           // #34D399
    static let danger = Color(red: 0.984, green: 0.443, blue: 0.522)            // #FB7185
    static let warning = Color(red: 0.984, green: 0.749, blue: 0.141)           // #FBBF24
    static let info = Color(red: 0.376, green: 0.647, blue: 0.980)              // #60A5FA
    static let inactive = Color(red: 0.494, green: 0.541, blue: 0.639)          // #7E8AA3

    // MARK: - Layout & Concentricity Tokens

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let badge: CGFloat = 8
        static let chip: CGFloat = 12
        static let row: CGFloat = 14
        static let card: CGFloat = 22
        static let composer: CGFloat = 28
        static let tabDock: CGFloat = 32

        /// Concentric corner radius helper: `max(0, outer - inset)`.
        static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat {
            max(0, outer - inset)
        }
    }

    enum Motion {
        static let snappy = Animation.spring(response: 0.30, dampingFraction: 0.80)
        static let fluid = Animation.spring(response: 0.42, dampingFraction: 0.84)
        static let gentle = Animation.easeInOut(duration: 0.24)
    }

    enum Typography {
        static let heroTitle: Font = .system(size: 32, weight: .bold, design: .rounded)
        static let screenTitle: Font = .system(size: 22, weight: .bold, design: .default)
        static let sectionHeader: Font = .footnote.weight(.semibold)
        static let cardTitle: Font = .subheadline.weight(.semibold)
        static let body: Font = .system(size: 15.5, weight: .regular, design: .default)
        static let math: Font = .system(size: 16, weight: .regular, design: .rounded)
        static let caption: Font = .caption
        static let badge: Font = .caption2.weight(.semibold)
        static let monoMetric: Font = .caption.monospacedDigit().weight(.semibold)
        static let monoLog: Font = .caption2.monospaced()
    }
}
