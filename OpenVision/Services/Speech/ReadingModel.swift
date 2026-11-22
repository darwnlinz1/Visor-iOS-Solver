// OpenVision - ReadingModel.swift
// What one answer looks like once it is ready to be read aloud and shown (PLAN.md §4.4).
//
// Pure Foundation (no UIKit/AVFoundation): built on Linux by scripts/swift-local/run.sh and on iOS.
// `ReplyAssembler` builds these values from `AnswerFormat` sections; `ReadingEngine` reads them;
// History stores `ReadingRecord`. Speech pieces are NOT stored here: they are rebuilt with
// `VietMathSpeech` when a segment is read, with the settings of that moment.

import Foundation

/// The four answer shapes of format v2.1 (PLAN.md §4.2).
enum AnswerType: String, CaseIterable, Equatable, Sendable {
    case mcq, essay, mixed, other
}

extension AnswerType: Codable {
    /// A value written by a newer app version decodes as `.other` instead of failing the whole
    /// record (a single bad value must never cost the user their History, see N18).
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = AnswerType(rawValue: value) ?? .other
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One item of an answer: one multiple-choice answer, one problem heading, one solution line,
/// the final result, one sentence of a plain answer, or an app notice.
struct ReadingSegment: Identifiable, Codable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// `Qn`: a multiple-choice, true/false or short answer.
        case mcq(Int)
        /// `Pn`: the heading of one essay problem.
        case problem(Int)
        /// `Ln`: one line of a worked solution.
        case line(Int)
        /// `FINAL`: the result of a problem.
        case final
        /// `ANSWER` or untagged text (one sentence).
        case answer
        /// Added by the app, not written by the model (for example the "answer was cut" notice).
        case notice
    }

    /// Position in the plan (0, 1, 2, …). Stable while the answer streams in.
    var id: Int
    var kind: Kind
    /// Short label: "Câu 3", "Dòng 2", "Đáp số" ("Question 3", "Line 2", "Answer"); empty for plain text.
    var title: String
    /// Shown on screen, formulas as the model wrote them: "Câu 3: a Đ, b S, c Đ, d S".
    var displayText: String
    /// Read aloud (after `VietMathSpeech` turns the `$…$` formulas into words): "Câu 3: a đúng, b sai, c đúng, d sai."
    var speechText: String
}

extension ReadingSegment.Kind {
    /// The question, problem or line number; nil for `final`, `answer` and `notice`.
    var number: Int? {
        switch self {
        case .mcq(let n), .problem(let n), .line(let n): return n
        case .final, .answer, .notice: return nil
        }
    }

    /// Name used in the stored JSON.
    var typeName: String {
        switch self {
        case .mcq: return "mcq"
        case .problem: return "problem"
        case .line: return "line"
        case .final: return "final"
        case .answer: return "answer"
        case .notice: return "notice"
        }
    }
}

extension ReadingSegment.Kind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, number
    }

    /// Stored as `{"type": "line", "number": 2}`. A type written by a newer app version decodes as
    /// `.answer` (read as plain text) instead of failing the record.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? ""
        let number = (try? container.decode(Int.self, forKey: .number)) ?? 0
        switch type {
        case "mcq": self = .mcq(number)
        case "problem": self = .problem(number)
        case "line": self = .line(number)
        case "final": self = .final
        case "notice": self = .notice
        default: self = .answer
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName, forKey: .type)
        if let number {
            try container.encode(number, forKey: .number)
        }
    }
}

/// Everything the app reads for one turn. Segments are appended while the answer streams in;
/// `isComplete` turns true when the reply has fully arrived.
struct ReadingPlan: Codable, Equatable, Sendable {
    var turnID: UUID
    /// "vi" or "en": one voice for the whole answer (fixes N5).
    var languageCode: String
    /// While the answer streams in: `.other` until its TYPE line (or, without one, its first tag
    /// line) has arrived, then the final type (`ReplyAssembler.update`).
    var answerType: AnswerType
    var segments: [ReadingSegment]
    var isComplete: Bool

    init(turnID: UUID, languageCode: String, answerType: AnswerType,
         segments: [ReadingSegment] = [], isComplete: Bool = false) {
        self.turnID = turnID
        self.languageCode = languageCode
        self.answerType = answerType
        self.segments = segments
        self.isComplete = isComplete
    }

    /// Replays a stored answer (History "Đọc lại"): a complete plan for a new turn, no network.
    init(record: ReadingRecord, turnID: UUID = UUID()) {
        self.init(turnID: turnID, languageCode: record.languageCode, answerType: record.answerType,
                  segments: record.segments, isComplete: true)
    }

    /// What History keeps of this answer (`Message.reading`).
    var record: ReadingRecord {
        ReadingRecord(languageCode: languageCode, answerType: answerType, segments: segments)
    }
}

/// The part of a `ReadingPlan` that History stores.
struct ReadingRecord: Codable, Equatable, Sendable {
    var languageCode: String
    var answerType: AnswerType
    var segments: [ReadingSegment]
}
