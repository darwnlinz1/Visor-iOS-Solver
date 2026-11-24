// Reybain - BlueprintSolverTests.swift
// Pure-logic layer of the Blueprint end-to-end suite (updated for v2.1 voice-first format, T3.3, T4.1, T4.4, T6.2, T8.3).

import XCTest
import UIKit
import AVFoundation
@testable import Reybain

@MainActor
final class BlueprintSolverTests: XCTestCase {

    // MARK: - Lesson 5 / T3.3: VietMathSpeech runs BEFORE cleanSpokenAudio (N4 regression tests)

    func testCleanSpokenAudioKeepsMathSemanticsAndStripsMarkdown() {
        XCTAssertEqual(TTSService.cleanSpokenAudio("**âm 2 ích cộng 4 bằng 0**"), "âm 2 ích cộng 4 bằng 0")
        XCTAssertEqual(TTSService.cleanSpokenAudio("-2 + 4 = 2"), "-2 + 4 = 2")
        XCTAssertEqual(TTSService.cleanSpokenAudio("   "), "")
        for sample in ["Tích phân $x$ bằng một phần hai.", "Đáp án {B}", "## Kết quả"] {
            let cleaned = TTSService.cleanSpokenAudio(sample)
            XCTAssertFalse(cleaned.contains("$") || cleaned.contains("\\") || cleaned.contains("{"), cleaned)
        }
    }

