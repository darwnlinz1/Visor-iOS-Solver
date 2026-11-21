// OpenVision - VietMathSpeech.swift
// Entry point of the spoken-math module (PLAN.md §4.3): answer text → pieces to speak, one sentence
// or one formula per piece. Pure Swift, Foundation only.

import Foundation

/// What the reading engine speaks: words (one utterance each; `isMath` marks a formula, read at
/// `mathRateFactor` and followed by `pauseAfterFormula`) or a pause inside a formula.
enum SpeechPiece: Equatable, Codable {
    case words(String, isMath: Bool)
    case pause(milliseconds: Int)
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

    /// The only entry point. Prose keeps its words (numbers, units and symbols are normalised);
    /// formulas are read in Vietnamese, or in English when `vietnamese` is false.
    static func render(_ text: String, vietnamese: Bool, style: MathReadingStyle) -> [SpeechPiece] {
        renderWithDiagnostics(text, vietnamese: vietnamese, style: style).pieces
    }

    static func renderWithDiagnostics(_ text: String, vietnamese: Bool, style: MathReadingStyle) -> Rendering {
        let reader = VietnameseMathReader(style: style)
        var pieces: [SpeechPiece] = []
        var warnings: [String] = []
        for span in MathSpanSplitter.split(text) {
            switch span {
            case .prose(let prose):
                let normalized = vietnamese ? reader.normalizeProse(prose) : prose
                for sentence in sentences(normalized) {
                    pieces.append(.words(sentence, isMath: false))
                }
            case .math(let source):
                let result = MathParser.parseWithDiagnostics(source, decimalComma: vietnamese)
                warnings += result.warnings
                if vietnamese {
                    pieces += reader.pieces(for: result.node)
                } else {
                    pieces.append(.words(source, isMath: true))
                }
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

    /// Sanitises, drops empty or punctuation-only pieces, splits long ones and tidies pauses.
    static func finalize(_ pieces: [SpeechPiece]) -> [SpeechPiece] {
        var out: [SpeechPiece] = []
        for piece in pieces {
            switch piece {
            case .words(let raw, let isMath):
                let text = sanitized(raw)
                guard text.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
                for part in splitLong(text) { out.append(.words(part, isMath: isMath)) }
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
