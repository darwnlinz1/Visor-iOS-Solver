// Reybain - ConversationListView.swift
// iOS 26 Liquid Glass "Lịch sử" screen & editorial ConversationDetailView:
// Obsidian aurora canvas, elevated glass cards with swipe-to-delete, offline SegmentCardView replay,
// floating PlaybackBar, and "Tiếp tục hội thoại" using v2.1 seedHistory.

import SwiftUI
import UIKit

struct ConversationListView: View {
    // MARK: - Environment

    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var router: AppRouter

    @ObservedObject private var conversationManager = ConversationManager.shared

    // MARK: - State

    @State private var searchText: String = ""

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground()

                Group {
                    if conversationManager.conversations.isEmpty {
                        emptyState
                    } else {
                        conversationList
                    }
                }
            }
            .navigationTitle("Lịch sử")
            .searchable(text: $searchText, prompt: "Tìm kiếm hội thoại")
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        HapticFeedback.light()
                        conversationManager.startNewConversation()
                        GeminiLiveService.shared.clearConversationHistory()
                        router.openLive()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundColor(Theme.accentBright)
                            .frame(width: 34, height: 34)
                            .liquidGlassPill(interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cuộc hội thoại mới")
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.iridescentIndigo.opacity(0.28),
                                Theme.iridescentCyan.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.specularRimGradient, lineWidth: 0.9)
                    )

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.intelligenceLinear)
            }

            VStack(spacing: 6) {
                Text("Chưa có hội thoại nào")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)

                Text("Hỏi Reybain trên màn hình Trực tiếp để xem lại và nghe lại lời giải tại đây.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Button {
                HapticFeedback.medium()
                router.openLive()
            } label: {
                Label("Bắt đầu hỏi ngay", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.accentBright)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .liquidGlassPill(tint: Theme.accent, interactive: true)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        List {
            ForEach(filteredConversations) { conversation in
                ZStack {
                    NavigationLink {
                        ConversationDetailView(conversation: conversation)
                    } label: {
                        EmptyView()
                    }
                    .opacity(0)

                    ConversationRow(conversation: conversation)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .onDelete(perform: deleteConversations)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var filteredConversations: [Conversation] {
        conversationManager.search(searchText)
    }

    private func deleteConversations(at offsets: IndexSet) {
        let targets = offsets.map { filteredConversations[$0] }
        for conversation in targets {
            conversationManager.deleteConversation(conversation)
        }
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(conversation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(conversation.lastActivityAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Theme.textTertiary)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Theme.textTertiary)
            }

            if let lastMessage = conversation.messages.last {
                Text(MathPrettyText.format(lastMessage.content))
                    .font(.footnote)
                    .foregroundColor(Theme.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                metaPill(
                    icon: "bubble.left",
                    text: "\(conversation.messages.count) tin",
                    tint: Theme.textSecondary
                )

                if conversation.hasPhotos {
                    metaPill(icon: "photo", text: "Có ảnh", tint: Theme.accent)
                }

                if conversation.messages.contains(where: { $0.reading != nil }) {
                    metaPill(icon: "speaker.wave.2", text: "Nghe lại được", tint: Theme.info)
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 18, style: .surface)
    }

    private func metaPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption2.monospacedDigit().weight(.medium))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(tint.opacity(0.12))
                .overlay(Capsule().strokeBorder(tint.opacity(0.24), lineWidth: 0.6))
        )
    }
}

// MARK: - Conversation Detail View

private struct HistoryPhotoPreview: Identifiable {
    let id = UUID()
    let data: Data
}

struct ConversationDetailView: View {
    let initialConversation: Conversation
    @EnvironmentObject var router: AppRouter
    @ObservedObject private var conversationManager = ConversationManager.shared
    @ObservedObject private var readingEngine = ReadingEngine.shared
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var resumed = false
    @State private var previewPhoto: HistoryPhotoPreview?

    init(conversation: Conversation) {
        self.initialConversation = conversation
    }

    private var conversation: Conversation {
        conversationManager.conversations.first(where: { $0.id == initialConversation.id }) ?? initialConversation
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        ForEach(conversation.messages) { message in
                            HistoryMessageItem(
                                message: message,
                                readingEngine: readingEngine,
                                readLineNumbers: settingsManager.settings.readLineNumbers,
                                onTapPhoto: { data in
                                    previewPhoto = HistoryPhotoPreview(data: data)
                                }
                            )
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }

                if readingEngine.plan != nil {
                    PlaybackBar(engine: readingEngine, settingsManager: settingsManager)
                        .padding(.horizontal, 14)
                        .padding(.bottom, Theme.Spacing.sm)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(Theme.Motion.snappy, value: readingEngine.plan == nil)
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $previewPhoto) { item in
            NavigationStack {
                ZStack {
                    Theme.bg.ignoresSafeArea()
                    if let uiImage = UIImage(data: item.data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                }
                .navigationTitle("Ảnh đề bài")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Đóng") { previewPhoto = nil }
                            .foregroundColor(Theme.accentBright)
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    HapticFeedback.success()
                    ConversationManager.shared.resumeConversation(conversation)
                    let seedMessages = conversation.messages.filter { $0.role == .user || $0.role == .assistant }
                    GeminiLiveService.shared.seedHistory(
                        from: seedMessages.map {
                            (isUser: $0.role == .user, text: $0.content, reading: $0.reading)
                        }
                    )
                    resumed = true
                    router.openLive()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: resumed ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                            .font(.caption.weight(.bold))
                        Text(resumed ? "Đã mở" : "Tiếp tục")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(resumed ? Theme.success : Theme.ctaForeground)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background {
                        if resumed {
                            Capsule()
                                .fill(Theme.success.opacity(0.18))
                                .overlay(Capsule().strokeBorder(Theme.success.opacity(0.45), lineWidth: 0.8))
                        } else {
                            Capsule().fill(Theme.buttonGradient)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(resumed)
            }
        }
    }
}

// MARK: - History Message Item

private struct HistoryMessageItem: View {
    let message: Message
    @ObservedObject var readingEngine: ReadingEngine
    let readLineNumbers: Bool
    var onTapPhoto: ((Data) -> Void)? = nil

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            if message.role == .user {
                TranscriptBubble(
                    text: message.content,
                    isUser: true,
                    isStreaming: false,
                    photoData: message.photoData,
                    onTapPhoto: onTapPhoto
                )
            } else if let record = message.reading, !record.segments.isEmpty {
                let isCurrent = readingEngine.plan?.record == record
                SegmentCardView(
                    record: record,
                    cardID: "\(message.id.uuidString)-",
                    activeSegmentIndex: isCurrent ? readingEngine.currentSegmentIndex : nil,
                    activeSpokenPiece: isCurrent ? readingEngine.currentPieceText : nil,
                    activeWordRange: isCurrent ? readingEngine.currentWordRange : nil,
                    isReadingActive: isCurrent && readingEngine.state == .reading,
                    onSelectSegment: { index in
                        HapticFeedback.light()
                        if isCurrent {
                            readingEngine.jump(to: index)
                        } else {
                            readingEngine.replay(record: record, startingAt: index)
                        }
                    },
                    onReplay: {
                        HapticFeedback.light()
                        readingEngine.replay(record: record)
                    }
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    TranscriptBubble(text: message.content, isUser: false, isStreaming: false)
                    Button {
                        HapticFeedback.light()
                        let parsed = AnswerFormat.parse(message.content)
                        let lang = TTSService.containsVietnamese(message.content) ? "vi" : "en"
                        let record = ReplyAssembler(languageCode: lang, readLineNumbers: readLineNumbers).record(for: parsed)
                        readingEngine.replay(record: record)
                    } label: {
                        Label("Đọc lại", systemImage: "speaker.wave.2.fill")
                            .font(Theme.Typography.badge)
                            .foregroundColor(Theme.accentBright)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .liquidGlassPill(tint: Theme.accent, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption2.monospacedDigit())
                .foregroundColor(Theme.textTertiary)
        }
    }
}

#Preview {
    ConversationListView()
        .environmentObject(SettingsManager.shared)
        .environmentObject(AppRouter())
        .preferredColorScheme(.dark)
}
