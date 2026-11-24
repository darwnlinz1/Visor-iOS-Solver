// Reybain - MathSpeechSettingsView.swift
// Vietnamese math reading configuration, Pronunciation Dictionary editor, and H13 Test Reader
// styled with OLED obsidian cards and elevated live LaTeX/spoken preview.

import SwiftUI

struct MathSpeechSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        Form {
            Section {
                Picker("Kiểu đọc toán", selection: $settingsManager.settings.mathVerbosity) {
                    Text("Tự nhiên (gọn)").tag("natural")
                    Text("Rõ ràng (đọc đóng/mở ngoặc, hết căn)").tag("explicit")
                }
                .reybainSettingsRow()

                Picker("Phân số có chữ (a/b)", selection: $settingsManager.settings.symbolicFractionWord) {
                    Text("a trên b").tag("tren")
                    Text("a phần b").tag("phan")
                }
                .reybainSettingsRow()

                Picker("Số âm (-3)", selection: $settingsManager.settings.negativeWord) {
                    Text("âm 3").tag("am")
                    Text("trừ 3").tag("tru")
                }
                .reybainSettingsRow()

                Picker("Tên chữ cái biến", selection: $settingsManager.settings.letterStyle) {
                    Text("Tên tiếng Việt (ích, bê, xê…)").tag("vietnameseNames")
                    Text("Để nguyên chữ cái (x, b, c…)").tag("asWritten")
                }
                .reybainSettingsRow()
            } header: {
                Text("Quy tắc đọc công thức")
            } footer: {
                Text("Áp dụng ngay cho mọi câu trả lời mới và khi đọc lại từ Lịch sử.")
            }

            Section {
                NavigationLink {
                    PronunciationDictionaryView()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconBadge(icon: "character.book.closed", tint: Theme.accentBright)
                        Text("Từ điển phát âm")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text("\(settingsManager.settings.pronunciationOverrides.count) tuỳ chỉnh")
                            .font(Theme.Typography.monoMetric)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()

                NavigationLink {
                    MathSpeechTesterView()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconBadge(icon: "waveform", tint: Theme.iridescentViolet)
                        Text("Thử đọc công thức (16 mẫu H13)")
                            .foregroundColor(Theme.textPrimary)
                    }
                }
                .reybainSettingsRow()
            } header: {
                Text("Tuỳ chỉnh & Kiểm tra")
            }
        }
        .reybainSettingsCanvas()
        .navigationTitle("Đọc toán tiếng Việt")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settingsManager.settings) { _, _ in
            ReadingEngine.shared.refreshConfigFromSettings()
        }
    }
}

// MARK: - Pronunciation Dictionary Editor

struct PronunciationDictionaryView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var newToken: String = ""
    @State private var newSpoken: String = ""
    @State private var showResetConfirm = false

    private var sortedOverrideKeys: [String] {
        settingsManager.settings.pronunciationOverrides.keys.sorted()
    }

    var body: some View {
        Form {
            Section {
                TextField("Ký hiệu / token (ví dụ: cos, x, \\Delta)", text: $newToken)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundColor(Theme.textPrimary)
                    .reybainSettingsRow()

                TextField("Cách đọc (ví dụ: cốt, ích, đen-ta)", text: $newSpoken)
                    .foregroundColor(Theme.textPrimary)
                    .reybainSettingsRow()

                Button {
                    let key = PronunciationDictionary.normalizedKey(newToken)
                    let val = newSpoken.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty, !val.isEmpty else { return }
                    settingsManager.settings.pronunciationOverrides[key] = val
                    ReadingEngine.shared.refreshConfigFromSettings()
                    newToken = ""
                    newSpoken = ""
                    HapticFeedback.success()
                } label: {
                    Label("Thêm vào từ điển", systemImage: "plus.circle.fill")
                        .foregroundColor(Theme.accentBright)
                }
                .disabled(newToken.trimmingCharacters(in: .whitespaces).isEmpty || newSpoken.trimmingCharacters(in: .whitespaces).isEmpty)
                .reybainSettingsRow()
            } header: {
                Text("Thêm ghi đè mới")
            } footer: {
                Text("Chỉ khớp theo token nguyên (ví dụ ghi đè \"sin\" không ảnh hưởng tới từ \"sinh\").")
            }

            Section {
                if sortedOverrideKeys.isEmpty {
                    Text("Chưa có ghi đè nào — đang dùng bảng phát âm chuẩn lớp học.")
                        .font(.footnote)
                        .foregroundColor(Theme.textSecondary)
                        .reybainSettingsRow()
                } else {
                    ForEach(sortedOverrideKeys, id: \.self) { key in
                        HStack {
                            Text(key)
                                .font(.body.monospaced())
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text(settingsManager.settings.pronunciationOverrides[key] ?? "")
                                .foregroundColor(Theme.accentBright)
                        }
                        .reybainSettingsRow()
                    }
                    .onDelete { offsets in
                        let keysToRemove = offsets.map { sortedOverrideKeys[$0] }
                        for key in keysToRemove {
                            settingsManager.settings.pronunciationOverrides.removeValue(forKey: key)
                        }
                        ReadingEngine.shared.refreshConfigFromSettings()
                    }
                }
            } header: {
                Text("Mục đã tuỳ chỉnh (\(sortedOverrideKeys.count))")
            }

            if !sortedOverrideKeys.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("Khôi phục từ điển mặc định", systemImage: "arrow.counterclockwise")
                    }
                    .reybainSettingsRow()
                }
            }
        }
        .reybainSettingsCanvas()
        .navigationTitle("Từ điển phát âm")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Khôi phục mặc định?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Xoá mọi tuỳ chỉnh", role: .destructive) {
                settingsManager.settings.pronunciationOverrides = [:]
            }
            Button("Huỷ", role: .cancel) {}
        }
    }
}

