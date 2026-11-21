// OpenVision - AnswerFormat.swift
// Parser for answer format v2.1 (PLAN.md §4.2): a TYPE line, then Q / P / L / FINAL / ANSWER lines.
//
// Pure Foundation (no UIKit/AVFoundation, no regular expressions): built on Linux by
// scripts/swift-local/run.sh and on iOS. Never traps, whatever the model sends.
//
// Streaming contract: `completedSections(in:)` only returns sections that can no longer change,
// so every intermediate result is a prefix (same sections, same order) of `parse(_:).sections`
// for the finished reply. Tagged Q / P / L / FINAL lines are returned when their line is complete;
// ANSWER and untagged text are returned sentence by sentence as each sentence completes.

import Foundation

/// One piece of an answer, in the order the model wrote it.
struct AnswerSection: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// `Qn:` a multiple-choice, true/false or short answer.
        case question(Int)
        /// `Pn:` the heading of one essay problem.
        case problem(Int)
        /// `Ln:` one line of a worked solution.
        case line(Int)
        /// `FINAL:` the result of a problem.
        case final
        /// `ANSWER:` or text without a tag: one sentence per section.
        case answer
    }

    /// The answer of a `question` section, normalized.
    enum QuestionAnswer: Equatable, Sendable {
        /// An option letter, upper-cased: "C".
        case choice(String)
        /// One verdict per statement: "a Đ, b S, c Đ, d S".
        case trueFalse([TrueFalseItem])
        /// A short answer or anything else, as written: "2,5".
        case value(String)
        /// `Qn: ?` (or nothing): the model could not read the question.
        case unreadable
    }

    struct TrueFalseItem: Equatable, Sendable {
        /// Statement letter, lower-cased: "a".
        var label: String
        var isTrue: Bool
    }

    var kind: Kind
    /// What follows the tag: markdown, tags and protocol tokens removed, formulas kept as written.
    var text: String

    init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }

    /// The normalized answer of a `question` section (nil for every other kind).
    var questionAnswer: QuestionAnswer? {
        guard case .question = kind else { return nil }
        return AnswerFormat.questionAnswer(from: text)
    }
}

/// A whole reply, parsed.
struct ParsedAnswer: Equatable, Sendable {
    /// The declared TYPE, or the type inferred from the tags when the TYPE line is missing.
    var type: AnswerType
    /// The TYPE line as written (nil when missing or not understood).
    var declaredType: AnswerType?
    var sections: [AnswerSection]
    /// The model asked to see (reply starts with `[[CAPTURE]]`): nothing is read, the app takes a photo.
    var requestsCapture: Bool
    /// The model closed the conversation with `[[END]]`.
    var endsConversation: Bool
    /// `finishReason == MAX_TOKENS`: the cut-off last line is dropped and the app adds a notice.
    var isTruncated: Bool
}

enum AnswerFormat {
    /// Reply of a model that must see something first (the app takes a photo and asks again).
    static let captureToken = "[[CAPTURE]]"
    /// Last line of a goodbye: the app speaks it and closes the session.
    static let endToken = "[[END]]"
    /// Gemini `finishReason` of a reply that hit `maxOutputTokens`.
    static let maxTokensFinishReason = "MAX_TOKENS"

    // MARK: - Entry points

    /// Parses a finished reply. With `finishReason == "MAX_TOKENS"` the last line is treated as cut
    /// off (it is dropped, like while streaming) and `isTruncated` is set.
    static func parse(_ raw: String, finishReason: String? = nil) -> ParsedAnswer {
        let full = scan(raw, isFinal: true)
        let resolved = resolveType(full)
        let truncated = isTruncated(finishReason: finishReason)
        var sections = full.sections
        if truncated && !full.requestsCapture {
            sections = scan(raw, isFinal: false).sections
        }
        return ParsedAnswer(type: resolved.type, declaredType: resolved.declared,
                            sections: full.requestsCapture ? [] : sections,
                            requestsCapture: full.requestsCapture,
                            endsConversation: endsConversation(raw),
                            isTruncated: truncated)
    }

    /// Sections of a reply that is still streaming in: only the ones that can no longer change.
    /// The last line is held back while it is incomplete (it may be half a tag); ANSWER and
    /// untagged text are released one finished sentence at a time.
    static func completedSections(in accumulated: String) -> [AnswerSection] {
        scan(accumulated, isFinal: false).sections
    }

