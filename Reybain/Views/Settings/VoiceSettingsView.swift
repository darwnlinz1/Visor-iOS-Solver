// Reybain - VoiceSettingsView.swift
// Listening settings: Direct Audio-to-Gemini toggle, wake word + live mic health pill,
// glasses mic preference, recognition language, silence timeout, and audio feedback.

import SwiftUI

struct VoiceSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @ObservedObject private var voiceCommandService = VoiceCommandService.shared

    var body: some View {
        Form {
            // Wake word
            Section {
                Toggle(isOn: $settingsManager.settings.wakeWordEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tự động lắng nghe từ đánh thức")
                            .foregroundColor(Theme.textPrimary)
                        Text("Tự bật micro nghe tên gọi ngay khi mở app và sau mỗi lượt trả lời")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()

                if settingsManager.settings.wakeWordEnabled {
                    TextField("Ok Vision", text: $settingsManager.settings.wakeWord)
                        .autocorrectionDisabled()
                        .foregroundColor(Theme.textPrimary)
                        .onSubmit { sanitizeWakeWord() }
                        .reybainSettingsRow()

                    HStack {
                        Text("Trạng thái micro nghe")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(voiceCommandService.isRecognitionHealthy ? Theme.success : Theme.warning)
                                .frame(width: 7, height: 7)
                                .shadow(
                                    color: (voiceCommandService.isRecognitionHealthy ? Theme.success : Theme.warning).opacity(0.7),
                                    radius: 3
                                )
                            Text(wakeWordStatusText)
                                .font(.caption.weight(.medium))
                                .foregroundColor(Theme.textPrimary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .liquidGlassPill(tint: voiceCommandService.isRecognitionHealthy ? Theme.success : Theme.warning)
                    }
                    .reybainSettingsRow()
                }
            } header: {
                Text("Gọi trợ lý")
            } footer: {
                Text("Nói \"\(settingsManager.settings.wakeWord)\" (hoặc \"Ok Reybain\" / \"Ô kê vi dơn\") rồi hỏi tự do bằng tiếng Việt hoặc tiếng Anh. Khi đang đọc bài, nói \"\(settingsManager.settings.wakeWord) tạm dừng / chậm lại / đọc lại câu 3\" để điều khiển.")
            }

            // Listening & Direct Audio to Gemini
            Section {
                Toggle(isOn: $settingsManager.settings.directAudioToGemini) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gửi thẳng âm thanh (Audio) lên Gemini")
                            .foregroundColor(Theme.textPrimary)
                        Text("Nhận diện tự nhiên song ngữ Việt–Anh và tự sửa lỗi nghe ở Chế độ bình thường & Chat")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()

                Toggle(isOn: $settingsManager.settings.preferGlassesMic) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dùng mic của kính")
                            .foregroundColor(Theme.textPrimary)
                        Text("Tự chuyển về mic & loa ngoài iPhone khi không đeo kính")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()

                Toggle(isOn: $settingsManager.settings.pauseWakeWordDuringMusic) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nhả mic kính khi đang nghe nhạc")
                            .foregroundColor(Theme.textPrimary)
                        Text("Tránh tiếng bíp và giữ nhạc A2DP khi bấm dừng/phát nhạc trên kính")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()

                Picker("Ngôn ngữ nghe", selection: $settingsManager.settings.recognitionLanguage) {
                    Text("Tự động (theo iPhone)").tag("auto")
                    Text("Tiếng Việt").tag("vi-VN")
                    Text("English").tag("en-US")
                }
                .reybainSettingsRow()

                Picker("Tự kết thúc khi im lặng", selection: $settingsManager.settings.conversationTimeout) {
                    Text("15 giây").tag(TimeInterval(15))
                    Text("30 giây").tag(TimeInterval(30))
                    Text("1 phút").tag(TimeInterval(60))
                    Text("2 phút").tag(TimeInterval(120))
                }
                .reybainSettingsRow()
            } header: {
                Text("Nghe")
            } footer: {
                Text("Từ đánh thức và lệnh điều khiển đọc bài luôn chạy nhẹ trên máy. Khi bật gửi thẳng âm thanh, câu hỏi giọng nói song ngữ Việt–Anh được gửi trực tiếp để Gemini nghe chuẩn xác.")
            }

            // Feedback
            Section {
                Toggle(isOn: $settingsManager.settings.spokenStatusUpdates) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Thông báo tiến trình qua loa")
                            .foregroundColor(Theme.textPrimary)
                        Text("Đọc ngắn khi chụp xong, tải ảnh lên, đổi key/model 503–429 và khi AI phản hồi")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()

                Toggle(isOn: $settingsManager.settings.playActivationSound) {
                    Text("Âm báo khi gọi trợ lý")
                        .foregroundColor(Theme.textPrimary)
                }
                .reybainSettingsRow()
            } header: {
                Text("Phản hồi")
            }
        }
        .reybainSettingsCanvas()
        .navigationTitle("Nghe & Từ đánh thức")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { sanitizeWakeWord() }
    }

    private var wakeWordStatusText: String {
        if voiceCommandService.isRecognitionHealthy {
            return AudioSessionManager.shared.isBluetoothHFPInputActive ? "Đang nghe (Mic kính)" : "Đang nghe (Mic iPhone)"
        }
        if settingsManager.settings.pauseWakeWordDuringMusic && AudioSessionManager.shared.isOtherAudioPlaying {
            return "Tạm nhả mic vì đang phát nhạc"
        }
        return voiceCommandService.authorizationStatus == .authorized ? "Đang chờ kích hoạt…" : "Chưa cấp quyền giọng nói"
    }

    private func sanitizeWakeWord() {
        let trimmed = settingsManager.settings.wakeWord.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            settingsManager.settings.wakeWord = Constants.Voice.defaultWakeWord
        } else if trimmed != settingsManager.settings.wakeWord {
            settingsManager.settings.wakeWord = trimmed
        }
    }
}

#Preview {
    NavigationStack {
        VoiceSettingsView()
            .environmentObject(SettingsManager.shared)
    }
    .preferredColorScheme(.dark)
}
