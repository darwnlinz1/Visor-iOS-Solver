// Reybain - WorkflowModeSettingsView.swift
// Operating mode settings: Study vs. General mode selector cards, Study prompt presets,
// Direct Audio-to-Gemini toggle, active button summary, and Ray-Ban music coexistence.

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
            audioAndCoexistenceSection
        }
        .reybainSettingsCanvas()
        .navigationTitle("Chế độ sử dụng")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var modeSelectionSection: some View {
        Section {
            ForEach(UsageMode.allCases) { mode in
                let isSelected = selectedMode == mode
                Button {
                    HapticFeedback.selection()
                    withAnimation(Theme.Motion.snappy) {
                        settingsManager.settings.usageMode = mode
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        SettingsIconBadge(
                            icon: mode.systemImage,
                            tint: isSelected ? Theme.accent : Theme.textSecondary
                        )
                        .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.displayName)
                                .font(.headline)
                                .foregroundColor(Theme.textPrimary)
                            Text(mode.summary)
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(isSelected ? Theme.accent : Theme.textTertiary)
                            .padding(.top, 2)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSelected ? Theme.bgCardHighlight : Theme.bgCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Theme.accent : Theme.bgElevatedStroke,
                                        lineWidth: isSelected ? 1.25 : 0.8
                                    )
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
            .foregroundColor(Theme.textPrimary)
            .lineLimit(2...4)
            .reybainSettingsRow()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(UsageMode.studyPromptPresets, id: \.self) { preset in
                        let isSelected = effectiveStudyPrompt == preset
                        Button {
                            HapticFeedback.light()
                            settingsManager.settings.studySolvePrompt = preset
                        } label: {
                            Text(preset)
                                .font(.caption.weight(isSelected ? .semibold : .medium))
                                .lineLimit(1)
                                .foregroundColor(isSelected ? Theme.accentBright : Theme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .liquidGlassPill(tint: isSelected ? Theme.accent : nil, interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .reybainSettingsRow()

            if !settingsManager.settings.studySolvePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Khôi phục prompt mặc định") {
                    settingsManager.settings.studySolvePrompt = ""
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.accentBright)
                .reybainSettingsRow()
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
                HStack(spacing: 12) {
                    SettingsIconBadge(icon: "eyeglasses", tint: Theme.accent)
                    Text("Cài đặt kết nối & tùy chỉnh nút kính")
                        .foregroundColor(Theme.textPrimary)
                }
            }
            .reybainSettingsRow()
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

    private var audioAndCoexistenceSection: some View {
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

            Toggle(isOn: $settingsManager.settings.spokenStatusUpdates) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Thông báo tiến trình qua loa kính")
                        .foregroundColor(Theme.textPrimary)
                    Text("Đọc ngắn khi chụp xong, đang tải lên 50%, chờ AI, lỗi 503/429 đổi key hoặc hạ model")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .reybainSettingsRow()

            Toggle(isOn: $settingsManager.settings.pauseWakeWordDuringMusic) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Không giữ mic kính khi đang nghe nhạc")
                        .foregroundColor(Theme.textPrimary)
                    Text("Giữ âm thanh nhạc A2DP và tránh tiếng bíp khi bấm dừng/phát nhạc trên kính")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .reybainSettingsRow()
        } header: {
            Text("Âm thanh & Thông báo trên kính")
        } footer: {
            Text("Mọi trạng thái trên màn hình điện thoại (chụp xong, upload, đổi API key, AI phản hồi) đều được đọc gọn qua loa kính. Khi đang nghe nhạc, app nhả mic HFP lúc rảnh để không phát tiếng bíp.")
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
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Text(action.displayName)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .reybainSettingsRow()
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
