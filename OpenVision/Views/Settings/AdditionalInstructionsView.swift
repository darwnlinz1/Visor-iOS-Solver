// OpenVision - AdditionalInstructionsView.swift
// Custom AI instructions editor (100% Vietnamese UI).

import SwiftUI

struct AdditionalInstructionsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var instructions: String = ""

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $instructions)
                .padding()
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))

            HStack {
                Spacer()
                Text("\(instructions.count) ký tự")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Hướng dẫn riêng")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Lưu") {
                    saveInstructions()
                    dismiss()
                }
            }

            ToolbarItem(placement: .cancellationAction) {
                Button("Huỷ") {
                    dismiss()
                }
            }
        }
        .onAppear {
            instructions = settingsManager.settings.userPrompt
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Divider()

                Text("Hướng dẫn này sẽ được nối vào system prompt của Gemini (ví dụ: trình độ lớp 12, phong cách trình bày, ngôn ngữ ưu tiên).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .background(Color(.systemBackground))
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
