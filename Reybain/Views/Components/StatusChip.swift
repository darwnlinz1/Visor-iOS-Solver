// Reybain - StatusChip.swift
// Interactive Liquid Glass status chips for the top strip of the Live screen.

import SwiftUI

struct StatusChip: View {
    let icon: String
    let label: String
    let tint: Color
    var isEmphasized: Bool = false
    var accessibilityHintText: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    chipContent
                }
                .buttonStyle(.plain)
            } else {
                chipContent
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityHint(accessibilityHintText ?? "")
    }

    private var chipContent: some View {
        HStack(spacing: 6) {
            if isEmphasized {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .shadow(color: tint.opacity(0.65), radius: 3)
            }

            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(tint)

            Text(label)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .liquidGlassPill(
            tint: isEmphasized ? tint : nil,
            interactive: action != nil
        )
    }
}

#Preview {
    ZStack {
        AnimatedBackground()
        HStack(spacing: 8) {
            StatusChip(icon: "eyeglasses", label: "Kính: Đã kết nối", tint: Theme.success, isEmphasized: true)
            StatusChip(icon: "mic.fill", label: "Mic iPhone · Trên máy", tint: Theme.info)
            StatusChip(icon: "sparkles", label: "Gemini · 2 key", tint: Theme.accent)
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
