// OpenVision - MathSpanSplitter.swift
// Splits an answer into prose and formula spans (PLAN.md §4.3). Pure Swift, Foundation only.

import Foundation

enum MathSpan: Equatable {
    case prose(String)
    /// Formula source without its delimiters.
    case math(String)
}

/// Finds formulas in answer text:
/// - delimited: `$…$`, `$$…$$` (read as one line), `\(…\)`, `\[…\]`;
/// - bare, in prose: Unicode math (x² ≤ √ π Δ ∈ …), LaTeX commands, and clear ASCII patterns
///   (`x^2`, `3/4`, `f(x) = …`, `-2x + 4 = 0`, `2*3*4`).
/// Conservative on purpose: "1-5", "Ray-Ban", "12/5/2026", "10:30", "2,5 cm" stay prose (numbers and
/// units in prose are normalised by the readers, not parsed as formulas).
enum MathSpanSplitter {
    /// - Parameter vietnamese: in English prose the words "a", "A" and "I" are never part of a bare
    ///   formula ("Is x = 2 a solution?").
    static func split(_ text: String, vietnamese: Bool = true) -> [MathSpan] {
        var spans: [MathSpan] = []
        for span in splitDelimited(text) {
            switch span {
            case .math: spans.append(span)
            case .prose(let prose): spans.append(contentsOf: splitBareFormulas(prose, vietnamese: vietnamese))
            }
        }
        return merged(spans)
    }

    // MARK: - Delimited formulas

