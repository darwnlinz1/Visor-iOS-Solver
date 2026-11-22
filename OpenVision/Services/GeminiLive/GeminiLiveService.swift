// OpenVision - GeminiLiveService.swift
// REST-based Gemini solver: streaming v2.1 (TYPE + Q/P/L/FINAL/ANSWER), resilient, agentic.
//
// Design notes (see PLAN.md):
// - API keys come ONLY from Settings (Keychain); never logged (not even prefixes).
// - Uses PromptV2 + AnswerFormat (v2.1): streams structured sections via `onPartialAnswer`
//   and reports `finishReason` via `onAnswerComplete` (fixing N12 MAX_TOKENS detection).

import Foundation
import UIKit
import AVFoundation

@MainActor
final class GeminiLiveService: ObservableObject {
    // MARK: - Singleton

    static let shared = GeminiLiveService()

    // MARK: - Published State

    @Published var connectionState: AIConnectionState = .disconnected
    @Published var isProcessing: Bool = false
    @Published var isModelSpeaking: Bool = false
    @Published var lastError: String?

    /// Diagnostics for Debug → "Câu trả lời thô" inspector (PLAN.md §4.7).
    @Published private(set) var lastRawReply: String = ""
    @Published private(set) var lastFinishReason: String?
    @Published private(set) var lastUsedModel: String?

    // MARK: - Endpoint & models

    static let apiHost = "generativelanguage.googleapis.com"
    /// Tried in order. Quota is per model, so the second model is a real fallback when the
    /// first one is exhausted or unavailable (404) for every key.
    static let modelChain = ["gemini-3.5-flash-lite", "gemini-3.1-flash-lite"]
    /// The primary model (diagnostics, settings UI).
    static var modelName: String { modelChain[0] }

    // MARK: - Multi-turn Conversation History

    /// Entries kept for follow-up questions: 3 user/model exchanges (Blueprint lesson 7).
    static let maxHistoryEntries = 6

    private var conversationHistory: [[String: Any]] = []

    /// Number of stored history entries (user + model turns) — read-only view for diagnostics/tests.
    var conversationHistoryCount: Int { conversationHistory.count }

    public func clearConversationHistory() {
        conversationHistory.removeAll()
        imageFingerprintInHistory = nil
    }

    /// Continue a past conversation from History using v2.1 format (T4.3 / T4.4).
    func seedHistory(from messages: [(isUser: Bool, text: String, reading: ReadingRecord?)]) {
        clearConversationHistory()
        var turns: [[String: Any]] = messages.suffix(Self.maxHistoryEntries).map { message in
            if message.isUser {
                return Self.userTurn(text: message.text, imageData: nil)
            }
            let modelText = message.reading.map { AnswerFormat.text(for: $0) }
                ?? AnswerFormat.text(forLegacyHistory: message.text)
            return Self.modelTurn(text: modelText, signature: nil)
        }
        while let first = turns.first, (first["role"] as? String) != "user" { turns.removeFirst() }
        conversationHistory = turns
    }

    /// Convenience overload for callers/tests without `ReadingRecord`.
    func seedHistory(from messages: [(isUser: Bool, text: String)]) {
        seedHistory(from: messages.map { (isUser: $0.isUser, text: $0.text, reading: nil) })
    }

    // MARK: - Callbacks

    var onTextReceived: ((String) -> Void)?
    var onAudioReceived: ((Data) -> Void)?
    var onTurnComplete: (() -> Void)?
    var onInputTranscription: ((String) -> Void)?
    var onOutputTranscription: ((String) -> Void)?
    var onConnectionStateChanged: ((AIConnectionState) -> Void)?
    var onDisconnected: (() -> Void)?

    // Callbacks backing ViewModel orchestration
    var agentMessageCallback: ((String) -> Void)?
    var processingChangedCallback: ((Bool) -> Void)?

    /// Streamed v2.1 parsed answer so far (cumulative prefix sections + decided AnswerType).
    var onPartialAnswer: ((ParsedAnswer) -> Void)?

    /// Final raw reply and Gemini `finishReason` (e.g. `"STOP"`, `"MAX_TOKENS"` — N12).
    var onAnswerComplete: ((_ raw: String, _ finishReason: String?) -> Void)?

