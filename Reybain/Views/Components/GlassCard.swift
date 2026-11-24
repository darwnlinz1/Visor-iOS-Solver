// Reybain - GlassCard.swift
// Backward-compatible GlassCard and StatusPill backed by iOS 26 LiquidGlass primitives.

import SwiftUI

/// A glassmorphic card delegating to `LiquidGlassCard` with continuous squircle geometry.
struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = Theme.Radius.card
    var opacity: CGFloat = 0.15
    var blurRadius: CGFloat = 10

    init(
        cornerRadius: CGFloat = Theme.Radius.card,
        opacity: CGFloat = 0.15,
        blurRadius: CGFloat = 10,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.blurRadius = blurRadius
    }

    var body: some View {
        LiquidGlassCard(cornerRadius: cornerRadius, style: .chrome) {
            content
        }
    }
}

/// Status pill showing connection state inside a Liquid Glass capsule.
struct StatusPill: View {
    let status: String
    let color: Color
    let isConnected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7.5, height: 7.5)
                .overlay {
                    if isConnected && !reduceMotion {
                        Circle()
                            .stroke(color.opacity(0.55), lineWidth: 1.5)
                            .scaleEffect(1.6)
                            .opacity(0.35)
                    }
                }

            Text(status)
                .font(.caption.weight(.medium))
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .liquidGlassPill(tint: isConnected ? color : nil)
    }
}

#Preview {
    ZStack {
        Theme.bg.ignoresSafeArea()
        VStack(spacing: 24) {
            StatusPill(status: "Gemini", color: Theme.success, isConnected: true)
            GlassCard {
                VStack(spacing: 10) {
                    Text("Reybain Liquid Glass")
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Text("Obsidian frosted glass surface")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
                .padding()
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
