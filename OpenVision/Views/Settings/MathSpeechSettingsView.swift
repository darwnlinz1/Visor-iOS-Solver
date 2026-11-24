// OpenVision - MathSpeechSettingsView.swift
// Vietnamese math reading configuration, Pronunciation Dictionary editor, and H13 Test Reader
// (PLAN.md §4.5, §4.6, §7 H13, T6.4).

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

                Picker("Phân số có chữ (a/b)", selection: $settingsManager.settings.symbolicFractionWord) {
                    Text("a trên b").tag("tren")
                    Text("a phần b").tag("phan")
                }

                Picker("Số âm (-3)", selection: $settingsManager.settings.negativeWord) {
                    Text("âm 3").tag("am")
                    Text("trừ 3").tag("tru")
                }

                Picker("Tên chữ cái biến", selection: $settingsManager.settings.letterStyle) {
                    Text("Tên tiếng Việt (ích, bê, xê…)").tag("vietnameseNames")
                    Text("Để nguyên chữ cái (x, b, c…)").tag("asWritten")
                }
            } header: {
                Text("Quy tắc đọc công thức")
            } footer: {
                Text("Áp dụng ngay cho mọi câu trả lời mới và khi đọc lại từ Lịch sử.")
            }

            Section {
                NavigationLink {
                    PronunciationDictionaryView()
                } label: {
                    HStack {
                        Label("Từ điển phát âm", systemImage: "character.book.closed")
                        Spacer()
                        Text("\(settingsManager.settings.pronunciationOverrides.count) tuỳ chỉnh")
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink {
                    MathSpeechTesterView()
                } label: {
                    Label("Thử đọc công thức (15 mẫu H13)", systemImage: "waveform")
                }
            } header: {
                Text("Tuỳ chỉnh & Kiểm tra")
            }
        }
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
                TextField("Cách đọc (ví dụ: cốt, ích, đen-ta)", text: $newSpoken)
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
                }
                .disabled(newToken.trimmingCharacters(in: .whitespaces).isEmpty || newSpoken.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Thêm ghi đè mới")
            } footer: {
                Text("Chỉ khớp theo token nguyên (ví dụ ghi đè \"sin\" không ảnh hưởng tới từ \"sinh\").")
            }

            Section {
                if sortedOverrideKeys.isEmpty {
                    Text("Chưa có ghi đè nào — đang dùng bảng phát âm chuẩn lớp học.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(sortedOverrideKeys, id: \.self) { key in
                        HStack {
                            Text(key)
                                .font(.body.monospaced())
                            Spacer()
                            Text(settingsManager.settings.pronunciationOverrides[key] ?? "")
                                .foregroundColor(Theme.accent)
                        }
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
                }
            }
        }
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

// MARK: - Test Reader (15 H13 Presets + Custom Formula Input)

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
                    .lineLimit(2...5)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Hiển thị: \(MathPrettyText.format(formulaInput))")
                        .font(.subheadline)
                        .foregroundColor(Theme.heading)

                    Text("Văn bản sẽ đọc:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(VietMathSpeech.spokenText(rendered.pieces))
                        .font(.callout.weight(.medium))
                        .foregroundColor(Theme.textPrimary)

                    if !rendered.warnings.isEmpty {
                        Text("Cảnh báo lệnh lạ: \(rendered.warnings.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(Theme.warning)
                    }
                }
                .padding(.vertical, 4)

                Button {
                    if ttsService.isSpeaking {
                        ttsService.stop()
                    } else {
                        speakCurrentFormula()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: ttsService.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                        Text(ttsService.isSpeaking ? "Dừng đọc" : "Nghe thử ngay")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .foregroundColor(ttsService.isSpeaking ? Theme.danger : Theme.accent)
                }
            } header: {
                Text("Thử đọc trực tiếp")
            }

            Section {
                ForEach(Self.presets, id: \.title) { preset in
                    Button {
                        formulaInput = preset.formula
                        speakCurrentFormula()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                            Text(MathPrettyText.format(preset.formula))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("15 mẫu chuẩn H13 + kiểm tra ngoặc âm")
            }
        }
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
