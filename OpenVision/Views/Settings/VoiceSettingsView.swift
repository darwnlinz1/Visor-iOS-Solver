// OpenVision - VoiceSettingsView.swift
// Listening settings (PLAN.md §4.5, T6.4): wake word, microphone, listening language, silence timeout, chimes.
// Reading speeds, pauses and voices moved to ReadingSettingsView.

import SwiftUI

struct VoiceSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        Form {
            // Wake word
            Section {
                Toggle(isOn: $settingsManager.settings.wakeWordEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Từ đánh thức")
                        Text("Chỉ nghe sau khi bạn gọi tên")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if settingsManager.settings.wakeWordEnabled {
                    TextField("Ok Vision", text: $settingsManager.settings.wakeWord)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Gọi trợ lý")
            } footer: {
                Text("Nói \"\(settingsManager.settings.wakeWord)\" rồi hỏi tự do, tiếng Việt hay tiếng Anh. Khi đang đọc bài, nói \"\(settingsManager.settings.wakeWord) tạm dừng / chậm lại / đọc lại câu 3\" để điều khiển.")
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
                Toggle(isOn: $settingsManager.settings.playActivationSound) {
                    Text("Âm báo khi gọi trợ lý")
                }
            } header: {
                Text("Phản hồi")
            }
        }
        .navigationTitle("Nghe & Từ đánh thức")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        VoiceSettingsView()
            .environmentObject(SettingsManager.shared)
    }
    .preferredColorScheme(.dark)
}