    /// The model asked to SEE (it replied with `captureToken`) and no photo was attached: take one
    /// (glasses camera, or a photo just synced to Camera Roll) and return it, or nil if none.
    var onCaptureRequested: ((_ question: String) async -> Data?)?

    // MARK: - Active Request Tracking

    private var activeTask: Task<Void, Error>?

    // MARK: - Initialization

    private init() {}

    // MARK: - Connection Lifecycle

    func connect() async throws {
        let keys = getAvailableKeyList()
        guard !keys.isEmpty else {
            throw AIBackendError.notConfigured
        }

        connectionState = .connected
        onConnectionStateChanged?(connectionState)
        AppLog.info(.gemini, "Connected to REST solver endpoint with \(keys.count) API key(s)")
    }

    func disconnect() async {
        guard connectionState != .disconnected else { return }

        AppLog.info(.gemini, "Disconnecting")
        activeTask?.cancel()
        activeTask = nil
        isProcessing = false
        isModelSpeaking = false

        connectionState = .disconnected
        onConnectionStateChanged?(connectionState)
        processingChangedCallback?(false)
        onDisconnected?()
    }

    func interrupt() async {
        AppLog.info(.gemini, "Interrupted")
        requestGeneration += 1
        activeTask?.cancel()
        activeTask = nil
        isProcessing = false
        isModelSpeaking = false
        processingChangedCallback?(false)
    }

    // MARK: - Messaging

    func sendText(_ text: String) async throws {
        try await sendRESTMessage(text, imageData: nil)
    }

    /// Primary solver entrypoint: send the wearer's words (+ optional glasses photo) to Gemini.
    func sendRESTMessage(_ text: String, imageData: Data?) async throws {
        requestGeneration += 1
        let generation = requestGeneration
        isProcessing = true
        processingChangedCallback?(true)
        lastError = nil

        defer {
            if generation == requestGeneration {
                isProcessing = false
                processingChangedCallback?(false)
            }
        }

        guard !getAvailableKeyList().isEmpty else {
            lastError = "Chưa có API key Gemini — vào Cài đặt → Gemini để dán key"
            throw AIBackendError.notConfigured
        }

        let question = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (imageData != nil ? "Giải giúp tôi bài toán hoặc câu hỏi trong ảnh này" : "Xin chào")
            : text

        var image = imageData
        var turn = try await performTurn(question: question, imageData: image, generation: generation)

        if Self.isCaptureRequest(turn.rawText), image == nil, let capture = onCaptureRequested {
            AppLog.info(.gemini, "Model asked to see — capturing a photo")
            if let photo = await capture(question) {
                guard generation == requestGeneration else { throw CancellationError() }
                image = photo
                turn = try await performTurn(question: question, imageData: photo, generation: generation)
            } else {
                let message = SolverIntent.missingPhotoMessage(for: question)
                turn = TurnResult(rawText: "TYPE: OTHER\nANSWER: \(message)", sentImage: nil, historyCopyTask: nil)
            }
        }
        if Self.isCaptureRequest(turn.rawText) {
            let message = SolverIntent.missingPhotoMessage(for: question)
            turn.rawText = "TYPE: OTHER\nANSWER: \(message)"
            turn.finishReason = "STOP"
        }

        lastRawReply = turn.rawText
        lastFinishReason = turn.finishReason
        deliver(turn.rawText, finishReason: turn.finishReason)
        await recordTurn(userText: question, sentImage: turn.sentImage, historyCopyTask: turn.historyCopyTask,
                         rawText: turn.rawText, signature: turn.signature)
    }

    private struct TurnResult {
        var rawText: String
        var sentImage: Data?
        var historyCopyTask: Task<Data, Never>?
        var signature: String? = nil
        var finishReason: String? = nil
    }

