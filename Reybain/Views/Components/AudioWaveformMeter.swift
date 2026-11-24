// Reybain - AudioWaveformMeter.swift
// Real-time animated waveform meter for Direct-Audio Voice Note recording (iOS 17–26 safe).

import SwiftUI

/// Live scrolling bar visualizer driven by normalized microphone levels (`0.0 ... 1.0`).
struct AudioWaveformMeter: View {
    /// Most-recent normalized RMS levels (`0.0 ... 1.0`). Feed 15–30 Hz samples from the audio recorder.
    let levels: [CGFloat]
    var barCount: Int = 26
    var barWidth: CGFloat = 2.6
    var barSpacing: CGFloat = 2.6
    var minBarHeight: CGFloat = 4
    var maxBarHeight: CGFloat = 24
    var isRecording: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = normalizedLevel(at: index)
                let height = minBarHeight + (maxBarHeight - minBarHeight) * level

                Capsule()
                    .fill(Theme.intelligenceLinear)
                    .opacity(0.45 + 0.55 * level)
                    .frame(width: barWidth, height: height)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.14, dampingFraction: 0.72),
                        value: height
                    )
            }
        }
        .frame(height: maxBarHeight)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func normalizedLevel(at index: Int) -> CGFloat {
        guard isRecording else { return 0.08 }

        // Map trailing `barCount` samples left-to-right (newest on the right).
        let clamped: CGFloat
        if levels.isEmpty {
            // Subtle idle breath envelope before the first audio buffer arrives
            let phase = Double(index) / Double(max(1, barCount - 1)) * .pi
            clamped = CGFloat(0.14 + 0.10 * sin(phase))
        } else {
            let offset = levels.count - barCount + index
            if offset >= 0 && offset < levels.count {
                clamped = min(1.0, max(0.06, levels[offset]))
            } else {
                clamped = 0.08
            }
        }

        // Gentle edge taper so the waveform nestles softly inside the capsule pill
        let normalizedPos = Double(index) / Double(max(1, barCount - 1))
        let edgeTaper = CGFloat(0.55 + 0.45 * sin(normalizedPos * .pi))
        return min(1.0, max(0.06, clamped * edgeTaper))
    }
}

#Preview {
    ZStack {
        Theme.bg.ignoresSafeArea()
        AudioWaveformMeter(
            levels: [0.12, 0.25, 0.42, 0.78, 0.92, 0.55, 0.34, 0.61, 0.85, 0.48, 0.28, 0.66, 0.90, 0.52, 0.30, 0.71, 0.84, 0.44, 0.22, 0.59, 0.73, 0.38, 0.19, 0.49]
        )
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .liquidGlassCard(cornerRadius: Theme.Radius.composer, style: .chrome)
        .padding()
    }
    .preferredColorScheme(.dark)
}
