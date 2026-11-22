// OpenVision - ReplyAssemblerSpeechTests.swift
// The whole wave 1 reading pipeline (PLAN.md §4.2–4.4, review item I3): a v2.1 reply goes through
// AnswerFormat → ReplyAssembler → VietMathSpeech, and the tests check the exact words the glasses
// will say for every segment with the default reading style (letter names, D3). They lock the
// cross-module cases from the wave 1 review: X1 ("Câu 12: 3/4." read as a division), B1 (Δ' read as
// "Delta"), B5 ("Bài 2.15" read as a decimal). Pure logic: runs on Linux (scripts/swift-local/run.sh)
// and in the iOS test target.

import XCTest
@testable import OpenVision

final class ReplyAssemblerSpeechTests: XCTestCase {

    // MARK: - Helpers

    private func prose(_ text: String) -> SpeechPiece { .words(text, isMath: false) }
    private func math(_ text: String) -> SpeechPiece { .words(text, isMath: true) }

    /// The plan for a finished reply, as the view model will build it.
    private func plan(_ reply: String, language: String, finishReason: String? = nil) -> ReadingPlan {
        ReplyAssembler(languageCode: language)
            .plan(turnID: UUID(), parsed: AnswerFormat.parse(reply, finishReason: finishReason))
    }

    /// What is said for each segment, in reading order. Also checks the §4.3 output constraints.
    private func spoken(_ plan: ReadingPlan, line: UInt = #line) -> [[SpeechPiece]] {
        let vietnamese = plan.languageCode == "vi"
        let segments = plan.segments.map {
            VietMathSpeech.render($0.speechText, vietnamese: vietnamese, style: .default)
        }
        for piece in segments.joined() {
            guard case .words(let words, _) = piece else { continue }
            XCTAssertFalse(words.contains { "\\${}^_".contains($0) }, "markup left in «\(words)»", line: line)
            XCTAssertLessThanOrEqual(words.count, 200, "piece longer than 200 characters: «\(words)»", line: line)
        }
        return segments
    }

    // MARK: - Vietnamese

    func testMultipleChoiceIsReadAsAnswersOnly() {
        let reading = plan("""
        TYPE: MCQ
        Q1: A
        Q2: a Đ, b S, c Đ, d S
        Q4: 2,5
        Q5: -1/2
        Q12: 3/4
        Q7: ?
        """, language: "vi")

        XCTAssertEqual(reading.answerType, .mcq)
        XCTAssertEqual(spoken(reading), [
            [prose("Câu 1: a.")],
            [prose("Câu 2: a đúng, bê sai, xê đúng, đê sai.")],
            [prose("Câu 4: 2 phẩy 5.")],
            [prose("Câu 5:"), math("âm một phần hai")],
            [prose("Câu 12:"), math("ba phần tư")],
            [prose("Câu 7: không đọc được đề.")],
        ])
    }

    func testEssayIsReadLineByLineWithFormulasInWords() {
        let reading = plan(#"""
        TYPE: ESSAY
        P1: Bài 2.15
        L1: Ta có $\Delta' = b'^2 - ac = 4 - 3 = 1$.
        L2: Vì $\Delta' > 0$ nên phương trình có hai nghiệm phân biệt.
        L3: $x_1 = 3$, $x_2 = 1$.
        FINAL: Vậy tập nghiệm là $S = \{1; 3\}$.
        """#, language: "vi")

        XCTAssertEqual(reading.answerType, .essay)
        XCTAssertEqual(spoken(reading), [
            [prose("Bài 2 chấm 15.")],
            [prose("Dòng 1."), prose("Ta có"),
             math("đen-ta phẩy bằng bê phẩy bình phương trừ a xê bằng 4 trừ 3 bằng 1")],
            [prose("Dòng 2."), prose("Vì"), math("đen-ta phẩy lớn hơn 0"),
             prose("nên phương trình có hai nghiệm phân biệt.")],
            [prose("Dòng 3."), math("ích một bằng 3"), math("ích hai bằng 1")],
            [prose("Đáp số: Vậy tập nghiệm là"), math("ét bằng tập hợp gồm 1 và 3")],
        ])
    }

    func testMixedReplyReadsBareUnicodeMathInsideALine() {
        let reading = plan(#"""
        TYPE: MIXED
        Q1: B
        P1: Bài 2
        L1: Ta có x² - 4x + 3 = 0 nên x = 1 hoặc x = 3.
        FINAL: Vậy $x \in \{1; 3\}$.
        """#, language: "vi")

        XCTAssertEqual(reading.answerType, .mixed)
        XCTAssertEqual(spoken(reading), [
            [prose("Câu 1: bê.")],
            [prose("Bài 2.")],
            [prose("Dòng 1."), prose("Ta có"), math("ích bình phương trừ 4 ích cộng 3 bằng 0"),
             prose("nên"), math("ích bằng 1"), prose("hoặc"), math("ích bằng 3")],
            [prose("Đáp số: Vậy"), math("ích thuộc tập hợp gồm 1 và 3")],
        ])
    }

    func testCutOffReplyEndsWithTheContinueNotice() {
        let reading = plan(#"""
        TYPE: ESSAY
        L1: Ta có $2x = 4$.
        L2: Suy ra $x = 2$.
        L3: Thay vào
        """#, language: "vi", finishReason: "MAX_TOKENS")

        XCTAssertEqual(spoken(reading), [
            [prose("Dòng 1."), prose("Ta có"), math("2 ích bằng 4")],
            [prose("Dòng 2."), prose("Suy ra"), math("ích bằng 2")],
            [prose("Lời giải dài nên mình dừng ở dòng 2."), prose("Bạn hỏi 'giải tiếp' để mình giải nốt.")],
        ])
    }

    // MARK: - English

    func testEnglishRepliesUseEnglishLabelsAndMathWords() {
        let answers = plan("""
        TYPE: MCQ
        Q12: 3/4
        Q3: a T, b F, c T, d F
        Q7: ?
        """, language: "en")
        XCTAssertEqual(spoken(answers), [
            [prose("Question 12:"), math("3 over 4")],
            [prose("Question 3: a true, b false, c true, d false.")],
            [prose("Question 7: unreadable.")],
        ])

        let essay = plan(#"""
        TYPE: ESSAY
        L1: We have $\Delta = b^2 - 4ac = 9$.
        FINAL: $x = 2$
        """#, language: "en")
        XCTAssertEqual(spoken(essay), [
            [prose("Line 1."), prose("We have"), math("delta equals b squared minus 4 a c equals 9")],
            [prose("Answer:"), math("x equals 2")],
        ])
    }
}
