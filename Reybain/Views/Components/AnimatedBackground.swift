// Reybain - AnimatedBackground.swift
// Calibrated OLED obsidian (#05060A) canvas with subtle Apple Intelligence indigo/cyan aurora.

import SwiftUI

/// Ambient OLED obsidian background with gentle indigo/cyan light clouds (Reduce Motion safe).
struct AnimatedBackground: View {
    @State private var animateGradient = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.bg

            GeometryReader { geometry in
                let w = geometry.size.width
                let h = geometry.size.height

                ZStack {
                    // 1. Top-leading midnight indigo-violet aurora cloud
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Theme.iridescentIndigo.opacity(0.16),
                                    Theme.iridescentViolet.opacity(0.06),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: w * 0.65
                            )
                        )
                        .frame(width: w * 1.25, height: w * 1.25)
                        .offset(
                            x: animateGradient ? -w * 0.14 : -w * 0.24,
                            y: animateGradient ? -h * 0.34 : -h * 0.28
                        )
                        .blur(radius: 80)

                    // 2. Top-trailing optical cyan cloud so floating glass chrome catches subtle refraction
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Theme.iridescentCyan.opacity(0.12),
                                    Theme.iridescentIndigo.opacity(0.04),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: w * 0.48
                            )
                        )
                        .frame(width: w * 0.92, height: w * 0.92)
                        .offset(
                            x: animateGradient ? w * 0.28 : w * 0.20,
                            y: animateGradient ? -h * 0.36 : -h * 0.30
                        )
                        .blur(radius: 72)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 10)
                .repeatForever(autoreverses: true)
            ) {
                animateGradient = true
            }
        }
    }
}

#Preview {
    ZStack {
        AnimatedBackground()
        Text("Reybain")
            .font(Theme.Typography.heroTitle)
            .foregroundStyle(Theme.intelligenceLinear)
    }
    .preferredColorScheme(.dark)
}
