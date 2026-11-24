// Reybain - VietMathSpeech.swift
// Entry point of the spoken-math module (PLAN.md §4.3): answer text → pieces to speak, one sentence
// or one formula per piece. Pure Swift, Foundation only.

import Foundation

/// What the reading engine speaks: words (one utterance each; `isMath` marks a formula, read at
/// `mathRateFactor` and followed by `pauseAfterFormula`) or a pause inside a formula.
enum SpeechPiece: Equatable, Codable {
    case words(String, isMath: Bool)
    case pause(milliseconds: Int)
}

/// One step of a formula reading: a word, punctuation glued to the previous word, or a short pause.
enum MathReadingItem: Equatable {
    case word(String)
    case punct(String)
    /// A short pause (`VietMathSpeech.shortPauseMilliseconds`) after a compound exponent, fraction,
    /// root…; dropped when nothing follows or when punctuation already pauses.
    case pause
}

enum VietMathSpeech {
    /// Longest `.words` text (PLAN.md §2.4: long utterances can stop mid-way).
    static let maxPieceLength = 200
    /// Pause after a compound exponent, fraction or root when the formula goes on.
    static let shortPauseMilliseconds = 200
    /// Characters that must never reach the voice.
    static let forbiddenCharacters: Set<Character> = ["\\", "$", "{", "}", "^", "_"]

    struct Rendering: Equatable {
        var pieces: [SpeechPiece]
        /// Unknown or unsupported commands met while reading (for the debug screen).
        var warnings: [String]
    }

    /// The only entry point. Prose keeps its words (in Vietnamese answers numbers, units and symbols
    /// are normalised); formulas are read in Vietnamese, or by `EnglishMathReader` when `vietnamese`
    /// is false. The pronunciation dictionary and letter names apply to Vietnamese answers only.
    static func render(_ text: String, vietnamese: Bool, style: MathReadingStyle) -> [SpeechPiece] {
        renderWithDiagnostics(text, vietnamese: vietnamese, style: style).pieces
    }

    static func renderWithDiagnostics(_ text: String, vietnamese: Bool, style: MathReadingStyle) -> Rendering {
        let reader = VietnameseMathReader(style: style)
        var pieces: [SpeechPiece] = []
        var warnings: [String] = []
        for span in MathSpanSplitter.split(text, vietnamese: vietnamese) {
            switch span {
            case .prose(let prose):
                let normalized = vietnamese ? reader.normalizeProse(prose) : prose
                for sentence in sentences(normalized) {
                    // ", thể tích …" right after a formula: the formula's own pause replaces the comma.
                    let text = String(sentence.drop(while: { [",", ";", ":", "."].contains($0) || $0.isWhitespace }))
                    pieces.append(.words(text, isMath: false))
                }
            case .math(let source):
                let result = MathParser.parseWithDiagnostics(source, decimalComma: vietnamese)
                warnings += result.warnings
                pieces += vietnamese ? reader.pieces(for: result.node) : EnglishMathReader().pieces(for: result.node)
            }
        }
        return Rendering(pieces: finalize(pieces), warnings: warnings)
    }

    /// The words of the pieces, joined (for the "Thử đọc" screen and logs).
    static func spokenText(_ pieces: [SpeechPiece]) -> String {
        pieces.compactMap { piece -> String? in
            if case .words(let text, _) = piece { return text }
            return nil
        }.joined(separator: " ")
    }

    // MARK: - Pieces

    /// Words, punctuation and pauses → pieces. A pause splits the words into two pieces.
    static func pieces(from items: [MathReadingItem], isMath: Bool) -> [SpeechPiece] {
        var pieces: [SpeechPiece] = []
        var words: [String] = []
        var pendingPause = false
        for item in items {
            switch item {
            case .word(let w):
                let trimmed = w.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                if pendingPause, !words.isEmpty {
                    pieces.append(.words(words.joined(separator: " "), isMath: isMath))
                    pieces.append(.pause(milliseconds: shortPauseMilliseconds))
                    words.removeAll()
                }
                pendingPause = false
                words.append(trimmed)
            case .punct(let p):
                guard !words.isEmpty else { continue }
                pendingPause = false  // the punctuation is the pause
                if let last = words.last, let lastChar = last.last, [",", ";", ":"].contains(lastChar) { continue }
                words[words.count - 1] += p
            case .pause:
                pendingPause = true
            }
        }
        if !words.isEmpty { pieces.append(.words(words.joined(separator: " "), isMath: isMath)) }
        return pieces
    }

    /// Sanitises, drops empty or punctuation-only pieces, splits long ones and tidies pauses.
    static func finalize(_ pieces: [SpeechPiece]) -> [SpeechPiece] {
        var out: [SpeechPiece] = []
        for piece in pieces {
            switch piece {
            case .words(let raw, let isMath):
                for part in splitLong(sanitized(raw)) where part.contains(where: { $0.isLetter || $0.isNumber }) {
                    out.append(.words(part, isMath: isMath))
                }
            case .pause(let ms):
                guard ms > 0 else { continue }
                if case .pause(let previous)? = out.last {
                    out[out.count - 1] = .pause(milliseconds: max(previous, ms))
                } else if !out.isEmpty {
                    out.append(piece)
                }
            }
        }
        while case .pause? = out.last { out.removeLast() }
        return out
    }

    /// No forbidden characters, single spaces, trimmed.
    static func sanitized(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var lastWasSpace = true
        for c in text {
            let isSpace = c.isWhitespace || forbiddenCharacters.contains(c)
            if isSpace {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(c)
                lastWasSpace = false
            }
        }
        if out.last == " " { out.removeLast() }
        return out
    }

    /// Splits text longer than `maxPieceLength` at the last ", " / "; " / ": " that fits, else at
    /// the last space, else hard.
    static func splitLong(_ text: String) -> [String] {
        var parts: [String] = []
        var rest = Substring(text)
        while rest.count > maxPieceLength {
            let window = rest.prefix(maxPieceLength)
            var cut: String.Index?
            var index = window.endIndex
            while index > window.startIndex {
                let previous = window.index(before: index)
                if [",", ";", ":"].contains(window[previous]), index < rest.endIndex, rest[index] == " " {
                    cut = index
                    break
                }
                index = previous
            }
            if cut == nil, let space = window.lastIndex(of: " "), space > window.startIndex { cut = space }
            let end = cut ?? window.endIndex
            let head = rest[..<end].trimmingCharacters(in: .whitespaces)
            if !head.isEmpty { parts.append(head) }
            rest = rest[end...].drop(while: { $0 == " " })
        }
        let tail = rest.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { parts.append(tail) }
        return parts
    }

    /// Prose split into sentences: after . ! ? … followed by a space, and at line breaks.
    static func sentences(_ text: String) -> [String] {
        let chars = Array(text)
        var result: [String] = []
        var current: [Character] = []
        func flush() {
            let sentence = String(current).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(sentence) }
            current.removeAll()
        }
        for (i, c) in chars.enumerated() {
            if c == "\n" || c == "\r" {
                flush()
                continue
            }
            current.append(c)
            if [".", "!", "?", "…"].contains(c), i + 1 < chars.count, chars[i + 1].isWhitespace {
                flush()
            }
        }
        flush()
        return result
    }
}
