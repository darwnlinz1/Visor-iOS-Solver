// OpenVision - PromptV2Tests.swift
// System prompt v2.1 contract (PLAN.md §4.2, T4.1): the TYPE + Q / P / L / FINAL / ANSWER format
// for every answer type, the rules that were kept (language, photos, [[CAPTURE]], [[END]], silent
// re-check, date, user instructions, memories), and what must be gone (dual channel, phone screen,
// tutor mode). Pure logic: runs on Linux (scripts/swift-local/run.sh) and in the iOS test target.

import XCTest
@testable import OpenVision

final class PromptV2Tests: XCTestCase {

    /// 2026-11-21 15:47:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_795_276_020)

    private func prompt(userPrompt: String = "", memories: [String: String] = [:]) throws -> String {
        let hanoi = try XCTUnwrap(TimeZone(secondsFromGMT: 7 * 3600))
        return PromptV2.systemPrompt(now: now, timeZone: hanoi, userPrompt: userPrompt, memories: memories)
    }

    func testPromptStatesTheV21AnswerFormat() throws {
        let prompt = try prompt()
        for required in ["TYPE:", "Q1:", "P1:", "L1:", "FINAL:", "ANSWER:",
                         "TYPE: MCQ", "TYPE: ESSAY", "TYPE: MIXED", "TYPE: OTHER",
                         "Q3: a Đ, b S, c Đ, d S", "Q4: 2,5", "Q7: ?",
                         "at most 25 words and at most 2 formulas", "between single dollar signs",
                         "all the Q lines first", "gets TYPE: ESSAY for that item only"] {
            XCTAssertTrue(prompt.contains(required), "prompt lacks \"\(required)\"")
        }
        for example in [PromptV2.mcqExample, PromptV2.essayExample, PromptV2.englishEssayExample,
                        PromptV2.mixedExample, PromptV2.otherExample, PromptV2.englishOtherExample] {
            XCTAssertTrue(prompt.contains(example), "every example is shown verbatim")
        }
        XCTAssertTrue(prompt.contains("NEVER reply in Vietnamese when the user's latest message is in English"))
        XCTAssertTrue(prompt.contains("never put 3 or more $...$ formulas on one L line"))
    }

    func testPromptExamplesParseAsTheirType() {
        let examples: [(String, AnswerType)] = [
            (PromptV2.mcqExample, .mcq), (PromptV2.essayExample, .essay),
            (PromptV2.mixedExample, .mixed), (PromptV2.otherExample, .other),
        ]
        for (example, type) in examples {
            let parsed = AnswerFormat.parse(example)
            XCTAssertEqual(parsed.type, type, example)
            XCTAssertEqual(parsed.declaredType, type, example)
            XCTAssertFalse(parsed.sections.isEmpty, example)
        }
        XCTAssertEqual(AnswerFormat.parse(PromptV2.mcqExample).sections.map(\.questionAnswer),
                       [.choice("A"), .choice("C"), .trueFalse([
                           .init(label: "a", isTrue: true), .init(label: "b", isTrue: false),
                           .init(label: "c", isTrue: true), .init(label: "d", isTrue: false)]), .value("2,5")])
        XCTAssertEqual(AnswerFormat.parse(PromptV2.essayExample).sections.map(\.kind),
                       [.problem(1), .line(1), .line(2), .line(3), .final, .problem(2), .line(1), .line(2), .final])
        let mixed = AnswerFormat.parse(PromptV2.mixedExample).sections.map(\.kind)
        XCTAssertEqual(mixed.prefix(3), [.question(1), .question(2), .question(3)], "MIXED: the Q block comes first")
        XCTAssertEqual(mixed.last, .final)
        for example in [PromptV2.essayExample, PromptV2.mixedExample] {
            for section in AnswerFormat.parse(example).sections where section.kind != .final {
                if case .line = section.kind {
                    XCTAssertLessThanOrEqual(section.text.split(separator: " ").count, 25, "the example obeys its own rule")
                    XCTAssertLessThanOrEqual(section.text.filter { $0 == "$" }.count, 4, "at most 2 formulas per line")
                }
            }
        }
    }

