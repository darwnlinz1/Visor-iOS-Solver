// Reybain - GeminiLiveService.swift
// REST-based Gemini solver: streaming v2.1 (TYPE + Q/P/L/FINAL/ANSWER), resilient, agentic.
//
// Design notes (see PLAN.md):
// - API keys come ONLY from Settings (Keychain); never logged (not even prefixes).
// - Uses PromptV2 + AnswerFormat (v2.1): streams structured sections via `onPartialAnswer`
//   and reports `finishReason` via `onAnswerComplete` (fixing N12 MAX_TOKENS detection).

import Foundation
import UIKit
import AVFoundation

/// Real-time transport & model status emitted by `GeminiLiveService` for live UI + spoken progress.
enum GeminiLiveStatus: Equatable, Sendable {
    case preparingImage
    case uploading(progress: Double, kilobytes: Int)
    case waitingForModel(model: String, keyLabel: String)
    case streaming(model: String)
    case retrying(reason: String, spokenCue: String)
}

/// Machine-readable cause of the final failure so the app NEVER blames the user's network
/// when the real problem was an invalid API key, HTTP 429 quota, HTTP 503 overload, or 404 model error.
enum GeminiFailureKind: Equatable, Sendable {
    case rateLimited
    case serverOverloaded
    case badAPIKey
    case modelUnavailable
    case network
    case blockedOrInvalid
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var lastReportedBucket: Int = -1

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = min(1.0, max(0.0, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
        let bucket = fraction >= 0.999 ? 10 : Int(fraction * 5.0)
        lock.lock()
        let shouldEmit = bucket > lastReportedBucket
        if shouldEmit { lastReportedBucket = bucket }
        lock.unlock()
        if shouldEmit {
            onProgress(fraction)
        }
    }
}

@MainActor
final class GeminiLiveService: ObservableObject {
    // MARK: - Singleton

    static let shared = GeminiLiveService()

    // MARK: - Published State

    @Published var connectionState: AIConnectionState = .disconnected
    @Published var isProcessing: Bool = false
    @Published var isModelSpeaking: Bool = false
    @Published var lastError: String?
    @Published private(set) var lastFailureKind: GeminiFailureKind?

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

    /// Real-time upload / thinking / retry status updates for the Live screen.
    var onStatusUpdate: ((GeminiLiveStatus) -> Void)?

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

    /// Primary solver entrypoint: send the wearer's words (+ optional glasses photo and/or direct audio) to Gemini.
    func sendRESTMessage(
        _ text: String,
        imageData: Data?,
        audioData: Data? = nil,
        audioMimeType: String = "audio/wav"
    ) async throws {
        activeTask?.cancel()
        requestGeneration += 1
        let generation = requestGeneration
        isProcessing = true
        processingChangedCallback?(true)
        lastError = nil
        lastFailureKind = nil

        let task = Task<Void, Error> { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            try await self.executeRESTMessage(
                text,
                imageData: imageData,
                audioData: audioData,
                audioMimeType: audioMimeType,
                generation: generation
            )
        }
        activeTask = task

        defer {
            if generation == requestGeneration {
                activeTask = nil
                isProcessing = false
                processingChangedCallback?(false)
            }
        }

        try await task.value
    }

