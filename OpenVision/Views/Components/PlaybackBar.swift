// OpenVision - PlaybackBar.swift
// Floating reading playback controls (PLAN.md §4.5, T6.1): prev, play/pause, next, repeat,
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
                    .frame(width: 8, height: 8)

                Text(statusLabel)
                    .font(Theme.Typography.badge)
                    .foregroundColor(Theme.textPrimary)

                if let progress = engine.progressLabel {
                    Text("· Mục \(progress)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(Theme.textSecondary)
                }

                Spacer()

                // Speed multiplier chip
                Button {
                    HapticFeedback.selection()
                    engine.cycleRate()
                } label: {
                    Text(engine.rateBadgeText)
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundColor(Theme.accentBright)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Theme.accentMuted)
                                .overlay(Capsule().stroke(Theme.accent.opacity(0.4), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tốc độ đọc \(engine.rateBadgeText)")
                .accessibilityHint("Chạm để đổi tốc độ")

                // Dictation quick toggle (for essay / mixed answers)
                if showsDictationToggle {
                    Button {
                        HapticFeedback.toggle()
                        engine.toggleDictationMode()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil.and.outline")
                                .font(.caption2)
                            Text("Đọc chép")
                                .font(Theme.Typography.badge)
                        }
                        .foregroundColor(settingsManager.settings.dictationMode ? .black.opacity(0.9) : Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(settingsManager.settings.dictationMode ? AnyShapeStyle(Theme.buttonGradient) : AnyShapeStyle(Theme.glass))
                                .overlay(
                                    Capsule().stroke(
                                        settingsManager.settings.dictationMode ? Theme.accent : Theme.bgElevatedStroke,
                                        lineWidth: 1
                                    )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(settingsManager.settings.dictationMode ? "Tắt chế độ đọc chép" : "Bật chế độ đọc chép")
                }
            }

            // Transport controls row
            HStack(spacing: Theme.Spacing.md) {
                controlButton(icon: "backward.end.fill", label: "Mục trước") {
                    HapticFeedback.light()
                    engine.previous()
                }

                Button {
                    HapticFeedback.medium()
                    engine.togglePauseResume()
                } label: {
                    Image(systemName: primaryPlayIcon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black.opacity(0.92))
                        .frame(width: 42, height: 36)
                        .background(Capsule().fill(Theme.buttonGradient))
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
                            .foregroundColor(.black.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Theme.buttonGradient))
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
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.bgElevated.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(Theme.accent.opacity(0.32), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        )
    }

    private func controlButton(icon: String, label: String, tint: Color = Theme.textPrimary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.07)))
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

#Preview {
    ZStack {
        Theme.bg.ignoresSafeArea()
        PlaybackBar(engine: ReadingEngine.shared, settingsManager: SettingsManager.shared)
            .padding()
    }
    .preferredColorScheme(.dark)
}
