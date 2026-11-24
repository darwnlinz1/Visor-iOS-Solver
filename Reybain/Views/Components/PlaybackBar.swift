// Reybain - PlaybackBar.swift
// Floating Liquid Glass mini-player dock: prev, play/pause, next, repeat,
// live speed cycle (0.75x / 1x / 1.25x / 1.5x), dictation toggle ("Đọc chép"), and stop.

import SwiftUI

struct PlaybackBar: View {
    @ObservedObject var engine: ReadingEngine
    @ObservedObject var settingsManager: SettingsManager

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Top status & progress row
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7.5, height: 7.5)
                    .shadow(color: statusColor.opacity(0.7), radius: 4)

                Text(statusLabel)
                    .font(Theme.Typography.badge)
                    .foregroundColor(Theme.textPrimary)

                if let progress = engine.progressLabel {
                    Text("· Mục \(progress)")
                        .font(Theme.Typography.monoMetric)
                        .foregroundColor(Theme.textSecondary)
                }

                Spacer()

                // Speed multiplier glass pill
                Button {
                    HapticFeedback.selection()
                    engine.cycleRate()
                } label: {
                    Text(engine.rateBadgeText)
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundColor(Theme.accentBright)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .liquidGlassPill(tint: Theme.accent, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tốc độ đọc \(engine.rateBadgeText)")
                .accessibilityHint("Chạm để đổi tốc độ")

                // Dictation quick toggle (for essay / mixed answers)
                if showsDictationToggle {
                    let isDictation = settingsManager.settings.dictationMode
                    Button {
                        HapticFeedback.toggle()
                        engine.toggleDictationMode()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil.and.outline")
                                .font(.caption2.weight(.semibold))
                            Text("Đọc chép")
                                .font(Theme.Typography.badge)
                        }
                        .foregroundColor(isDictation ? Theme.ctaForeground : Theme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background {
                            if isDictation {
                                Capsule()
                                    .fill(Theme.buttonGradient)
                                    .shadow(color: Theme.glow.opacity(0.35), radius: 6, y: 2)
                            }
                        }
                        .modifier(OptionalGlassPillModifier(isActive: !isDictation))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isDictation ? "Tắt chế độ đọc chép" : "Bật chế độ đọc chép")
                }
            }

            // Transport controls row
            HStack(spacing: Theme.Spacing.sm) {
                controlButton(icon: "backward.end.fill", label: "Mục trước") {
                    HapticFeedback.light()
                    engine.previous()
                }

                Button {
                    HapticFeedback.medium()
                    engine.togglePauseResume()
                } label: {
                    Image(systemName: primaryPlayIcon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Theme.ctaForeground)
                        .frame(width: 46, height: 36)
                        .background(Capsule().fill(Theme.buttonGradient))
                        .shadow(color: Theme.glow.opacity(0.42), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(primaryPlayLabel)

                controlButton(icon: "forward.end.fill", label: "Mục tiếp theo") {
                    HapticFeedback.light()
                    engine.next()
                }

                controlButton(icon: "arrow.counterclockwise", label: "Đọc lại mục hiện tại") {
                    HapticFeedback.light()
                    engine.repeatCurrent()
                }

                Spacer()

                if engine.state == .waitingForNext {
                    Button {
                        HapticFeedback.light()
                        engine.resume()
                    } label: {
                        Text("Dòng tiếp")
                            .font(Theme.Typography.badge)
                            .foregroundColor(Theme.ctaForeground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Theme.buttonGradient))
                            .shadow(color: Theme.glow.opacity(0.35), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Đọc dòng tiếp theo")
                }

                controlButton(icon: "stop.fill", label: "Dừng đọc", tint: Theme.danger) {
                    HapticFeedback.light()
                    engine.stop()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: 24, style: .chrome)
        .appleIntelligenceGlow(
            isActive: engine.state == .reading,
            cornerRadius: 24,
            lineWidth: 1.1,
            glowRadius: 6
        )
    }

    private func controlButton(icon: String, label: String, tint: Color = Theme.textPrimary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(tint == Theme.danger ? Theme.danger.opacity(0.14) : Color.white.opacity(0.07))
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            tint == Theme.danger ? Theme.danger.opacity(0.36) : Color.white.opacity(0.12),
                            lineWidth: 0.75
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var showsDictationToggle: Bool {
        guard let type = engine.plan?.answerType else { return false }
        return type == .essay || type == .mixed
    }

    private var primaryPlayIcon: String {
        engine.state == .reading ? "pause.fill" : "play.fill"
    }

    private var primaryPlayLabel: String {
        switch engine.state {
        case .reading: return "Tạm dừng đọc"
        case .paused: return "Tiếp tục đọc"
        case .waitingForNext: return "Đọc dòng tiếp"
        case .finished, .idle: return "Đọc lại từ đầu"
        }
    }

    private var statusLabel: String {
        switch engine.state {
        case .idle: return "Đã dừng"
        case .reading: return "Đang đọc"
        case .paused: return "Tạm dừng"
        case .waitingForNext: return "Chờ \"tiếp\""
        case .finished: return "Đã đọc xong"
        }
    }

    private var statusColor: Color {
        switch engine.state {
        case .reading: return Theme.accent
        case .paused, .waitingForNext: return Theme.warning
        case .finished: return Theme.info
        case .idle: return Theme.inactive
        }
    }
}

private struct OptionalGlassPillModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.liquidGlassPill(interactive: true)
        } else {
            content
        }
    }
}

#Preview {
    ZStack {
        AnimatedBackground()
        PlaybackBar(engine: ReadingEngine.shared, settingsManager: SettingsManager.shared)
            .padding()
    }
    .preferredColorScheme(.dark)
}
