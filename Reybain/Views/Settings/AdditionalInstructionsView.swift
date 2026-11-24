// Reybain - AdditionalInstructionsView.swift
// Custom AI instructions editor styled with obsidian glass-bordered container & tabular counter.

import SwiftUI

struct AdditionalInstructionsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var instructions: String = ""

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.md) {
                TextEditor(text: $instructions)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.bgCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Theme.bgElevatedStroke, lineWidth: 0.9)
                            )
                    )
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)

                HStack {
                    Text("Nối vào system prompt của Gemini")
                        .font(.caption)
                        .foregroundColor(Theme.textTertiary)
                    Spacer()
                    Text("\(instructions.count) ký tự")
                        .font(Theme.Typography.monoMetric)
                        .foregroundColor(Theme.accentBright)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .liquidGlassPill(tint: Theme.accent)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle("Hướng dẫn riêng")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Lưu") {
                    HapticFeedback.success()
                    saveInstructions()
                    dismiss()
                }
                .fontWeight(.semibold)
                .foregroundColor(Theme.accentBright)
            }

            ToolbarItem(placement: .cancellationAction) {
                Button("Huỷ") {
                    dismiss()
                }
                .foregroundColor(Theme.textSecondary)
            }
        }
        .onAppear {
            instructions = settingsManager.settings.userPrompt
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Divider()
                    .overlay(Color.white.opacity(0.08))

                Text("Hướng dẫn này sẽ được nối vào system prompt của Gemini (ví dụ: trình độ lớp 12, phong cách trình bày, ngôn ngữ ưu tiên).")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, 10)
            }
            .background(Theme.bgSurface.opacity(0.96))
        }
    }

    private func saveInstructions() {
        settingsManager.settings.userPrompt = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsManager.saveNow()
    }
}

#Preview {
    NavigationStack {
        AdditionalInstructionsView()
            .environmentObject(SettingsManager.shared)
    }
    .preferredColorScheme(.dark)
}
