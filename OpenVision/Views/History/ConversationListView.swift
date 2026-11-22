// OpenVision - ConversationListView.swift
// Redesigned "Lịch sử" screen (PLAN.md §4.5, T5.5, T6.3):
// 100% Vietnamese UI, structured SegmentCardView rendering, offline "Đọc lại" via ReadingEngine,
// and "Tiếp tục hội thoại" using v2.1 seedHistory.

import SwiftUI

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
            Group {
                if conversationManager.conversations.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .navigationTitle("Lịch sử")
            .searchable(text: $searchText, prompt: "Tìm kiếm hội thoại")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        HapticFeedback.light()
                        conversationManager.startNewConversation()
                        GeminiLiveService.shared.clearConversationHistory()
                        router.openLive()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Cuộc hội thoại mới")
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundColor(Theme.accent.opacity(0.7))

            Text("Chưa có hội thoại nào")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)

            Text("Hỏi bài trên màn hình Trực tiếp để xem lại và nghe lại lời giải tại đây.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        List {
            ForEach(filteredConversations) { conversation in
                NavigationLink {
                    ConversationDetailView(conversation: conversation)
                } label: {
                    ConversationRow(conversation: conversation)
                }
            }
            .onDelete(perform: deleteConversations)
        }
        .listStyle(.plain)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(conversation.lastActivityAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let lastMessage = conversation.messages.last {
                Text(MathPrettyText.format(lastMessage.content))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Label("\(conversation.messages.count) tin", systemImage: "bubble.left")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if conversation.hasPhotos {
                    Label("Có ảnh", systemImage: "photo")
                        .font(.caption)
                        .foregroundColor(Theme.accent)
                }

                if conversation.messages.contains(where: { $0.reading != nil }) {
                    Label("Nghe lại được", systemImage: "speaker.wave.2")
                        .font(.caption)
                        .foregroundColor(Theme.info)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Conversation Detail View

struct ConversationDetailView: View {
    let conversation: Conversation
    @EnvironmentObject var router: AppRouter
    @ObservedObject private var readingEngine = ReadingEngine.shared
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var resumed = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.md) {
                    ForEach(conversation.messages) { message in
                        HistoryMessageItem(message: message, readingEngine: readingEngine)
                    }
                }
                .padding()
            }

            if readingEngine.plan != nil {
                PlaybackBar(engine: readingEngine, settingsManager: settingsManager)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    HapticFeedback.success()
                    ConversationManager.shared.resumeConversation(conversation)
                    GeminiLiveService.shared.seedHistory(
                        from: conversation.messages.map {
                            (isUser: $0.role == .user, text: $0.content, reading: $0.reading)
                        }
                    )
                    resumed = true
                    router.openLive()
                } label: {
                    Label(resumed ? "Đã mở" : "Tiếp tục", systemImage: resumed ? "checkmark.circle" : "arrow.right.circle")
                }
                .disabled(resumed)
            }
        }
    }
}

// MARK: - History Message Item

private struct HistoryMessageItem: View {
    let message: Message
    @ObservedObject var readingEngine: ReadingEngine

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            if message.role == .user {
                TranscriptBubble(
                    text: message.content,
                    isUser: true,
                    isStreaming: false,
                    photoData: message.photoData
                )
            } else if let record = message.reading, !record.segments.isEmpty {
                let isCurrent = readingEngine.plan?.record == record
                SegmentCardView(
                    record: record,
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
                VStack(alignment: .leading, spacing: 6) {
                    TranscriptBubble(text: message.content, isUser: false, isStreaming: false)
                    Button {
                        HapticFeedback.light()
                        let parsed = AnswerFormat.parse(message.content)
                        let lang = TTSService.containsVietnamese(message.content) ? "vi" : "en"
                        let record = ReplyAssembler(languageCode: lang).record(for: parsed)
                        readingEngine.replay(record: record)
                    } label: {
                        Label("Đọc lại", systemImage: "speaker.wave.2.fill")
                            .font(Theme.Typography.badge)
                            .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ConversationListView()
        .environmentObject(SettingsManager.shared)
        .environmentObject(AppRouter())
        .preferredColorScheme(.dark)
}
