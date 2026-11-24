// Reybain - TranscriptBubble.swift
// Editorial obsidian & Liquid Glass chat bubbles, voice-note badge, and iridescent typing indicator.

import SwiftUI

/// Animated typing indicator (three pulsing Apple Intelligence iridescent dots).
struct TypingIndicator: View {
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let dotColors: [Color] = [
        Theme.iridescentCyan,
        Theme.iridescentIndigo,
        Theme.iridescentViolet
    ]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(dotColors[index])
                    .frame(width: 6.5, height: 6.5)
                    .scaleEffect(reduceMotion ? 1.0 : (animating ? 1.15 : 0.78))
                    .opacity(reduceMotion ? 0.85 : (animating ? 1.0 : 0.30))
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.16),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .liquidGlassPill()
        .onAppear { animating = true }
    }
}

/// One editorial transcript bubble (`BẠN` or `REYBAIN`).
struct TranscriptBubble: View {
    let text: String
    let isUser: Bool
    let isStreaming: Bool
    var photoData: Data? = nil
    var onTapPhoto: ((Data) -> Void)? = nil

    private var isVoiceNoteMessage: Bool {
        isUser && text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("🎙")
    }

    private var cleanVoiceNoteLabel: String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "🎙", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 44) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                senderHeader

                if isUser, let photoData, let uiImage = UIImage(data: photoData) {
                    Button {
                        onTapPhoto?(photoData)
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 200, maxHeight: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Theme.specularRimGradient, lineWidth: 0.85)
                            )
                            .shadow(color: Color.black.opacity(0.35), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Xem ảnh đã đính kèm")
                }

                if !text.isEmpty {
                    Group {
                        if isVoiceNoteMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.intelligenceLinear)
                                    .frame(width: 26, height: 26)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(0.10))
                                    )

                                Text(cleanVoiceNoteLabel.isEmpty ? "Tin nhắn thoại" : cleanVoiceNoteLabel)
                                    .font(.subheadline.weight(.medium).monospacedDigit())
                                    .foregroundColor(Theme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                        } else {
                            Text(isUser ? text : MathPrettyText.format(text))
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.textPrimary)
                                .lineSpacing(isUser ? 3 : 3.5)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 11)
                        }
                    }
                    .background(bubbleBackground)
                }
            }

            if !isUser { Spacer(minLength: 28) }
        }
    }

    @ViewBuilder
    private var senderHeader: some View {
        HStack(spacing: 5) {
            if !isUser {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.accent)
            }
            Text(isUser ? "Bạn" : "Reybain")
                .font(Theme.Typography.badge)
                .foregroundColor(isUser ? Theme.accentBright : Theme.heading.opacity(0.9))
                .textCase(.uppercase)
                .tracking(0.8)
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if isUser {
            shape
                .fill(Theme.userBubbleGradient)
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Theme.accentBright.opacity(0.42),
                                Theme.iridescentIndigo.opacity(0.24),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
                )
                .shadow(color: Theme.iridescentIndigo.opacity(0.22), radius: 12, y: 4)
        } else {
            shape
                .fill(Theme.bgCard.opacity(0.95))
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
                )
                .shadow(color: Color.black.opacity(0.32), radius: 12, y: 5)
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
                            Circle().fill(Theme.success).frame(width: 7, height: 7)
                            Text("Ảnh kính đã đính kèm")
                                .font(Theme.Typography.badge)
                                .foregroundColor(Theme.accentBright)
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
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Theme.specularRimGradient, lineWidth: 0.85)
                            )
                    }
                    .padding(10)
                    .liquidGlassCard(cornerRadius: 20, style: .surface)
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
                .foregroundColor(Theme.textPrimary)

            if isRunning {
                ProgressView()
                    .scaleEffect(0.75)
                    .tint(Theme.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .liquidGlassPill(tint: Theme.accent)
    }
}

#Preview {
    ZStack {
        AnimatedBackground()
        VStack(spacing: 20) {
            TranscriptBubble(text: "🎙 Tin nhắn thoại · 0:07", isUser: true, isStreaming: false)
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
