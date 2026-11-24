// OpenVision - BlueprintGeminiE2ETests.swift
// End-to-end through the REAL GeminiLiveService (v2.1 streaming, finishReason, retry policy,
// conversation history) and the REAL TTSService + VietMathSpeech, with network stubbed by GeminiStub.

import XCTest
@testable import OpenVision

@MainActor
final class BlueprintGeminiE2ETests: XCTestCase {

    private var service: GeminiLiveService { GeminiLiveService.shared }

    private var savedText: ((String) -> Void)?
    private var savedPartial: ((ParsedAnswer) -> Void)?
    private var savedComplete: ((String, String?) -> Void)?
    private var savedAgent: ((String) -> Void)?
    private var savedOutput: ((String) -> Void)?
    private var savedProcessing: ((Bool) -> Void)?
    private var savedCapture: ((String) async -> Data?)?
    private var savedStatus: ((GeminiLiveStatus) -> Void)?

    private let answer = #"""
    TYPE: ESSAY
    L1: Ta có $2x + 3 = 7$, chuyển vế được $2x = 4$.
    L2: Chia hai vế cho $2$, suy ra $x = 2$.
    FINAL: Vậy nghiệm của phương trình là $x = 2$.
    """#

    override func setUp() async throws {
        savedText = service.onTextReceived
        savedPartial = service.onPartialAnswer
        savedComplete = service.onAnswerComplete
        savedAgent = service.agentMessageCallback
        savedOutput = service.onOutputTranscription
        savedProcessing = service.processingChangedCallback
        savedCapture = service.onCaptureRequested
        savedStatus = service.onStatusUpdate
        service.onCaptureRequested = nil
        service.onStatusUpdate = nil
        service.apiKeysOverride = ["AQ.test-key-A", "AQ.test-key-B", "AQ.test-key-C"]
        service.onTextReceived = nil
        service.onPartialAnswer = nil
        service.onAnswerComplete = nil
        service.agentMessageCallback = nil
        service.onOutputTranscription = nil
        service.processingChangedCallback = nil
        service.urlProtocolClasses = [GeminiStub.self]
        service.clearConversationHistory()
        service.resetNetworkState()
        GeminiStub.reset()
    }

    override func tearDown() async throws {
        service.urlProtocolClasses = []
        service.apiKeysOverride = nil
        service.onCaptureRequested = savedCapture
        service.onStatusUpdate = savedStatus
        service.clearConversationHistory()
        service.resetNetworkState()
        service.onTextReceived = savedText
        service.onPartialAnswer = savedPartial
        service.onAnswerComplete = savedComplete
        service.agentMessageCallback = savedAgent
        service.onOutputTranscription = savedOutput
        service.processingChangedCallback = savedProcessing
        GeminiStub.reset()
    }

    // MARK: - Checklist test 1: shutter photo + question -> v2.1 streamed answer

    func testShutterPhotoQuestionSendsAnUprightPhotoAtUltraHighDetailAndStreamsV21Sections() async throws {
        let photo = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 4032, height: 3024))
        GeminiStub.enqueue(.stream(answer, finishReason: "STOP"))

        var partials: [ParsedAnswer] = []
        var completed: (raw: String, reason: String?)?
        service.onPartialAnswer = { partials.append($0) }
        service.onAnswerComplete = { raw, reason in completed = (raw, reason) }

        try await service.sendRESTMessage("giải câu này", imageData: photo)

        let request = try XCTUnwrap(GeminiStub.captured.first)
        XCTAssertEqual(GeminiStub.captured.count, 1)
        XCTAssertTrue(request.url.path.hasSuffix("/gemini-3.5-flash-lite:streamGenerateContent"), request.url.absoluteString)
        XCTAssertEqual(request.query("alt"), "sse")
        XCTAssertNil(request.query("key"), "the API key must not be in the URL")
        XCTAssertEqual(request.apiKey, "AQ.test-key-A")

        let turn = try XCTUnwrap(request.contents.last)
        let sent = try XCTUnwrap(turn.imageData)
        let info = try XCTUnwrap(PhotoPayload.imageInfo(sent))
        XCTAssertEqual(max(info.width, info.height), PhotoPayload.uploadMaxDimension)
        XCTAssertEqual(info.orientation, 1)
        XCTAssertEqual(turn.imageMIMEType, "image/jpeg")
        XCTAssertEqual(turn.mediaResolution, "MEDIA_RESOLUTION_ULTRA_HIGH")
        XCTAssertEqual(turn.text, "giải câu này")
        XCTAssertNil(request.generationConfig["mediaResolution"])
        XCTAssertEqual((request.generationConfig["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "LOW")
        XCTAssertEqual(request.generationConfig["maxOutputTokens"] as? Int, 8192)
        XCTAssertTrue(request.systemPrompt.contains("TYPE:"))
        XCTAssertFalse(request.systemPrompt.contains("DISPLAY:"))

        XCTAssertEqual(completed?.raw, answer)
        XCTAssertEqual(completed?.reason, "STOP")
        let finalParsed = AnswerFormat.parse(answer, finishReason: "STOP")
        XCTAssertFalse(partials.isEmpty)
        for partial in partials {
            XCTAssertTrue(finalParsed.sections.starts(with: partial.sections), "streamed sections must be a prefix of final sections")
        }
        XCTAssertEqual(service.conversationHistoryCount, 2)
        XCTAssertTrue(service.historyContainsImage)
    }

    func testMaxTokensFinishReasonReachesCallbackAndAddsTruncationNotice() async throws {
        let cutReply = "TYPE: ESSAY\nL1: Ta có $2x = 4$.\nL2: Suy ra"
        GeminiStub.enqueue(.stream(cutReply, finishReason: "MAX_TOKENS"))

        var receivedReason: String?
        var receivedRaw: String?
        service.onAnswerComplete = { raw, reason in
            receivedRaw = raw
            receivedReason = reason
        }

        try await service.sendRESTMessage("giải bài dài", imageData: nil)
        XCTAssertEqual(receivedReason, "MAX_TOKENS")
        let parsed = AnswerFormat.parse(try XCTUnwrap(receivedRaw), finishReason: receivedReason)
        XCTAssertTrue(parsed.isTruncated)
        let plan = ReplyAssembler(languageCode: "vi").plan(turnID: UUID(), parsed: parsed)
        XCTAssertEqual(plan.segments.last?.kind, .notice)
    }

    // MARK: - Follow-up context without re-uploading

    func testFollowUpOnTheSamePhotoKeepsContextWithoutReuploading() async throws {
        let photo = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 4032, height: 3024))
        GeminiStub.enqueue(.stream(answer, signature: "c2lnLTE="))
        GeminiStub.enqueue(.stream("TYPE: OTHER\nANSWER: Vì ta chuyển 3 sang vế phải rồi chia hai vế cho 2."))

        try await service.sendRESTMessage("giải câu này", imageData: photo)
        try await service.sendRESTMessage("Tại sao lại ra x bằng 2?", imageData: photo)

        let followUp = try XCTUnwrap(GeminiStub.captured.last)
        XCTAssertEqual(followUp.contents.count, 3)
        XCTAssertNil(followUp.contents[2].imageData)
        XCTAssertEqual(followUp.contents[2].text, "Tại sao lại ra x bằng 2?")
        let historyPhoto = try XCTUnwrap(followUp.contents[0].imageData)
        let info = try XCTUnwrap(PhotoPayload.imageInfo(historyPhoto))
        XCTAssertEqual(max(info.width, info.height), Int(PhotoPayload.historyMaxDimension))
        XCTAssertEqual(followUp.contents[1].role, "model")
        XCTAssertEqual(followUp.contents[1].thoughtSignature, "c2lnLTE=")
    }

    func testANewPhotoIsUploadedAgain() async throws {
        let first = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 4032, height: 3024))
        let second = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 3024, height: 4032))
        GeminiStub.enqueue(.stream(answer))
        GeminiStub.enqueue(.stream(answer))
        try await service.sendRESTMessage("giải câu này", imageData: first)
        try await service.sendRESTMessage("còn câu này?", imageData: second)
        let sent = try XCTUnwrap(GeminiStub.captured.last?.contents.last?.imageData)
        XCTAssertEqual(PhotoPayload.imageInfo(sent)?.height, PhotoPayload.uploadMaxDimension)
    }

    func testUnrelatedQuestionsGoVerbatimInEitherLanguage() async throws {
        for question in ["Thủ đô của Pháp là gì?", "What's the weather like for a picnic?"] {
            GeminiStub.enqueue(.stream("TYPE: OTHER\nANSWER: ok"))
            try await service.sendRESTMessage(question, imageData: nil)
            let turn = try XCTUnwrap(GeminiStub.captured.last?.contents.last)
            XCTAssertEqual(turn.text, question)
            XCTAssertNil(turn.imageData)
        }
    }

    func testHistoryKeepsTheLastThreeExchanges() async throws {
        for i in 1...4 {
            GeminiStub.enqueue(.stream("TYPE: OTHER\nANSWER: trả lời \(i)"))
            try await service.sendRESTMessage("câu hỏi \(i)", imageData: nil)
        }
        XCTAssertEqual(service.conversationHistoryCount, GeminiLiveService.maxHistoryEntries)
        XCTAssertEqual(GeminiStub.captured.last?.contents.count, 7)
        XCTAssertEqual(GeminiStub.captured.last?.contents.first?.text, "câu hỏi 1")
    }

    // MARK: - Retry policy

    func testQuotaExhaustedKeyRotatesImmediately() async throws {
        GeminiStub.enqueue(.status(429, body: #"{"error":{"code":429,"status":"RESOURCE_EXHAUSTED"}}"#))
        GeminiStub.enqueue(.stream(answer))
        try await service.sendRESTMessage("giải câu này", imageData: nil)
        XCTAssertEqual(GeminiStub.captured.count, 2)
        XCTAssertNotEqual(GeminiStub.captured[0].apiKey, GeminiStub.captured[1].apiKey)
    }

    func testWhenEveryKeyIsExhaustedTheFallbackModelAnswers() async throws {
        for _ in 0..<3 {
            GeminiStub.enqueue(.status(429, body: #"{"error":{"code":429,"status":"RESOURCE_EXHAUSTED"}}"#))
        }
        GeminiStub.enqueue(.stream(answer))
        try await service.sendRESTMessage("giải câu này", imageData: nil)
        XCTAssertEqual(GeminiStub.captured.count, 4)
        XCTAssertTrue(GeminiStub.captured[3].url.path.contains("/\(GeminiLiveService.modelChain[1]):"))
    }

    func testRetiredModelFallsBackInsteadOfFailing() async throws {
        GeminiStub.enqueue(.status(404, body: #"{"error":{"code":404,"message":"models/gemini-3.5-flash-lite is not found"}}"#))
        GeminiStub.enqueue(.stream(answer))
        try await service.sendRESTMessage("giải câu này", imageData: nil)
        XCTAssertTrue(GeminiStub.captured[1].url.path.contains("/\(GeminiLiveService.modelChain[1]):"))
    }

    func testRevokedKeyIsSkippedInsteadOfFailingTheTurn() async throws {
        GeminiStub.enqueue(.status(403, body: #"{"error":{"code":403,"status":"PERMISSION_DENIED"}}"#))
        GeminiStub.enqueue(.status(400, body: #"{"error":{"message":"API key not valid. Please pass a valid API key."}}"#))
        GeminiStub.enqueue(.stream(answer))
        try await service.sendRESTMessage("giải câu này", imageData: nil)
        XCTAssertEqual(GeminiStub.captured.count, 3)
        XCTAssertEqual(Set(GeminiStub.captured.map { $0.apiKey }).count, 3)
    }

    func testUnsupportedMediaResolutionStepsDownAndRetries() async throws {
        let photo = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 2048, height: 1536))
        let rejected = #"{"error":{"message":"Invalid JSON payload received. Unknown name \"mediaResolution\""}}"#
        GeminiStub.enqueue(.status(400, body: rejected))
        GeminiStub.enqueue(.status(400, body: rejected))
        GeminiStub.enqueue(.stream(answer))
        try await service.sendRESTMessage("giải câu này", imageData: photo)
        XCTAssertEqual(GeminiStub.captured.count, 3)
        XCTAssertEqual(GeminiStub.captured[0].contents.last?.mediaResolution, "MEDIA_RESOLUTION_ULTRA_HIGH")
        XCTAssertNil(GeminiStub.captured[1].contents.last?.mediaResolution)
        XCTAssertEqual(GeminiStub.captured[1].generationConfig["mediaResolution"] as? String, "MEDIA_RESOLUTION_HIGH")
        XCTAssertNil(GeminiStub.captured[2].generationConfig["mediaResolution"])
        XCTAssertNil(GeminiStub.captured[2].contents.last?.mediaResolution)
    }

    func testUnsupportedThinkingLevelIsDroppedAndRetried() async throws {
        GeminiStub.enqueue(.status(400, body: #"{"error":{"message":"thinking_level is not supported for this model"}}"#))
        GeminiStub.enqueue(.stream(answer))
        try await service.sendRESTMessage("giải câu này", imageData: nil)
        XCTAssertNotNil(GeminiStub.captured[0].generationConfig["thinkingConfig"])
        XCTAssertNil(GeminiStub.captured[1].generationConfig["thinkingConfig"])
    }

    // MARK: - Agent capture loop

    func testModelAsksToSeeAndTheAppCapturesThenAsksAgain() async throws {
        let photo = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 2048, height: 1536))
        GeminiStub.enqueue(.stream("[[CAPTURE]]"))
        GeminiStub.enqueue(.stream(answer))
        var captures = 0
        service.onCaptureRequested = { _ in
            captures += 1
            return photo
        }
        var partials: [ParsedAnswer] = []
        var finalText: String?
        service.onPartialAnswer = { partials.append($0) }
        service.onTextReceived = { finalText = $0 }

        try await service.sendRESTMessage("câu 3 chọn gì", imageData: nil)

        XCTAssertEqual(captures, 1)
        XCTAssertEqual(GeminiStub.captured.count, 2)
        XCTAssertNil(GeminiStub.captured[0].contents.last?.imageData)
        XCTAssertNotNil(GeminiStub.captured[1].contents.last?.imageData)
        XCTAssertEqual(GeminiStub.captured[1].contents.last?.text, "câu 3 chọn gì")
        XCTAssertEqual(finalText, answer)
        XCTAssertFalse(partials.flatMap(\.sections).contains { $0.text.contains("CAPTURE") })
        XCTAssertEqual(service.conversationHistoryCount, 2)
    }

    func testWhenNoPhotoCanBeTakenTheGlassesSaySo() async throws {
        GeminiStub.enqueue(.stream("[[CAPTURE]]"))
        service.onCaptureRequested = { _ in nil }
        var finalText: String?
        service.onTextReceived = { finalText = $0 }
        try await service.sendRESTMessage("giải câu này", imageData: nil)
        let parsed = AnswerFormat.parse(try XCTUnwrap(finalText))
        XCTAssertEqual(parsed.sections.map(\.text).joined(separator: " "), SolverIntent.missingPhotoMessage(for: "giải câu này"))
        XCTAssertEqual(GeminiStub.captured.count, 1)
    }

    func testRejectedThoughtSignatureResetsTheHistoryOnce() async throws {
        GeminiStub.enqueue(.stream(answer, signature: "b2xk"))
        GeminiStub.enqueue(.status(400, body: #"{"error":{"message":"Thought signature is not valid"}}"#))
        GeminiStub.enqueue(.stream(answer))
        try await service.sendRESTMessage("giải câu này", imageData: nil)
        try await service.sendRESTMessage("tại sao?", imageData: nil)
        XCTAssertEqual(GeminiStub.captured.count, 3)
        XCTAssertEqual(GeminiStub.captured[2].contents.count, 1)
    }

    func testServerOverloadBacksOffAndRetries() async throws {
        GeminiStub.enqueue(.status(503, body: #"{"error":{"code":503,"status":"UNAVAILABLE","message":"This model is currently experiencing high demand."}}"#))
        GeminiStub.enqueue(.stream(answer))
        var finalText: String?
        var statuses: [GeminiLiveStatus] = []
        service.onTextReceived = { finalText = $0 }
        service.onStatusUpdate = { statuses.append($0) }
        try await service.sendRESTMessage("giải câu này", imageData: nil)
        XCTAssertEqual(finalText, answer)
        XCTAssertEqual(GeminiStub.captured.count, 2)
        XCTAssertTrue(GeminiStub.captured[1].url.path.contains("/\(GeminiLiveService.modelChain[1]):"),
                      "HTTP 503 high-demand should fail over immediately to the fallback model")
        XCTAssertTrue(statuses.contains { if case .retrying = $0 { return true }; return false })
    }

    func testABadRequestFailsFastInsteadOfLooping() async throws {
        GeminiStub.enqueue(.status(400, body: #"{"error":{"message":"Request contains an invalid argument."}}"#))
        do {
            try await service.sendRESTMessage("giải câu này", imageData: nil)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(GeminiStub.captured.count, 1)
        }
    }

    func testDroppedStreamKeepsTheAnswerSoFar() async throws {
        let partialReply = "TYPE: ESSAY\nL1: Đáp án là B vì đạo hàm luôn dương.\nL2: $f'(x) = 3x^2"
        GeminiStub.enqueue(.stream(partialReply, dropAtEnd: true))
        var finalText: String?
        service.onTextReceived = { finalText = $0 }
        try await service.sendRESTMessage("câu 3 chọn gì", imageData: nil)
        XCTAssertEqual(GeminiStub.captured.count, 1)
        let parsed = AnswerFormat.parse(finalText ?? "")
        XCTAssertFalse(parsed.sections.isEmpty)
        XCTAssertEqual(parsed.sections.first?.text, "Đáp án là B vì đạo hàm luôn dương.")
    }

    func testDeadNetworkIsRetriedThenReportedNotHung() async throws {
        for _ in 0...GeminiLiveService.maxNetworkRetries {
            GeminiStub.enqueue(.stream("", dropAtEnd: true))
        }
        let started = Date()
        do {
            try await service.sendRESTMessage("giải câu này", imageData: nil)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(GeminiStub.captured.count, GeminiLiveService.maxNetworkRetries + 1)
            XCTAssertLessThan(Date().timeIntervalSince(started), 15)
        }
    }

    // MARK: - Checklist test 2 / lessons 4-5: v2.1 spoken answer plays cleanly through TTSService

    func testSpokenAnswerPlaysCompletelyAndBargeInStaysClosedUntilTheEnd() async throws {
        GeminiStub.enqueue(.stream(answer))
        var finalText: String?
        service.onTextReceived = { finalText = $0 }
        try await service.sendRESTMessage("giải câu này", imageData: nil)
        let parsed = AnswerFormat.parse(try XCTUnwrap(finalText))
        let plan = ReplyAssembler(languageCode: "vi").plan(turnID: UUID(), parsed: parsed)
        XCTAssertEqual(plan.answerType, .essay)
        XCTAssertEqual(plan.segments.count, 3)

        let combinedSpeech = plan.segments.map(\.speechText).joined(separator: " ")
        let pieces = TTSService.spokenPieces(for: combinedSpeech, vietnamese: true, style: .default)
        XCTAssertGreaterThanOrEqual(pieces.count, 2)
        for piece in pieces {
            XCTAssertFalse(piece.text.contains("$") || piece.text.contains("\\"))
        }

        let tts = TTSService.shared
        let savedEnded = tts.onSpeechEnded
        defer { tts.onSpeechEnded = savedEnded }
        let ended = expectation(description: "speech finished")
        ended.assertForOverFulfill = false
        tts.onSpeechEnded = { ended.fulfill() }

        tts.speak(combinedSpeech, languageCode: "vi")
        XCTAssertTrue(tts.isSpeaking)
        XCTAssertGreaterThanOrEqual(tts.pendingUtterances, 2)
        await fulfillment(of: [ended], timeout: 60)
        XCTAssertFalse(tts.isSpeaking)
        XCTAssertEqual(tts.pendingUtterances, 0)
        XCTAssertEqual(SolverIntent.ttsEchoSettleNanoseconds, 350_000_000)
    }
}

// MARK: - Scripted Gemini endpoint

final class GeminiStub: URLProtocol {
    struct Reply {
        var status: Int
        var body: String
        var chunks: [String]
        var dropAtEnd: Bool

        static func stream(_ text: String, dropAtEnd: Bool = false, signature: String? = nil, finishReason: String? = nil) -> Reply {
            var chunks = GeminiStub.sseChunks(text)
            if signature != nil || finishReason != nil {
                var part: [String: Any] = ["text": ""]
                if let signature { part["thoughtSignature"] = signature }
                var candidate: [String: Any] = ["content": ["role": "model", "parts": [part]]]
                if let finishReason { candidate["finishReason"] = finishReason }
                let event: [String: Any] = ["candidates": [candidate]]
                let json = (try? JSONSerialization.data(withJSONObject: event)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                chunks.append("data: \(json)\r\n\r\n")
            }
            return Reply(status: 200, body: "", chunks: chunks, dropAtEnd: dropAtEnd)
        }

        static func status(_ code: Int, body: String) -> Reply {
            Reply(status: code, body: body, chunks: [], dropAtEnd: false)
        }
    }

    struct Turn {
        let role: String
        let text: String?
        let imageData: Data?
        let imageMIMEType: String?
        let mediaResolution: String?
        let thoughtSignature: String?
    }

    struct Captured {
        let url: URL
        let apiKey: String?
        let json: [String: Any]

        func query(_ name: String) -> String? {
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
        }

        var generationConfig: [String: Any] { json["generationConfig"] as? [String: Any] ?? [:] }

        var systemPrompt: String {
            let parts = (json["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]]
            return parts?.compactMap { $0["text"] as? String }.joined() ?? ""
        }

        var contents: [Turn] {
            (json["contents"] as? [[String: Any]] ?? []).map { turn in
                let parts = turn["parts"] as? [[String: Any]] ?? []
                let imagePart = parts.first { $0["inlineData"] != nil }
                let inline = imagePart?["inlineData"] as? [String: Any]
                return Turn(role: turn["role"] as? String ?? "",
                            text: parts.compactMap { $0["text"] as? String }.first,
                            imageData: (inline?["data"] as? String).flatMap { Data(base64Encoded: $0) },
                            imageMIMEType: inline?["mimeType"] as? String,
                            mediaResolution: (imagePart?["mediaResolution"] as? [String: Any])?["level"] as? String,
                            thoughtSignature: parts.compactMap { $0["thoughtSignature"] as? String }.first)
            }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [Reply] = []
    nonisolated(unsafe) private static var log: [Captured] = []

    static var captured: [Captured] { lock.withLock { log } }

    static func reset() {
        lock.withLock {
            replies = []
            log = []
        }
    }

    static func enqueue(_ reply: Reply) {
        lock.withLock { replies.append(reply) }
    }

    static func sseChunks(_ text: String, pieces: Int = 5) -> [String] {
        guard !text.isEmpty else { return [] }
        let characters = Array(text)
        let size = max(1, characters.count / pieces)
        return stride(from: 0, to: characters.count, by: size).map { start in
            let piece = String(characters[start..<min(start + size, characters.count)])
            let event: [String: Any] = ["candidates": [["content": ["role": "model", "parts": [["text": piece]]]]]]
            let json = (try? JSONSerialization.data(withJSONObject: event)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return "data: \(json)\r\n\r\n"
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "generativelanguage.googleapis.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body = Self.readBody(request)
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let reply: Reply = Self.lock.withLock {
            Self.log.append(Captured(url: url, apiKey: request.value(forHTTPHeaderField: "x-goog-api-key"), json: json))
            return Self.replies.isEmpty ? .status(500, body: "no scripted reply") : Self.replies.removeFirst()
        }
        let contentType = reply.status == 200 ? "text/event-stream" : "application/json"
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if reply.status != 200 {
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        }
        for chunk in reply.chunks {
            client?.urlProtocol(self, didLoad: Data(chunk.utf8))
        }
        if reply.dropAtEnd {
            if !reply.chunks.isEmpty { Thread.sleep(forTimeInterval: 0.3) }
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
