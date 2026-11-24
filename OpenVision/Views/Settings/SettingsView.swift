// OpenVision - SettingsView.swift
// Redesigned Settings hierarchy (PLAN.md §4.5, T6.4, T6.5):
// 1. Kính Ray-Ban Meta | 2. Gemini | 3. Nghe | 4. Đọc câu trả lời | 5. Đọc toán tiếng Việt
// 6. Trợ lý | 7. Gỡ lỗi | 8. Giới thiệu (fixed GitHub repo link, N16).

import SwiftUI

struct SettingsView: View {
    // MARK: - Environment

    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var glassesManager: GlassesManager
    @EnvironmentObject var router: AppRouter

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $router.settingsPath) {
            Form {
                // 0. Chế độ sử dụng (Giải bài tập / Sử dụng bình thường)
                Section {
                    NavigationLink(value: SettingsDestination.workflowMode) {
                        HStack {
                            Label("Chế độ hoạt động", systemImage: settingsManager.settings.usageMode.systemImage)
                            Spacer()
                            Text(settingsManager.settings.usageMode.displayName)
                                .font(.caption)
                                .foregroundColor(Theme.accent)
                        }
                    }
                } header: {
                    Text("Chế độ sử dụng")
                } footer: {
                    Text(settingsManager.settings.usageMode.summary)
                }

                // 1. Kính Ray-Ban Meta
                Section {
                    NavigationLink(value: SettingsDestination.glasses) {
                        HStack {
                            Label("Kính Ray-Ban Meta", systemImage: "eyeglasses")
                            Spacer()
                            if glassesManager.sdkUnavailableReason != nil {
                                Text("Lỗi SDK")
                                    .font(.caption)
                                    .foregroundColor(Theme.danger)
                            } else {
                                Text(glassesManager.connectedDevice != nil ? "Đã kết nối" : (glassesManager.isRegistered ? "Đã đăng ký" : "Chưa đăng ký"))
                                    .font(.caption)
                                    .foregroundColor(glassesManager.isRegistered ? Theme.success : Theme.warning)
                            }
                        }
                    }
                } header: {
                    Text("Kính Ray-Ban Meta")
                }

                // 2. Gemini
                Section {
                    NavigationLink(value: SettingsDestination.gemini) {
                        HStack {
                            Label("Gemini API", systemImage: "sparkles")
                            Spacer()
                            if settingsManager.settings.isGeminiConfigured {
                                Text("\(GeminiLiveService.parseKeys(settingsManager.settings.geminiAPIKey).count) key")
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Chưa có key")
                                    .foregroundColor(Theme.warning)
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(Theme.warning)
                            }
                        }
                    }
                } header: {
                    Text("Gemini")
                }

                // 3. Nghe & 4. Đọc câu trả lời & 5. Đọc toán tiếng Việt
                Section {
                    NavigationLink(value: SettingsDestination.voice) {
                        HStack {
                            Label("Nghe & Từ đánh thức", systemImage: "mic.fill")
                            Spacer()
                            Text(settingsManager.settings.wakeWordEnabled ? settingsManager.settings.wakeWord : "Tắt")
                                .foregroundColor(.secondary)
                        }
                    }

                    NavigationLink(value: SettingsDestination.reading) {
                        HStack {
                            Label("Đọc câu trả lời", systemImage: "speaker.wave.2.fill")
                            Spacer()
                            Text(settingsManager.settings.dictationMode ? "Đọc chép" : "Tự động")
                                .foregroundColor(.secondary)
                        }
                    }

                    NavigationLink(value: SettingsDestination.mathSpeech) {
                        HStack {
                            Label("Đọc toán tiếng Việt", systemImage: "function")
                            Spacer()
                            Text(settingsManager.settings.mathVerbosity == "explicit" ? "Rõ ràng" : "Tự nhiên")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Giọng nói & Đọc bài")
                }

                // 6. Trợ lý
                Section {
                    NavigationLink {
                        AdditionalInstructionsView()
                    } label: {
                        Label("Hướng dẫn riêng", systemImage: "text.quote")
                    }

                    NavigationLink {
                        MemoriesView()
                    } label: {
                        HStack {
                            Label("Ghi nhớ", systemImage: "brain")
                            Spacer()
                            Text("\(settingsManager.settings.memories.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Trợ lý")
                }

                // 7. Gỡ lỗi
                Section {
                    NavigationLink(value: SettingsDestination.debug) {
                        HStack {
                            Label("Gỡ lỗi & Log", systemImage: "ladybug.fill")
                            Spacer()
                            Text("\(AppLogStore.shared.entries.count) dòng")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Chẩn đoán")
                }

                // 8. Giới thiệu
                Section {
                    HStack {
                        Label("Phiên bản app", systemImage: "info.circle")
                        Spacer()
                        Text("\(Config.appVersion) (\(Config.buildNumber))")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Meta DAT SDK", systemImage: "shippingbox")
                        Spacer()
                        Text("1.0.1")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Model Gemini", systemImage: "cpu")
                        Spacer()
                        Text(GeminiLiveService.modelName)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/darwnlinz1/Visor-iOS-Solver")!) {
                        Label("Mã nguồn trên GitHub", systemImage: "link")
                    }
                } header: {
                    Text("Giới thiệu")
                } footer: {
                    Text("OpenVision là phần mềm mã nguồn mở (MIT) cho kính Ray-Ban Meta.")
                }
            }
            .navigationTitle("Cài đặt")
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .workflowMode: WorkflowModeSettingsView()
                case .glasses: GlassesSettingsView()
                case .gemini: GeminiSettingsView()
                case .voice: VoiceSettingsView()
                case .reading: ReadingSettingsView()
                case .mathSpeech: MathSpeechSettingsView()
                case .debug: DebugSettingsView()
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager.shared)
        .environmentObject(GlassesManager.shared)
        .environmentObject(AppRouter())
        .preferredColorScheme(.dark)
}
