// OpenVision - TranscriptBubble.swift
// Emerald-themed transcript bubbles and typing indicator (iOS 17+ onChange fixed, Vietnamese labels).

import SwiftUI

/// Animated typing indicator (three pulsing emerald dots).
struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 7, height: 7)
                    .opacity(animating ? 1.0 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.18),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Theme.glass)
                .overlay(Capsule().stroke(Theme.bgElevatedStroke, lineWidth: 1))
        )
        .onAppear { animating = true }
    }
}

/// One transcript bubble.
struct TranscriptBubble: View {
    let text: String
    let isUser: Bool
    let isStreaming: Bool
    var photoData: Data? = nil
    var onTapPhoto: ((Data) -> Void)? = nil

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                Text(isUser ? "Bạn" : "Vision")
                    .font(Theme.Typography.badge)
                    .foregroundColor(isUser ? Theme.accent.opacity(0.9) : Theme.heading.opacity(0.85))
                    .textCase(.uppercase)
                    .tracking(1.0)

                if isUser, let photoData, let uiImage = UIImage(data: photoData) {
                    Button {
                        onTapPhoto?(photoData)
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 190, maxHeight: 135)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                                    .stroke(Theme.accent.opacity(0.45), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Xem ảnh đã đính kèm")
                }

                if !text.isEmpty {
                    Text(isUser ? text : MathPrettyText.format(text))
                        .font(Theme.Typography.body)
                        .foregroundColor(isUser ? Color.black.opacity(0.92) : Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(bubbleBackground)
                }
            }

            if !isUser { Spacer(minLength: 32) }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.buttonGradient)
                .shadow(color: Theme.accent.opacity(0.28), radius: 10, y: 2)
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.bgCard.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Theme.accent.opacity(0.32), Theme.bgElevatedStroke],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        }
    }
}

/// Compact transcript pair (retained for previews and legacy callers).
struct TranscriptView: View {
    let userText: String
    let aiText: String
    let isAIStreaming: Bool
    var userPhotoData: Data? = nil
    var onDetachPhoto: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            if userText.isEmpty, let photoData = userPhotoData, let uiImage = UIImage(data: photoData) {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.success).frame(width: 8, height: 8)
                            Text("Ảnh kính đã đính kèm")
                                .font(Theme.Typography.badge)
                                .foregroundColor(Theme.accent)
                            if let onDetach = onDetachPhoto {
                                Button(action: onDetach) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                .accessibilityLabel("Gỡ ảnh đính kèm")
                            }
                        }
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 180, maxHeight: 130)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 1.5))
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Theme.bgElevated.opacity(0.92))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.accent.opacity(0.3), lineWidth: 1))
                    )
                }
            }

            if !userText.isEmpty {
                TranscriptBubble(text: userText, isUser: true, isStreaming: false, photoData: userPhotoData)
            }

            if !aiText.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        TranscriptBubble(text: aiText, isUser: false, isStreaming: isAIStreaming)
                            .id("reply")
                    }
                    .frame(maxHeight: 200)
                    .fixedSize(horizontal: false, vertical: aiText.count < 220)
                    .onChange(of: aiText) { _, _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("reply", anchor: .bottom)
                        }
                    }
                }
            } else if isAIStreaming {
                HStack {
                    TypingIndicator()
                    Spacer()
                }
            }
        }
    }
}

/// Tool status indicator
struct ToolStatusView: View {
    let toolName: String
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.subheadline)
                .foregroundColor(Theme.accent)

            Text(toolName)
                .font(.subheadline.weight(.medium))

            if isRunning {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(Theme.accent)
            }
        }
        .foregroundColor(Theme.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Theme.accent.opacity(0.15))
                .overlay(Capsule().stroke(Theme.accent.opacity(0.4), lineWidth: 1))
        )
    }
}

#Preview {
    ZStack {
        Theme.bg.ignoresSafeArea()
        VStack(spacing: 20) {
            TranscriptView(
                userText: "Giải phương trình x^2 - 5x + 6 = 0",
                aiText: "Dòng 1: Ta có $\\Delta = (-5)^2 - 4 \\cdot 6 = 1$.",
                isAIStreaming: false
            )
            TypingIndicator()
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
