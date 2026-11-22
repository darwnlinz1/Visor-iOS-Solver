// OpenVision - AnswerFormatTests.swift
// Answer format v2.1 parser (PLAN.md §4.2, T4.2): tags and their variants, missing TYPE,
// untagged text, true/false normalization, protocol tokens, and the streaming contract
// (every intermediate result is a prefix of the final parse, and the type, once known, is the
// final type). Pure logic: runs on Linux (scripts/swift-local/run.sh) and in the iOS test target.

import XCTest
@testable import OpenVision

final class AnswerFormatTests: XCTestCase {

    // MARK: - Fixtures (the four shapes of PLAN.md §4.2)

    private let mcqReply = """
    TYPE: MCQ
    Q1: A
    Q2: C
    Q3: a Đ, b S, c Đ, d S
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
    ANSWER: Nó là biểu tượng của nước Pháp.
    """

    private let allTrueFalse: [AnswerSection.TrueFalseItem] = [
        .init(label: "a", isTrue: true), .init(label: "b", isTrue: false),
        .init(label: "c", isTrue: true), .init(label: "d", isTrue: false),
    ]

    // MARK: - The four answer types

    func testMCQReplyGivesOneSectionPerQuestion() {
        let parsed = AnswerFormat.parse(mcqReply)
        XCTAssertEqual(parsed.type, .mcq)
        XCTAssertEqual(parsed.declaredType, .mcq)
        XCTAssertEqual(parsed.sections, [
            AnswerSection(.question(1), "A"),
            AnswerSection(.question(2), "C"),
            AnswerSection(.question(3), "a Đ, b S, c Đ, d S"),
            AnswerSection(.question(4), "2,5"),
            AnswerSection(.question(7), "?"),
        ])
        XCTAssertEqual(parsed.sections.map(\.questionAnswer), [
            .choice("A"), .choice("C"), .trueFalse(allTrueFalse), .value("2,5"), .unreadable,
        ])
        XCTAssertFalse(parsed.requestsCapture)
        XCTAssertFalse(parsed.endsConversation)
        XCTAssertFalse(parsed.isTruncated)
    }

