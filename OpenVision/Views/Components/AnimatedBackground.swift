// OpenVision - AnimatedBackground.swift
// Calm emerald ambient gradient background (ParticleEffect timer leak removed per PLAN.md N16, T6.1).

import SwiftUI

/// Animated gradient background for the app
struct AnimatedBackground: View {
    @State private var animateGradient = false

    var body: some View {
        ZStack {
            Theme.bg

            GeometryReader { geometry in
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Theme.accent.opacity(0.22), Theme.accentDeep.opacity(0.10), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geometry.size.width * 0.55
                            )
                        )
                        .frame(width: geometry.size.width * 1.2)
                        .offset(
                            x: animateGradient ? geometry.size.width * 0.05 : -geometry.size.width * 0.05,
                            y: animateGradient ? -geometry.size.height * 0.04 : geometry.size.height * 0.02
                        )
                        .blur(radius: 70)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Theme.glow.opacity(0.14), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geometry.size.width * 0.4
                            )
                        )
                        .frame(width: geometry.size.width * 0.8)
                        .offset(x: 0, y: -geometry.size.height * (animateGradient ? 0.34 : 0.30))
                        .blur(radius: 60)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 8)
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
        Text("OpenVision")
            .font(.largeTitle.bold())
            .foregroundColor(.white)
    }
    .preferredColorScheme(.dark)
}
