// OpenVision - WorkflowModeSettingsView.swift
// Operating mode settings: Study (auto short solve prompt on button press) vs. General (capture + free-form voice),
// configurable Study solve prompt, active button summary, and Ray-Ban music coexistence toggle.

import SwiftUI

struct WorkflowModeSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    private var selectedMode: UsageMode {
        settingsManager.settings.usageMode
    }

    var body: some View {
        Form {
            modeSelectionSection
            studyPromptSection
            activeButtonSummarySection
            musicCoexistenceSection
        }
        .navigationTitle("Chế độ sử dụng")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var modeSelectionSection: some View {
        Section {
            ForEach(UsageMode.allCases) { mode in
                Button {
                    HapticFeedback.light()
                    settingsManager.settings.usageMode = mode
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: mode.systemImage)
                            .font(.title3)
                            .foregroundColor(selectedMode == mode ? Theme.accent : .secondary)
                            .frame(width: 28, alignment: .center)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.displayName)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(mode.summary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        if selectedMode == mode {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(Theme.accent)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Chọn chế độ hoạt động")
        } footer: {
            Text("Chuyển nhanh bất cứ lúc nào giữa Giải bài tập và Sử dụng bình thường mà không cần khởi động lại ứng dụng.")
        }
    }

    private var studyPromptSection: some View {
        Section {
            TextField(
                "Giải bài trong ảnh này.",
                text: $settingsManager.settings.studySolvePrompt,
                axis: .vertical
            )
            .lineLimit(2...4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(UsageMode.studyPromptPresets, id: \.self) { preset in
                        let isSelected = effectiveStudyPrompt == preset
                        Button {
                            HapticFeedback.light()
                            settingsManager.settings.studySolvePrompt = preset
                        } label: {
                            Text(preset)
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(isSelected ? Theme.accent.opacity(0.22) : Color.secondary.opacity(0.16))
                                )
                                .overlay(
                                    Capsule().stroke(isSelected ? Theme.accent : Color.clear, lineWidth: 1)
                                )
                                .foregroundColor(isSelected ? Theme.accent : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            if !settingsManager.settings.studySolvePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Khôi phục prompt mặc định") {
                    settingsManager.settings.studySolvePrompt = ""
                }
                .font(.caption)
                .foregroundColor(Theme.accent)
            }
        } header: {
            Text("Prompt ngắn cho chế độ Giải bài tập")
        } footer: {
            if selectedMode == .study {
                Text("Đang dùng prompt: \"\(effectiveStudyPrompt)\". Khi nhấn 1 lần nút kính, ảnh sẽ được gửi ngay kèm câu lệnh này.")
            } else {
                Text("Ở chế độ Sử dụng bình thường, prompt này không tự gửi — sau khi nhấn nút chụp, app mở mic để bạn đọc lệnh tự do.")
            }
        }
    }

    private var activeButtonSummarySection: some View {
        Section {
            buttonSummaryRow(
                title: "Nhấn 1 lần (Capture / Action)",
                action: GlassesWorkflowPolicy.action(for: .shortPress, settings: settingsManager.settings)
            )
            buttonSummaryRow(
                title: "Nhấn 2 lần",
                action: GlassesWorkflowPolicy.action(for: .doublePress, settings: settingsManager.settings)
            )
            buttonSummaryRow(
                title: "Giữ nút",
                action: GlassesWorkflowPolicy.action(for: .hold, settings: settingsManager.settings)
            )

            NavigationLink {
                GlassesSettingsView()
            } label: {
                Label("Cài đặt kết nối & tùy chỉnh nút kính", systemImage: "eyeglasses")
            }
        } header: {
            Text("Thao tác nút trên kính hiện tại")
        } footer: {
            if settingsManager.settings.useCustomButtonMapping {
                Text("Bạn đang bật tùy chỉnh nút riêng trong mục Kính Ray-Ban Meta (ghi đè preset theo chế độ).")
            } else {
                Text("Tự động cập nhật theo chế độ \"\(selectedMode.displayName)\".")
            }
        }
    }

    private var musicCoexistenceSection: some View {
        Section {
            Toggle(isOn: $settingsManager.settings.pauseWakeWordDuringMusic) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Không giữ mic kính khi đang nghe nhạc")
                    Text("Giữ âm thanh nhạc A2DP và tránh tiếng bíp khi bấm dừng/phát nhạc trên kính")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Âm thanh & Nghe nhạc trên kính")
        } footer: {
            Text("Khi bật, lúc nhạc đang phát app sẽ nhả kênh mic Bluetooth HFP lúc rảnh. Bạn vẫn nhấn 1 lần nút kính để giải bài / hỏi, và nhấn 2 lần để đọc lại câu trả lời cũ bình thường.")
        }
    }

    // MARK: - Helpers

    private var effectiveStudyPrompt: String {
        UsageMode.resolvedSolvePrompt(
            customPrompt: settingsManager.settings.studySolvePrompt,
            speaksVietnamese: true
        )
    }

    private func buttonSummaryRow(title: String, action: GlassesButtonAction) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(action.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationStack {
        WorkflowModeSettingsView()
            .environmentObject(SettingsManager.shared)
            .environmentObject(GlassesManager.shared)
    }
    .preferredColorScheme(.dark)
}