    static func endsConversation(_ raw: String) -> Bool {
        raw.range(of: endToken, options: .caseInsensitive) != nil
    }

    static func isTruncated(finishReason: String?) -> Bool {
        finishReason?.uppercased() == maxTokensFinishReason
    }

    /// The notice read after a reply that was cut by `MAX_TOKENS` (PLAN.md §4.2). "giải tiếp" is a
    /// new question for Gemini, not the reading command "tiếp tục".
    static func truncationNotice(after sections: [AnswerSection], languageCode: String) -> String {
        let vietnamese = languageCode.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("vi")
        let place: String
        switch sections.last?.kind {
        case .line(let n)?: place = vietnamese ? "dòng \(n)" : "line \(n)"
        case .question(let n)?: place = vietnamese ? "câu \(n)" : "question \(n)"
        case .problem(let n)?: place = vietnamese ? "bài \(n)" : "problem \(n)"
        default:
            return vietnamese
                ? "Câu trả lời dài nên mình dừng ở đây. Bạn hỏi 'giải tiếp' để mình giải nốt."
                : "The answer is long, so I stopped here. Say 'solve the rest' and I will finish it."
        }
        return vietnamese
            ? "Lời giải dài nên mình dừng ở \(place). Bạn hỏi 'giải tiếp' để mình giải nốt."
            : "The solution is long, so I stopped at \(place). Say 'solve the rest' and I will finish it."
    }

    // MARK: - Question answers (MCQ, true/false, short answer)

    /// Normalizes what follows `Qn:`: "?" → unreadable, "a Đ, b S, c Đ, d S" (also D/S, T/F,
    /// đúng/sai, true/false, unlabeled "Đ S Đ S" or "ĐSĐS") → true/false items, a lone letter →
    /// choice, anything else → value.
    static func questionAnswer(from text: String) -> AnswerSection.QuestionAnswer {
        var answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while answer.last == "." { answer.removeLast() }
        answer = answer.trimmingCharacters(in: .whitespaces)
        if answer.allSatisfy({ $0 == "?" || $0 == "？" }) { return .unreadable }   // also ""
        if let items = trueFalseItems(in: answer) { return .trueFalse(items) }
        if let letter = choiceLetter(in: answer) { return .choice(letter) }
        return .value(answer)
    }

    private static func choiceLetter(in answer: String) -> String? {
        let core = answer.trimmingCharacters(in: CharacterSet(charactersIn: "()[]* "))
        guard core.count == 1, let letter = core.first, letter.isASCII,
              "abcdefgh".contains(letter.lowercased()) else { return nil }
        return letter.uppercased()
    }

    private static func trueFalseItems(in answer: String) -> [AnswerSection.TrueFalseItem]? {
        let separators = Set<Character>(",;:.)(-–—/|=[]*")
        let tokens = answer.split(whereSeparator: { $0.isWhitespace || separators.contains($0) }).map(String.init)
        guard !tokens.isEmpty, tokens.count <= 32 else { return nil }

        // Labeled: "a Đ, b S, c Đ, d S", "a) Đúng b) Sai", "A: True, B: False".
        if tokens.count % 2 == 0 {
            var items: [AnswerSection.TrueFalseItem] = []
            var labels = Set<String>()
            for pair in stride(from: 0, to: tokens.count, by: 2) {
                let label = tokens[pair].lowercased()
                guard label.count == 1, "abcdefgh".contains(label), labels.insert(label).inserted,
                      let isTrue = verdict(tokens[pair + 1]) else {
                    items = []
                    break
                }
                items.append(.init(label: label, isTrue: isTrue))
            }
            // A single pair with a bare "D" verdict is more likely two options ("A, D") — unless the
            // tokens also read as unlabeled verdicts ("D S" = Đ, S), handled below.
            if !items.isEmpty && !(items.count == 1 && (tokens[1].lowercased() == "d" || verdict(tokens[0]) != nil)) {
                return items
            }
        }

        // Unlabeled verdicts: "Đ S Đ S", "Đúng, Sai, Đúng, Sai", "True False True False".
        if tokens.count >= 2 {
            let verdicts = tokens.compactMap(verdict)
            if verdicts.count == tokens.count && !tokens.allSatisfy({ $0.lowercased() == "d" }) {
                return labeled(verdicts)
            }
        }

        // Compact: "ĐSĐS", "DSDS", "TFTF".
        if tokens.count == 1, let word = tokens.first, (2...8).contains(word.count) {
            let verdicts = word.compactMap { verdict(String($0)) }
            if verdicts.count == word.count && !word.allSatisfy({ $0 == "d" || $0 == "D" }) {
                return labeled(verdicts)
            }
        }
        return nil
    }