    static func splitDelimited(_ text: String) -> [MathSpan] {
        let chars = Array(text)
        var spans: [MathSpan] = []
        var prose: [Character] = []
        func flush() {
            if !prose.isEmpty { spans.append(.prose(String(prose))) }
            prose.removeAll()
        }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                let d = chars[i + 1]
                if d == "(" || d == "[" {
                    let closer: Character = d == "(" ? ")" : "]"
                    let end = find(["\\", closer], in: chars, from: i + 2) ?? chars.count
                    flush()
                    spans.append(.math(String(chars[(i + 2)..<end])))
                    i = min(end + 2, chars.count)
                    continue
                }
                if d == "$" {  // an escaped dollar is not a delimiter (and is never spoken)
                    prose.append(" ")
                    i += 2
                    continue
                }
            }
            if c == "$" {
                if i + 1 < chars.count, chars[i + 1] == "$" {
                    if let end = find(["$", "$"], in: chars, from: i + 2) {
                        flush()
                        spans.append(.math(String(chars[(i + 2)..<end])))
                        i = end + 2
                    } else {
                        i += 2
                    }
                    continue
                }
                if let end = closingDollar(in: chars, from: i + 1) {
                    flush()
                    spans.append(.math(String(chars[(i + 1)..<end])))
                    i = end + 1
                } else {
                    i += 1  // a lone "$": dropped, the rest stays prose
                }
                continue
            }
            prose.append(c)
            i += 1
        }
        flush()
        return spans
    }

    private static func find(_ pattern: [Character], in chars: [Character], from start: Int) -> Int? {
        guard pattern.count <= chars.count, start <= chars.count - pattern.count else { return nil }
        var j = start
        while j <= chars.count - pattern.count {
            if chars[j] == pattern[0], chars[j + 1] == pattern[1] { return j }
            j += 1
        }
        return nil
    }

    /// The matching single `$` on the same line (formulas are one line, PLAN.md §4.2).
    private static func closingDollar(in chars: [Character], from start: Int) -> Int? {
        var j = start
        while j < chars.count {
            let c = chars[j]
            if c == "\n" { return nil }
            if c == "\\" { j += 2; continue }
            if c == "$" { return j > start ? j : nil }
            j += 1
        }
        return nil
    }

    // MARK: - Bare formulas in prose

    private struct Chunk {
        var start: Int
        var end: Int  // exclusive
        var coreStart: Int
        var coreEnd: Int
        var compatible = false
        var anchor = false
        var isLabel = false
    }

    /// Characters that make a chunk a formula on their own (Unicode math, minus prose punctuation).
    static let anchorCharacters: Set<Character> = {
        var set = Set(MathLexer.unicodeReplacements.keys)
        set.formUnion(MathLexer.superscripts.keys)
        set.formUnion(MathLexer.subscripts.keys)
        set.formUnion(MathLexer.greekCharacters.keys)
        set.subtract(["°", "º", "…", "–", "：", "；", "，", "⟨", "⟩", "µ"])
        return set
    }()

    private static let asciiMathCharacters: Set<Character> = [
        "+", "-", "*", "/", "=", "<", ">", "^", "_", "(", ")", "[", "]", "{", "}", "|", "!", "'", ",", ".", ";",
        ":", "%", "\\",
    ]
    private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "?", "!", "…", "\"", "”", "’", "»"]
    private static let leadingPunctuation: Set<Character> = ["\"", "“", "‘", "«"]

    static func splitBareFormulas(_ prose: String, vietnamese: Bool = true) -> [MathSpan] {
        let chars = Array(stripMarkdown(prose))
        guard chars.contains(where: { !$0.isWhitespace }) else { return chars.isEmpty ? [] : [.prose(String(chars))] }
        var chunks: [Chunk] = []
        var i = 0
        while i < chars.count {
            if chars[i].isWhitespace { i += 1; continue }
            var j = i
            while j < chars.count, !chars[j].isWhitespace { j += 1 }
            chunks.append(Chunk(start: i, end: j, coreStart: i, coreEnd: j))
            i = j
        }
        for n in chunks.indices {
            classify(&chunks[n], chars, previous: n > 0 ? String(chars[chunks[n - 1].start..<chunks[n - 1].end]) : nil)
            if !vietnamese, ["a", "A", "I"].contains(String(chars[chunks[n].coreStart..<chunks[n].coreEnd])) {
                chunks[n].compatible = false  // English words, not variables
            }
        }

        var spans: [MathSpan] = []
        var proseStart = 0
        var n = 0
        while n < chunks.count {
            guard chunks[n].compatible else { n += 1; continue }
            var m = n
            while m + 1 < chunks.count, chunks[m + 1].compatible { m += 1 }
            var first = n
            while first <= m, chunks[first].isLabel { first += 1 }
            if first <= m, (first...m).contains(where: { chunks[$0].anchor }) {
                let start = chunks[first].coreStart
                var end = chunks[m].end
                while end > start, trailingPunctuation.contains(chars[end - 1]) { end -= 1 }
                if end > start {
                    if start > proseStart { spans.append(.prose(String(chars[proseStart..<start]))) }
                    spans.append(.math(String(chars[start..<end])))
                    proseStart = end
                }
            }
            n = m + 1
        }
        if proseStart < chars.count { spans.append(.prose(String(chars[proseStart...]))) }
        return spans
    }

    private static func classify(_ chunk: inout Chunk, _ chars: [Character], previous: String?) {
        var coreStart = chunk.start
        var coreEnd = chunk.end
        while coreStart < coreEnd, leadingPunctuation.contains(chars[coreStart]) { coreStart += 1 }
        while coreEnd > coreStart, trailingPunctuation.contains(chars[coreEnd - 1]) { coreEnd -= 1 }
        chunk.coreStart = coreStart
        chunk.coreEnd = coreEnd
        guard coreStart < coreEnd else { return }
        let core = Array(chars[coreStart..<coreEnd])

        // Labels: "A." "b)" "1." "100." at the start of an option or a step. A chunk ending with ":"
        // ("12:", "TH1:") is also a label, set below once it is known to hold no math.
        let rawEnd = chars[chunk.end - 1]
        let labelCore = rawEnd == ")" && core.last == ")" ? core.dropLast() : core[...]
        let isNumberLabel = (1...3).contains(labelCore.count) && labelCore.allSatisfy { MathLexer.isDigit($0) }
        let isLetterLabel = labelCore.count == 1 && MathLexer.isASCIILetter(labelCore[labelCore.startIndex])
        if rawEnd == "." || rawEnd == ")", isNumberLabel || isLetterLabel {
            chunk.isLabel = true
        }
        if isDate(core, previous: previous) || isTime(core) { return }

        var anchor = false
        var k = 0
        while k < core.count {
            let c = core[k]
            if c == "\\" {
                // A LaTeX command: its name is not a word.
                var e = k + 1
                while e < core.count, MathLexer.isASCIILetter(core[e]) { e += 1 }
                if e > k + 1 { anchor = true }
                k = max(e, k + 1)
                continue
            }
            if MathLexer.isASCIILetter(c) {
                var e = k
                while e < core.count, MathLexer.isASCIILetter(core[e]) { e += 1 }
                let run = String(core[k..<e])
                let afterDigit = k > 0 && MathLexer.isDigit(core[k - 1])
                guard isMathWord(run, afterDigit: afterDigit) else { return }
                if e < core.count, core[e] == "'", run.count == 1 { anchor = true }  // f'(x)
                k = e
                continue
            }
            if MathLexer.isDigit(c) { k += 1; continue }
            if anchorCharacters.contains(c) { anchor = true; k += 1; continue }
            if c.isLetter { return }  // a Vietnamese (or other) word
            if asciiMathCharacters.contains(c) {
                switch c {
                case "^", "_", "=", "<", ">", "+", "*":
                    anchor = true
                case "/":
                    if isFractionSlash(core, at: k) { anchor = true }
                case "|":
                    let before = k > 0 && (core[k - 1].isLetter || core[k - 1].isNumber)
                    let after = k + 1 < core.count && (core[k + 1].isLetter || core[k + 1].isNumber)
                    if before || after { anchor = true }
                default:
                    break
                }
                k += 1
                continue
            }
            if MathLexer.unicodeReplacements[c] != nil || c == "°" || c == "º" { k += 1; continue }
            return  // quotes, "@", "#", emoji…
        }
        chunk.compatible = true
        chunk.anchor = anchor
        // "Câu 12: 3/4.", "Bước 1: x = 2.", "TH1: x ≥ 0.": the label and its colon stay prose, so the
        // colon is never read as division. "Δ: x - y + 1 = 0" holds math and stays in the formula.
        if rawEnd == ":", !anchor { chunk.isLabel = true }
    }

    /// A run of ASCII letters that can be part of a formula.
    private static func isMathWord(_ run: String, afterDigit: Bool) -> Bool {
        if run.count == 1 { return true }
        if MathParser.functionNameSet.contains(run) { return true }
        if let name = MathParser.functionNames.first(where: { run.hasPrefix($0) }), run.count - name.count <= 1 {
            return true  // "sinx", "lnx"
        }
        if run.count <= 4, run.allSatisfy({ $0.isUppercase }) { return true }  // AB, ABC, ABCD
        if MathParser.unitSymbols.contains(run) { return true }
        if afterDigit, run.count <= 3 { return true }  // 4ac, 2xy
        return false
    }

    /// "3/4", "a/b", "x/2" — not a unit ("km/h") or part of a date.
    private static func isFractionSlash(_ core: [Character], at k: Int) -> Bool {
        guard k > 0, k + 1 < core.count else { return false }
        let before = core[k - 1]
        let after = core[k + 1]
        let operandBefore = before.isLetter || before.isNumber || before == ")" || before == "}"
        let operandAfter = after.isLetter || after.isNumber || after == "(" || after == "\\" || after == "-"
        guard operandBefore, operandAfter else { return false }
        // Units: letters on both sides that form a compound unit.
        var s = k - 1
        while s > 0, MathLexer.isASCIILetter(core[s - 1]) { s -= 1 }
        var e = k + 2
        while e < core.count, MathLexer.isASCIILetter(core[e]) { e += 1 }
        let left = String(core[s..<k])
        let right = String(core[(k + 1)..<e])
        if MathParser.unitSymbols.contains(left), MathParser.unitSymbols.contains(right) { return false }
        return true
    }

    /// "12/5/2026", "12/5" after "ngày", "1/1/24".
    private static func isDate(_ core: [Character], previous: String?) -> Bool {
        let parts = String(core).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { MathLexer.isDigit($0) } }) else {
            return false
        }
        if parts.count >= 3 { return true }
        let word = previous?.lowercased().trimmingCharacters(in: .punctuationCharacters) ?? ""
        return ["ngày", "hôm", "sáng", "chiều", "tối", "date", "on"].contains(word)
    }

    /// "10:30", "7:05".
    private static func isTime(_ core: [Character]) -> Bool {
        let parts = String(core).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return false }
        guard parts[0].count <= 2, parts.dropFirst().allSatisfy({ $0.count == 2 }) else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { MathLexer.isDigit($0) } }
    }

    // MARK: - Markdown

    /// Removes emphasis markers, code ticks and heading marks so "**2,5**" is not read as multiplication.
    /// A single "*" between two operands ("2*3") or between spaces ("a * b") stays.
    static func stripMarkdown(_ text: String) -> String {
        let chars = Array(text)
        var out: [Character] = []
        out.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "`" { i += 1; continue }
            if c == "#" {
                // Markdown heading marks ("## Kết luận"): never spoken.
                var j = i
                while j < chars.count, chars[j] == "#" { j += 1 }
                let atLineStart = i == 0 || chars[i - 1].isWhitespace
                if atLineStart, j == chars.count || chars[j].isWhitespace { i = j; continue }
            }
            if c == "*" || c == "_" {
                var j = i
                while j < chars.count, chars[j] == c { j += 1 }
                let count = j - i
                if count >= 2 { i = j; continue }  // ** or __
                if c == "*" {
                    let before: Character? = i > 0 ? chars[i - 1] : nil
                    let after: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                    let operandBefore = before.map { $0.isLetter || $0.isNumber || $0 == ")" } ?? false
                    let operandAfter = after.map { $0.isLetter || $0.isNumber || $0 == "(" } ?? false
                    let spaceBefore = before.map { $0.isWhitespace } ?? true
                    let spaceAfter = after.map { $0.isWhitespace } ?? true
                    if (operandBefore && operandAfter) || (spaceBefore && spaceAfter) {
                        out.append(c)
                    }
                    i += 1
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return String(out)
    }

    // MARK: - Helpers

    private static func merged(_ spans: [MathSpan]) -> [MathSpan] {
        var out: [MathSpan] = []
        for span in spans {
            if case .prose(let text) = span, text.isEmpty { continue }
            if case .math(let text) = span, text.allSatisfy({ $0.isWhitespace }) { continue }
            if case .prose(let text) = span, case .prose(let previous)? = out.last {
                out[out.count - 1] = .prose(previous + text)
            } else {
                out.append(span)
            }
        }
        return out
    }
}