    private func performTurn(question: String, imageData: Data?, generation: Int) async throws -> TurnResult {
        let allKeys = getAvailableKeyList()

        var prepared: Data?
        if let imageData {
            prepared = await Task.detached(priority: .userInitiated) { PhotoPayload.uploadJPEG(from: imageData) ?? imageData }.value
        }
        let fullUpload = prepared

        if let data = prepared, historyContainsImage, imageFingerprintInHistory == PhotoPayload.fingerprint(data) {
            prepared = nil
            AppLog.info(.gemini, "Photo already in conversation history — not re-uploading")
        }
        if let data = prepared {
            AppLog.info(.gemini, "Attached image payload: \(data.count) bytes (\(PhotoPayload.mimeType(for: data)))")
        }
        var historyCopyTask: Task<Data, Never>? = prepared.map { data in
            Task.detached(priority: .utility) { PhotoPayload.historyCopy(of: data) }
        }

        let started = Date()
        let maxAttempts = allKeys.count * Self.modelChain.count + 3
        var attempt = 0
        var networkFailures = 0
        var healedSignatures = false
        var lastErrorMessage = "Không nhận được phản hồi từ Gemini API"

        retryLoop: while attempt < maxAttempts && Date().timeIntervalSince(started) < Self.overallDeadline {
            guard generation == requestGeneration, !Task.isCancelled else {
                historyCopyTask?.cancel()
                throw CancellationError()
            }
            attempt += 1
            let candidate = nextCandidate(keys: allKeys)
            let model = candidate.model
            let key = candidate.key
            let keyLabel = "key \(candidate.keyNumber)/\(allKeys.count)"
            let contents = conversationHistory + [Self.userTurn(text: question, imageData: prepared,
                                                                  perPartMediaResolution: mediaResolutionMode == .perPartUltraHigh)]
            let body = try makeRequestBody(contents: contents)
            AppLog.info(.gemini, "Sending request (attempt \(attempt)/\(maxAttempts), \(body.count / 1024) KB) to \(model) with \(keyLabel)")

            let outcome = await performStreamingRequest(body: body, model: model, key: key, generation: generation)
            switch outcome {
            case .success(let rawText, let signature, let finishReason):
                lastUsedModel = model
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
                AppLog.info(.gemini, "\(model) answered (\(rawText.count) chars, finish=\(finishReason ?? "none")) in \(elapsed)s")
                return TurnResult(rawText: rawText, sentImage: prepared, historyCopyTask: historyCopyTask,
                                  signature: signature, finishReason: finishReason)

            case .cancelled:
                historyCopyTask?.cancel()
                throw CancellationError()

            case .rateLimited(let retryAfter):
                AppLog.warning(.gemini, "\(model) quota exhausted for \(keyLabel) — rotating")
                coolDown(model: model, key: key, for: retryAfter ?? 60)
                lastErrorMessage = "Gemini quota exhausted (429)"

            case .badKey(let message):
                AppLog.warning(.gemini, "\(keyLabel) rejected (\(message)) — dropping for an hour")
                coolDown(model: nil, key: key, for: 3600)
                lastErrorMessage = message

            case .modelUnavailable(let message):
                AppLog.warning(.gemini, "\(model) unavailable (\(message)) — falling back to next model")
                coolDown(model: model, key: nil, for: 3600)
                lastErrorMessage = message

            case .unsupportedField(let capability, let message):
                guard downgrade(capability) else {
                    lastErrorMessage = message
                    break retryLoop
                }
                AppLog.info(.gemini, "Model rejected \(capability) — retrying without it")
                attempt -= 1

            case .staleSignature(let message):
                guard !healedSignatures else {
                    lastErrorMessage = message
                    break retryLoop
                }
                healedSignatures = true
                AppLog.warning(.gemini, "History rejected (\(message)) — clearing it and retrying")
                clearConversationHistory()
                if prepared == nil, let fullUpload {
                    prepared = fullUpload
                    historyCopyTask = Task.detached(priority: .utility) { PhotoPayload.historyCopy(of: fullUpload) }
                }
                attempt -= 1

            case .serverError(let message):
                AppLog.warning(.gemini, "Server error from \(model): \(message)")
                lastErrorMessage = message
                await backoff(attempt: attempt)

            case .network(let message, let partial, let signature, let finishReason):
                if !AnswerFormat.parse(partial).sections.isEmpty {
                    lastUsedModel = model
                    AppLog.warning(.gemini, "Stream dropped after \(partial.count) chars (\(message)) — using partial answer")
                    return TurnResult(rawText: partial, sentImage: prepared, historyCopyTask: historyCopyTask,
                                      signature: signature, finishReason: finishReason)
                }
                lastErrorMessage = message
                networkFailures += 1
                if networkFailures > Self.maxNetworkRetries { break retryLoop }
                await backoff(attempt: networkFailures)

            case .fatal(let message):
                lastErrorMessage = message
                break retryLoop
            }
        }

        historyCopyTask?.cancel()
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
        AppLog.error(.gemini, "Giving up after \(attempt) attempt(s), \(elapsed)s: \(lastErrorMessage)")
        self.lastError = lastErrorMessage
        throw AIBackendError.requestFailed(lastErrorMessage)
    }