    private static func labeled(_ verdicts: [Bool]) -> [AnswerSection.TrueFalseItem] {
        zip("abcdefghijklmnopqrstuvwxyz", verdicts).map { .init(label: String($0.0), isTrue: $0.1) }
    }

    private static func verdict(_ token: String) -> Bool? {
        switch token.lowercased() {
        case "đ", "ð", "d", "đúng", "dung", "đung", "t", "true": return true
        case "s", "sai", "f", "false": return false
        default: return nil
        }
    }

    // MARK: - TYPE values

    /// "MCQ", "ESSAY", "MIXED", "OTHER" (any case; Vietnamese names accepted). Nil when unknown.
    static func answerType(fromTypeValue value: String) -> AnswerType? {
        let v = value.uppercased()
        let mixed = v.contains("MIXED") || v.contains("HỖN HỢP") || v.contains("HON HOP")
        let mcq = v.contains("MCQ") || v.contains("MULTIPLE") || v.contains("TRẮC NGHIỆM") || v.contains("TRAC NGHIEM")
        let essay = v.contains("ESSAY") || v.contains("TỰ LUẬN") || v.contains("TU LUAN")
        let other = v.contains("OTHER") || v.contains("KHÁC") || v.contains("KHAC")
        if mixed || (mcq && essay) { return .mixed }
        if mcq { return .mcq }
        if essay { return .essay }
        if other { return .other }
        return nil
    }

    // MARK: - Sentences

    private static let sentenceTerminators: Set<Character> = [".", "!", "?", "…"]

    /// Splits text into sentences: a terminator (. ! ? …) followed by whitespace, never inside `$…$`,
    /// so "2.5" and formulas stay whole. With `isComplete == false` only finished sentences are
    /// returned (the text may still grow), and they never change as it grows.
    static func sentences(in text: String, isComplete: Bool = true) -> [String] {
        let chars = Array(text)
        var result: [String] = []
        var start = 0
        var inMath = false
        var i = 0

        func take(_ end: Int) {
            guard start < end else { return }
            let sentence = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.contains(where: { $0.isLetter || $0.isNumber }) { result.append(sentence) }
            start = end
        }

        while i < chars.count {
            let ch = chars[i]
            if ch == "$" && (i == 0 || chars[i - 1] != "\\") {
                inMath.toggle()
                if i + 1 < chars.count && chars[i + 1] == "$" { i += 1 }   // "$$" is one delimiter
            } else if !inMath && sentenceTerminators.contains(ch) {
                let next = i + 1
                if next < chars.count ? chars[next].isWhitespace : isComplete {
                    take(next)
                }
            }
            i += 1
        }
        if isComplete { take(chars.count) }
        return result
    }

    // MARK: - Scanner

    private enum Tag: Equatable {
        case type, question(Int), problem(Int), line(Int), final, answer
    }

    private enum LineClass {
        /// Incomplete line that may still become a tag, a code fence or a table row.
        case undecided
        /// Nothing to read: empty, markdown rule, code fence, table separator.
        case skip
        /// Text without a tag (leading markdown markers removed).
        case plain(String)
        /// A tag and the raw text after it.
        case tag(Tag, String)
    }

    private struct ScanResult {
        var sections: [AnswerSection] = []
        var declaredTypes: [AnswerType] = []
        /// Q / P / L / FINAL / ANSWER tags of complete lines, in order (type inference).
        var tags: [Tag] = []
        var requestsCapture = false
    }

