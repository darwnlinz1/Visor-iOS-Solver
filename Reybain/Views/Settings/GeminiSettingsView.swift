// Reybain - GeminiSettingsView.swift
// Gemini API key configuration with Keychain trust indicator and model chain pills.

import SwiftUI

struct GeminiSettingsView: View {
    // MARK: - Environment

    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var apiKey: String = ""
    @State private var didSaveExplicitly: Bool = false

    private var parsedKeyCount: Int {
        GeminiLiveService.parseKeys(apiKey).count
    }

    // MARK: - Body

    var body: some View {
        Form {
            // Keychain trust & count header
            Section {
                HStack(spacing: 12) {
                    SettingsIconBadge(
                        icon: parsedKeyCount > 0 ? "lock.shield.fill" : "exclamationmark.shield.fill",
                        tint: parsedKeyCount > 0 ? Theme.success : Theme.warning
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(parsedKeyCount > 0 ? "Keychain bảo mật" : "Chưa có API key")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text(parsedKeyCount > 0
                             ? "Lưu an toàn trong Keychain của máy, không nằm trong mã nguồn."
                             : "Dán ít nhất 1 API key từ Google AI Studio để dùng Reybain.")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }

                    Spacer(minLength: 4)

                    Text("\(parsedKeyCount) key")
                        .font(Theme.Typography.monoMetric)
                        .foregroundColor(parsedKeyCount > 0 ? Theme.success : Theme.warning)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .liquidGlassPill(tint: parsedKeyCount > 0 ? Theme.success : Theme.warning)
                }
                .padding(.vertical, 4)
                .reybainSettingsRow()

                VStack(alignment: .leading, spacing: 6) {
                    Text("API key (nhiều key: cách nhau bằng dấu phẩy)")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    SecureField("AQ.… hoặc AIza…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(Theme.textPrimary)
                }
                .reybainSettingsRow()
            } header: {
                Text("Xác thực")
            } footer: {
                Text("Quota tính theo PROJECT và theo model, không theo key: chỉ thêm key từ các project Google Cloud khác nhau mới tăng quota. Khi model chính hết quota, app tự chuyển sang \(GeminiLiveService.modelChain.dropFirst().joined(separator: ", ")).")
            }

            // Model Chain Pills
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(GeminiLiveService.modelChain.enumerated()), id: \.offset) { index, model in
                            HStack(spacing: 6) {
                                Text("\(index + 1)")
                                    .font(.caption2.monospacedDigit().weight(.bold))
                                    .foregroundColor(Theme.ctaForeground)
                                    .frame(width: 18, height: 18)
                                    .background(
                                        Circle().fill(
                                            index == 0
                                                ? AnyShapeStyle(Theme.buttonGradient)
                                                : AnyShapeStyle(Theme.bgElevated)
                                        )
                                    )

                                Text(model)
                                    .font(Theme.Typography.monoLog)
                                    .foregroundColor(index == 0 ? Theme.accentBright : Theme.textPrimary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .liquidGlassPill(tint: index == 0 ? Theme.accent : nil)

                            if index < GeminiLiveService.modelChain.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .reybainSettingsRow()
            } header: {
                Text("Chuỗi model dự phòng")
            } footer: {
                Text("Câu trả lời được truyền dần (streaming): kính đọc câu đầu tiên ngay khi có.")
            }

            // Help
            Section {
                Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                    HStack(spacing: 12) {
                        SettingsIconBadge(icon: "key.fill", tint: Theme.iridescentCyan)
                        Text("Lấy API key (Google AI Studio)")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                .reybainSettingsRow()
            } header: {
                Text("Trợ giúp")
            }
        }
        .reybainSettingsCanvas()
        .navigationTitle("Gemini")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            apiKey = settingsManager.settings.geminiAPIKey
            didSaveExplicitly = false
        }
        .onDisappear {
            if !didSaveExplicitly {
                saveSettings()
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Lưu") {
                    HapticFeedback.success()
                    didSaveExplicitly = true
                    saveSettings()
                    dismiss()
                }
                .fontWeight(.semibold)
                .foregroundColor(Theme.accentBright)
            }
        }
    }

    // MARK: - Methods

    private func saveSettings() {
        // Normalised to "key1, key2" — GeminiLiveService.parseKeys reads any separator.
        let normalized = GeminiLiveService.parseKeys(apiKey).joined(separator: ", ")
        let changed = normalized != settingsManager.settings.geminiAPIKey
        settingsManager.settings.geminiAPIKey = normalized
        settingsManager.saveNow()
        if changed {
            GeminiLiveService.shared.resetNetworkState()
        }
    }
}

#Preview {
    NavigationStack {
        GeminiSettingsView()
            .environmentObject(SettingsManager.shared)
    }
    .preferredColorScheme(.dark)
}