    func testSpokenPiecesFixesN4MathCorruption() {
        let texts: [(String, [String])] = [
            (#"Ta có $\frac{1}{2}$ cộng $\sqrt{4}$ bằng **2,5**."#,
             ["Ta có", "một phần hai", "cộng", "căn 4", "bằng 2 phẩy 5."]),
            (#"$\sqrt{x}$"#, ["căn ích"]),
            (#"$x \le 2$"#, ["ích nhỏ hơn hoặc bằng 2"]),
            ("-2x + 4 = 0", ["âm 2 ích cộng 4 bằng 0"]),
            ("2*3*4 = 24", ["2 nhân 3 nhân 4 bằng 24"]),
            (#"Đáp án $\boxed{B}$"#, ["Đáp án", "bê"]),
            (#"\[ x = 2 \]"#, ["ích bằng 2"]),
        ]
        for (input, expected) in texts {
            let pieces = TTSService.spokenPieces(for: input, vietnamese: true, style: .default).map(\.text)
            XCTAssertEqual(pieces, expected, "N4 regression for: \(input)")
        }
    }

    // MARK: - Bilingual: the voice follows the answer's language

    func testLanguageDetection() {
        XCTAssertTrue(TTSService.containsVietnamese("Giải câu này"))
        XCTAssertTrue(TTSService.containsVietnamese("giai bai nay giup minh"))
        XCTAssertFalse(TTSService.containsVietnamese("solve this"))
        XCTAssertFalse(TTSService.containsVietnamese("That statement is true for every structure."))
        XCTAssertFalse(TTSService.containsVietnamese("Tap the congress button"))
    }

    func testVoiceFollowsAnswerLanguage() {
        let english = TTSService.voice(forText: "The answer is B because the derivative is positive.")
        XCTAssertTrue(english?.language.hasPrefix("en") ?? false, "English answer -> English voice, got \(String(describing: english?.language))")
        if AVSpeechSynthesisVoice(language: "vi-VN") != nil {
            let vietnamese = TTSService.voice(forText: "Đáp án là B vì đạo hàm dương.")
            XCTAssertEqual(vietnamese?.language, "vi-VN")
            let chosenEnglish = AVSpeechSynthesisVoice(language: "en-GB")
            XCTAssertEqual(TTSService.voice(forText: "x bằng 2", english: chosenEnglish)?.language, "vi-VN",
                           "a Vietnamese answer is never read by an English voice")
        }
    }

    // MARK: - Streaming & SSE parsing

    func testSSEParsingJoinsTextPartsAndSkipsThoughts() {
        let line = #"data: {"candidates":[{"content":{"parts":[{"text":"thinking...","thought":true},{"text":"TYPE: OTHER\nANSWER: x "},{"text":"bằng 2."}]},"finishReason":"STOP"}]}"#
        let chunk = GeminiLiveService.parseSSELine(line)
        XCTAssertEqual(chunk?.text, "TYPE: OTHER\nANSWER: x bằng 2.")
        XCTAssertEqual(chunk?.finishReason, "STOP")
        XCTAssertNil(GeminiLiveService.parseSSELine(": keep-alive"))
        XCTAssertNil(GeminiLiveService.parseSSELine(""))
        let blocked = GeminiLiveService.parseSSELine(#"data: {"promptFeedback":{"blockReason":"SAFETY"}}"#)
        XCTAssertEqual(blocked?.blockReason, "SAFETY")
        let last = GeminiLiveService.parseSSELine(#"data: {"candidates":[{"content":{"parts":[{"text":"","thoughtSignature":"c2lnbmF0dXJl"}]},"finishReason":"STOP"}]}"#)
        XCTAssertEqual(last?.text, "")
        XCTAssertEqual(last?.thoughtSignature, "c2lnbmF0dXJl")
        XCTAssertEqual(last?.finishReason, "STOP")
    }

    func testModelTurnKeepsTheThoughtSignature() {
        let turn = GeminiLiveService.modelTurn(text: "TYPE: OTHER\nANSWER: x bằng 2", signature: "c2ln")
        let parts = turn["parts"] as? [[String: Any]]
        XCTAssertEqual(parts?.count, 2)
        XCTAssertEqual(parts?.last?["thoughtSignature"] as? String, "c2ln")
        XCTAssertEqual((GeminiLiveService.modelTurn(text: "ok", signature: nil)["parts"] as? [[String: Any]])?.count, 1)
    }

    // MARK: - Keys & agent protocol

    func testKeysAreParsedFromSettingsText() {
        XCTAssertEqual(GeminiLiveService.parseKeys(" AQ.aaa, AIzabbb\nAQ.ccc;AQ.aaa "), ["AQ.aaa", "AIzabbb", "AQ.ccc"])
        XCTAssertEqual(GeminiLiveService.parseKeys(""), [])
    }

    func testAgentCaptureToken() {
        XCTAssertTrue(GeminiLiveService.isCaptureRequest("[[CAPTURE]]"))
        XCTAssertTrue(GeminiLiveService.isCaptureRequest("  [[capture]]\n"))
        XCTAssertFalse(GeminiLiveService.isCaptureRequest("TYPE: MCQ\nQ1: A"))
    }

    // MARK: - Retry policy

    func testHTTPFailuresAreClassifiedForTheRetryPolicy() {
        typealias G = GeminiLiveService
        XCTAssertEqual(G.classifyHTTPError(status: 429, body: "", retryAfter: "7"), .rateLimited(retryAfter: 7))
        XCTAssertEqual(G.classifyHTTPError(status: 429, body: "", retryAfter: nil), .rateLimited(retryAfter: nil))
        guard case .badKey = G.classifyHTTPError(status: 403, body: "PERMISSION_DENIED", retryAfter: nil) else {
            return XCTFail("a revoked key must rotate, not fail the turn")
        }
        guard case .badKey = G.classifyHTTPError(status: 400, body: "API key not valid. Please pass a valid API key.", retryAfter: nil) else {
            return XCTFail("an invalid key must rotate, not fail the turn")
        }
        XCTAssertEqual(G.classifyHTTPError(status: 400, body: "Invalid JSON payload received. Unknown name \"mediaResolution\"", retryAfter: nil),
                       .unsupportedField(.mediaResolution, "HTTP 400: Invalid JSON payload received. Unknown name \"mediaResolution\""))
        guard case .unsupportedField(.thinking, _) = G.classifyHTTPError(status: 400, body: "thinking_level is not supported for this model", retryAfter: nil) else {
            return XCTFail("an unsupported thinking level must trigger a retry without it")
        }
        guard case .staleSignature = G.classifyHTTPError(status: 400, body: "Thought signature is not valid", retryAfter: nil) else {
            return XCTFail("a rejected thought signature must reset the history, not fail every follow-up")
        }
        guard case .modelUnavailable = G.classifyHTTPError(status: 404, body: "models/x is not found", retryAfter: nil) else {
            return XCTFail("a retired model must fall back to the next model")
        }
        guard case .serverError = G.classifyHTTPError(status: 503, body: "overloaded", retryAfter: nil) else {
            return XCTFail("5xx must back off and retry")
        }
        guard case .fatal = G.classifyHTTPError(status: 400, body: "Request contains an invalid argument.", retryAfter: nil) else {
            return XCTFail("a genuinely bad request must not loop")
        }
        XCTAssertLessThanOrEqual(G.overallDeadline, 180)
        XCTAssertGreaterThanOrEqual(G.idleTimeout, 45)
    }

    // MARK: - Photo payload

    func testSmallUprightJPEGPassesThroughUntouched() throws {
        let original = try XCTUnwrap(Self.jpeg(width: 3072, height: 2304))
        XCTAssertEqual(PhotoPayload.uploadJPEG(from: original), original)
        XCTAssertEqual(PhotoPayload.mimeType(for: original), "image/jpeg")
    }

    func testTwelveMegapixelPhotoIsSentAt3072px() throws {
        let original = try XCTUnwrap(Self.jpeg(width: 4032, height: 3024))
        let payload = try XCTUnwrap(PhotoPayload.uploadJPEG(from: original))
        let info = try XCTUnwrap(PhotoPayload.imageInfo(payload))
        XCTAssertEqual(max(info.width, info.height), PhotoPayload.uploadMaxDimension)
        XCTAssertEqual(info.orientation, 1)
        XCTAssertLessThan(payload.count, original.count)
    }

    func testNonJPEGIsReencodedAsJPEG() throws {
        let png = try XCTUnwrap(Self.image(width: 2000, height: 1500).pngData())
        XCTAssertEqual(PhotoPayload.mimeType(for: png), "image/png")
        let payload = try XCTUnwrap(PhotoPayload.uploadJPEG(from: png))
        XCTAssertEqual(PhotoPayload.mimeType(for: payload), "image/jpeg")
        XCTAssertEqual(PhotoPayload.imageInfo(payload)?.width, 2000)
    }

    func testHistoryCopyIsLighterButReadable() throws {
        let original = try XCTUnwrap(Self.jpeg(width: 3072, height: 2304))
        let copy = PhotoPayload.historyCopy(of: original)
        let info = try XCTUnwrap(PhotoPayload.imageInfo(copy))
        XCTAssertEqual(max(info.width, info.height), Int(PhotoPayload.historyMaxDimension))
        XCTAssertLessThan(copy.count, original.count)
        let small = try XCTUnwrap(Self.jpeg(width: 800, height: 600))
        XCTAssertEqual(PhotoPayload.historyCopy(of: small), small)
        XCTAssertNotEqual(PhotoPayload.fingerprint(original), PhotoPayload.fingerprint(small))
    }

    // MARK: - Workflow, wake words (T8.3), and LiveTurnGrouper (T6.2)

    func testRecognizerLanguageSetting() {
        XCTAssertEqual(VoiceCommandService.recognitionLocaleIdentifier("vi-VN"), "vi-VN")
        XCTAssertEqual(VoiceCommandService.recognitionLocaleIdentifier("en-US"), "en-US")
        XCTAssertFalse(VoiceCommandService.recognitionLocaleIdentifier("auto").contains("_"))
    }

    func testPhotoContextLivesFor120SecondsAndFiveQuestions() {
        let shot = Date()
        var context = CapturedPhotoContext(data: Data([0xFF, 0xD8, 0xFF]), timestamp: shot)
        XCTAssertTrue(context.isFresh(at: shot.addingTimeInterval(119)))
        XCTAssertFalse(context.isFresh(at: shot.addingTimeInterval(120)))
        context.useCount = CapturedPhotoContext.maxUses
        XCTAssertFalse(context.isFresh(at: shot.addingTimeInterval(1)))
        XCTAssertEqual(SolverIntent.recentPhotoWindow, 120)
    }

    func testStopIsMatchedOnWordsInBothLanguages() {
        for stop in ["stop", "dừng lại", "thôi", "Okay stop", "be quiet", "ngừng đi"] {
            XCTAssertTrue(SolverIntent.isStopCommand(stop), stop)
        }
        for question in ["what's on the desktop", "giải câu này", "stop video", "Tại sao ra x bằng 2?"] {
            XCTAssertFalse(SolverIntent.isStopCommand(question), question)
        }
    }

    func testMessagesAreSpokenInTheWearersLanguage() {
        XCTAssertTrue(SolverIntent.missingPhotoMessage(for: "giải câu này").contains("Không tìm thấy ảnh"))
        XCTAssertTrue(SolverIntent.missingPhotoMessage(for: "solve this").contains("No photo found"))
        XCTAssertTrue(TTSService.containsVietnamese(SolverIntent.networkFailureMessage(for: "câu 2 thì sao")))
        XCTAssertTrue(SolverIntent.missingKeyMessage(for: "giải câu này").contains("API key"))
        XCTAssertFalse(TTSService.containsVietnamese(SolverIntent.networkFailureMessage(for: "and question two?")))
    }

    func testWakeWordIsStrippedAndNoisyVariantsAreRemoved() {
        XCTAssertEqual(VoiceCommandService.stripWakeWord(from: "ô kê vi dơn giải câu này", defaultWakeWord: "ok vision"), "giải câu này")
        XCTAssertEqual(VoiceCommandService.stripWakeWord(from: "Ok Vision what does this say", defaultWakeWord: "ok vision"), "what does this say")
        XCTAssertEqual(VoiceCommandService.stripWakeWord(from: "vi dơn câu 2 thì sao", defaultWakeWord: "ok vision"), "câu 2 thì sao")
        for variant in ["ô kê vi dơn", "ok vi dơn", "vi dơn", "ok vision"] {
            XCTAssertTrue(VoiceCommandService.wakeWordVariations.contains(variant), variant)
        }
        // T8.3 / B12: noisy false-positive variants are removed.
        for noisy in ["a vision", "heavy vision", "have vision", "obey vision"] {
            XCTAssertFalse(VoiceCommandService.wakeWordVariations.contains(noisy), "noisy variant \(noisy) should be removed")
        }
    }

    func testSystemPromptUsesV21ContractAndNoScreenRule() {
        let prompt = GeminiLiveService.shared.buildSystemPrompt()
        XCTAssertTrue(prompt.contains("TYPE: MCQ"))
        XCTAssertTrue(prompt.contains("TYPE: ESSAY"))
        XCTAssertTrue(prompt.contains("TYPE: MIXED"))
        XCTAssertTrue(prompt.contains("TYPE: OTHER"))
        XCTAssertTrue(prompt.contains(PromptV2.noScreenRule))
        XCTAssertTrue(prompt.contains("ALWAYS answer in the language the user used"))
        XCTAssertTrue(prompt.contains(GeminiLiveService.captureToken))
        XCTAssertTrue(prompt.contains(GeminiLiveService.endToken))
        XCTAssertFalse(prompt.contains("DISPLAY:"))
        XCTAssertFalse(prompt.contains("SPOKEN:"))
        XCTAssertFalse(prompt.lowercased().contains("do not reveal the final answer"))
    }

    func testMathOnlySentencesFollowTheRepliesLanguage() {
        XCTAssertTrue(TTSService.isLanguageNeutral("x = 2."))
        XCTAssertTrue(TTSService.isLanguageNeutral("B."))
        XCTAssertFalse(TTSService.isLanguageNeutral("The answer is B."))
        XCTAssertFalse(TTSService.isLanguageNeutral("Vậy x bằng 2."))
    }

    func testGoodbyeTokenEndsTheSessionAndIsNeverSpoken() {
        let reply = "TYPE: OTHER\nANSWER: Không có gì, chúc bạn học tốt!\n[[END]]"
        XCTAssertTrue(GeminiLiveService.endsConversation(reply))
        let parsed = AnswerFormat.parse(reply)
        XCTAssertTrue(parsed.endsConversation)
        XCTAssertFalse(parsed.sections.map(\.text).joined().contains("END"))
        XCTAssertFalse(GeminiLiveService.endsConversation("TYPE: MCQ\nQ1: A"))
        XCTAssertTrue(GeminiLiveService.shared.buildSystemPrompt().contains(GeminiLiveService.endToken))
    }

    func testHistoryRepliesAreFedBackInV21Shape() {
        let record = ReplyAssembler(languageCode: "vi").record(for: AnswerFormat.parse("TYPE: MCQ\nQ1: B\nQ2: C"))
        let rebuilt = AnswerFormat.text(for: record)
        let reparsed = AnswerFormat.parse(rebuilt)
        XCTAssertEqual(reparsed.type, .mcq)
        XCTAssertEqual(reparsed.sections.count, 2)
        XCTAssertEqual(reparsed.sections[0].questionAnswer, .choice("B"))
        XCTAssertEqual(reparsed.sections[1].questionAnswer, .choice("C"))
    }

    func testLiveTurnGrouperPairsMessagesAndAttachesActiveStreamingPlan() {
        let user1 = Message.user("Giải câu 1")
        let record = ReplyAssembler(languageCode: "vi").record(for: AnswerFormat.parse("TYPE: MCQ\nQ1: A"))
        let assistant1 = Message.assistant("Câu 1: A", reading: record)
        let user2 = Message.user("Giải câu 2")
        let streaming = ReplyAssembler(languageCode: "vi").plan(turnID: UUID(), parsed: AnswerFormat.parse("TYPE: MCQ\nQ2: B"))

        let turns = LiveTurnGrouper.turns(
            from: [user1, assistant1, user2],
            pendingUserText: "Giải câu 2",
            pendingPhotoData: nil,
            activePlan: streaming,
            isThinking: false
        )
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].readingRecord, record)
        XCTAssertEqual(turns[1].userText, "Giải câu 2")
        XCTAssertEqual(turns[1].readingRecord, streaming.record)
        XCTAssertTrue(turns[1].isActiveTurn)
    }

    // MARK: - Helpers

    static func image(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let text = "2x + 3 = 7. Tìm x." as NSString
            text.draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: CGFloat(height) / 12)])
        }
    }

    static func jpeg(width: Int, height: Int) -> Data? {
        image(width: width, height: height).jpegData(compressionQuality: 0.9)
    }
}