    /// One pass over the reply. `isFinal == false`: the last line may still grow, so it is
    /// classified as a prefix and nothing that could change is emitted.
    private static func scan(_ raw: String, isFinal: Bool) -> ScanResult {
        var result = ScanResult()
        let lines = raw.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
        var pending: Tag?          // Q / P / L / FINAL with nothing after it: content on the next line
        var sawContent = false     // a line other than TYPE was seen ([[CAPTURE]] must come first)

        func flushPending() {
            guard let tag = pending else { return }
            pending = nil
            switch tag {
            case .question(let n): result.sections.append(AnswerSection(.question(n), ""))   // read as unreadable
            case .problem(let n): result.sections.append(AnswerSection(.problem(n), ""))     // "Bài n."
            default: break                                                                  // empty L / FINAL
            }
        }

        func appendSentences(of content: String, isComplete: Bool) {
            for sentence in sentences(in: clean(content), isComplete: isComplete) {
                result.sections.append(AnswerSection(.answer, sentence))
            }
        }

        lineLoop: for (index, line) in lines.enumerated() {
            let isComplete = isFinal || index < lines.count - 1
            let lineClass = classify(Array(line), isComplete: isComplete)

            if !sawContent {
                var probe: String?
                switch lineClass {
                case .tag(.type, _), .skip, .undecided: probe = nil
                case .tag(_, let content), .plain(let content): probe = content
                }
                if let probe {
                    let head = probe.trimmingCharacters(in: .whitespaces).uppercased()
                    if head.hasPrefix(captureToken) {
                        result.sections = []
                        result.requestsCapture = true
                        return result
                    }
                    if !isComplete && captureToken.hasPrefix(head) { break lineLoop }
                }
            }

            switch lineClass {
            case .undecided:
                break lineLoop
            case .skip:
                continue
            case .tag(.type, let content):
                guard isComplete else { break lineLoop }
                flushPending()
                if let type = answerType(fromTypeValue: clean(content)) { result.declaredTypes.append(type) }
            case .tag(.answer, let content):
                flushPending()
                sawContent = true
                if isComplete { result.tags.append(.answer) }
                appendSentences(of: content, isComplete: isComplete)
                if !isComplete { break lineLoop }
            case .tag(let tag, let content):
                flushPending()
                sawContent = true
                guard isComplete else { break lineLoop }
                result.tags.append(tag)
                let text = cleanTagged(content)
                if text.isEmpty {
                    pending = tag
                } else if let kind = sectionKind(tag) {
                    result.sections.append(AnswerSection(kind, text))
                }
            case .plain(let content):
                sawContent = true
                if let tag = pending {
                    guard isComplete else { break lineLoop }
                    pending = nil
                    let text = cleanTagged(content)
                    if !text.isEmpty, let kind = sectionKind(tag) {
                        result.sections.append(AnswerSection(kind, text))
                    }
                } else {
                    appendSentences(of: content, isComplete: isComplete)
                    if !isComplete { break lineLoop }
                }
            }
        }
        if isFinal { flushPending() }
        return result
    }

    private static func sectionKind(_ tag: Tag) -> AnswerSection.Kind? {
        switch tag {
        case .type: return nil
        case .question(let n): return .question(n)
        case .problem(let n): return .problem(n)
        case .line(let n): return .line(n)
        case .final: return .final
        case .answer: return .answer
        }
    }

    private static func resolveType(_ scan: ScanResult) -> (type: AnswerType, declared: AnswerType?) {
        let declaredSet = Set(scan.declaredTypes)
        var declared = scan.declaredTypes.first
        if declaredSet.contains(.mixed) || (declaredSet.contains(.mcq) && declaredSet.contains(.essay)) {
            declared = .mixed
        }
        if let declared { return (declared, declared) }

        // No TYPE line: the first tag decides (Q → MCQ, L / P → ESSAY, anything else → OTHER);
        // Q and L / P tags together make it MIXED.
        let hasQuestion = scan.tags.contains { if case .question = $0 { return true } else { return false } }
        let hasEssay = scan.tags.contains {
            switch $0 {
            case .problem, .line: return true
            default: return false
            }
        }
        if hasQuestion && hasEssay { return (.mixed, nil) }
        switch scan.tags.first {
        case .question?: return (.mcq, nil)
        case .problem?, .line?: return (.essay, nil)
        default: return (.other, nil)
        }
    }

    // MARK: - Content cleaning

    /// Removes protocol tokens and markdown bold, collapses runs of spaces. Leading space is trimmed,
    /// trailing space is kept (a sentence boundary needs the space after its terminator).
    private static func clean(_ content: String) -> String {
        var text = content
        for token in [endToken, captureToken] {
            text = text.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: "**", with: "")
        var collapsed = ""
        var lastWasSpace = false
        for ch in text {
            let isSpace = ch.isWhitespace
            if isSpace && lastWasSpace { continue }
            collapsed.append(isSpace ? " " : ch)
            lastWasSpace = isSpace
        }
        while collapsed.first == " " { collapsed.removeFirst() }
        return collapsed
    }