    private func executeRESTMessage(
        _ text: String,
        imageData: Data?,
        audioData: Data?,
        audioMimeType: String,
        generation: Int
    ) async throws {
        guard !getAvailableKeyList().isEmpty else {
            lastError = "Chưa có API key Gemini — vào Cài đặt → Gemini để dán key"
            throw AIBackendError.notConfigured
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let question: String
        if !trimmed.isEmpty {
            question = text
        } else if let audioData, !audioData.isEmpty {
            question = "Nghe đoạn ghi âm của người dùng và trả lời trực tiếp bằng ngôn ngữ họ nói."
        } else if imageData != nil {
            question = "Giải giúp tôi bài toán hoặc câu hỏi trong ảnh này"
        } else {
            question = "Xin chào"
        }

        var image = imageData
        var turn = try await performTurn(
            question: question,
            imageData: image,
            audioData: audioData,
            audioMimeType: audioMimeType,
            generation: generation
        )

        if Self.isCaptureRequest(turn.rawText), image == nil, let capture = onCaptureRequested {
            AppLog.info(.gemini, "Model asked to see — capturing a photo")
            if let photo = await capture(question) {
                guard generation == requestGeneration, !Task.isCancelled else { throw CancellationError() }
                image = photo
                turn = try await performTurn(
                    question: question,
                    imageData: photo,
                    audioData: audioData,
                    audioMimeType: audioMimeType,
                    generation: generation
                )
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

    private func performTurn(
        question: String,
        imageData: Data?,
        audioData: Data?,
        audioMimeType: String,
        generation: Int
    ) async throws -> TurnResult {
        let allKeys = getAvailableKeyList()

        var prepared: Data?
        if let imageData {
            onStatusUpdate?(.preparingImage)
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
        let activeAudio: Data? = (audioData?.isEmpty == false) ? audioData : nil
        if let activeAudio {
            AppLog.info(.gemini, "Attached audio payload: \(activeAudio.count) bytes (\(audioMimeType))")
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
        var finalFailureKind: GeminiFailureKind = .network

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
            let contents = conversationHistory + [Self.userTurn(
                text: question,
                imageData: prepared,
                audioData: activeAudio,
                audioMimeType: audioMimeType,
                perPartMediaResolution: mediaResolutionMode == .perPartUltraHigh
            )]
            let body = try makeRequestBody(contents: contents)
            AppLog.info(.gemini, "Sending request (attempt \(attempt)/\(maxAttempts), \(body.count / 1024) KB) to \(model) with \(keyLabel)")

            let outcome = await performStreamingRequest(
                body: body,
                model: model,
                key: key,
                keyLabel: keyLabel,
                generation: generation
            )
            switch outcome {
            case .success(let rawText, let signature, let finishReason):
                lastUsedModel = model
                lastFailureKind = nil
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
                AppLog.info(.gemini, "\(model) answered (\(rawText.count) chars, finish=\(finishReason ?? "none")) in \(elapsed)s")
                return TurnResult(rawText: rawText, sentImage: prepared, historyCopyTask: historyCopyTask,
                                  signature: signature, finishReason: finishReason)

            case .cancelled:
                historyCopyTask?.cancel()
                throw CancellationError()

            case .rateLimited(let retryAfter):
                AppLog.warning(.gemini, "\(model) quota exhausted (429) for \(keyLabel) — rotating key first")
                coolDown(model: model, key: key, for: retryAfter ?? 60)
                lastErrorMessage = "Gemini API hết hạn mức (HTTP 429) trên \(model) (\(keyLabel))"
                finalFailureKind = .rateLimited
                let cue = Self.rotationNotice(
                    code: "429",
                    currentModel: model,
                    currentKeyNumber: candidate.keyNumber,
                    next: peekNextCandidate(keys: allKeys),
                    speaksVietnamese: SolverIntent.speaksVietnamese
                )
                onStatusUpdate?(.retrying(reason: cue.screen, spokenCue: cue.spoken))
                if allCandidatesCoolingDown(keys: allKeys) {
                    await backoff(attempt: attempt)
                }

            case .badKey(let message):
                AppLog.warning(.gemini, "\(keyLabel) rejected by Google (\(message)) — dropping for an hour")
                coolDown(model: nil, key: key, for: 3600)
                lastErrorMessage = "API \(keyLabel) bị Google từ chối: \(message)"
                finalFailureKind = .badAPIKey
                if let next = peekNextCandidate(keys: allKeys) {
                    let screen = "API key \(candidate.keyNumber) bị từ chối — đổi sang key \(next.keyNumber)"
                    let spoken = SolverIntent.speaksVietnamese
                        ? "API key \(candidate.keyNumber) không hợp lệ, đang đổi sang key \(next.keyNumber)."
                        : "API key \(candidate.keyNumber) was rejected, switching to key \(next.keyNumber)."
                    onStatusUpdate?(.retrying(reason: screen, spokenCue: spoken))
                } else {
                    break retryLoop
                }

            case .modelUnavailable(let message):
                AppLog.warning(.gemini, "\(model) unavailable (404: \(message)) — falling back to next model")
                coolDown(model: model, key: nil, for: 3600)
                lastErrorMessage = "Model \(model) không khả dụng (404): \(message)"
                finalFailureKind = .modelUnavailable
                if let next = peekNextCandidate(keys: allKeys) {
                    let screen = "\(model) không khả dụng (404) — hạ xuống \(next.model)"
                    let spoken = SolverIntent.speaksVietnamese
                        ? "Model \(Self.shortModelLabel(model)) không khả dụng, đang hạ xuống model \(Self.shortModelLabel(next.model))."
                        : "Model \(Self.shortModelLabel(model)) is unavailable, falling back to model \(Self.shortModelLabel(next.model))."
                    onStatusUpdate?(.retrying(reason: screen, spokenCue: spoken))
                } else {
                    break retryLoop
                }

            case .unsupportedField(let capability, let message):
                guard downgrade(capability) else {
                    lastErrorMessage = message
                    finalFailureKind = .blockedOrInvalid
                    break retryLoop
                }
                AppLog.info(.gemini, "Model rejected \(capability) — retrying without it")
                attempt -= 1

            case .staleSignature(let message):
                guard !healedSignatures else {
                    lastErrorMessage = message
                    finalFailureKind = .blockedOrInvalid
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
                AppLog.warning(.gemini, "Server error from \(model) (\(keyLabel)): \(message)")
                lastErrorMessage = message
                finalFailureKind = .serverOverloaded
                // Key-first fallback policy: cool down ONLY this (model, key) so we exhaust every API key
                // on the primary model (3.5) before dropping down to the fallback model (3.1).
                let isOverloaded = message.contains("503")
                    || message.localizedCaseInsensitiveContains("high demand")
                    || message.localizedCaseInsensitiveContains("unavailable")
                    || message.localizedCaseInsensitiveContains("overloaded")
                let cooldownSeconds: TimeInterval = isOverloaded ? 30 : 15
                coolDown(model: model, key: key, for: cooldownSeconds)
                let code = isOverloaded ? "503" : "5xx"
                let cue = Self.rotationNotice(
                    code: code,
                    currentModel: model,
                    currentKeyNumber: candidate.keyNumber,
                    next: peekNextCandidate(keys: allKeys),
                    speaksVietnamese: SolverIntent.speaksVietnamese
                )
                onStatusUpdate?(.retrying(reason: cue.screen, spokenCue: cue.spoken))
                if allCandidatesCoolingDown(keys: allKeys) {
                    await backoff(attempt: attempt)
                }

            case .network(let message, let partial, let signature, let finishReason):
                if !AnswerFormat.parse(partial).sections.isEmpty {
                    lastUsedModel = model
                    lastFailureKind = nil
                    AppLog.warning(.gemini, "Stream dropped after \(partial.count) chars (\(message)) — using partial answer")
                    return TurnResult(rawText: partial, sentImage: prepared, historyCopyTask: historyCopyTask,
                                      signature: signature, finishReason: finishReason)
                }
                lastErrorMessage = message
                finalFailureKind = .network
                networkFailures += 1
                if networkFailures > Self.maxNetworkRetries { break retryLoop }
                let screen = "Mạng chập chờn — đang thử kết nối lại (\(networkFailures)/\(Self.maxNetworkRetries))…"
                let spoken = SolverIntent.speaksVietnamese
                    ? "Mạng đang chập chờn, đang thử kết nối lại."
                    : "The network dropped, retrying connection."
                onStatusUpdate?(.retrying(reason: screen, spokenCue: spoken))
                await backoff(attempt: networkFailures)

            case .fatal(let message):
                lastErrorMessage = message
                finalFailureKind = .blockedOrInvalid
                break retryLoop
            }
        }

        historyCopyTask?.cancel()
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
        AppLog.error(.gemini, "Giving up after \(attempt) attempt(s), \(elapsed)s [kind=\(finalFailureKind)]: \(lastErrorMessage)")
        self.lastError = lastErrorMessage
        self.lastFailureKind = finalFailureKind
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
            (turn["parts"] as? [[String: Any]])?.contains { part in
                guard let inline = part["inlineData"] as? [String: Any] else { return false }
                let mime = (inline["mimeType"] as? String) ?? "image/"
                return mime.hasPrefix("image/")
            } ?? false
        }
    }

    static func userTurn(
        text: String,
        imageData: Data?,
        audioData: Data? = nil,
        audioMimeType: String = "audio/wav",
        perPartMediaResolution: Bool = false
    ) -> [String: Any] {
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
        if let audioData, !audioData.isEmpty {
            parts.append([
                "inlineData": [
                    "mimeType": audioMimeType,
                    "data": audioData.base64EncodedString()
                ]
            ])
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

    private func performStreamingRequest(
        body: Data,
        model: String,
        key: String,
        keyLabel: String,
        generation: Int
    ) async -> AttemptOutcome {
        let endpoint = "https://\(Self.apiHost)/v1beta/models/\(model):streamGenerateContent?alt=sse"
        guard let url = URL(string: endpoint) else { return .fatal("Invalid Gemini URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = body
        request.timeoutInterval = Self.idleTimeout

        let payloadKB = max(1, body.count / 1024)
        let hasLargePayload = body.count >= 16 * 1024
        if hasLargePayload {
            onStatusUpdate?(.uploading(progress: 0.05, kilobytes: payloadKB))
        } else {
            onStatusUpdate?(.waitingForModel(model: model, keyLabel: keyLabel))
        }

        let progressDelegate = UploadProgressDelegate { [weak self] fraction in
            Task { @MainActor [weak self] in
                guard let self, self.requestGeneration == generation else { return }
                if fraction >= 0.999 {
                    self.onStatusUpdate?(.waitingForModel(model: model, keyLabel: keyLabel))
                } else if hasLargePayload {
                    self.onStatusUpdate?(.uploading(progress: fraction, kilobytes: payloadKB))
                }
            }
        }

        var accumulated = ""
        var signature: String?
        var finishReason: String?
        var didNotifyStreaming = false
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: progressDelegate)
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
            onStatusUpdate?(.waitingForModel(model: model, keyLabel: keyLabel))
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
                if !didNotifyStreaming {
                    didNotifyStreaming = true
                    onStatusUpdate?(.streaming(model: model))
                }
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

    private func allCandidatesCoolingDown(keys: [String]) -> Bool {
        let now = Date()
        return Self.modelChain.allSatisfy { model in
            keys.allSatisfy { key in isCoolingDown(model: model, key: key, now: now) }
        }
    }

    private func cooldownKey(_ model: String?, _ key: String?) -> String {
        "\(model ?? "*")|\(key ?? "*")"
    }

    private func peekNextCandidate(keys: [String]) -> (model: String, keyNumber: Int)? {
        let now = Date()
        let total = keys.count
        guard total > 0 else { return nil }
        for model in Self.modelChain {
            for i in 0..<total {
                let idx = (currentKeyIndex + i) % total
                if !isCoolingDown(model: model, key: keys[idx], now: now) {
                    return (model, idx + 1)
                }
            }
        }
        return nil
    }

    nonisolated static func shortModelLabel(_ model: String) -> String {
        if model.contains("3.5") { return "3.5" }
        if model.contains("3.1") { return "3.1" }
        if model.contains("2.5") { return "2.5" }
        return model.replacingOccurrences(of: "gemini-", with: "")
    }

    nonisolated static func rotationNotice(
        code: String,
        currentModel: String,
        currentKeyNumber: Int,
        next: (model: String, keyNumber: Int)?,
        speaksVietnamese: Bool
    ) -> (screen: String, spoken: String) {
        let curShort = shortModelLabel(currentModel)
        if let next {
            if next.model == currentModel {
                let screen = "\(currentModel) · key \(currentKeyNumber) lỗi \(code) — đổi sang key \(next.keyNumber)"
                let spoken = speaksVietnamese
                    ? "Model \(curShort) key \(currentKeyNumber) bị lỗi \(code), đang chuyển sang key \(next.keyNumber)."
                    : "Model \(curShort) key \(currentKeyNumber) returned \(code), switching to key \(next.keyNumber)."
                return (screen, spoken)
            } else {
                let nextShort = shortModelLabel(next.model)
                let screen = "Hết key cho \(currentModel) (\(code)) — hạ xuống \(next.model) (key \(next.keyNumber))"
                let spoken = speaksVietnamese
                    ? "Hết key cho model \(curShort), đang hạ xuống model \(nextShort)."
                    : "All keys for model \(curShort) hit \(code), falling back to model \(nextShort)."
                return (screen, spoken)
            }
        }
        let screen = "Tất cả API key đều gặp lỗi \(code) — đang chờ thử lại…"
        let spoken = speaksVietnamese
            ? "Tất cả API key đang bị lỗi \(code), đang thử lại."
            : "All API keys hit \(code), retrying."
        return (screen, spoken)
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
            memories: settings.memories,
            modeHint: settings.usageMode.systemPromptHint
        )
    }
}
