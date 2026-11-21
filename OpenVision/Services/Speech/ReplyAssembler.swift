// OpenVision - ReplyAssembler.swift
// Parsed answer sections → what the wearer sees and hears (PLAN.md §4.2 reading table, §4.4).
//
// Pure Foundation: built on Linux by scripts/swift-local/run.sh and on iOS. The view model only
// calls this type, so the whole "reply → ReadingPlan → History record" path is unit-tested.
// Formulas stay as `$…$` in `speechText`; `VietMathSpeech` turns them into words when a segment
// is read.

import Foundation

struct ReplyAssembler: Equatable, Sendable {
    /// "vi" or "en": labels ("Câu 3" / "Question 3") and the voice of the whole answer.
    let languageCode: String
    /// Setting `readLineNumbers`: say "Dòng 1." / "Line 1." before each solution line.
    let readLineNumbers: Bool

    init(languageCode: String, readLineNumbers: Bool = true) {
        self.languageCode = Self.normalizedLanguageCode(languageCode)
        self.readLineNumbers = readLineNumbers
    }

    /// "vi", "vi-VN", "VI" → "vi"; anything else → "en" (the app answers in Vietnamese or English).
    static func normalizedLanguageCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("vi") ? "vi" : "en"
    }

    private var vietnamese: Bool { languageCode == "vi" }

    // MARK: - Streaming

    /// The plan of a turn whose reply has not arrived yet.
    func emptyPlan(turnID: UUID, answerType: AnswerType = .other) -> ReadingPlan {
        ReadingPlan(turnID: turnID, languageCode: languageCode, answerType: answerType)
    }

    /// Adds the segments for the sections not yet in `plan`. `sections` is the cumulative result of
    /// `AnswerFormat.completedSections(in:)`; returns only the new segments (for `ReadingEngine.append`).
    @discardableResult
    func update(_ plan: inout ReadingPlan, streamed sections: [AnswerSection]) -> [ReadingSegment] {
        guard !plan.isComplete, sections.count > plan.segments.count else { return [] }
        let added = segments(for: Array(sections[plan.segments.count...]), firstID: plan.segments.count)
        plan.segments.append(contentsOf: added)
        return added
    }

    /// Completes a streamed plan with the final parse: the sections that had not streamed yet, the
    /// "answer was cut" notice after a `MAX_TOKENS` reply, the final answer type. Returns the new segments.
    @discardableResult
    func finish(_ plan: inout ReadingPlan, with parsed: ParsedAnswer) -> [ReadingSegment] {
        guard !plan.isComplete else { return [] }
        var added = update(&plan, streamed: parsed.sections)
        if parsed.isTruncated {
            let notice = noticeSegment(AnswerFormat.truncationNotice(after: parsed.sections, languageCode: languageCode),
                                       id: plan.segments.count)
            plan.segments.append(notice)
            added.append(notice)
        }
        plan.answerType = parsed.type
        plan.isComplete = true
        return added
    }

    // MARK: - Whole reply

    /// The complete plan of a finished reply (typed question, replay of a stored raw reply, tests).
    func plan(turnID: UUID, parsed: ParsedAnswer) -> ReadingPlan {
        var plan = emptyPlan(turnID: turnID, answerType: parsed.type)
        finish(&plan, with: parsed)
        return plan
    }

    /// What History stores for a finished reply.
    func record(for parsed: ParsedAnswer) -> ReadingRecord {
        plan(turnID: UUID(), parsed: parsed).record
    }

    // MARK: - Segments

    func segments(for sections: [AnswerSection], firstID: Int = 0) -> [ReadingSegment] {
        sections.enumerated().map { segment(for: $0.element, id: firstID + $0.offset) }
    }

    /// One section → one segment, per the reading table of PLAN.md §4.2.
    func segment(for section: AnswerSection, id: Int) -> ReadingSegment {
        let text = section.text
        switch section.kind {
        case .question(let n):
            let title = vietnamese ? "Câu \(n)" : "Question \(n)"
            let display: String
            let speech: String
            switch section.questionAnswer ?? .unreadable {
            case .choice(let letter):
                display = "\(title): \(letter)"
                speech = "\(title): \(letter)."
            case .value(let value):
                display = "\(title): \(value)"
                speech = "\(title): " + Self.terminated(value)
            case .trueFalse(let items):
                display = "\(title): " + items.map { "\($0.label) \(verdictSymbol($0.isTrue))" }.joined(separator: ", ")
                speech = "\(title): " + items.map { "\($0.label) \(verdictWord($0.isTrue))" }.joined(separator: ", ") + "."
            case .unreadable:
                display = "\(title): ?"
                speech = vietnamese ? "\(title): không đọc được đề." : "\(title): unreadable."
            }
            return ReadingSegment(id: id, kind: .mcq(n), title: title, displayText: display, speechText: speech)

        case .problem(let n):
            let title = vietnamese ? "Bài \(n)" : "Problem \(n)"
            let heading: String
            if text.isEmpty {
                heading = title
            } else if Self.starts(text, withAnyOf: Self.headingWords) {
                heading = text                       // "Bài 1", "Câu 2 (2 điểm)": the paper's own label
            } else {
                heading = "\(title): \(text)"        // "Bài 1: Giải phương trình"
            }
            return ReadingSegment(id: id, kind: .problem(n), title: title, displayText: heading,
                                  speechText: Self.terminated(heading))

        case .line(let n):
            let title = vietnamese ? "Dòng \(n)" : "Line \(n)"
            let speech = readLineNumbers ? "\(title). " + Self.terminated(text) : Self.terminated(text)
            return ReadingSegment(id: id, kind: .line(n), title: title, displayText: "\(title): \(text)", speechText: speech)

        case .final:
            let title = vietnamese ? "Đáp số" : "Answer"
            let display = Self.starts(text, withAnyOf: Self.finalLabels) ? text : "\(title): \(text)"
            return ReadingSegment(id: id, kind: .final, title: title, displayText: display,
                                  speechText: Self.terminated(display))

        case .answer:
            return ReadingSegment(id: id, kind: .answer, title: "", displayText: text, speechText: Self.terminated(text))
        }
    }

    /// A message from the app itself, read and shown like a plain answer.
    func noticeSegment(_ text: String, id: Int) -> ReadingSegment {
        ReadingSegment(id: id, kind: .notice, title: vietnamese ? "Lưu ý" : "Note",
                       displayText: text, speechText: Self.terminated(text))
    }

    // MARK: - Wording

    private func verdictSymbol(_ isTrue: Bool) -> String {
        vietnamese ? (isTrue ? "Đ" : "S") : (isTrue ? "T" : "F")
    }

    private func verdictWord(_ isTrue: Bool) -> String {
        vietnamese ? (isTrue ? "đúng" : "sai") : (isTrue ? "true" : "false")
    }

    /// Words that already make a problem heading ("Bài 1", "Câu 2", "Problem 3", "Part a").
    private static let headingWords = ["bài", "bai", "câu", "cau", "phần", "phan", "ví dụ", "vi du",
                                       "problem", "question", "exercise", "part", "example"]

    /// Labels a FINAL line may already start with: not repeated ("Đáp số: Đáp số: …").
    private static let finalLabels = ["đáp số", "dap so", "đáp án", "dap an", "kết luận", "ket luan",
                                      "final answer", "answer"]

    private static func starts(_ text: String, withAnyOf words: [String]) -> Bool {
        let lower = text.lowercased()
        return words.contains { word in
            guard lower.hasPrefix(word) else { return false }
            guard let next = lower.dropFirst(word.count).first else { return true }
            return !next.isLetter
        }
    }

    /// A sentence ends with punctuation, so each segment is read with a falling tone and a pause.
    private static func terminated(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return trimmed }
        return ".!?…:;,".contains(last) ? trimmed : trimmed + "."
    }
}