    /// Content of a complete Q / P / L / FINAL line: cleaned, trimmed, stray emphasis stars removed.
    private static func cleanTagged(_ content: String) -> String {
        clean(content).trimmingCharacters(in: CharacterSet(charactersIn: "* ").union(.whitespacesAndNewlines))
    }

    // MARK: - Line classification

    private enum Keyword {
        case type, question, problem, line, final, answer
    }

    private struct KeywordSpec {
        let spelling: [Character]
        let keyword: Keyword
        let numbered: Bool
    }

    /// Tag words, longest first. Case-insensitive; a space matches any run of whitespace.
    private static let keywords: [KeywordSpec] = {
        let table: [(String, Keyword, Bool)] = [
            ("final answer", .final, false), ("kết luận", .final, false), ("ket luan", .final, false),
            ("đáp số", .final, false), ("dap so", .final, false), ("final", .final, false),
            ("trả lời", .answer, false), ("tra loi", .answer, false), ("answer", .answer, false),
            ("type", .type, false),
            ("question", .question, true), ("câu", .question, true), ("cau", .question, true), ("q", .question, true),
            ("problem", .problem, true), ("bài", .problem, true), ("bai", .problem, true), ("p", .problem, true),
            ("line", .line, true), ("dòng", .line, true), ("dong", .line, true), ("l", .line, true),
        ]
        return table.map { KeywordSpec(spelling: Array($0.0), keyword: $0.1, numbered: $0.2) }
            .sorted { $0.spelling.count > $1.spelling.count }
    }()

    /// Markdown that may come before a tag: bullets, headings, quotes, bold, invisible characters.
    private static let leadingDecorations: Set<Character> = ["-", "*", "#", "•", ">", "+", "_", "–", "—", "·", "\u{FEFF}", "\u{200B}"]

    private static func classify(_ chars: [Character], isComplete: Bool) -> LineClass {
        let n = chars.count
        var i = 0
        var run: Character?
        var runLength = 0
        var boldOpen = false
        while i < n, chars[i].isWhitespace || leadingDecorations.contains(chars[i]) {
            let ch = chars[i]
            if ch == "*" || ch == "_" {
                runLength = (run == ch) ? runLength + 1 : 1
                run = ch
                if runLength >= 2 { boldOpen = true }
            } else {
                run = nil
                runLength = 0
            }
            i += 1
        }
        guard i < n else { return isComplete ? .skip : .undecided }

        var start = i
        var bracketOpen = false
        if chars[start] == "[" {
            bracketOpen = true
            start += 1
            while start < n, chars[start].isWhitespace || chars[start] == "*" { start += 1 }
        }

        var mayBecomeTag = false
        if start < n {
            for spec in keywords {
                switch matchTag(spec, chars, at: start, boldOpen: boldOpen, bracketOpen: bracketOpen, isComplete: isComplete) {
                case .tag(let tag, let contentStart):
                    return .tag(tag, contentStart < n ? String(chars[contentStart...]) : "")
                case .partial:
                    mayBecomeTag = true
                case .failed:
                    continue
                }
            }
        } else if !isComplete {
            mayBecomeTag = true
        }
        if mayBecomeTag && !isComplete { return .undecided }
        return plain(chars, isComplete: isComplete)
    }

    private enum TagMatch {
        case tag(Tag, contentStart: Int)
        case partial
        case failed
    }

