// OpenVision - ConversationManager.swift
// Manages conversation history with persistence, photo downscaling/dedup, and safe backup on decode errors (N11).

import Foundation

/// Manages conversation history and persistence
@MainActor
final class ConversationManager: ObservableObject {
    // MARK: - Singleton

    static let shared = ConversationManager()

    // MARK: - Published State

    /// All conversations
    @Published var conversations: [Conversation] = []

    /// Currently active conversation
    @Published var currentConversation: Conversation?

    // MARK: - File Storage

    private let fileURL: URL

    /// Fingerprints of raw photos already stored in the current conversation so follow-up turns
    /// do not duplicate base64 photo payloads on disk (PLAN.md N11).
    private var storedPhotoFingerprints: [UUID: Set<Int>] = [:]

    // MARK: - Configuration

    /// Inactivity timeout before starting new conversation (5 minutes)
    private let inactivityTimeout: TimeInterval = Constants.Storage.conversationInactivityTimeout

    /// Maximum conversations to keep
    private let maxConversations: Int = Constants.Storage.maxConversations

    /// Max pixel dimension for thumbnails saved inside History (PLAN.md T6.3).
    private static let historyThumbnailMaxDimension = 1024

    // MARK: - Initialization

    private init() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = documentsURL.appendingPathComponent(Constants.Storage.conversationsFileName)

        loadConversations()
    }

    // MARK: - Conversation Management

    /// Start a new conversation
    func startNewConversation() {
        let conversation = Conversation()
        currentConversation = conversation
        conversations.insert(conversation, at: 0)
        saveConversations()
        AppLog.info(.history, "Started new conversation: \(conversation.id.uuidString.prefix(8))")
    }

    /// Get or create current conversation
    func getOrCreateCurrentConversation() -> Conversation {
        if let current = currentConversation {
            let timeSinceActivity = Date().timeIntervalSince(current.lastActivityAt)
            if timeSinceActivity < inactivityTimeout {
                return current
            }
        }
        startNewConversation()
        return currentConversation!
    }

    /// True while the current conversation is still within its inactivity window — i.e. a new
    /// message would append to it rather than start a new conversation. Model context (memory)
    /// follows this same boundary.
    var isCurrentConversationFresh: Bool {
        guard let current = currentConversation else { return false }
        return Date().timeIntervalSince(current.lastActivityAt) < inactivityTimeout
    }

    /// Add a message to the current conversation
    func addMessage(_ message: Message) {
        var conversation = getOrCreateCurrentConversation()
        conversation.addMessage(message)

        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }

        currentConversation = conversation
        saveConversations()
    }

    /// Add user message (stores each distinct photo once as a <= 1024 px JPEG, N11).
    func addUserMessage(_ text: String, photoData: Data? = nil) {
        let conversation = getOrCreateCurrentConversation()
        var storedPhoto: Data? = nil
        if let photoData {
            let fp = PhotoPayload.fingerprint(photoData)
            var seen = storedPhotoFingerprints[conversation.id] ?? []
            if seen.insert(fp).inserted {
                storedPhotoFingerprints[conversation.id] = seen
                storedPhoto = PhotoPayload.renderJPEG(
                    from: photoData,
                    maxPixelSize: Self.historyThumbnailMaxDimension,
                    quality: 0.75
                ) ?? photoData
            }
        }
        let message = Message.user(text, photoData: storedPhoto)
        addMessage(message)
    }

    /// Add assistant message with optional v2.1 reading record for offline replay.
    func addAssistantMessage(_ text: String, reading: ReadingRecord? = nil) {
        let message = Message.assistant(text, reading: reading)
        addMessage(message)
    }

    /// Add tool message
    func addToolMessage(name: String, result: String) {
        let message = Message.tool(name: name, result: result)
        addMessage(message)
    }

    /// Delete a conversation
    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        storedPhotoFingerprints.removeValue(forKey: conversation.id)

        if currentConversation?.id == conversation.id {
            currentConversation = nil
        }

        saveConversations()
        AppLog.info(.history, "Deleted conversation: \(conversation.id.uuidString.prefix(8))")
    }

    /// Delete all conversations
    func deleteAllConversations() {
        conversations.removeAll()
        storedPhotoFingerprints.removeAll()
        currentConversation = nil
        saveConversations()
        AppLog.info(.history, "Deleted all conversations")
    }

    /// Resume a conversation
    func resumeConversation(_ conversation: Conversation) {
        var resumed = conversation
        resumed.lastActivityAt = Date()
        currentConversation = resumed

        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations.remove(at: index)
            conversations.insert(resumed, at: 0)
        }

        AppLog.info(.history, "Resumed conversation: \(conversation.id.uuidString.prefix(8))")
    }

    // MARK: - Persistence

    /// Load conversations from disk; if decoding fails, preserve the unreadable file as `.bak`
    /// so the next save never silently destroys the user's history (PLAN.md N11).
    private func loadConversations() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            AppLog.info(.history, "No conversations file found")
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            conversations = try decoder.decode([Conversation].self, from: data)
            AppLog.info(.history, "Loaded \(conversations.count) conversations")
            currentConversation = conversations.first
        } catch {
            AppLog.error(.history, "Error loading conversations: \(error.localizedDescription) — backing up file to .bak")
            backupCorruptedFile()
        }
    }

    private func backupCorruptedFile() {
        let fm = FileManager.default
        let baseBak = fileURL.appendingPathExtension("bak")
        let target: URL
        if fm.fileExists(atPath: baseBak.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            target = fileURL.deletingLastPathComponent()
                .appendingPathComponent("\(fileURL.lastPathComponent).\(stamp).bak")
        } else {
            target = baseBak
        }
        do {
            try fm.moveItem(at: fileURL, to: target)
            AppLog.warning(.history, "Moved unreadable conversations file to \(target.lastPathComponent)")
        } catch {
            AppLog.error(.history, "Failed to move unreadable conversations file: \(error.localizedDescription)")
        }
    }

    /// Save conversations to disk
    private func saveConversations() {
        if conversations.count > maxConversations {
            conversations = Array(conversations.prefix(maxConversations))
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(conversations)
            try data.write(to: fileURL, options: .atomic)
            AppLog.debug(.history, "Saved \(conversations.count) conversations")
        } catch {
            AppLog.error(.history, "Error saving conversations: \(error.localizedDescription)")
        }
    }

    // MARK: - Search

    /// Search conversations
    func search(_ query: String) -> [Conversation] {
        guard !query.isEmpty else { return conversations }

        return conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(query) ||
            conversation.messages.contains { message in
                message.content.localizedCaseInsensitiveContains(query)
            }
        }
    }

    // MARK: - Statistics

    var totalMessageCount: Int {
        conversations.reduce(0) { $0 + $1.messages.count }
    }

    var totalPhotoCount: Int {
        conversations.reduce(0) { sum, conversation in
            sum + conversation.messages.filter { $0.hasPhoto }.count
        }
    }
}
