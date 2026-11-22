// OpenVision - StatusChip.swift
// Interactive status chips for the top strip of the Live screen (PLAN.md §4.5, T6.1).

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
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(tint)

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isEmphasized ? tint.opacity(0.16) : Theme.bgElevated.opacity(0.9))
                .overlay(
                    Capsule()
                        .stroke(isEmphasized ? tint.opacity(0.55) : Theme.bgElevatedStroke, lineWidth: 1)
                )
        )
    }
}

#Preview {
    ZStack {
        Theme.bg.ignoresSafeArea()
        HStack {
            StatusChip(icon: "eyeglasses", label: "Kính: Đã kết nối", tint: Theme.success, isEmphasized: true)
            StatusChip(icon: "mic.fill", label: "iPhone · Trên máy", tint: Theme.info)
            StatusChip(icon: "sparkles", label: "2 key", tint: Theme.accent)
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
