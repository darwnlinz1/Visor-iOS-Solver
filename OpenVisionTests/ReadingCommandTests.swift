// OpenVision - ReadingCommandTests.swift
// Pure Foundation unit tests for ReadingCommand bilingual parser (PLAN.md §4.4, T5.3).
// Runs on Linux via scripts/swift-local/run.sh and in OpenVisionTests on iOS simulator.

import XCTest
@testable import OpenVision

final class ReadingCommandTests: XCTestCase {

    func testVietnameseCommands() {
        XCTAssertEqual(ReadingCommand.parse("tạm dừng"), .pause)
        XCTAssertEqual(ReadingCommand.parse("dừng chút"), .pause)
        XCTAssertEqual(ReadingCommand.parse("tiếp tục"), .resume)
        XCTAssertEqual(ReadingCommand.parse("tiếp"), .resume)
        XCTAssertEqual(ReadingCommand.parse("đọc tiếp"), .resume)
        XCTAssertEqual(ReadingCommand.parse("dòng tiếp"), .next)
        XCTAssertEqual(ReadingCommand.parse("câu tiếp"), .next)
        XCTAssertEqual(ReadingCommand.parse("bỏ qua"), .next)
        XCTAssertEqual(ReadingCommand.parse("dòng trước"), .previous)
        XCTAssertEqual(ReadingCommand.parse("quay lại"), .previous)
        XCTAssertEqual(ReadingCommand.parse("đọc lại"), .repeatCurrent)
        XCTAssertEqual(ReadingCommand.parse("nhắc lại"), .repeatCurrent)
        XCTAssertEqual(ReadingCommand.parse("đọc lại từ đầu"), .restart)
        XCTAssertEqual(ReadingCommand.parse("chậm lại"), .slower)
        XCTAssertEqual(ReadingCommand.parse("nhanh lên"), .faster)
        XCTAssertEqual(ReadingCommand.parse("dừng lại"), .stop)
        XCTAssertEqual(ReadingCommand.parse("thôi"), .stop)
    }

    func testEnglishCommands() {
        XCTAssertEqual(ReadingCommand.parse("pause"), .pause)
        XCTAssertEqual(ReadingCommand.parse("continue"), .resume)
        XCTAssertEqual(ReadingCommand.parse("resume"), .resume)
        XCTAssertEqual(ReadingCommand.parse("next"), .next)
        XCTAssertEqual(ReadingCommand.parse("next line"), .next)
        XCTAssertEqual(ReadingCommand.parse("back"), .previous)
        XCTAssertEqual(ReadingCommand.parse("repeat"), .repeatCurrent)
        XCTAssertEqual(ReadingCommand.parse("from the start"), .restart)
        XCTAssertEqual(ReadingCommand.parse("slower"), .slower)
        XCTAssertEqual(ReadingCommand.parse("faster"), .faster)
        XCTAssertEqual(ReadingCommand.parse("stop"), .stop)
    }

    func testJumpCommandsWithDigitsAndWords() {
        XCTAssertEqual(ReadingCommand.parse("đọc lại câu 3"), .jump(3, scope: .question))
        XCTAssertEqual(ReadingCommand.parse("đọc lại dòng 5"), .jump(5, scope: .line))
        XCTAssertEqual(ReadingCommand.parse("câu 12"), .jump(12, scope: .question))
        XCTAssertEqual(ReadingCommand.parse("dòng ba"), .jump(3, scope: .line))
        XCTAssertEqual(ReadingCommand.parse("câu mười lăm"), .jump(15, scope: .question))
        XCTAssertEqual(ReadingCommand.parse("câu hai mươi mốt"), .jump(21, scope: .question))
        XCTAssertEqual(ReadingCommand.parse("đọc lại bài hai"), .jump(2, scope: .problem))
        XCTAssertEqual(ReadingCommand.parse("question 4"), .jump(4, scope: .question))
        XCTAssertEqual(ReadingCommand.parse("line 2"), .jump(2, scope: .line))
    }

    func testRealQuestionsAreNeverMisclassifiedAsReadingCommands() {
        let questions = [
            "tại sao câu 3 chọn C?",
            "giải thích dòng 2 giúp mình",
            "giải chi tiết câu 3",
            "giải tiếp đi",
            "còn câu 2 thì sao?",
            "why is question 3 C?",
            "explain step by step",
            "solve the rest",
            "what is the derivative of x squared?"
        ]
        for q in questions {
            XCTAssertNil(ReadingCommand.parse(q), "Question must reach Gemini, not trigger a reading command: \(q)")
        }
    }
}
