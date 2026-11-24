// Reybain - SettingsView.swift
// iOS 26 Liquid Glass Settings Hub on OLED obsidian:
// Brand Hero Card, color-coded SettingsIconBadge rows, live device/Gemini status, and MIT footer.

import SwiftUI

struct SettingsView: View {
    // MARK: - Environment

    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var glassesManager: GlassesManager
    @EnvironmentObject var router: AppRouter

    private var keyCount: Int {
        GeminiLiveService.parseKeys(settingsManager.settings.geminiAPIKey).count
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $router.settingsPath) {
            Form {
                // Hero Brand & Live Status Card
                Section {
                    brandHeroCard
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                // 0. Chế độ sử dụng (Giải bài tập / Sử dụng bình thường)
                Section {
                    NavigationLink(value: SettingsDestination.workflowMode) {
                        HStack(spacing: 12) {
                            SettingsIconBadge(
                                icon: settingsManager.settings.usageMode.systemImage,
                                tint: Theme.iridescentViolet
                            )
                            Text("Chế độ hoạt động")
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text(settingsManager.settings.usageMode.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundColor(Theme.accentBright)
                        }
                    }
                    .reybainSettingsRow()
                } header: {
                    Text("Chế độ sử dụng")
                } footer: {
                    Text(settingsManager.settings.usageMode.summary)
                }

                // 1. Kính Ray-Ban Meta
                Section {
                    NavigationLink(value: SettingsDestination.glasses) {
                        HStack(spacing: 12) {
                            SettingsIconBadge(icon: "eyeglasses", tint: Theme.accent)
                            Text("Kính Ray-Ban Meta")
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            if glassesManager.sdkUnavailableReason != nil {
                                Text("Lỗi SDK")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Theme.danger)
                            } else {
                                Text(glassesStatusLabel)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(glassesStatusTint)
                            }
                        }
                    }
                    .reybainSettingsRow()
                } header: {
                    Text("Kính Ray-Ban Meta")
                }

                // 2. Gemini
                Section {
                    NavigationLink(value: SettingsDestination.gemini) {
                        HStack(spacing: 12) {
                            SettingsIconBadge(icon: "sparkles", tint: Theme.iridescentCyan)
                            Text("Gemini API")
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            if settingsManager.settings.isGeminiConfigured {
                                Text("\(keyCount) key")
                                    .font(Theme.Typography.monoMetric)
                                    .foregroundColor(Theme.textSecondary)
                            } else {
                                HStack(spacing: 4) {
                                    Text("Chưa có key")
                                        .font(.caption.weight(.semibold))
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.caption)
                                }
                                .foregroundColor(Theme.warning)
                            }
                        }
                    }
                    .reybainSettingsRow()
                } header: {
                    Text("Gemini")
                }

                // 3. Nghe & 4. Đọc câu trả lời & 5. Đọc toán tiếng Việt
                Section {
                    NavigationLink(value: SettingsDestination.voice) {
                        HStack(spacing: 12) {
                            SettingsIconBadge(icon: "mic.fill", tint: Theme.info)
                            Text("Nghe & Từ đánh thức")
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text(settingsManager.settings.wakeWordEnabled ? settingsManager.settings.wakeWord : "Tắt")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .reybainSettingsRow()

                    NavigationLink(value: SettingsDestination.reading) {
                        HStack(spacing: 12) {
                            SettingsIconBadge(icon: "speaker.wave.2.fill", tint: Theme.iridescentIndigo)
                            Text("Đọc câu trả lời")
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text(settingsManager.settings.dictationMode ? "Đọc chép" : "Tự động")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .reybainSettingsRow()

                    NavigationLink(value: SettingsDestination.mathSpeech) {
                        HStack(spacing: 12) {
                            SettingsIconBadge(icon: "function", tint: Theme.accentBright)
                            Text("Đọc toán tiếng Việt")
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text(settingsManager.settings.mathVerbosity == "explicit" ? "Rõ ràng" : "Tự nhiên")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .reybainSettingsRow()
                } header: {
                    Text("Giọng nói & Đọc bài")
                }

                // 6. Trợ lý
                Section {
                    NavigationLink {
                        AdditionalInstructionsView()
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIconBadge(icon: "text.quote", tint: Theme.iridescentMagenta)
                            Text("Hướng dẫn riêng")
                                .foregroundColor(Theme.textPrimary)
                        }
                    }
                    .reybainSettingsRow()

                    NavigationLink {
                        MemoriesView()
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIconBadge(icon: "brain", tint: Theme.iridescentMagenta)
                            Text("Ghi nhớ")
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text("\(settingsManager.settings.memories.count)")
                                .font(Theme.Typography.monoMetric)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .reybainSettingsRow()
                } header: {
                    Text("Trợ lý")
                }

                // 7. Gỡ lỗi
                Section {
                    NavigationLink(value: SettingsDestination.debug) {
                        HStack(spacing: 12) {
                            SettingsIconBadge(icon: "ladybug.fill", tint: Theme.warning)
                            Text("Gỡ lỗi & Log")
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text("\(AppLogStore.shared.entries.count) dòng")
                                .font(Theme.Typography.monoMetric)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .reybainSettingsRow()
                } header: {
                    Text("Chẩn đoán")
                }

                // 8. Giới thiệu
                Section {
                    HStack(spacing: 12) {
                        SettingsIconBadge(icon: "info.circle", tint: Theme.textSecondary)
                        Text("Phiên bản app")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text("\(Config.appVersion) (\(Config.buildNumber))")
                            .font(Theme.Typography.monoMetric)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .reybainSettingsRow()

                    HStack(spacing: 12) {
                        SettingsIconBadge(icon: "shippingbox", tint: Theme.textSecondary)
                        Text("Meta DAT SDK")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text("1.0.1")
                            .font(Theme.Typography.monoMetric)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .reybainSettingsRow()

                    HStack(spacing: 12) {
                        SettingsIconBadge(icon: "cpu", tint: Theme.iridescentCyan)
                        Text("Model Gemini")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text(GeminiLiveService.modelName)
                            .font(Theme.Typography.monoLog)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .reybainSettingsRow()

                    Link(destination: URL(string: "https://github.com/darwnlinz1/Visor-iOS-Solver")!) {
                        HStack(spacing: 12) {
                            SettingsIconBadge(icon: "link", tint: Theme.accent)
                            Text("Mã nguồn trên GitHub")
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(Theme.textTertiary)
                        }
                    }
                    .reybainSettingsRow()
                } header: {
                    Text("Giới thiệu")
                } footer: {
                    Text("Reybain là phần mềm mã nguồn mở (MIT) cho kính Ray-Ban Meta.")
                }
            }
            .reybainSettingsCanvas()
            .navigationTitle("Cài đặt")
            .toolbar(.hidden, for: .tabBar)
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

    // MARK: - Brand Hero Card

    private var brandHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.iridescentIndigo.opacity(0.30), Theme.iridescentCyan.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay(Circle().strokeBorder(Theme.specularRimGradient, lineWidth: 0.85))

                    SwirlMark(size: 30)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Reybain")
                            .font(Theme.Typography.screenTitle)
                            .foregroundColor(Theme.textPrimary)

                        Text("v\(Config.appVersion)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundColor(Theme.accentBright)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Theme.accentMuted)
                                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 0.7))
                            )
                    }

                    Text("Ray-Ban Meta × Google Gemini AI")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                heroStatusPill(
                    dotColor: glassesStatusTint,
                    text: "Kính: \(glassesStatusLabel)"
                )

                heroStatusPill(
                    dotColor: keyCount > 0 ? Theme.success : Theme.warning,
                    text: keyCount > 0 ? "Gemini · \(keyCount) key" : "Gemini · Chưa có key"
                )
            }
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: Theme.Radius.card, style: .tinted(Theme.iridescentIndigo))
    }

    private func heroStatusPill(dotColor: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6.5, height: 6.5)
                .shadow(color: dotColor.opacity(0.7), radius: 3)
            Text(text)
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7))
        )
    }

    private var glassesStatusLabel: String {
        if glassesManager.sdkUnavailableReason != nil { return "Lỗi SDK" }
        if glassesManager.connectedDevice != nil { return "Đã kết nối" }
        return glassesManager.isRegistered ? "Đã đăng ký" : "Chưa đăng ký"
    }

    private var glassesStatusTint: Color {
        if glassesManager.sdkUnavailableReason != nil { return Theme.danger }
        if glassesManager.connectedDevice != nil { return Theme.success }
        return glassesManager.isRegistered ? Theme.warning : Theme.inactive
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager.shared)
        .environmentObject(GlassesManager.shared)
        .environmentObject(AppRouter())
        .preferredColorScheme(.dark)
}
