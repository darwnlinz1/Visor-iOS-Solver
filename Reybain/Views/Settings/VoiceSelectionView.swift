// Reybain - VoiceSelectionView.swift
// Apple voice picker styled with OLED obsidian rows, quality tier pills, and active preview badge.

import SwiftUI
import AVFoundation
import UIKit

struct VoiceSelectionView: View {
    /// "vi" or "en".
    let languagePrefix: String
    let title: String
    let sample: String
    @Binding var selection: String?

    // MARK: - State

    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var testingVoiceId: String?
    /// Held for the duration of a preview: a synthesizer created inside a function is released as
    /// soon as it returns and speaks nothing.
    @State private var previewSynthesizer = AVSpeechSynthesizer()

    // MARK: - Body

    var body: some View {
        List {
            Section {
                voiceRow(name: "Tự động (giọng tốt nhất đã cài)", quality: nil, identifier: nil)
                    .reybainSettingsRow()
            } footer: {
                Text("Tự chọn giọng chất lượng cao nhất (Premium › Enhanced › Default) có trên máy.")
            }

            ForEach([AVSpeechSynthesisVoiceQuality.premium, .enhanced, .default], id: \.rawValue) { quality in
                let group = voices.filter { $0.quality == quality }
                if !group.isEmpty {
                    Section {
                        ForEach(group, id: \.identifier) { voice in
                            voiceRow(name: voice.name, quality: voice.quality, identifier: voice.identifier)
                                .reybainSettingsRow()
                        }
                    } header: {
                        Text(TTSService.qualityDisplayName(quality))
                    }
                }
            }

            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconBadge(icon: "square.and.arrow.down", tint: Theme.accent)
                        Text("Mở Cài đặt iOS để tải thêm giọng")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                .reybainSettingsRow()
            } footer: {
                Text("Giọng Enhanced/Premium phát âm tự nhiên hơn nhiều. Tải trong Cài đặt iOS → Trợ năng → Nội dung được đọc → Giọng nói.")
            }
        }
        .reybainSettingsCanvas()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            TTSService.invalidateVoiceCache()
            voices = TTSService.availableVoices(for: languagePrefix)
        }
        .onDisappear {
            previewSynthesizer.stopSpeaking(at: .immediate)
            testingVoiceId = nil
        }
    }

    // MARK: - Voice Row

    @ViewBuilder
    private func voiceRow(name: String, quality: AVSpeechSynthesisVoiceQuality?, identifier: String?) -> some View {
        let isPreviewing = testingVoiceId == identifier
        let isSelected = selection == identifier

        HStack(spacing: 10) {
            Button {
                HapticFeedback.selection()
                selection = identifier
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(name)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                .foregroundColor(Theme.textPrimary)

                            if let quality, quality != .default {
                                qualityBadge(quality)
                            }
                        }

                        if let quality {
                            Text(TTSService.qualityDisplayName(quality))
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Button {
                HapticFeedback.light()
                preview(identifier: identifier)
            } label: {
                Image(systemName: isPreviewing ? "speaker.wave.2.fill" : "play.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isPreviewing ? Theme.accentBright : Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(isPreviewing ? Theme.accent.opacity(0.20) : Color.white.opacity(0.05))
                    )
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Nghe thử \(name)")

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Theme.accentBright)
                    .font(.body)
            }
        }
    }

    @ViewBuilder
    private func qualityBadge(_ quality: AVSpeechSynthesisVoiceQuality) -> some View {
        let isPremium = quality == .premium
        let tint = isPremium ? Theme.iridescentViolet : Theme.accent
        let label = isPremium ? "Premium" : "Enhanced"

        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(tint.opacity(0.16))
                    .overlay(Capsule().strokeBorder(tint.opacity(0.36), lineWidth: 0.6))
            )
    }

    // MARK: - Actions

    private func preview(identifier: String?) {
        if ReadingEngine.shared.isActive {
            ReadingEngine.shared.stop()
        }
        TTSService.shared.stop()
        previewSynthesizer.stopSpeaking(at: .immediate)
        testingVoiceId = identifier
        Task { @MainActor in
            await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                preferGlasses: SettingsManager.shared.settings.preferGlassesMic
            )
            let utterance = AVSpeechUtterance(string: sample)
            utterance.voice = identifier.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
                ?? TTSService.bestVoice(for: languagePrefix == "vi" ? "vi-VN" : "en-US")
            utterance.rate = SettingsManager.shared.settings.clampedSpeechRate
            previewSynthesizer.speak(utterance)
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if testingVoiceId == identifier { testingVoiceId = nil }
        }
    }
}

#Preview {
    NavigationStack {
        VoiceSelectionView(
            languagePrefix: "vi",
            title: "Giọng tiếng Việt",
            sample: "Xin chào, đáp án là x bằng 2.",
            selection: .constant(nil)
        )
    }
    .preferredColorScheme(.dark)
}
