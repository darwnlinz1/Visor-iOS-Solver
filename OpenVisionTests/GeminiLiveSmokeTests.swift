// OpenVision - GeminiLiveSmokeTests.swift
// OPT-IN smoke test against the REAL Gemini API using the v2.1 AnswerFormat + VietMathSpeech contract.

import XCTest
@testable import OpenVision

@MainActor
final class GeminiLiveSmokeTests: XCTestCase {

    private var service: GeminiLiveService { GeminiLiveService.shared }
    private var savedText: ((String) -> Void)?
    private var savedAgent: ((String) -> Void)?
    private var savedPartial: ((ParsedAnswer) -> Void)?
    private var savedComplete: ((String, String?) -> Void)?

    override func setUp() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["OPENVISION_LIVE_GEMINI"] == "1",
                          "live Gemini smoke test is opt-in (OPENVISION_LIVE_GEMINI=1)")
        let keys = GeminiLiveService.parseKeys(env["OPENVISION_GEMINI_API_KEYS"] ?? "")
        try XCTSkipIf(keys.isEmpty, "set OPENVISION_GEMINI_API_KEYS for the live smoke test")
        savedText = service.onTextReceived
        savedAgent = service.agentMessageCallback
        savedPartial = service.onPartialAnswer
        savedComplete = service.onAnswerComplete
        service.agentMessageCallback = nil
        service.onPartialAnswer = nil
        service.onAnswerComplete = nil
        service.urlProtocolClasses = []
        service.apiKeysOverride = keys
        service.clearConversationHistory()
        service.resetNetworkState()
    }

    override func tearDown() async throws {
        service.onTextReceived = savedText
        service.agentMessageCallback = savedAgent
        service.onPartialAnswer = savedPartial
        service.onAnswerComplete = savedComplete
        service.apiKeysOverride = nil
        service.clearConversationHistory()
    }

    func testVietnameseQuestionAboutAPhotoGetsAVietnameseV21Answer() async throws {
        let photo = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 2400, height: 1200))
        let reply = try await ask("giải câu này", photo: photo)
        let parsed = AnswerFormat.parse(reply)
        let plan = ReplyAssembler(languageCode: "vi").plan(turnID: UUID(), parsed: parsed)
        XCTAssertFalse(plan.segments.isEmpty, "expected parsed v2.1 sections: \(reply)")
        let voiced = plan.segments.map {
            VietMathSpeech.spokenText(VietMathSpeech.render($0.speechText, vietnamese: true, style: .default))
        }.joined(separator: " ")
        XCTAssertTrue(TTSService.containsVietnamese(voiced), "Vietnamese question -> Vietnamese answer: \(voiced)")
        XCTAssertTrue(voiced.contains("2"), "2x + 3 = 7 -> x = 2: \(voiced)")
        XCTAssertFalse(voiced.contains("$") || voiced.contains("\\"), "no raw LaTeX in spoken text: \(voiced)")
    }

    func testEnglishQuestionGetsAnEnglishAnswer() async throws {
        let photo = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 2400, height: 1200))
        let reply = try await ask("what is x in this equation?", photo: photo)
        let parsed = AnswerFormat.parse(reply)
        let plan = ReplyAssembler(languageCode: "en").plan(turnID: UUID(), parsed: parsed)
        XCTAssertFalse(plan.segments.isEmpty)
        let voiced = plan.segments.map {
            VietMathSpeech.spokenText(VietMathSpeech.render($0.speechText, vietnamese: false, style: .default))
        }.joined(separator: " ")
        XCTAssertFalse(TTSService.containsVietnamese(voiced), "English question -> English answer: \(voiced)")
        XCTAssertTrue(voiced.contains("2"), voiced)
    }

    func testUnrelatedQuestionIsAnsweredNormallyDespiteThePhoto() async throws {
        let photo = try XCTUnwrap(BlueprintSolverTests.jpeg(width: 2400, height: 1200))
        let reply = try await ask("Thủ đô của nước Pháp là gì?", photo: photo)
        XCTAssertTrue(reply.contains("Paris"), reply)
    }

    private func ask(_ question: String, photo: Data?) async throws -> String {
        var reply: String?
        service.onTextReceived = { reply = $0 }
        try await service.sendRESTMessage(question, imageData: photo)
        return try XCTUnwrap(reply)
    }
}
