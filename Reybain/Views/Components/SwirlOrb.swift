// Reybain - SwirlOrb.swift
// Reybain's iridescent Liquid Glass prism rosette with lifelike state-driven breathing.
//
// Motion uses two fixed breathing frequencies (slowFreq / fastFreq) blended per state
// so transitions never jump sine phase:
//   • idle      — gentle slow breathe
//   • listening — contracts & focuses with optical cyan glow
//   • thinking  — steady indigo/violet pulse with subtle working flutter
//   • speaking  — expands with luminous cyan-indigo-violet-magenta bloom

import SwiftUI

struct SwirlOrb: View {
    enum Mode: Equatable { case idle, listening, thinking, speaking }

    var mode: Mode = .idle
    var size: CGFloat = 250

    private let loopCount = 9
    private let slowFreq: Double = 1.2
    private let fastFreq: Double = 3.3

    @State private var baseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
            let rot = t * 0.06
            let breathe = reduceMotion
                ? 1.0
                : (1.0 + sin(t * slowFreq) * ampSlow + sin(t * fastFreq) * ampFast)

            core(rotation: rot)
                .scaleEffect(breathe)
        }
        .scaleEffect(baseScale)
        .overlay(stateGlow)
        .onChange(of: mode) { _, newMode in apply(newMode) }
        .onAppear { apply(mode) }
    }

    // MARK: - State Motion Parameters

    private var ampSlow: Double {
        switch mode {
        case .idle: return 0.020
        case .listening: return 0.008
        case .thinking: return 0.015
        case .speaking: return 0.056
        }
    }

    private var ampFast: Double {
        switch mode {
        case .idle: return 0.0
        case .listening: return 0.0
        case .thinking: return 0.028
        case .speaking: return 0.010
        }
    }

    private func apply(_ m: Mode) {
        withAnimation(.easeInOut(duration: 0.45)) {
            switch m {
            case .idle:
                baseScale = 1.00
                glowOpacity = 0.00
            case .listening:
                baseScale = 0.91
                glowOpacity = 0.40
            case .thinking:
                baseScale = 0.98
                glowOpacity = 0.32
            case .speaking:
                baseScale = 1.08
                glowOpacity = 0.58
            }
        }
    }

    private var stateGlowColor: Color {
        switch mode {
        case .idle: return Theme.iridescentIndigo
        case .listening: return Theme.iridescentCyan
        case .thinking: return Theme.iridescentViolet
        case .speaking: return Theme.iridescentMagenta
        }
    }

    /// Additive iridescent halo tuned per state without washing out the dark obsidian center.
    private var stateGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        stateGlowColor.opacity(0.95),
                        Theme.iridescentIndigo.opacity(0.45),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.56
                )
            )
            .frame(width: size * 1.18, height: size * 1.18)
            .blur(radius: 24)
            .opacity(glowOpacity)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    // MARK: - Prism Torus Core

    @ViewBuilder
    private func core(rotation: Double) -> some View {
        ZStack {
            // Soft iridescent ambient bloom
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.iridescentCyan.opacity(0.32),
                            Theme.iridescentIndigo.opacity(0.22),
                            Theme.iridescentViolet.opacity(0.10),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.60
                    )
                )
                .frame(width: size * 1.22, height: size * 1.22)
                .blur(radius: 28)

            // Deep obsidian-indigo torus core hole
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.iridescentIndigo.opacity(0.24), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.24
                    )
                )
                .frame(width: size * 0.54, height: size * 0.54)
                .blur(radius: 15)

            rosette(spin: rotation).blur(radius: 8).opacity(0.82)
            rosette(spin: rotation)
        }
        .frame(width: size * 1.3, height: size * 1.3)
    }

    @ViewBuilder
    private func rosette(spin: Double) -> some View {
        ZStack {
            ForEach(0..<loopCount, id: \.self) { i in
                let angle = Double(i) / Double(loopCount) * 2 * .pi + spin
                let layerOpacity = i.isMultiple(of: 2) ? 0.95 : 0.72
                Ellipse()
                    .stroke(
                        Theme.loopGradient,
                        style: StrokeStyle(lineWidth: max(1.2, size * 0.013), lineCap: .round)
                    )
                    .opacity(layerOpacity)
                    .frame(width: size * 0.88, height: size * 0.50)
                    .rotationEffect(.radians(angle))
            }
        }
    }
}

/// Compact line-art prism mark for brand headers and badges.
struct SwirlMark: View {
    var size: CGFloat = 28
    var color: Color? = nil

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                if let color {
                    Ellipse()
                        .stroke(color, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                        .frame(width: size * 0.90, height: size * 0.52)
                        .rotationEffect(.degrees(Double(i) * 60))
                } else {
                    Ellipse()
                        .stroke(Theme.loopGradient, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                        .frame(width: size * 0.90, height: size * 0.52)
                        .rotationEffect(.degrees(Double(i) * 60))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    ZStack {
        AnimatedBackground()
        VStack(spacing: 32) {
            SwirlOrb(mode: .speaking, size: 180)
            SwirlMark(size: 36)
        }
    }
    .preferredColorScheme(.dark)
}
