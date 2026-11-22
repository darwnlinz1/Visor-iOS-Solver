// OpenVision - ReplyAssemblerTests.swift
// Parsed sections → ReadingPlan / ReadingRecord (PLAN.md §4.2 reading table, §4.4): the exact
// text shown and read for every kind, in Vietnamese and English, with and without line numbers,
// built while streaming, and stored in History (Codable round trip). Pure logic: runs on Linux
// (scripts/swift-local/run.sh) and in the iOS test target.

import XCTest
@testable import OpenVision

final class ReplyAssemblerTests: XCTestCase {

    // MARK: - Fixtures

    private let mcqReply = """
    TYPE: MCQ
    Q1: A
    Q2: C
    Q3: a D, b S, c D, d S
    Q4: 2,5
    Q7: ?
    """

    private let essayReply = #"""
    TYPE: ESSAY
    P1: Bài 1
    L1: Ta có $\Delta = b^2 - 4ac = 9$.
    L2: Vì $\Delta > 0$ nên phương trình có hai nghiệm phân biệt.
    L3: $x_1 = 2$, $x_2 = \frac{1}{2}$.
    FINAL: Vậy tập nghiệm là $S = \{\frac{1}{2}; 2\}$.
    """#

    private let englishEssayReply = """
    TYPE: ESSAY
    P1: Problem 1
    L1: We have $2x = 4$
    L2: So $x = 2$.
    FINAL: $x = 2$
    """

    private let mixedReply = #"""
    TYPE: MIXED
    Q1: B
    Q2: a S, b Đ, c Đ, d S
    P1: Bài 1
    L1: $2x + 3 = 7$ nên $2x = 4$.
    L2: $x = 2$.
    FINAL: Vậy $x = 2$.
    """#

    private let otherReply = """
    TYPE: OTHER
    ANSWER: Đây là tháp Eiffel ở Paris, hoàn thành năm 1889. Tháp cao khoảng 330 mét.
    ANSWER: Nó là biểu tượng của nước Pháp
    """

    /// No TYPE line: the first tag line decides the type (L → ESSAY), the lead-in sentence does not.
    private let untypedEssayReply = #"""
    Lời giải như sau.
    L1: $2x + 3 = 7$ nên $2x = 4$.
    L2: $x = 2$.
    FINAL: Vậy $x = 2$.
    """#

    /// No TYPE line: Q → MCQ.
    private let untypedMCQReply = """
    Q1: A
    Q2: C
    Q3: a Đ, b S, c Đ, d S
    """

    private let vietnamese = ReplyAssembler(languageCode: "vi")
    private let english = ReplyAssembler(languageCode: "en")

    private func plan(_ reply: String, _ assembler: ReplyAssembler, finishReason: String? = nil) -> ReadingPlan {
        assembler.plan(turnID: UUID(), parsed: AnswerFormat.parse(reply, finishReason: finishReason))
    }

    // MARK: - Multiple choice

    func testMCQIsReadAsQuestionNumberAndAnswerOnly() {
        let plan = plan(mcqReply, vietnamese)
        XCTAssertEqual(plan.answerType, .mcq)
        XCTAssertEqual(plan.languageCode, "vi")
        XCTAssertTrue(plan.isComplete)
        XCTAssertEqual(plan.segments, [
            ReadingSegment(id: 0, kind: .mcq(1), title: "Câu 1", displayText: "Câu 1: A", speechText: "Câu 1: A."),
            ReadingSegment(id: 1, kind: .mcq(2), title: "Câu 2", displayText: "Câu 2: C", speechText: "Câu 2: C."),
            ReadingSegment(id: 2, kind: .mcq(3), title: "Câu 3", displayText: "Câu 3: a Đ, b S, c Đ, d S",
                           speechText: "Câu 3: a đúng, b sai, c đúng, d sai."),
            ReadingSegment(id: 3, kind: .mcq(4), title: "Câu 4", displayText: "Câu 4: 2,5", speechText: "Câu 4: 2,5."),
            ReadingSegment(id: 4, kind: .mcq(7), title: "Câu 7", displayText: "Câu 7: ?", speechText: "Câu 7: không đọc được đề."),
        ])
    }

    func testMCQInEnglish() {
        XCTAssertEqual(plan(mcqReply, english).segments.map(\.speechText), [
            "Question 1: A.", "Question 2: C.", "Question 3: a true, b false, c true, d false.",
            "Question 4: 2,5.", "Question 7: unreadable.",
        ])
        XCTAssertEqual(plan(mcqReply, english).segments[2].displayText, "Question 3: a T, b F, c T, d F")
        XCTAssertEqual(plan(mcqReply, english).segments.map(\.title).first, "Question 1")
    }

    // MARK: - Essay

    func testEssayIsReadLineByLineWithLineNumbers() {
        let plan = plan(essayReply, vietnamese)
        XCTAssertEqual(plan.answerType, .essay)
        XCTAssertEqual(plan.segments, [
            ReadingSegment(id: 0, kind: .problem(1), title: "Bài 1", displayText: "Bài 1", speechText: "Bài 1."),
            ReadingSegment(id: 1, kind: .line(1), title: "Dòng 1",
                           displayText: #"Dòng 1: Ta có $\Delta = b^2 - 4ac = 9$."#,
                           speechText: #"Dòng 1. Ta có $\Delta = b^2 - 4ac = 9$."#),
            ReadingSegment(id: 2, kind: .line(2), title: "Dòng 2",
                           displayText: #"Dòng 2: Vì $\Delta > 0$ nên phương trình có hai nghiệm phân biệt."#,
                           speechText: #"Dòng 2. Vì $\Delta > 0$ nên phương trình có hai nghiệm phân biệt."#),
            ReadingSegment(id: 3, kind: .line(3), title: "Dòng 3",
                           displayText: #"Dòng 3: $x_1 = 2$, $x_2 = \frac{1}{2}$."#,
                           speechText: #"Dòng 3. $x_1 = 2$, $x_2 = \frac{1}{2}$."#),
            ReadingSegment(id: 4, kind: .final, title: "Đáp số",
                           displayText: #"Đáp số: Vậy tập nghiệm là $S = \{\frac{1}{2}; 2\}$."#,
                           speechText: #"Đáp số: Vậy tập nghiệm là $S = \{\frac{1}{2}; 2\}$."#),
        ])
    }

    func testLineNumbersCanBeSilent() {
        let silent = ReplyAssembler(languageCode: "vi", readLineNumbers: false)
        let segments = plan(essayReply, silent).segments
        XCTAssertEqual(segments[1].speechText, #"Ta có $\Delta = b^2 - 4ac = 9$."#)
        XCTAssertEqual(segments[1].displayText, #"Dòng 1: Ta có $\Delta = b^2 - 4ac = 9$."#, "the screen always numbers the lines")
        XCTAssertEqual(segments[4].speechText, #"Đáp số: Vậy tập nghiệm là $S = \{\frac{1}{2}; 2\}$."#)
    }

    func testEssayInEnglish() {
        XCTAssertEqual(plan(englishEssayReply, english).segments.map(\.speechText), [
            "Problem 1.", "Line 1. We have $2x = 4$.", "Line 2. So $x = 2$.", "Answer: $x = 2$.",
        ])
        XCTAssertEqual(plan(englishEssayReply, english).segments.map(\.displayText), [
            "Problem 1", "Line 1: We have $2x = 4$", "Line 2: So $x = 2$.", "Answer: $x = 2$",
        ])
    }

    func testProblemHeadingsAndFinalLabelsAreNotDoubled() {
        let reply = """
        TYPE: ESSAY
        P1: Bài 1
        P2: Câu 2 (2 điểm)
        Bài 3: Giải phương trình
        P4:
        FINAL: Đáp số: $x = 2$
        FINAL: Kết luận: $x = 2$
        FINAL: $x = 3$
        """
        XCTAssertEqual(plan(reply, vietnamese).segments.map(\.speechText), [
            "Bài 1.", "Câu 2 (2 điểm).", "Bài 3: Giải phương trình.", "Bài 4.",
            "Đáp số: $x = 2$.", "Kết luận: $x = 2$.", "Đáp số: $x = 3$.",
        ])
        XCTAssertEqual(plan("P1: Solve the system\nFINAL: Answer: 5", english).segments.map(\.displayText),
                       ["Problem 1: Solve the system", "Answer: 5"])
    }

    // MARK: - Mixed and other

    func testMixedKeepsTheOrderOfTheReply() {
        let plan = plan(mixedReply, vietnamese)
        XCTAssertEqual(plan.answerType, .mixed)
        XCTAssertEqual(plan.segments.map(\.kind), [.mcq(1), .mcq(2), .problem(1), .line(1), .line(2), .final])
        XCTAssertEqual(plan.segments.map(\.id), Array(0..<6))
        XCTAssertEqual(plan.segments.map(\.speechText), [
            "Câu 1: B.", "Câu 2: a sai, b đúng, c đúng, d sai.", "Bài 1.",
            "Dòng 1. $2x + 3 = 7$ nên $2x = 4$.", "Dòng 2. $x = 2$.", "Đáp số: Vậy $x = 2$.",
        ])
    }

    func testOtherIsReadAsWritten() {
        let plan = plan(otherReply, vietnamese)
        XCTAssertEqual(plan.answerType, .other)
        XCTAssertEqual(plan.segments.map(\.kind), [.answer, .answer, .answer])
        XCTAssertEqual(plan.segments.map(\.title), ["", "", ""])
        XCTAssertEqual(plan.segments.map(\.displayText), [
            "Đây là tháp Eiffel ở Paris, hoàn thành năm 1889.", "Tháp cao khoảng 330 mét.", "Nó là biểu tượng của nước Pháp",
        ])
        XCTAssertEqual(plan.segments.last?.speechText, "Nó là biểu tượng của nước Pháp.", "every spoken segment ends a sentence")
    }

    func testSpeechNeverContainsTagsOrTokensButKeepsFormulas() {
        let replies = [mcqReply, essayReply, englishEssayReply, mixedReply, otherReply,
                       "**TYPE:** MCQ\n- **Q1:** A [[END]]\n## L1: $x = 1$\n[[END]]"]
        for reply in replies {
            for segment in plan(reply, vietnamese).segments {
                for forbidden in ["TYPE", "[[", "**", "Q1:", "L1:", "FINAL:", "ANSWER:"] {
                    XCTAssertFalse(segment.speechText.contains(forbidden), "\(forbidden) in \(segment.speechText)")
                    XCTAssertFalse(segment.displayText.contains(forbidden), "\(forbidden) in \(segment.displayText)")
                }
                XCTAssertTrue(segment.speechText.last.map { ".!?…:;,".contains($0) } ?? false, segment.speechText)
            }
        }
        XCTAssertTrue(plan(essayReply, vietnamese).segments[1].speechText.contains(#"$\Delta = b^2 - 4ac = 9$"#),
                      "formulas are left for VietMathSpeech")
    }

    func testLanguageCodeIsNormalized() {
        XCTAssertEqual(ReplyAssembler(languageCode: "vi-VN").languageCode, "vi")
        XCTAssertEqual(ReplyAssembler(languageCode: " VI ").languageCode, "vi")
        XCTAssertEqual(ReplyAssembler(languageCode: "en-US").languageCode, "en")
        XCTAssertEqual(ReplyAssembler(languageCode: "fr").languageCode, "en")
        XCTAssertEqual(ReplyAssembler(languageCode: "vi-VN").readLineNumbers, true, "line numbers are read by default")
    }

    // MARK: - Streaming and MAX_TOKENS

    func testStreamedPlanGrowsByAppendingAndEndsAsTheFinalPlan() {
        // Each reply with the index of the line that decides its type: the TYPE line, or without
        // one the first tag line.
        let replies: [(reply: String, typeLine: Int)] = [
            (mcqReply, 0), (essayReply, 0), (mixedReply, 0), (otherReply, 0),
            (untypedEssayReply, 1), (untypedMCQReply, 0),
        ]
        for (reply, typeLine) in replies {
            let turnID = UUID()
            let parsed = AnswerFormat.parse(reply)
            let expected = vietnamese.plan(turnID: turnID, parsed: parsed)
            var plan = vietnamese.emptyPlan(turnID: turnID)
            var scalars = String.UnicodeScalarView()
            var completeLines = 0
            for scalar in reply.unicodeScalars {
                scalars.append(scalar)
                if scalar == "\n" { completeLines += 1 }
                let before = plan.segments
                let added = vietnamese.update(&plan, streamed: AnswerFormat.partialAnswer(in: String(scalars)))
                XCTAssertEqual(plan.segments, before + added)
                XCTAssertTrue(expected.segments.starts(with: plan.segments), "streamed segments must never change")
                XCTAssertEqual(plan.segments.map(\.id), Array(plan.segments.indices), "ids are positions")
                XCTAssertEqual(plan.answerType, completeLines > typeLine ? parsed.type : .other,
                               "type after \(String(scalars).debugDescription)")
                XCTAssertFalse(plan.isComplete)
            }
            XCTAssertLessThan(plan.segments.count, expected.segments.count, "the last line waits for the end of the reply")
            vietnamese.finish(&plan, with: parsed)
            XCTAssertEqual(plan, expected)
            var doubled = parsed
            doubled.sections += parsed.sections
            XCTAssertEqual(vietnamese.update(&plan, streamed: doubled), [], "a complete plan is final")
            XCTAssertEqual(vietnamese.finish(&plan, with: parsed), [])
            XCTAssertEqual(plan, expected)
        }
        XCTAssertEqual(AnswerFormat.parse(untypedEssayReply).type, .essay)
        XCTAssertEqual(AnswerFormat.parse(untypedMCQReply).type, .mcq)
    }

    func testStreamedPlanTakesItsTypeFromTheTypeLine() {
        var plan = vietnamese.emptyPlan(turnID: UUID())
        vietnamese.update(&plan, streamed: AnswerFormat.partialAnswer(in: "TYPE: MCQ"))
        XCTAssertEqual(plan.answerType, .other, "the TYPE line may still grow")
        let added = vietnamese.update(&plan, streamed: AnswerFormat.partialAnswer(in: "TYPE: MCQ\nQ1: A\nQ2: B\n"))
        XCTAssertEqual(added.map(\.speechText), ["Câu 1: A.", "Câu 2: B."])
        XCTAssertEqual(plan.answerType, .mcq)
        vietnamese.update(&plan, streamed: AnswerFormat.partialAnswer(in: "TYPE: MCQ\nQ1: A\nQ2: B\nTYPE: ESSAY\nL1: x\n"))
        XCTAssertEqual(plan.answerType, .mcq, "a known type never changes")
        vietnamese.finish(&plan, with: AnswerFormat.parse("TYPE: MCQ\nQ1: A\nQ2: B\nTYPE: ESSAY\nL1: x"))
        XCTAssertEqual(plan.answerType, .mcq)
        XCTAssertEqual(plan.segments.map(\.kind), [.mcq(1), .mcq(2), .line(1)])

        var guessed = vietnamese.emptyPlan(turnID: UUID(), answerType: .essay)
        vietnamese.update(&guessed, streamed: AnswerFormat.partialAnswer(in: "Lời giải như sau.\nL1"))
        XCTAssertEqual(guessed.answerType, .essay, "an undecided reply leaves the plan's type alone")
        XCTAssertEqual(guessed.segments.count, 1)
    }

    func testTruncatedReplyEndsWithANotice() {
        let cut = "TYPE: ESSAY\nL1: Ta có $a = 1$.\nL2: Suy ra $b = 2$.\nL3: Khi đó $\\frac{1}{"
        let plan = plan(cut, vietnamese, finishReason: "MAX_TOKENS")
        XCTAssertEqual(plan.segments.map(\.kind), [.line(1), .line(2), .notice])
        XCTAssertEqual(plan.segments.last, ReadingSegment(
            id: 2, kind: .notice, title: "Lưu ý",
            displayText: "Lời giải dài nên mình dừng ở dòng 2. Bạn hỏi 'giải tiếp' để mình giải nốt.",
            speechText: "Lời giải dài nên mình dừng ở dòng 2. Bạn hỏi 'giải tiếp' để mình giải nốt."))
        let englishPlan = self.plan(cut, english, finishReason: "MAX_TOKENS")
        XCTAssertEqual(englishPlan.segments.last?.title, "Note")
        XCTAssertEqual(englishPlan.segments.last?.speechText,
                       "The solution is long, so I stopped at line 2. Say 'solve the rest' and I will finish it.")
        XCTAssertFalse(self.plan(cut, vietnamese).segments.contains { $0.kind == .notice }, "no notice after a normal finish")
    }

    func testCaptureRequestHasNothingToRead() {
        let plan = plan("[[CAPTURE]]", vietnamese)
        XCTAssertEqual(plan.segments, [])
        XCTAssertTrue(plan.isComplete)
    }

    // MARK: - History (Codable)

    func testRecordRoundTripsThroughJSON() throws {
        for reply in [mcqReply, essayReply, mixedReply, otherReply] {
            let parsed = AnswerFormat.parse(reply)
            let record = vietnamese.record(for: parsed)
            XCTAssertEqual(record.segments, vietnamese.plan(turnID: UUID(), parsed: parsed).segments)
            let decoded = try JSONDecoder().decode(ReadingRecord.self, from: JSONEncoder().encode(record))
            XCTAssertEqual(decoded, record)

            let plan = vietnamese.plan(turnID: UUID(), parsed: parsed)
            XCTAssertEqual(try JSONDecoder().decode(ReadingPlan.self, from: JSONEncoder().encode(plan)), plan)
            XCTAssertEqual(ReadingPlan(record: plan.record, turnID: plan.turnID), plan, "replaying a record rebuilds the plan")
        }
    }

    func testEveryKindRoundTripsAndHasAStableJSONShape() throws {
        let kinds: [ReadingSegment.Kind] = [.mcq(3), .problem(2), .line(12), .final, .answer, .notice]
        for kind in kinds {
            XCTAssertEqual(try JSONDecoder().decode(ReadingSegment.Kind.self, from: JSONEncoder().encode(kind)), kind)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(ReadingSegment.Kind.mcq(3)), as: UTF8.self), #"{"number":3,"type":"mcq"}"#)
        XCTAssertEqual(String(decoding: try encoder.encode(ReadingSegment.Kind.final), as: UTF8.self), #"{"type":"final"}"#)
        XCTAssertEqual(String(decoding: try encoder.encode(AnswerType.mixed), as: UTF8.self), #""mixed""#)
        XCTAssertEqual(ReadingSegment.Kind.line(4).number, 4)
        XCTAssertNil(ReadingSegment.Kind.final.number)
    }

    func testValuesFromANewerAppVersionDecodeSafely() throws {
        let json = #"""
        {"languageCode":"vi","answerType":"quiz","segments":[
          {"id":0,"kind":{"type":"hint","number":2},"title":"","displayText":"x","speechText":"x."},
          {"id":1,"kind":{"type":"line"},"title":"Dòng","displayText":"y","speechText":"y."}
        ]}
        """#
        let record = try JSONDecoder().decode(ReadingRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.answerType, .other)
        XCTAssertEqual(record.segments.map(\.kind), [.answer, .line(0)])
    }
}