    // MARK: - Agent protocol

    static let captureToken = AnswerFormat.captureToken
    static let endToken = AnswerFormat.endToken

    static func endsConversation(_ raw: String) -> Bool {
        AnswerFormat.endsConversation(raw)
    }

    static func isCaptureRequest(_ raw: String) -> Bool {
        AnswerFormat.parse(raw).requestsCapture
    }

    // MARK: - Request plumbing

    nonisolated static let overallDeadline: TimeInterval = 120
    nonisolated static let idleTimeout: TimeInterval = 75
    nonisolated static let maxNetworkRetries = 2

    var urlProtocolClasses: [AnyClass] = [] {
        didSet { session = Self.makeSession(protocolClasses: urlProtocolClasses) }
    }

    var apiKeysOverride: [String]?

    enum MediaResolutionMode: Equatable {
        case perPartUltraHigh, configHigh, none
    }

    enum Capability: Equatable {
        case mediaResolution, thinking
    }

    private(set) var mediaResolutionMode: MediaResolutionMode = .perPartUltraHigh
    private(set) var thinkingSupported = true

    private var session: URLSession = GeminiLiveService.makeSession(protocolClasses: [])
    private var requestGeneration = 0
    private var imageFingerprintInHistory: Int?

    private nonisolated static func makeSession(protocolClasses: [AnyClass]) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = idleTimeout
        config.timeoutIntervalForResource = overallDeadline + 30
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        if !protocolClasses.isEmpty {
            config.protocolClasses = protocolClasses + (config.protocolClasses ?? [])
        }
        return URLSession(configuration: config)
    }

    private func downgrade(_ capability: Capability) -> Bool {
        switch capability {
        case .mediaResolution:
            switch mediaResolutionMode {
            case .perPartUltraHigh: mediaResolutionMode = .configHigh
            case .configHigh: mediaResolutionMode = .none
            case .none: return false
            }
        case .thinking:
            guard thinkingSupported else { return false }
            thinkingSupported = false
        }
        return true
    }

    enum AttemptOutcome: Equatable {
        case success(String, signature: String?, finishReason: String?)
        case cancelled
        case rateLimited(retryAfter: TimeInterval?)
        case badKey(String)
        case modelUnavailable(String)
        case unsupportedField(Capability, String)
        case staleSignature(String)
        case serverError(String)
        case network(String, partial: String, signature: String?, finishReason: String?)
        case fatal(String)
    }

    var historyContainsImage: Bool {
        conversationHistory.contains { turn in
            (turn["parts"] as? [[String: Any]])?.contains { $0["inlineData"] != nil } ?? false
        }
    }

    static func userTurn(text: String, imageData: Data?, perPartMediaResolution: Bool = false) -> [String: Any] {
        var parts: [[String: Any]] = []
        if let imageData {
            var part: [String: Any] = [
                "inlineData": [
                    "mimeType": PhotoPayload.mimeType(for: imageData),
                    "data": imageData.base64EncodedString()
                ]
            ]
            if perPartMediaResolution {
                part["mediaResolution"] = ["level": "MEDIA_RESOLUTION_ULTRA_HIGH"]
            }
            parts.append(part)
        }
        parts.append(["text": text])
        return ["role": "user", "parts": parts]
    }

    static func modelTurn(text: String, signature: String?) -> [String: Any] {
        var parts: [[String: Any]] = [["text": text]]
        if let signature, !signature.isEmpty {
            parts.append(["text": "", "thoughtSignature": signature])
        }
        return ["role": "model", "parts": parts]
    }

    private func makeRequestBody(contents: [[String: Any]]) throws -> Data {
        var generationConfig: [String: Any] = [
            "temperature": 0.2,
            "maxOutputTokens": 8192
        ]
        if mediaResolutionMode == .configHigh {
            generationConfig["mediaResolution"] = "MEDIA_RESOLUTION_HIGH"
        }
        if thinkingSupported {
            generationConfig["thinkingConfig"] = ["thinkingLevel": "LOW"]
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": buildSystemPrompt()]]],
            "contents": contents,
            "generationConfig": generationConfig
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [])
    }

    private func performStreamingRequest(body: Data, model: String, key: String, generation: Int) async -> AttemptOutcome {
        let endpoint = "https://\(Self.apiHost)/v1beta/models/\(model):streamGenerateContent?alt=sse"
        guard let url = URL(string: endpoint) else { return .fatal("Invalid Gemini URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = body
        request.timeoutInterval = Self.idleTimeout

        var accumulated = ""
        var signature: String?
        var finishReason: String?
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .network("No HTTP response", partial: "", signature: nil, finishReason: nil)
            }
            guard (200...299).contains(http.statusCode) else {
                var errorBody = ""
                for try await line in bytes.lines {
                    errorBody += line
                    if errorBody.count > 4000 { break }
                }
                AppLog.error(.gemini, "HTTP error \(http.statusCode): \(String(errorBody.prefix(300)))")
                return Self.classifyHTTPError(status: http.statusCode, body: errorBody,
                                              retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
            }
            for try await line in bytes.lines {
                guard generation == requestGeneration else { return .cancelled }
                guard let chunk = Self.parseSSELine(line) else { continue }
                if let reason = chunk.blockReason {
                    return .fatal("Gemini blocked the request (\(reason))")
                }
                if let sig = chunk.thoughtSignature { signature = sig }
                // Read finishReason BEFORE skipping empty-text chunks (final SSE chunk often has text == "", N12).
                if let reason = chunk.finishReason, !reason.isEmpty { finishReason = reason }
                guard !chunk.text.isEmpty else { continue }
                accumulated += chunk.text
                let partial = AnswerFormat.partialAnswer(in: accumulated)
                if !partial.requestsCapture && (!partial.sections.isEmpty || partial.isTypeKnown) {
                    onPartialAnswer?(partial)
                }
            }
            if accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .serverError("Empty response from Gemini")
            }
            return .success(accumulated, signature: signature, finishReason: finishReason)
        } catch is CancellationError {
            return .cancelled
        } catch {
            if (error as? URLError)?.code == .cancelled { return .cancelled }
            AppLog.error(.gemini, "Request error: \(error.localizedDescription)")
            return .network(error.localizedDescription, partial: accumulated, signature: signature, finishReason: finishReason)
        }
    }

    private func deliver(_ rawText: String, finishReason: String?) {
        if let onAnswerComplete {
            onAnswerComplete(rawText, finishReason)
        } else if let agentMessage = agentMessageCallback {
            agentMessage(rawText)
        } else {
            let parsed = AnswerFormat.parse(rawText, finishReason: finishReason)
            let summary = parsed.sections.map(\.text).joined(separator: " ")
            onOutputTranscription?(summary)
        }
        onTextReceived?(rawText)
    }

    private func recordTurn(userText: String, sentImage: Data?, historyCopyTask: Task<Data, Never>?,
                            rawText: String, signature: String?) async {
        var historyImage: Data?
        if let historyCopyTask {
            historyImage = await historyCopyTask.value
        }
        conversationHistory.append(Self.userTurn(text: userText, imageData: historyImage))
        conversationHistory.append(Self.modelTurn(text: rawText, signature: signature))
        if conversationHistory.count > Self.maxHistoryEntries {
            conversationHistory.removeFirst(conversationHistory.count - Self.maxHistoryEntries)
        }
        if let sentImage {
            imageFingerprintInHistory = PhotoPayload.fingerprint(sentImage)
        }
        if !historyContainsImage {
            imageFingerprintInHistory = nil
        }
    }

    private func backoff(attempt: Int) async {
        let base = min(8.0, pow(2.0, Double(max(0, attempt - 1))))
        let delay = base + Double.random(in: 0...0.4)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    // MARK: - Response parsing (pure, unit-testable)

    struct StreamChunk: Equatable {
        var text: String
        var finishReason: String?
        var blockReason: String?
        var thoughtSignature: String? = nil
    }

    static func parseSSELine(_ line: String) -> StreamChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parseResponseObject(json)
    }

    static func parseResponseObject(_ json: [String: Any]) -> StreamChunk {
        var text = ""
        var finishReason: String?
        var signature: String?
        if let candidates = json["candidates"] as? [[String: Any]], let first = candidates.first {
            finishReason = first["finishReason"] as? String
            if let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                for part in parts {
                    if let sig = part["thoughtSignature"] as? String, !sig.isEmpty { signature = sig }
                    guard (part["thought"] as? Bool) != true else { continue }
                    if let t = part["text"] as? String { text += t }
                }
            }
        }
        let blockReason = (json["promptFeedback"] as? [String: Any])?["blockReason"] as? String
        return StreamChunk(text: text, finishReason: finishReason, blockReason: blockReason, thoughtSignature: signature)
    }

    static func classifyHTTPError(status: Int, body: String, retryAfter: String?) -> AttemptOutcome {
        let lower = body.lowercased()
        let summary = "HTTP \(status): \(body.prefix(300))"
        switch status {
        case 429:
            return .rateLimited(retryAfter: retryAfter.flatMap { TimeInterval($0) })
        case 401, 403:
            return .badKey(summary)
        case 404:
            return .modelUnavailable(summary)
        case 400:
            if lower.contains("api key") || lower.contains("api_key") {
                return .badKey(summary)
            }
            if lower.contains("mediaresolution") || lower.contains("media_resolution") || lower.contains("media resolution") {
                return .unsupportedField(.mediaResolution, summary)
            }
            if lower.contains("thinking") {
                return .unsupportedField(.thinking, summary)
            }
            if lower.contains("signature") {
                return .staleSignature(summary)
            }
            return .fatal(summary)
        case 408, 500...599:
            return .serverError(summary)
        default:
            return .fatal(summary)
        }
    }

    // MARK: - Keys, models, rotation & cooldown

    nonisolated static func parseKeys(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw.components(separatedBy: CharacterSet(charactersIn: ",; \n\r\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func getAvailableKeyList() -> [String] {
        if let apiKeysOverride { return apiKeysOverride }
        return Self.parseKeys(SettingsManager.shared.settings.geminiAPIKey)
    }

    private var currentKeyIndex = 0
    private var cooldowns: [String: Date] = [:]

    private func isCoolingDown(model: String, key: String, now: Date) -> Bool {
        [cooldownKey(model, key), cooldownKey(nil, key), cooldownKey(model, nil)].contains { (cooldowns[$0] ?? .distantPast) > now }
    }

    private func cooldownKey(_ model: String?, _ key: String?) -> String {
        "\(model ?? "*")|\(key ?? "*")"
    }

    private func nextCandidate(keys: [String]) -> (model: String, key: String, keyNumber: Int) {
        let now = Date()
        let total = keys.count
        for model in Self.modelChain {
            for i in 0..<total {
                let idx = (currentKeyIndex + i) % total
                if !isCoolingDown(model: model, key: keys[idx], now: now) {
                    currentKeyIndex = (idx + 1) % total
                    return (model, keys[idx], idx + 1)
                }
            }
        }
        var best = (model: Self.modelChain[0], key: keys[0], keyNumber: 1)
        var bestEnd = Date.distantFuture
        for model in Self.modelChain {
            for (idx, key) in keys.enumerated() {
                let end = [cooldownKey(model, key), cooldownKey(nil, key), cooldownKey(model, nil)]
                    .compactMap { cooldowns[$0] }.max() ?? .distantPast
                if end < bestEnd {
                    bestEnd = end
                    best = (model, key, idx + 1)
                }
            }
        }
        return best
    }

    private func coolDown(model: String?, key: String?, for seconds: TimeInterval) {
        cooldowns[cooldownKey(model, key)] = Date().addingTimeInterval(max(1, seconds))
    }

    func resetNetworkState() {
        currentKeyIndex = 0
        cooldowns.removeAll()
        mediaResolutionMode = .perPartUltraHigh
        thinkingSupported = true
    }

    // MARK: - System Prompt (v2.1, PLAN.md §4.2, T4.1)

    func buildSystemPrompt() -> String {
        let settings = SettingsManager.shared.settings
        return PromptV2.systemPrompt(
            now: Date(),
            timeZone: .current,
            userPrompt: settings.userPrompt,
            memories: settings.memories
        )
    }
}
