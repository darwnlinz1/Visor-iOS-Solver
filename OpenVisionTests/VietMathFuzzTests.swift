// OpenVision - VietMathFuzzTests.swift
// Robustness of VietMathSpeech (PLAN.md §5, task T3.4): 1000 random strings built from LaTeX,
// Unicode math and Vietnamese fragments, with a fixed seed. No crash, no LaTeX characters in the
// output, no piece over 200 characters, under 2 seconds in total.

import XCTest
@testable import OpenVision

final class VietMathFuzzTests: XCTestCase {

    /// SplitMix64: small, deterministic on every platform (no SystemRandomNumberGenerator).
    private struct SplitMix64 {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }

        mutating func pick<T>(_ items: [T]) -> T { items[below(items.count)] }
    }

    private static let latex = [
        "\\frac", "\\frac{1}{2}", "\\dfrac", "\\sqrt", "\\sqrt[3]", "\\int", "\\int_0^1", "\\iint", "\\sum",
        "\\sum_{i=1}^{n}", "\\prod", "\\lim", "\\lim_{x \\to 0}", "\\sin", "\\cos", "\\tan", "\\cot", "\\log",
        "\\log_2", "\\ln", "\\left(", "\\right)", "\\left.", "\\right.", "\\left\\{", "\\right|", "\\begin{cases}",
        "\\end{cases}", "\\begin{pmatrix}", "\\end{pmatrix}", "\\begin{array}{l}", "\\end{array}", "\\\\", "&",
        "\\text{", "\\text{nếu }", "\\mathrm{d}", "\\operatorname{sgn}", "\\mathbb{R}", "\\mathbb", "\\overrightarrow",
        "\\vec", "\\widehat", "\\angle", "\\triangle", "\\le", "\\ge", "\\neq", "\\approx", "\\pm", "\\in", "\\notin",
        "\\subset", "\\cup", "\\cap", "\\emptyset", "\\infty", "\\Delta", "\\alpha", "\\pi", "\\circ", "\\%",
        "\\{", "\\}", "\\lvert", "\\rvert", "\\cdot", "\\times", "\\div", "\\to", "\\Rightarrow", "\\Leftrightarrow",
        "\\forall", "\\exists", "\\binom", "\\choose", "\\foo", "\\partial", "\\,", "\\;", "\\!", "\\quad", "\\",
        "\\(", "\\)", "\\[", "\\]", "\\$", "\\displaystyle", "\\boxed", "^{", "_{", "^\\circ", "{,}",
    ]

    private static let symbols = [
        "{", "}", "(", ")", "[", "]", "^", "_", "$", "$$", "|", "+", "-", "*", "**", "/", "=", "<", ">", "!", "'",
        ",", ";", ":", ".", "%", "&", "~", "#", "`", "\"", "->", "<=", "!=", "//",
    ]

    private static let unicode = [
        "²", "³", "√", "≤", "≥", "≠", "≈", "×", "÷", "±", "∞", "∫", "∑", "Σ", "π", "Δ", "∆", "→", "⇒", "⇔", "∈", "∉",
        "⊂", "∪", "∩", "∅", "°", "ⁿ", "⁻¹", "₁", "₂", "½", "ℝ", "ℕ", "α", "β", "θ", "∛", "−", "–", "·", "…", "′", "∠",
        "△", "⊥", "∥", "µ", "Ω",
    ]

    private static let vietnamese = [
        "Ta có", "nghiệm", "phương trình", "bằng", "đ", "ữ", "Câu 1:", "Dòng 2.", "và", "nếu", "hoặc", "Đáp số",
        "tập nghiệm", "Vậy", "nên", "a\u{0301}", "ươ", "Ray-Ban", "12/5/2026", "1-5", "10:30", "2,5 cm", "3.14",
        "1.000.000", "60 km/h", "-3", "50%", "30°C", "A.", "b)", "😀", "\u{200B}", "\t",
    ]

    private static let ascii = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map(String.init)

    private func randomText(_ rng: inout SplitMix64) -> String {
        var text = ""
        for _ in 0..<rng.below(41) {
            switch rng.below(10) {
            case 0, 1, 2: text += rng.pick(Self.latex)
            case 3, 4: text += rng.pick(Self.symbols)
            case 5: text += rng.pick(Self.unicode)
            case 6: text += rng.pick(Self.vietnamese)
            case 7, 8: text += rng.pick(Self.ascii)
            default: text += rng.pick([" ", " ", "\n", "  ", "$", "{", "}"])
            }
        }
        return text
    }

    private func style(_ rng: inout SplitMix64) -> MathReadingStyle {
        MathReadingStyle(verbosity: rng.pick(MathReadingStyle.Verbosity.allCases),
                         symbolicFraction: rng.pick(MathReadingStyle.SymbolicFraction.allCases),
                         negativeWord: rng.pick(MathReadingStyle.NegativeWord.allCases),
                         letterStyle: rng.pick(MathReadingStyle.LetterStyle.allCases),
                         pronunciationOverrides: rng.below(4) == 0 ? ["x": "ích-xì", "\\cos": "cô-sin", "{": "}"] : [:])
    }

    private func assertValid(_ pieces: [SpeechPiece], for text: String, file: StaticString = #filePath, line: UInt = #line) {
        for (n, piece) in pieces.enumerated() {
            switch piece {
            case .words(let words, _):
                XCTAssertFalse(words.isEmpty, "empty piece for \(text.debugDescription)", file: file, line: line)
                XCTAssertLessThanOrEqual(words.count, VietMathSpeech.maxPieceLength, words, file: file, line: line)
                XCTAssertFalse(words.contains { VietMathSpeech.forbiddenCharacters.contains($0) },
                               "\(text.debugDescription) → \(words.debugDescription)", file: file, line: line)
                XCTAssertTrue(words.contains { $0.isLetter || $0.isNumber }, words, file: file, line: line)
            case .pause(let ms):
                XCTAssertGreaterThan(ms, 0, file: file, line: line)
                let isEdge = n == 0 || n == pieces.count - 1
                XCTAssertFalse(isEdge, "pause at the edge for \(text.debugDescription)", file: file, line: line)
                if n > 0, case .pause = pieces[n - 1] {
                    XCTFail("two pauses in a row for \(text.debugDescription)", file: file, line: line)
                }
            }
        }
    }

    func testThousandRandomStrings() {
        var rng = SplitMix64(seed: 0x0F15_1011_2026)
        var inputs: [(String, Bool, MathReadingStyle)] = []
        for _ in 0..<1000 {
            let text = randomText(&rng)
            inputs.append((text, rng.below(4) != 0, style(&rng)))
        }
        let start = Date()
        var outputs: [[SpeechPiece]] = []
        outputs.reserveCapacity(inputs.count)
        for (text, vietnamese, style) in inputs {
            outputs.append(VietMathSpeech.render(text, vietnamese: vietnamese, style: style))
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.0, "1000 renders took \(elapsed) s")

        for ((text, _, _), pieces) in zip(inputs, outputs) {
            assertValid(pieces, for: text)
        }
        // Deterministic: the same input reads the same way twice.
        for (text, vietnamese, style) in inputs.prefix(100) {
            XCTAssertEqual(VietMathSpeech.render(text, vietnamese: vietnamese, style: style),
                           VietMathSpeech.render(text, vietnamese: vietnamese, style: style), text.debugDescription)
        }
    }

    func testParserAndSplitterSurviveRawFragments() {
        var rng = SplitMix64(seed: 42)
        for _ in 0..<1000 {
            let text = randomText(&rng)
            _ = MathParser.parseWithDiagnostics(text, decimalComma: rng.below(2) == 0)
            for span in MathSpanSplitter.split(text) {
                if case .math(let source) = span { _ = MathParser.parse(source) }
            }
        }
    }

    func testPathologicalNesting() {
        let style = MathReadingStyle.default
        for text in [
            String(repeating: "\\frac{", count: 300), String(repeating: "(", count: 2000),
            String(repeating: "|", count: 1000), String(repeating: "-", count: 2000) + "x",
            "$" + String(repeating: "\\sqrt{", count: 400) + "x" + String(repeating: "}", count: 400) + "$",
            "$" + String(repeating: "x^{", count: 300) + "2" + String(repeating: "}", count: 300) + "$",
            String(repeating: "\\left( ", count: 500), String(repeating: "\\begin{cases} ", count: 200),
            String(repeating: "$x$ ", count: 300), String(repeating: "Δ", count: 3000),
            "$" + String(repeating: "a", count: 5000) + "$", String(repeating: "$$ ", count: 1000),
        ] {
            assertValid(VietMathSpeech.render(text, vietnamese: true, style: style), for: String(text.prefix(40)))
        }
    }
}
