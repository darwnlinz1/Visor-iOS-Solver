// Reybain - ReadingSettingsView.swift
// Answer reading settings styled with OLED obsidian cards, tabular slider value pills,
// dictation mode controls, voice pickers, and luminous full-width "Nghe thử" CTA.

import SwiftUI
import AVFoundation

struct ReadingSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @ObservedObject private var readingEngine = ReadingEngine.shared
    @State private var isPlayingDemo = false

    private func voiceName(_ identifier: String?, language: String) -> String {
        if let identifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice.name
        }
        return TTSService.bestVoice(for: language).map { "Tự động · \($0.name)" } ?? "Tự động"
    }

    private func percent(_ rate: Float) -> String {
        String(format: "%.0f%%", rate / 0.5 * 100)
    }

    private func valueBadge(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.monoMetric)
            .foregroundColor(Theme.accentBright)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Theme.accentMuted)
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.32), lineWidth: 0.7))
            )
    }

    var body: some View {
        Form {
            // Trắc nghiệm
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Tốc độ trắc nghiệm")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        valueBadge(percent(settingsManager.settings.mcqRate))
                    }
                    Slider(value: $settingsManager.settings.mcqRate, in: 0.35...0.6, step: 0.025)
                        .tint(Theme.accent)
                }
                .reybainSettingsRow()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Nghỉ giữa các câu")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        valueBadge(String(format: "%.1f giây", settingsManager.settings.pauseBetweenAnswers))
                    }
                    Slider(value: $settingsManager.settings.pauseBetweenAnswers, in: 0...2.0, step: 0.1)
                        .tint(Theme.accent)
                }
                .reybainSettingsRow()
            } header: {
                Text("Trắc nghiệm")
            } footer: {
                Text("Đọc gọn từng đáp án (ví dụ: \"Câu 1: A. Câu 2: C. Câu 3: a đúng, b sai…\").")
            }

            // Tự luận
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Tốc độ tự luận")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        valueBadge(percent(settingsManager.settings.essayRate))
                    }
                    Slider(value: $settingsManager.settings.essayRate, in: 0.25...0.6, step: 0.025)
                        .tint(Theme.accent)
                }
                .reybainSettingsRow()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hệ số tốc độ công thức")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        valueBadge(String(format: "%.0f%%", settingsManager.settings.mathRateFactor * 100))
                    }
                    Slider(value: $settingsManager.settings.mathRateFactor, in: 0.6...1.0, step: 0.05)
                        .tint(Theme.accent)
                }
                .reybainSettingsRow()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Nghỉ giữa các dòng")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        valueBadge(String(format: "%.1f giây", settingsManager.settings.pauseBetweenLines))
                    }
                    Slider(value: $settingsManager.settings.pauseBetweenLines, in: 0...5.0, step: 0.2)
                        .tint(Theme.accent)
                }
                .reybainSettingsRow()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Nghỉ sau công thức")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        valueBadge(String(format: "%.1f giây", settingsManager.settings.pauseAfterFormula))
                    }
                    Slider(value: $settingsManager.settings.pauseAfterFormula, in: 0...1.5, step: 0.1)
                        .tint(Theme.accent)
                }
                .reybainSettingsRow()

                Toggle("Đọc số dòng (\"Dòng 1\", \"Dòng 2\")", isOn: $settingsManager.settings.readLineNumbers)
                    .foregroundColor(Theme.textPrimary)
                    .reybainSettingsRow()

                Toggle(isOn: $settingsManager.settings.dictationMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chế độ đọc chép")
                            .foregroundColor(Theme.textPrimary)
                        Text("Tự dừng sau mỗi dòng tự luận chờ bạn nói \"tiếp\"")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()

                if settingsManager.settings.dictationMode {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Tự đi tiếp sau")
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            valueBadge(
                                settingsManager.settings.dictationAutoContinue <= 0
                                    ? "Chờ lệnh"
                                    : String(format: "%.0f giây", settingsManager.settings.dictationAutoContinue)
                            )
                        }
                        Slider(value: $settingsManager.settings.dictationAutoContinue, in: 0...30, step: 1)
                            .tint(Theme.accent)
                    }
                    .reybainSettingsRow()

                    Toggle("Đọc công thức hai lần khi đọc chép", isOn: $settingsManager.settings.repeatFormulaInDictation)
                        .foregroundColor(Theme.textPrimary)
                        .reybainSettingsRow()
                }
            } header: {
                Text("Tự luận")
            }

            // Chung
            Section {
                NavigationLink {
                    VoiceSelectionView(
                        languagePrefix: "vi",
                        title: "Giọng tiếng Việt",
                        sample: "Câu 1: A. Dòng 1: ích bình phương trừ 5 ích cộng 6 bằng 0.",
                        selection: $settingsManager.settings.selectedVietnameseVoiceIdentifier
                    )
                } label: {
                    HStack {
                        Text("Giọng tiếng Việt")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text(voiceName(settingsManager.settings.selectedVietnameseVoiceIdentifier, language: "vi-VN"))
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()

                NavigationLink {
                    VoiceSelectionView(
                        languagePrefix: "en",
                        title: "Giọng tiếng Anh",
                        sample: "Question 1: C. Line 1: x squared minus 5 x plus 6 equals 0.",
                        selection: $settingsManager.settings.selectedVoiceIdentifier
                    )
                } label: {
                    HStack {
                        Text("Giọng tiếng Anh")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text(voiceName(settingsManager.settings.selectedVoiceIdentifier, language: "en-US"))
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Tốc độ câu trả lời thường")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        valueBadge(percent(settingsManager.settings.speechRate))
                    }
                    Slider(value: $settingsManager.settings.speechRate, in: 0.35...0.6, step: 0.025)
                        .tint(Theme.accent)
                }
                .reybainSettingsRow()

                Toggle(isOn: $settingsManager.settings.hideTextSpeakOnly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ẩn chữ, chỉ nghe")
                            .foregroundColor(Theme.textPrimary)
                        Text("Tối giản màn hình Trực tiếp khi chỉ dùng tai nghe / kính")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()
            } header: {
                Text("Chung")
            }

            // Nghe thử đề mẫu
            Section {
                if readingEngine.state == .waitingForNext {
                    Button {
                        HapticFeedback.light()
                        readingEngine.resume()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "forward.fill")
                            Text("Dòng tiếp theo")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .foregroundColor(Theme.accentBright)
                    }
                    .reybainSettingsRow()

                    Button {
                        HapticFeedback.light()
                        readingEngine.repeatCurrent()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.counterclockwise")
                            Text("Đọc lại dòng vừa nghe")
                            Spacer()
                        }
                        .foregroundColor(Theme.textPrimary)
                    }
                    .reybainSettingsRow()
                }

                Button {
                    HapticFeedback.medium()
                    if readingEngine.isActive {
                        isPlayingDemo = false
                        readingEngine.stop()
                    } else {
                        playDemoSample()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Spacer()
                        Image(systemName: readingEngine.isActive ? "stop.fill" : "play.circle.fill")
                            .font(.subheadline.weight(.bold))
                        Text(readingEngine.isActive ? "Dừng nghe thử" : "Nghe thử với cài đặt hiện tại")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .foregroundColor(readingEngine.isActive ? Theme.danger : Theme.ctaForeground)
                    .padding(.vertical, 12)
                    .background {
                        if readingEngine.isActive {
                            Capsule()
                                .fill(Theme.danger.opacity(0.18))
                                .overlay(Capsule().strokeBorder(Theme.danger.opacity(0.45), lineWidth: 0.9))
                        } else {
                            Capsule()
                                .fill(Theme.buttonGradient)
                                .shadow(color: Theme.glow.opacity(0.40), radius: 8, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            } footer: {
                Text("Đọc mẫu 3 câu trắc nghiệm và 1 bài tự luận 4 dòng theo đúng tốc độ, khoảng nghỉ và cách đọc toán hiện tại.")
            }
        }
        .reybainSettingsCanvas()
        .navigationTitle("Đọc câu trả lời")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settingsManager.settings) { _, _ in
            readingEngine.refreshConfigFromSettings()
        }
        .onChange(of: readingEngine.isActive) { _, active in
            if !active { isPlayingDemo = false }
        }
        .onDisappear {
            if isPlayingDemo && readingEngine.isActive {
                isPlayingDemo = false
                readingEngine.stop()
            }
        }
    }

    private func playDemoSample() {
        let sample = #"""
        TYPE: MIXED
        Q1: A
        Q2: a Đ, b S, c Đ, d S
        Q3: 2,5
        P1: Bài 1
        L1: Ta có phương trình $x^2 - 5x + 6 = 0$.
        L2: Tính $\Delta = (-5)^2 - 4 \cdot 6 = 1$.
        L3: Vì $\Delta > 0$ nên phương trình có hai nghiệm phân biệt.
        L4: $x_1 = 2$, $x_2 = 3$.
        FINAL: Vậy tập nghiệm là $S = \{2; 3\}$.
        """#
        let parsed = AnswerFormat.parse(sample)
        let assembler = ReplyAssembler(languageCode: "vi", readLineNumbers: settingsManager.settings.readLineNumbers)
        let record = assembler.record(for: parsed)
        isPlayingDemo = true
        readingEngine.replay(record: record)
    }
}

#Preview {
    NavigationStack {
        ReadingSettingsView()
            .environmentObject(SettingsManager.shared)
    }
    .preferredColorScheme(.dark)
}