// MARK: - Test Reader (16 H13 Presets + Custom Formula Input)

struct MathSpeechTesterView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @ObservedObject private var ttsService = TTSService.shared
    @State private var formulaInput: String = "$x^2 - 5x + 6 = 0$"

    private static let presets: [(title: String, formula: String)] = [
        ("1. Phương trình bậc 2", "$x^2 - 5x + 6 = 0$"),
        ("2. Phân số số", #"$\frac{3}{4}$"#),
        ("3. Căn thức biểu thức", #"$\sqrt{x^2+1}$"#),
        ("4. Tích phân xác định", #"$\int_0^1 x e^x\,dx$"#),
        ("5. Giới hạn", #"$\lim_{x \to 0} \frac{\sin x}{x} = 1$"#),
        ("6. Lô-ga-rít", #"$\log_2 8 = 3$"#),
        ("7. Đạo hàm", "$f'(x) = 3x^2 - 3$"),
        ("8. Véc-tơ vuông góc", #"$\overrightarrow{AB} \perp \overrightarrow{CD}$"#),
        ("9. Đoạn số", #"$x \in [1; 3]$"#),
        ("10. Biệt thức Delta", #"$\Delta = b^2 - 4ac$"#),
        ("11. Thập phân & đơn vị", "2,5 cm"),
        ("12. Ngoặc bình phương", "$(x+1)^2$"),
        ("13. Hệ phương trình", #"$\begin{cases} x+y=3 \\ x-y=1 \end{cases}$"#),
        ("14. Tổ hợp", "$C_5^2 = 10$"),
        ("15. Bất đẳng thức & số âm", #"$-3 < x \le 2$"#),
        ("16. Phân biệt (-5)² và -5²", "$(-5)^2 = 25$ còn $-5^2 = -25$"),
    ]

    private var rendered: VietMathSpeech.Rendering {
        VietMathSpeech.renderWithDiagnostics(
            formulaInput,
            vietnamese: true,
            style: settingsManager.settings.mathReadingStyle
        )
    }

    var body: some View {
        Form {
            Section {
                TextField("Nhập công thức LaTeX hoặc lời văn…", text: $formulaInput, axis: .vertical)
                    .font(.body.monospaced())
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2...5)
                    .reybainSettingsRow()

                // Live pretty-math + Vietnamese spoken preview card
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("HIỂN THỊ")
                            .font(Theme.Typography.badge)
                            .tracking(0.6)
                            .foregroundColor(Theme.accentBright)
                        Text(MathPrettyText.format(formulaInput))
                            .font(Theme.Typography.math)
                            .foregroundColor(Theme.heading)
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("VĂN BẢN SẼ ĐỌC")
                            .font(Theme.Typography.badge)
                            .tracking(0.6)
                            .foregroundColor(Theme.textSecondary)
                        Text(VietMathSpeech.spokenText(rendered.pieces))
                            .font(.callout.weight(.medium))
                            .foregroundColor(Theme.textPrimary)
                            .lineSpacing(3)
                    }

                    if !rendered.warnings.isEmpty {
                        Text("Cảnh báo lệnh lạ: \(rendered.warnings.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(Theme.warning)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.bgCardHighlight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 0.9)
                        )
                )
                .padding(.vertical, 4)
                .reybainSettingsRow()

                Button {
                    HapticFeedback.light()
                    if ttsService.isSpeaking {
                        ttsService.stop()
                    } else {
                        speakCurrentFormula()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Spacer()
                        Image(systemName: ttsService.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                        Text(ttsService.isSpeaking ? "Dừng đọc" : "Nghe thử ngay")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundColor(ttsService.isSpeaking ? Theme.danger : Theme.ctaForeground)
                    .padding(.vertical, 11)
                    .background {
                        if ttsService.isSpeaking {
                            Capsule()
                                .fill(Theme.danger.opacity(0.18))
                                .overlay(Capsule().strokeBorder(Theme.danger.opacity(0.45), lineWidth: 0.8))
                        } else {
                            Capsule().fill(Theme.buttonGradient)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .reybainSettingsRow()
            } header: {
                Text("Thử đọc trực tiếp")
            }

            Section {
                ForEach(Self.presets, id: \.title) { preset in
                    Button {
                        HapticFeedback.light()
                        formulaInput = preset.formula
                        speakCurrentFormula()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Theme.textPrimary)
                            Text(MathPrettyText.format(preset.formula))
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .reybainSettingsRow()
                }
            } header: {
                Text("16 mẫu chuẩn H13 + kiểm tra ngoặc âm")
            }
        }
        .reybainSettingsCanvas()
        .navigationTitle("Thử đọc công thức")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if ttsService.isSpeaking && !ReadingEngine.shared.isActive {
                ttsService.stop()
            }
        }
    }

    private func speakCurrentFormula() {
        let text = formulaInput
        Task { @MainActor in
            await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                preferGlasses: settingsManager.settings.preferGlassesMic
            )
            ttsService.speak(text, languageCode: "vi")
        }
    }
}

#Preview {
    NavigationStack {
        MathSpeechSettingsView()
            .environmentObject(SettingsManager.shared)
    }
    .preferredColorScheme(.dark)
}