    func testEssayReplyKeepsEveryLineAndTheFinal() {
        let parsed = AnswerFormat.parse(essayReply)
        XCTAssertEqual(parsed.type, .essay)
        XCTAssertEqual(parsed.sections, [
            AnswerSection(.problem(1), "Bài 1"),
            AnswerSection(.line(1), #"Ta có $\Delta = b^2 - 4ac = 9$."#),
            AnswerSection(.line(2), #"Vì $\Delta > 0$ nên phương trình có hai nghiệm phân biệt."#),
            AnswerSection(.line(3), #"$x_1 = 2$, $x_2 = \frac{1}{2}$."#),
            AnswerSection(.final, #"Vậy tập nghiệm là $S = \{\frac{1}{2}; 2\}$."#),
        ])
        XCTAssertNil(parsed.sections[0].questionAnswer, "only Q sections have a question answer")
    }

    func testMixedReplyKeepsTheQuestionsBeforeTheEssay() {
        let parsed = AnswerFormat.parse(mixedReply)
        XCTAssertEqual(parsed.type, .mixed)
        XCTAssertEqual(parsed.sections.map(\.kind), [.question(1), .question(2), .problem(1), .line(1), .line(2), .final])
        XCTAssertEqual(parsed.sections[1].questionAnswer, .trueFalse([
            .init(label: "a", isTrue: false), .init(label: "b", isTrue: true),
            .init(label: "c", isTrue: true), .init(label: "d", isTrue: false),
        ]))
    }

    func testOtherReplyIsReadSentenceBySentence() {
        let parsed = AnswerFormat.parse(otherReply)
        XCTAssertEqual(parsed.type, .other)
        XCTAssertEqual(parsed.sections, [
            AnswerSection(.answer, "Đây là tháp Eiffel ở Paris, hoàn thành năm 1889."),
            AnswerSection(.answer, "Tháp cao khoảng 330 mét."),
            AnswerSection(.answer, "Nó là biểu tượng của nước Pháp."),
        ])
    }

    // MARK: - Tag variants

    func testTagVariantsTheModelActuallyEmits() {
        let questionOne = AnswerSection(.question(1), "A")
        let variants: [(String, AnswerSection)] = [
            ("Q1: A", questionOne),
            ("**Q1:** A", questionOne),
            ("**Q1**: A", questionOne),
            ("**Q1** A", questionOne),
            ("- Q1: A", questionOne),
            ("* Q1: A", questionOne),
            ("## Q1: A", questionOne),
            ("[Q1] A", questionOne),
            ("Q1. A", questionOne),
            ("Q1) A", questionOne),
            ("Q1 - A", questionOne),
            ("Q 1: A", questionOne),
            ("Q1 : A", questionOne),
            ("Q1: **A**", questionOne),
            ("   Q1:    A   ", questionOne),
            ("q1: a", AnswerSection(.question(1), "a")),
            ("Q12: B", AnswerSection(.question(12), "B")),
            ("L2: $x = 2$", AnswerSection(.line(2), "$x = 2$")),
            ("**L2:** $x = 2$", AnswerSection(.line(2), "$x = 2$")),
            ("l2: $x = 2$", AnswerSection(.line(2), "$x = 2$")),
            ("p3: Bài 3", AnswerSection(.problem(3), "Bài 3")),
            ("final: $x = 2$", AnswerSection(.final, "$x = 2$")),
            ("**FINAL:** $x = 2$", AnswerSection(.final, "$x = 2$")),
            ("## FINAL: $x = 2$", AnswerSection(.final, "$x = 2$")),
            ("Final answer: 42", AnswerSection(.final, "42")),
            ("answer: Paris.", AnswerSection(.answer, "Paris.")),
            ("**ANSWER:** Paris.", AnswerSection(.answer, "Paris.")),
            ("- ANSWER: Paris.", AnswerSection(.answer, "Paris.")),
        ]
        for (line, expected) in variants {
            XCTAssertEqual(AnswerFormat.parse(line).sections, [expected], line)
            XCTAssertEqual(AnswerFormat.parse("TYPE: MIXED\n" + line).sections, [expected], line)
        }
    }

    func testVietnameseAndEnglishAliases() {
        let aliases: [(String, AnswerSection)] = [
            ("Câu 5: B", AnswerSection(.question(5), "B")),
            ("CÂU 5: B", AnswerSection(.question(5), "B")),
            ("cau 5: B", AnswerSection(.question(5), "B")),
            ("Câu 5. B", AnswerSection(.question(5), "B")),
            ("**Câu 5:** B", AnswerSection(.question(5), "B")),
            ("Question 5: B", AnswerSection(.question(5), "B")),
            ("Ca\u{0302}u 5: B", AnswerSection(.question(5), "B")),   // decomposed "â"
            ("Dòng 2: Ta có $x = 1$.", AnswerSection(.line(2), "Ta có $x = 1$.")),
            ("DÒNG 2: Ta có $x = 1$.", AnswerSection(.line(2), "Ta có $x = 1$.")),
            ("DONG 2: Ta có $x = 1$.", AnswerSection(.line(2), "Ta có $x = 1$.")),
            ("Line 2: We have $x = 1$.", AnswerSection(.line(2), "We have $x = 1$.")),
            ("Bài 1: Giải phương trình", AnswerSection(.problem(1), "Giải phương trình")),
            ("BAI 1: Giải phương trình", AnswerSection(.problem(1), "Giải phương trình")),
            ("Problem 1: Solve the equation", AnswerSection(.problem(1), "Solve the equation")),
            ("Đáp số: $x = 2$", AnswerSection(.final, "$x = 2$")),
            ("ĐÁP SỐ: $x = 2$", AnswerSection(.final, "$x = 2$")),
            ("dap so: $x = 2$", AnswerSection(.final, "$x = 2$")),
            ("Kết luận: $x = 2$", AnswerSection(.final, "$x = 2$")),
            ("KET LUAN: $x = 2$", AnswerSection(.final, "$x = 2$")),
            ("Trả lời: Paris.", AnswerSection(.answer, "Paris.")),
            ("TRA LOI: Paris.", AnswerSection(.answer, "Paris.")),
        ]
        for (line, expected) in aliases {
            XCTAssertEqual(AnswerFormat.parse(line).sections, [expected], line)
        }
    }

    func testLinesThatOnlyLookLikeTagsStayText() {
        let texts = [
            "Final answer is 42.",
            "Finally, x = 2.",
            "Q1 2024 doanh thu tăng.",
            "Paris là thủ đô.",
            "Lực F = 10 N.",
            "Câu hỏi này dễ.",
            "Đáp án: C",
            "Typewriter nghĩa là máy đánh chữ.",
            "-3 < x ≤ 2 là nghiệm.",
            "Q1.5 là một số.",
        ]
        for text in texts {
            XCTAssertEqual(AnswerFormat.parse(text).sections, [AnswerSection(.answer, text)], text)
        }
    }

    /// The bug behind lesson 5: the word "display" or `\displaystyle` used to cut the speech.
    func testWordDisplayInsideContentDoesNotTruncate() {
        let reply = #"""
        TYPE: OTHER
        ANSWER: Bạn nhìn display của máy tính, kết quả là 12. Công thức dùng \displaystyle cũng không sao. Câu cuối vẫn phải được đọc.
        Display: chữ này vẫn được đọc.
        """#
        let parsed = AnswerFormat.parse(reply)
        XCTAssertEqual(parsed.sections.map(\.text), [
            "Bạn nhìn display của máy tính, kết quả là 12.",
            #"Công thức dùng \displaystyle cũng không sao."#,
            "Câu cuối vẫn phải được đọc.",
            "Display: chữ này vẫn được đọc.",
        ])
        let line = #"L1: $\displaystyle \sum_{k=1}^{3} k \cdot 2 = 12$ nên DISPLAY không cắt câu."#
        XCTAssertEqual(AnswerFormat.parse(line).sections,
                       [AnswerSection(.line(1), #"$\displaystyle \sum_{k=1}^{3} k \cdot 2 = 12$ nên DISPLAY không cắt câu."#)])
    }

    // MARK: - Missing TYPE, untagged text

    func testMissingTypeIsInferredFromTheFirstTag() {
        let cases: [(String, AnswerType)] = [
            ("Q1: A\nQ2: B", .mcq),
            ("L1: $x = 2$\nFINAL: $x = 2$", .essay),
            ("P1: Bài 1\nL1: $x = 2$", .essay),
            ("ANSWER: Paris.", .other),
            ("FINAL: 42", .other),
            ("Đây là đáp án.\nQ1: A", .mcq),
            ("Q1: A\nP1: Bài 1\nL1: $x = 1$\nFINAL: $x = 1$", .mcq),
            ("L1: $x = 1$\nQ2: B", .essay),
        ]
        for (reply, type) in cases {
            let parsed = AnswerFormat.parse(reply)
            XCTAssertEqual(parsed.type, type, reply)
            XCTAssertNil(parsed.declaredType, reply)
        }
        XCTAssertEqual(AnswerFormat.parse("Đây là đáp án.\nQ1: A").sections,
                       [AnswerSection(.answer, "Đây là đáp án."), AnswerSection(.question(1), "A")])
    }

    func testDeclaredTypeWins() {
        XCTAssertEqual(AnswerFormat.parse("TYPE: ESSAY\nQ3: C").type, .essay)
        XCTAssertEqual(AnswerFormat.parse("**TYPE:** mcq\nQ1: A").declaredType, .mcq)
        XCTAssertEqual(AnswerFormat.parse("type: Trắc nghiệm\nQ1: A").type, .mcq)
        XCTAssertEqual(AnswerFormat.parse("TYPE: tự luận\nL1: x").type, .essay)
        XCTAssertEqual(AnswerFormat.parse("TYPE: MCQ + ESSAY\nQ1: A").type, .mixed)
        let unknown = AnswerFormat.parse("TYPE: banana\nQ1: A")
        XCTAssertNil(unknown.declaredType)
        XCTAssertEqual(unknown.type, .mcq, "an unreadable TYPE falls back to inference")
        XCTAssertEqual(unknown.sections, [AnswerSection(.question(1), "A")], "the TYPE line is never read")
    }

    /// The type is decided once, by the first line that can decide it, so the type a streamed
    /// reply shows early is the type of the finished reply.
    func testLaterLinesNeverChangeTheType() {
        let twoTypes = AnswerFormat.parse("TYPE: MCQ\nQ1: A\nTYPE: ESSAY\nL1: x")
        XCTAssertEqual(twoTypes.type, .mcq, "a second TYPE line does not make it MIXED")
        XCTAssertEqual(twoTypes.declaredType, .mcq)
        XCTAssertEqual(twoTypes.sections, [AnswerSection(.question(1), "A"), AnswerSection(.line(1), "x")])

        let lateType = AnswerFormat.parse("Q1: A\nTYPE: ESSAY\nL1: x")
        XCTAssertEqual(lateType.type, .mcq, "a TYPE line after the first tag comes too late")
        XCTAssertNil(lateType.declaredType, "the type came from the Q tag")

        XCTAssertEqual(AnswerFormat.parse("TYPE: banana\nL1: x\nTYPE: MCQ\nQ1: A").type, .essay)
        XCTAssertEqual(AnswerFormat.parse("ANSWER: Có.\nTYPE: MCQ\nQ1: A").type, .other)
        XCTAssertEqual(AnswerFormat.parse("Đây là đáp án.\nTYPE: ESSAY\nQ1: A").type, .essay,
                       "untagged text decides nothing")
        XCTAssertTrue(AnswerFormat.parse("Paris là thủ đô.").isTypeKnown, "a finished reply always has a type")
    }

    func testPartialAnswerKnowsTheTypeOnceItsLineIsComplete() {
        let cases: [(String, AnswerType?)] = [   // nil: not decided yet
            ("", nil),
            ("TYPE: MC", nil),
            ("TYPE: MCQ", nil),                  // may still grow into "TYPE: MCQ + ESSAY"
            ("TYPE: MCQ\n", .mcq),
            ("TYPE: MCQ\nQ1: A\nQ2: B\n", .mcq),
            ("**TYPE:** essay\nL1", .essay),
            ("TYPE: MIXED\r\nQ1", .mixed),
            ("TYPE: OTHER\nANSWER: Xin", .other),
            ("TYPE: banana\n", nil),             // a value that is not understood decides nothing
            ("TYPE: banana\nQ1: A\n", .mcq),
            ("TYPE: MCQ\nQ1: A\nTYPE: ESSAY\nL1: x\n", .mcq),
            ("Q1: A", nil),
            ("Q1: A\n", .mcq),
            ("Q3:\n", .mcq),
            ("P1: Bài 1\n", .essay),
            ("Đây là đáp án.\n", nil),           // untagged text decides nothing
            ("Đây là đáp án.\nL1: x", nil),
            ("Đây là đáp án.\nL1: x\n", .essay),
            ("ANSWER: Xin chào. Mình", nil),     // sentences stream before the line is complete
            ("ANSWER: Xin chào.\n", .other),
            ("[[CAPTURE]]", nil),
        ]
        for (prefix, type) in cases {
            let partial = AnswerFormat.partialAnswer(in: prefix)
            XCTAssertEqual(partial.isTypeKnown, type != nil, prefix.debugDescription)
            XCTAssertEqual(partial.type, type ?? .other, prefix.debugDescription)
            XCTAssertEqual(partial.sections, AnswerFormat.completedSections(in: prefix), prefix.debugDescription)
            XCTAssertFalse(partial.isTruncated, prefix.debugDescription)
        }
        XCTAssertEqual(AnswerFormat.partialAnswer(in: "TYPE: MCQ\nQ1: A\nQ2: B\n").sections,
                       [AnswerSection(.question(1), "A"), AnswerSection(.question(2), "B")])
        XCTAssertEqual(AnswerFormat.partialAnswer(in: "**TYPE:** mcq\n").declaredType, .mcq)
        XCTAssertNil(AnswerFormat.partialAnswer(in: "Q1: A\n").declaredType)
        XCTAssertNil(AnswerFormat.partialAnswer(in: "TYPE: MCQ").declaredType)
        XCTAssertTrue(AnswerFormat.partialAnswer(in: "[[CAPTURE]]").requestsCapture)
        XCTAssertTrue(AnswerFormat.partialAnswer(in: "TYPE: OTHER\nANSWER: Tạm biệt! [[END]]").endsConversation)
        XCTAssertFalse(AnswerFormat.partialAnswer(in: "TYPE: OTHER\nANSWER: Tạm biệt! [[EN").endsConversation)
    }

    func testUntaggedReplyIsOtherSplitIntoSentences() {
        let parsed = AnswerFormat.parse("Paris là thủ đô của Pháp. Nó nằm bên sông Seine!\nBạn cần gì nữa? Giá vé là 2.5 euro.")
        XCTAssertEqual(parsed.type, .other)
        XCTAssertNil(parsed.declaredType)
        XCTAssertEqual(parsed.sections.map(\.text),
                       ["Paris là thủ đô của Pháp.", "Nó nằm bên sông Seine!", "Bạn cần gì nữa?", "Giá vé là 2.5 euro."])
        XCTAssertTrue(parsed.sections.allSatisfy { $0.kind == .answer })
        XCTAssertEqual(AnswerFormat.parse("Just a plain answer without tags.").sections,
                       [AnswerSection(.answer, "Just a plain answer without tags.")])
        XCTAssertEqual(AnswerFormat.sentences(in: "Ta có $a. b$ và x. Hết"), ["Ta có $a. b$ và x.", "Hết"],
                       "a formula is never split")
        XCTAssertEqual(AnswerFormat.sentences(in: "Một. Hai", isComplete: false), ["Một."],
                       "an unfinished sentence is held back")
    }

    /// "1." is the number of a list item, not a sentence of its own.
    func testListMarkersDoNotEndASentence() {
        XCTAssertEqual(AnswerFormat.parse("1. Paris là thủ đô của Pháp.\n2. Nó có tháp Eiffel.").sections,
                       [AnswerSection(.answer, "1. Paris là thủ đô của Pháp."), AnswerSection(.answer, "2. Nó có tháp Eiffel.")])
        XCTAssertEqual(AnswerFormat.parse("ANSWER: 1. Mở app. 2. Chụp ảnh.").sections,
                       [AnswerSection(.answer, "1. Mở app."), AnswerSection(.answer, "2. Chụp ảnh.")])
        XCTAssertEqual(AnswerFormat.sentences(in: "a. Mở app. B. Chụp ảnh. 12. Gửi đi."),
                       ["a. Mở app.", "B. Chụp ảnh.", "12. Gửi đi."])
        XCTAssertEqual(AnswerFormat.sentences(in: "Chọn đáp án a. Ta có x = 2. Đáp số là 2. Hết."),
                       ["Chọn đáp án a.", "Ta có x = 2.", "Đáp số là 2.", "Hết."],
                       "a sentence that ends with a letter or a number still ends")
        XCTAssertEqual(AnswerFormat.sentences(in: "1. Mở", isComplete: false), [], "the marker waits for its sentence")
        XCTAssertEqual(AnswerFormat.sentences(in: "1. Mở app. 2", isComplete: false), ["1. Mở app."])
    }

    // MARK: - Question answers

    func testTrueFalseVariantsAreNormalized() {
        let variants = [
            "a Đ, b S, c Đ, d S",
            "a) Đ; b) S; c) Đ; d) S",
            "a-Đ, b-S, c-Đ, d-S",
            "a D, b S, c D, d S",
            "a T, b F, c T, d F",
            "a đúng, b sai, c đúng, d sai",
            "a. Đúng b. Sai c. Đúng d. Sai",
            "a true, b false, c true, d false",
            "A: True, B: False, C: True, D: False",
            "a: dung, b: sai, c: dung, d: sai",
            "a \u{0110}u\u{0301}ng, b sai, c \u{0110}u\u{0301}ng, d sai",   // decomposed "ú"
            "Đ S Đ S",
            "Đúng, Sai, Đúng, Sai",
            "D S D S",
            "ĐSĐS",
            "TFTF",
        ]
        for answer in variants {
            XCTAssertEqual(AnswerFormat.questionAnswer(from: answer), .trueFalse(allTrueFalse), answer)
            XCTAssertEqual(AnswerFormat.parse("Q3: \(answer)").sections.first?.questionAnswer, .trueFalse(allTrueFalse), answer)
        }
        XCTAssertEqual(AnswerFormat.questionAnswer(from: "a Đ, b S"),
                       .trueFalse([.init(label: "a", isTrue: true), .init(label: "b", isTrue: false)]))
        XCTAssertEqual(AnswerFormat.questionAnswer(from: "D S"),
                       .trueFalse([.init(label: "a", isTrue: true), .init(label: "b", isTrue: false)]))
    }

    func testChoicesShortAnswersAndUnreadableQuestions() {
        let cases: [(String, AnswerSection.QuestionAnswer)] = [
            ("A", .choice("A")),
            ("c", .choice("C")),
            ("D", .choice("D")),
            ("(B)", .choice("B")),
            ("C.", .choice("C")),
            ("F", .choice("F")),
            ("A, D", .value("A, D")),
            ("2,5", .value("2,5")),
            ("-3", .value("-3")),
            ("x = 2", .value("x = 2")),
            ("B. $x = 2$", .value("B. $x = 2$")),
            ("Đúng", .value("Đúng")),
            ("?", .unreadable),
            ("??", .unreadable),
            ("", .unreadable),
        ]
        for (answer, expected) in cases {
            XCTAssertEqual(AnswerFormat.questionAnswer(from: answer), expected, answer)
        }
    }

    // MARK: - Protocol tokens

    func testEndTokenIsDetectedAndNeverInASection() {
        let goodbye = "TYPE: OTHER\nANSWER: Không có gì, chúc bạn học tốt!\n[[END]]"
        let parsed = AnswerFormat.parse(goodbye)
        XCTAssertTrue(parsed.endsConversation)
        XCTAssertEqual(parsed.sections, [AnswerSection(.answer, "Không có gì, chúc bạn học tốt!")])

        let inline = AnswerFormat.parse("ANSWER: Tạm biệt! [[end]]")
        XCTAssertTrue(inline.endsConversation)
        XCTAssertEqual(inline.sections, [AnswerSection(.answer, "Tạm biệt!")])
        XCTAssertEqual(AnswerFormat.parse("TYPE: MCQ\nQ1: A [[END]]").sections, [AnswerSection(.question(1), "A")])
        XCTAssertFalse(AnswerFormat.parse("TYPE: OTHER\nANSWER: x bằng 2.").endsConversation)
    }

    func testCaptureRequestIsDetectedAndNothingIsRead() {
        for reply in ["[[CAPTURE]]", "  [[capture]]\n", "TYPE: OTHER\n[[CAPTURE]]", "TYPE: OTHER\nANSWER: [[CAPTURE]]",
                      "**[[CAPTURE]]**", "[[CAPTURE]]\nMình cần xem ảnh."] {
            let parsed = AnswerFormat.parse(reply)
            XCTAssertTrue(parsed.requestsCapture, reply)
            XCTAssertEqual(parsed.sections, [], reply)
        }
        let reply = "[[CAPTURE]]\nMình cần xem ảnh."
        for end in reply.indices {
            XCTAssertEqual(AnswerFormat.completedSections(in: String(reply[...end])), [], "never read while it may be a capture request")
        }
        let late = AnswerFormat.parse("TYPE: OTHER\nANSWER: Xin chào [[CAPTURE]]")
        XCTAssertFalse(late.requestsCapture, "only a reply that starts with the token asks for a photo")
        XCTAssertEqual(late.sections, [AnswerSection(.answer, "Xin chào")])
        XCTAssertFalse(AnswerFormat.parse("TYPE: MCQ\nQ1: A").requestsCapture)
    }

    // MARK: - Layout the model may choose

    func testEmptyTagTakesTheNextLine() {
        XCTAssertEqual(AnswerFormat.parse("TYPE: ESSAY\nL1:\n$$x = 2$$\n\nFINAL:\nx = 2").sections,
                       [AnswerSection(.line(1), "$$x = 2$$"), AnswerSection(.final, "x = 2")])
        XCTAssertEqual(AnswerFormat.parse("Q3:\na Đ, b S, c Đ, d S").sections.first?.questionAnswer, .trueFalse(allTrueFalse))
        let skipped = AnswerFormat.parse("Q5:\nQ6: B")
        XCTAssertEqual(skipped.sections, [AnswerSection(.question(5), ""), AnswerSection(.question(6), "B")])
        XCTAssertEqual(skipped.sections.first?.questionAnswer, .unreadable)
        XCTAssertEqual(AnswerFormat.parse("L1:\nL2: x").sections, [AnswerSection(.line(2), "x")], "an empty line has nothing to read")
        XCTAssertEqual(AnswerFormat.parse("P2:").sections, [AnswerSection(.problem(2), "")])

        XCTAssertEqual(AnswerFormat.completedSections(in: "Q3:\n"), [])
        XCTAssertEqual(AnswerFormat.completedSections(in: "Q3:\na Đ, b S"), [])
        XCTAssertEqual(AnswerFormat.completedSections(in: "Q3:\na Đ, b S\n"), [AnswerSection(.question(3), "a Đ, b S")])
    }

    func testMarkdownNoiseIsNotRead() {
        let reply = "```\nTYPE: MCQ\nQ1: A\n---\n***\n| Câu | Đáp án |\n|---|:---:|\n| 2 | B |\n```"
        let parsed = AnswerFormat.parse(reply)
        XCTAssertEqual(parsed.type, .mcq)
        XCTAssertEqual(parsed.sections, [
            AnswerSection(.question(1), "A"),
            AnswerSection(.answer, "Câu, Đáp án"),
            AnswerSection(.answer, "2, B"),
        ])
        XCTAssertEqual(AnswerFormat.parse("TYPE: MCQ\r\nQ1: A\r\nQ2: B\r\n").sections,
                       [AnswerSection(.question(1), "A"), AnswerSection(.question(2), "B")])
        XCTAssertEqual(AnswerFormat.parse("\u{FEFF}TYPE: MCQ\nQ1: A").type, .mcq)
        XCTAssertEqual(AnswerFormat.parse("- Paris là thủ đô.\n* Nó đẹp.\n## Hết.").sections.map(\.text),
                       ["Paris là thủ đô.", "Nó đẹp.", "Hết."])
    }

    // MARK: - Streaming

    func testHalfTagLastLineIsHeldBack() {
        XCTAssertEqual(AnswerFormat.completedSections(in: "TYPE: OTHER\nANSWER: Xin chào. Mình"),
                       [AnswerSection(.answer, "Xin chào.")])
        let essayStart = "TYPE: ESSAY\nL1: Ta có $x = 2$.\n"
        for tail in ["**FIN", "FIN", "Q", "Câu", "Đáp", "D", "L1", "L1: Ta có", "TYPE: ES", "[", "|", "```"] {
            XCTAssertEqual(AnswerFormat.completedSections(in: essayStart + tail), [AnswerSection(.line(1), "Ta có $x = 2$.")], tail)
        }
        XCTAssertEqual(AnswerFormat.completedSections(in: "TYPE: MCQ\nQ1: A"), [], "a Q line waits for its end")
        XCTAssertEqual(AnswerFormat.completedSections(in: "TYPE: MCQ\nQ1: A\nQ2"), [AnswerSection(.question(1), "A")])
        XCTAssertEqual(AnswerFormat.completedSections(in: "Paris là thủ đô. N"), [AnswerSection(.answer, "Paris là thủ đô.")])
        XCTAssertEqual(AnswerFormat.completedSections(in: "TYPE: OTHER\nANSWER: Một.\nAN"), [AnswerSection(.answer, "Một.")])
    }

    func testStreamingReleasesSectionsEarly() {
        XCTAssertEqual(AnswerFormat.completedSections(in: "TYPE: ESSAY\nL1: Ta có $x = 1$.\nL2: Vậy"),
                       [AnswerSection(.line(1), "Ta có $x = 1$.")])
        XCTAssertEqual(AnswerFormat.completedSections(in: "TYPE: OTHER\nANSWER: Câu một. Câu hai"),
                       [AnswerSection(.answer, "Câu một.")], "a long ANSWER line starts being read at its first sentence")
    }

    func testStreamingIsAlwaysAPrefixOfTheFinalParse() {
        let replies = [
            mcqReply, essayReply, mixedReply, otherReply,
            "Paris là thủ đô của Pháp. Nó nằm bên sông Seine!\nBạn cần gì nữa?",
            "**TYPE:** MCQ\n- **Q1:** A\n## Q2: B\n[Q3] a) Đ; b) S\nCâu 4. 2,5\n",
            "TYPE: ESSAY\nL1:\n$$x = 2$$\nFINAL:\nx = 2\nCâu 5:\nQ6: B",
            "TYPE: OTHER\nANSWER: Không có gì, chúc bạn học tốt!\n[[END]]",
            "TYPE: MCQ\r\nQ1: A\r\nQ2: B",
            "TYPE: ESSAY\nDo\u{0300}ng 1: Ta co\u{0301} $x = 1$. Vi\u{0300} vậy\nĐa\u{0301}p số: $x = 1$",
            "```\nTYPE: MCQ\nQ1: A\n---\n| Câu | Đáp án |\n|---|---|\n```",
            "TYPE: OTHER\nANSWER: Giá là 2.5 euro. Ta có $a. b$ chưa đóng. Rồi.\nDisplay: vẫn đọc. \\displaystyle cũng vậy.",
            "TYPE: ESSAY\nL1: Ta có $\\frac{1}{",
            "1. Paris là thủ đô của Pháp.\n2. Nó có tháp Eiffel.",
            "ANSWER: 1. Mở app. 2. Chụp ảnh.",
            "TYPE: OTHER\nANSWER: a. Mở app.  b. Chụp ảnh. 12. Gửi đi.\nChọn đáp án a. Ta có x = 2.",
        ]
        for reply in replies {
            assertStreamingContract(reply)
        }
    }

    func testRandomRepliesNeverBreakTheStreamingContract() {
        let pieces = [
            "TYPE: MCQ", "TYPE: ESSAY", "TYPE: OTHER", "Q1:", "Q12: B", "**Q3:**", " a Đ, b S", "L1:", "L2: $x^2 = 4$.",
            "P1: Bài 1", "FINAL:", "ANSWER:", "Câu 4.", "Đáp số:", " Đúng.", " x = 2.5.", " Xin chào. ", "Paris!",
            "[[END]]", "[[CAPTURE]]", "$", "$$", "**", "- ", "# ", "|", "```", "?", " ", "\r\n", "Ca\u{0302}u 2: C",
            "…", "TRẢ LỜI: Có.", "\n", "\n", "\n", "\n",
        ]
        var random = SeededRandom(seed: 20261121)
        for _ in 0..<150 {
            var reply = ""
            for _ in 0..<random.next(in: 3...14) {
                reply += pieces[random.next(in: 0...(pieces.count - 1))]
            }
            assertStreamingContract(reply)
        }
    }

    // MARK: - MAX_TOKENS

    func testMaxTokensDropsTheCutLineAndNamesTheLastLine() {
        let cut = "TYPE: ESSAY\nL1: Ta có $a = 1$.\nL2: Suy ra $b = 2$.\nL3: Khi đó $\\frac{1}{"
        let parsed = AnswerFormat.parse(cut, finishReason: "MAX_TOKENS")
        XCTAssertTrue(parsed.isTruncated)
        XCTAssertEqual(parsed.type, .essay)
        XCTAssertEqual(parsed.sections.map(\.kind), [.line(1), .line(2)], "the cut-off line is not read")
        XCTAssertEqual(AnswerFormat.truncationNotice(after: parsed.sections, languageCode: "vi"),
                       "Lời giải dài nên mình dừng ở dòng 2. Bạn hỏi 'giải tiếp' để mình giải nốt.")
        XCTAssertEqual(AnswerFormat.truncationNotice(after: parsed.sections, languageCode: "en-US"),
                       "The solution is long, so I stopped at line 2. Say 'solve the rest' and I will finish it.")
        XCTAssertEqual(AnswerFormat.truncationNotice(after: [AnswerSection(.question(12), "B")], languageCode: "vi-VN"),
                       "Lời giải dài nên mình dừng ở câu 12. Bạn hỏi 'giải tiếp' để mình giải nốt.")
        XCTAssertEqual(AnswerFormat.truncationNotice(after: [AnswerSection(.answer, "Một.")], languageCode: "vi"),
                       "Câu trả lời dài nên mình dừng ở đây. Bạn hỏi 'giải tiếp' để mình giải nốt.")
        XCTAssertEqual(AnswerFormat.truncationNotice(after: [], languageCode: "en"),
                       "The answer is long, so I stopped here. Say 'solve the rest' and I will finish it.")

        let complete = AnswerFormat.parse(cut, finishReason: "STOP")
        XCTAssertFalse(complete.isTruncated)
        XCTAssertEqual(complete.sections.count, 3, "a normal finish reads every line")
        XCTAssertTrue(AnswerFormat.isTruncated(finishReason: "max_tokens"))
        XCTAssertFalse(AnswerFormat.isTruncated(finishReason: nil))
    }

    // MARK: - Robustness

    func testOddInputNeverCrashes() {
        let inputs = [
            "", "\n", "\n\n\n", ":", "Q:", "Q99999: A", "Q-1: x", "TYPE:", "**", "[[", "]]", "$$$", "\\", "😀 Q1: 😀",
            "\u{0}", "L1: " + String(repeating: "a", count: 10_000), String(repeating: "Q1: A\n", count: 2_000),
            "TYPE: MCQ\u{2028}Q1: A", "Q1:\u{301}", "\u{301}\u{301}", "[Q1", "[Q1]", "**Q1**", "Q1.", "Q1-",
        ]
        for input in inputs {
            let parsed = AnswerFormat.parse(input)
            _ = AnswerFormat.parse(input, finishReason: "MAX_TOKENS")
            _ = AnswerFormat.completedSections(in: input)
            for section in parsed.sections {
                _ = section.questionAnswer
            }
        }
        XCTAssertEqual(AnswerFormat.parse("").sections, [])
        XCTAssertEqual(AnswerFormat.parse("Q99999: A").sections, [AnswerSection(.answer, "Q99999: A")],
                       "a five-digit number is not a question number")
        XCTAssertEqual(AnswerFormat.parse("TYPE: MCQ\u{2028}Q1: A").sections, [AnswerSection(.question(1), "A")])
    }

    // MARK: - Helpers

    /// Grows `reply` one Unicode scalar at a time (finer than the network's chunks) and checks that
    /// what was released never changes, never contains a protocol token, and ends as the final parse;
    /// and that the type is `.other` until it is known, then the final type for good.
    private func assertStreamingContract(_ reply: String, file: StaticString = #filePath, line: UInt = #line) {
        let parsed = AnswerFormat.parse(reply)
        let final = parsed.sections
        for section in final {
            XCTAssertFalse(containsToken(section.text), "token in \"\(section.text)\" of \(reply.debugDescription)", file: file, line: line)
        }
        var scalars = String.UnicodeScalarView()
        var previous: [AnswerSection] = []
        var typeWasKnown = false
        for scalar in reply.unicodeScalars {
            scalars.append(scalar)
            let text = String(scalars)
            let answer = AnswerFormat.partialAnswer(in: text)
            let partial = answer.sections
            guard final.starts(with: partial), partial.starts(with: previous),
                  partial == AnswerFormat.completedSections(in: text) else {
                XCTFail("streamed \(partial) after \(previous) is not a prefix of \(final) for \(text.debugDescription)",
                        file: file, line: line)
                return
            }
            guard answer.type == (answer.isTypeKnown ? parsed.type : .other),
                  answer.declaredType == (answer.isTypeKnown ? parsed.declaredType : nil),
                  answer.isTypeKnown || !typeWasKnown else {
                XCTFail("streamed type \(answer.type) (known: \(answer.isTypeKnown), declared: \(String(describing: answer.declaredType))) "
                        + "for \(text.debugDescription), final \(parsed.type)", file: file, line: line)
                return
            }
            previous = partial
            typeWasKnown = answer.isTypeKnown
        }
        let truncated = AnswerFormat.parse(reply, finishReason: "MAX_TOKENS")
        XCTAssertEqual(truncated.sections, previous, "MAX_TOKENS reads exactly what streamed", file: file, line: line)
        XCTAssertEqual(truncated.type, parsed.type, "MAX_TOKENS does not change the type", file: file, line: line)
    }

    private func containsToken(_ text: String) -> Bool {
        let upper = text.uppercased()
        return upper.contains("[[END]]") || upper.contains("[[CAPTURE]]")
    }

    func testTextForReadingRecordRoundTrips() {
        let assembler = ReplyAssembler(languageCode: "vi")
        for sample in [mcqReply, essayReply, mixedReply, otherReply] {
            let original = AnswerFormat.parse(sample)
            let record = assembler.record(for: original)
            let rebuilt = AnswerFormat.text(for: record)
            let reparsed = AnswerFormat.parse(rebuilt)
            XCTAssertEqual(reparsed.type, original.type, rebuilt)
            XCTAssertEqual(reparsed.sections.count, original.sections.count, rebuilt)
        }
        let legacy = AnswerFormat.text(forLegacyHistory: "Paris là thủ đô của Pháp.")
        let parsedLegacy = AnswerFormat.parse(legacy)
        XCTAssertEqual(parsedLegacy.type, .other)
        XCTAssertEqual(parsedLegacy.sections.first?.text, "Paris là thủ đô của Pháp.")
    }
}

/// SplitMix64: a fixed seed gives the same "random" replies on every run and platform.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Int>) -> Int {
        let width = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % width)
    }
}