    func testPromptKeepsLanguagePhotoAndProtocolRules() throws {
        let prompt = try prompt()
        XCTAssertTrue(prompt.contains("ALWAYS answer in the language the user used"))
        XCTAssertTrue(prompt.contains("clearly unrelated to the photo"), "unrelated questions are answered normally")
        XCTAssertTrue(prompt.contains("reply with exactly [[CAPTURE]] and nothing else"))
        XCTAssertTrue(prompt.contains(AnswerFormat.captureToken))
        XCTAssertTrue(prompt.contains("put [[END]] alone on the very last line"))
        XCTAssertTrue(prompt.contains(AnswerFormat.endToken))
        XCTAssertTrue(prompt.contains("silently re-check the result"))
        XCTAssertTrue(prompt.contains("Follow-up questions may refer to a photo earlier in this conversation"))
    }

    func testPromptDropsTheDualChannelAndTheTutorMode() throws {
        let prompt = try prompt(userPrompt: "Gọi tôi là Lan.", memories: ["lớp": "12"])
        let lower = prompt.lowercased()
        for gone in ["DISPLAY:", "SPOKEN:", "2 to 4 complete sentences"] {
            XCTAssertFalse(prompt.contains(gone), "prompt still contains \"\(gone)\"")
        }
        for gone in ["dual-channel", "phone screen", "under 250 characters", "tutor", "do not reveal the final answer"] {
            XCTAssertFalse(lower.contains(gone), "prompt still contains \"\(gone)\"")
        }
    }

    func testPromptForbidsSendingTheUserToAScreen() throws {
        let prompt = try prompt()
        XCTAssertTrue(prompt.contains(PromptV2.noScreenRule))
        XCTAssertTrue(prompt.lowercased().contains("never tell the user to look at the phone or at a screen"))
        XCTAssertTrue(prompt.contains("never apologize for a long answer"), "D5: no apology for length")
        XCTAssertTrue(prompt.contains("Always give the complete solution and the final answer"), "D1: no hint-only mode (N17)")
    }

    func testDateAndTimeAreWrittenInTheUsersTimeZone() throws {
        XCTAssertTrue(try prompt().contains("The current date and time is 2026-11-21T22:47:00+07:00 in the user's local time zone."))
        let utc = PromptV2.systemPrompt(now: now, timeZone: try XCTUnwrap(TimeZone(identifier: "UTC")), userPrompt: "", memories: [:])
        XCTAssertTrue(utc.contains("2026-11-21T15:47:00Z"), utc.suffix(200).description)
    }

    func testUserInstructionsAndMemoriesAreAppendedInAStableOrder() throws {
        let plain = try prompt()
        XCTAssertFalse(plain.contains("Additional instructions from user:"))
        XCTAssertFalse(plain.contains("Things to remember about the user:"))
        XCTAssertEqual(try prompt(userPrompt: "  \n "), plain, "blank instructions add nothing")

        let personal = try prompt(userPrompt: "Gọi tôi là Lan.", memories: ["trường": "THPT A", "lớp": "12", "biệt danh": "Lan"])
        XCTAssertTrue(personal.hasPrefix(plain), "personal parts come after the contract")
        XCTAssertTrue(personal.hasSuffix("""


        Additional instructions from user:
        Gọi tôi là Lan.

        Things to remember about the user:
        - biệt danh: Lan
        - lớp: 12
        - trường: THPT A
        """))
        XCTAssertEqual(personal, try prompt(userPrompt: "Gọi tôi là Lan.", memories: ["lớp": "12", "biệt danh": "Lan", "trường": "THPT A"]),
                       "same settings, same prompt")
    }

    func testPromptHasNoTemplateLeftovers() throws {
        let prompt = try prompt()
        XCTAssertFalse(prompt.contains("\\#("), "every interpolation was resolved")
        XCTAssertFalse(prompt.contains("\t"))
        XCTAssertFalse(prompt.hasPrefix(" ") || prompt.hasPrefix("\n"))
        XCTAssertTrue(prompt.contains(#"$\frac{3}{4}$"#), "LaTeX backslashes reach the model unescaped")
    }
}