    private static func matchTag(_ spec: KeywordSpec, _ c: [Character], at start: Int,
                                 boldOpen: Bool, bracketOpen: Bool, isComplete: Bool) -> TagMatch {
        let n = c.count
        let endOfInput: TagMatch = isComplete ? .failed : .partial
        var i = start

        // 1. The tag word.
        for letter in spec.spelling {
            guard i < n else { return endOfInput }
            if letter == " " {
                guard c[i].isWhitespace else { return .failed }
                while i < n, c[i].isWhitespace { i += 1 }
                continue
            }
            guard c[i].lowercased() == String(letter) else { return .failed }
            i += 1
        }

        // 2. Its number ("Q12", "Câu 12") or, for words, a word boundary ("finally" is not FINAL).
        var number = 0
        if spec.numbered {
            while i < n, c[i].isWhitespace { i += 1 }
            var digits = 0
            while i < n, c[i].isASCII, let digit = c[i].wholeNumberValue {
                digits += 1
                guard digits <= 4 else { return .failed }
                number = number * 10 + digit
                i += 1
            }
            if digits == 0 { return i < n ? .failed : endOfInput }
            if i == n && !isComplete { return .partial }   // more digits may follow
        } else if i < n, c[i].isLetter || c[i].isNumber {
            return .failed
        }

        let tag: Tag
        switch spec.keyword {
        case .type: tag = .type
        case .question: tag = .question(number)
        case .problem: tag = .problem(number)
        case .line: tag = .line(number)
        case .final: tag = .final
        case .answer: tag = .answer
        }

        // 3. Closing markdown: "**Q1**", "[Q1]", "Q1 :".
        var closedBold = false
        var closedBracket = false
        var stars = 0
        while i < n {
            let ch = c[i]
            if ch == "*" || ch == "_" {
                stars += 1
                if stars >= 2 { closedBold = true }
            } else if ch == "]" && bracketOpen && !closedBracket {
                closedBracket = true
            } else if !ch.isWhitespace {
                break
            }
            i += 1
        }
        let labelled = (boldOpen && closedBold) || (bracketOpen && closedBracket)
        guard i < n else { return labelled ? .tag(tag, contentStart: n) : endOfInput }

        // 4. The separator.
        var contentStart: Int
        let ch = c[i]
        if ch == ":" || ch == "：" {
            contentStart = i + 1
        } else if spec.numbered && ch == ")" {
            contentStart = i + 1
        } else if spec.numbered && (ch == "." || ch == "-" || ch == "–" || ch == "—") {
            // "Q1. A", "Q1 - A"; not "Q1.5" or "Q1-A".
            if i + 1 < n {
                guard c[i + 1].isWhitespace else { return labelled ? .tag(tag, contentStart: i) : .failed }
            } else if !isComplete {
                return labelled ? .tag(tag, contentStart: i) : .partial
            }
            contentStart = i + 1
        } else if labelled {
            contentStart = i
        } else {
            return .failed
        }

        // 5. Bold closed after the colon ("**Q1:** A") and spaces.
        while contentStart < n, c[contentStart] == "*" || c[contentStart].isWhitespace { contentStart += 1 }
        return .tag(tag, contentStart: contentStart)
    }

    /// Bullet, heading, quote and bold markers at the start of untagged text. A minus sign that is
    /// part of the text ("-3 < x") stays.
    private static func markdownPrefixEnd(_ c: [Character]) -> Int {
        let n = c.count
        let bullets: Set<Character> = ["-", "*", "•", "+", ">", "–", "—", "·"]
        var i = 0
        while i < n {
            let ch = c[i]
            if ch.isWhitespace || ch == "\u{FEFF}" || ch == "\u{200B}" {
                i += 1
            } else if (ch == "*" || ch == "_") && i + 1 < n && c[i + 1] == ch {
                while i < n, c[i] == ch { i += 1 }
            } else if ch == "#" {
                while i < n, c[i] == "#" { i += 1 }
            } else if bullets.contains(ch) && i + 1 < n && c[i + 1].isWhitespace {
                i += 2
            } else {
                break
            }
        }
        return i
    }

    private static func plain(_ chars: [Character], isComplete: Bool) -> LineClass {
        let start = markdownPrefixEnd(chars)
        let body = start < chars.count ? String(chars[start...]) : ""
        if body.first == "`" || body.first == "|" {
            // Code fences and table rows are only judged once the line is complete.
            guard isComplete else { return .undecided }
            let line = body.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { return .skip }
            if line.count >= 2, line.hasPrefix("|"), line.hasSuffix("|") {
                let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if cells.count >= 2 {
                    let readable = cells.filter { cell in cell.contains(where: { $0.isLetter || $0.isNumber }) }
                    return readable.isEmpty ? .skip : .plain(readable.joined(separator: ", "))
                }
            }
        }
        if isComplete && !body.contains(where: { $0.isLetter || $0.isNumber }) { return .skip }
        return .plain(body)
    }
}
