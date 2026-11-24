// OpenVision - VoiceSettingsView.swift
// Listening settings (PLAN.md §4.5, T6.4): wake word, microphone, listening language, silence timeout, chimes.
// Reading speeds, pauses and voices moved to ReadingSettingsView.

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
                        Text("Tự bật micro nghe tên gọi ngay khi mở app và sau mỗi lượt trả lời")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if settingsManager.settings.wakeWordEnabled {
                    TextField("Ok Vision", text: $settingsManager.settings.wakeWord)
                        .autocorrectionDisabled()
                        .onSubmit { sanitizeWakeWord() }

                    HStack {
                        Text("Trạng thái micro nghe")
                        Spacer()
                        Circle()
                            .fill(voiceCommandService.isRecognitionHealthy ? Theme.success : Theme.warning)
                            .frame(width: 8, height: 8)
                        Text(wakeWordStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Gọi trợ lý")
            } footer: {
                Text("Nói \"\(settingsManager.settings.wakeWord)\" (hoặc \"Ô kê vi dơn\" / \"Hey Vision\") rồi hỏi tự do bằng tiếng Việt hoặc tiếng Anh. Khi đang đọc bài, nói \"\(settingsManager.settings.wakeWord) tạm dừng / chậm lại / đọc lại câu 3\" để điều khiển.")
            }

            // Listening
            Section {
                Toggle(isOn: $settingsManager.settings.preferGlassesMic) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dùng mic của kính")
                        Text("Tự chuyển về mic & loa ngoài iPhone khi không đeo kính")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $settingsManager.settings.pauseWakeWordDuringMusic) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nhả mic kính khi đang nghe nhạc")
                        Text("Tránh tiếng bíp và giữ nhạc A2DP khi bấm dừng/phát nhạc trên kính")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Picker("Ngôn ngữ nghe", selection: $settingsManager.settings.recognitionLanguage) {
                    Text("Tự động (theo iPhone)").tag("auto")
                    Text("Tiếng Việt").tag("vi-VN")
                    Text("English").tag("en-US")
                }

                Picker("Tự kết thúc khi im lặng", selection: $settingsManager.settings.conversationTimeout) {
                    Text("15 giây").tag(TimeInterval(15))
                    Text("30 giây").tag(TimeInterval(30))
                    Text("1 phút").tag(TimeInterval(60))
                    Text("2 phút").tag(TimeInterval(120))
                }
            } header: {
                Text("Nghe")
            } footer: {
                Text("iOS ưu tiên nhận dạng trên máy khi khả dụng (không cần gửi âm thanh lên mạng). Câu trả lời luôn theo đúng ngôn ngữ câu hỏi.")
            }

            // Feedback
            Section {
                Toggle(isOn: $settingsManager.settings.spokenStatusUpdates) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Thông báo tiến trình qua loa")
                        Text("Đọc ngắn khi chụp xong, tải ảnh lên, đổi key/model 503–429 và khi AI phản hồi")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $settingsManager.settings.playActivationSound) {
                    Text("Âm báo khi gọi trợ lý")
                }
            } header: {
                Text("Phản hồi")
            }
        }
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
