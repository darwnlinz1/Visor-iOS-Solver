// OpenVision - MathPrettyText.swift
// Pure Foundation lightweight LaTeX-to-Unicode prettifier for native SwiftUI Text (PLAN.md §4.5, T6.1).
// Replaces the heavy KaTeX + WKWebView bundle with crisp inline Unicode math rendering.

import Foundation

enum MathPrettyText {
    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "n": "ⁿ", "i": "ⁱ", "x": "ˣ", "y": "ʸ",
    ]

    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ",
        "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ",
        "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ",
    ]

    private static let symbolMap: [(String, String)] = [
        ("\\Leftrightarrow", "⇔"), ("\\Longleftrightarrow", "⇔"),
        ("\\Rightarrow", "⇒"), ("\\Longrightarrow", "⇒"),
        ("\\Leftarrow", "⇐"), ("\\leftrightarrow", "↔"),
        ("\\rightarrow", "→"), ("\\to", "→"), ("\\mapsto", "↦"),
        ("\\leq", "≤"), ("\\le", "≤"), ("\\geq", "≥"), ("\\ge", "≥"),
        ("\\neq", "≠"), ("\\ne", "≠"), ("\\approx", "≈"), ("\\equiv", "≡"),
        ("\\sim", "∼"), ("\\backsim", "∼"), ("\\cong", "≅"),
        ("\\pm", "±"), ("\\mp", "∓"), ("\\times", "×"), ("\\cdot", "·"), ("\\div", "÷"),
        ("\\infty", "∞"), ("\\emptyset", "∅"), ("\\varnothing", "∅"),
        ("\\notin", "∉"), ("\\in", "∈"), ("\\subseteq", "⊆"), ("\\subset", "⊂"),
        ("\\supseteq", "⊇"), ("\\supset", "⊃"), ("\\cup", "∪"), ("\\cap", "∩"),
        ("\\setminus", "∖"), ("\\forall", "∀"), ("\\exists", "∃"), ("\\nexists", "∄"),
        ("\\perp", "⊥"), ("\\parallel", "∥"), ("\\angle", "∠"), ("\\triangle", "△"),
        ("\\iint", "∬"), ("\\iiint", "∭"), ("\\oint", "∮"), ("\\int", "∫"),
        ("\\sum", "∑"), ("\\prod", "∏"), ("\\partial", "∂"), ("\\nabla", "∇"),
        ("\\therefore", "∴"), ("\\because", "∵"), ("\\ldots", "…"), ("\\cdots", "⋯"), ("\\dots", "…"),
        ("\\circ", "°"), ("\\degree", "°"), ("\\mid", "|"), ("\\lvert", "|"), ("\\rvert", "|"),
        ("\\land", "∧"), ("\\lor", "∨"), ("\\neg", "¬"),
        ("\\alpha", "α"), ("\\beta", "β"), ("\\gamma", "γ"), ("\\delta", "δ"),
        ("\\epsilon", "ε"), ("\\varepsilon", "ε"), ("\\zeta", "ζ"), ("\\eta", "η"),
        ("\\theta", "θ"), ("\\iota", "ι"), ("\\kappa", "κ"), ("\\lambda", "λ"),
        ("\\mu", "μ"), ("\\nu", "ν"), ("\\xi", "ξ"), ("\\pi", "π"),
        ("\\rho", "ρ"), ("\\sigma", "σ"), ("\\tau", "τ"), ("\\phi", "φ"),
        ("\\varphi", "φ"), ("\\chi", "χ"), ("\\psi", "ψ"), ("\\omega", "ω"),
        ("\\Gamma", "Γ"), ("\\Delta", "Δ"), ("\\Theta", "Θ"), ("\\Lambda", "Λ"),
        ("\\Xi", "Ξ"), ("\\Pi", "Π"), ("\\Sigma", "Σ"), ("\\Phi", "Φ"),
        ("\\Psi", "Ψ"), ("\\Omega", "Ω"),
        ("\\{", "{"), ("\\}", "}"), ("\\%", "%"),
        ("\\,", " "), ("\\;", " "), ("\\:", " "), ("\\!", ""), ("\\quad", " "), ("\\qquad", "  "),
    ]

    private static let blackboardMap: [String: String] = [
        "R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ",
    ]

    private static let functionCommands: [String] = [
        "sin", "cos", "tan", "cot", "sec", "csc",
        "arcsin", "arccos", "arctan", "arccot",
        "sinh", "cosh", "tanh", "log", "ln", "lg", "exp", "lim", "max", "min", "gcd", "lcm", "det",
    ]

    /// Turns raw text with inline `$...$` / `\(...\)` / `\[...\]` LaTeX into readable Unicode text.
    static func format(_ input: String) -> String {
        guard !input.isEmpty else { return "" }
        let spans = MathSpanSplitter.splitDelimited(input)
        var out = ""
        for span in spans {
            switch span {
            case .prose(let prose):
                out += prose
            case .math(let latex):
                out += formatFormula(latex)
            }
        }
        return collapseSpaces(out)
    }

    /// Formats a single LaTeX formula (without `$` delimiters) into clean Unicode.
    static func formatFormula(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }

        // Strip sizing commands (\left, \right, \big, \Big, \displaystyle, \textstyle)
        for cmd in ["\\displaystyle", "\\textstyle", "\\left", "\\right", "\\Bigg", "\\bigg", "\\Big", "\\big"] {
            s = s.replacingOccurrences(of: cmd, with: "")
        }

        // Convert cases / matrix environments to compact inline text
        s = replaceEnvironments(in: s)

        // Unwrap formatting commands: \text{...}, \mathrm{...}, \boxed{...}, \mathbf{...}
        for cmd in ["\\text", "\\mathrm", "\\mathbf", "\\mathit", "\\operatorname", "\\boxed"] {
            s = replaceUnaryCommand(cmd, in: s) { $0 }
        }

        // Blackboard sets: \mathbb{R} -> ℝ
        s = replaceUnaryCommand("\\mathbb", in: s) { inner in
            let key = inner.trimmingCharacters(in: .whitespaces)
            return blackboardMap[key] ?? key
        }

        // Vectors / angles / overlines
        s = replaceUnaryCommand("\\overrightarrow", in: s) { "→\($0)" }
        s = replaceUnaryCommand("\\vec", in: s) { "→\($0)" }
        s = replaceUnaryCommand("\\widehat", in: s) { "∠\($0)" }
        s = replaceUnaryCommand("\\overline", in: s) { $0 }

        // Fractions: \frac{a}{b}, \dfrac{a}{b}, \tfrac{a}{b}
        for cmd in ["\\dfrac", "\\tfrac", "\\frac"] {
            s = replaceBinaryCommand(cmd, in: s) { num, den in
                let n = formatFormula(num)
                let d = formatFormula(den)
                let nWrap = needsParensInFraction(n) ? "(\(n))" : n
                let dWrap = needsParensInFraction(d) ? "(\(d))" : d
                return "\(nWrap)/\(dWrap)"
            }
        }

        // Binomial: \binom{n}{k}
        s = replaceBinaryCommand("\\binom", in: s) { n, k in
            "C(\(formatFormula(n)), \(formatFormula(k)))"
        }

        // Roots: \sqrt[n]{x} and \sqrt{x}
        s = replaceSqrt(in: s)

        // Named functions (\sin -> sin)
        for fn in functionCommands {
            s = replaceWordCommand("\\\(fn)", with: fn, in: s)
        }

        // Symbols & Greek letters
        for (latex, unicode) in symbolMap {
            if latex.last?.isLetter == true {
                s = replaceWordCommand(latex, with: unicode, in: s)
            } else {
                s = s.replacingOccurrences(of: latex, with: unicode)
            }
        }

        // Superscripts & subscripts (run after symbols so ^\circ -> ^° -> °)
        s = s.replacingOccurrences(of: "^°", with: "°")
        s = replaceScripts(in: s)

        // Strip any remaining braces and unknown command backslashes cleanly
        s = s.replacingOccurrences(of: "{", with: "")
        s = s.replacingOccurrences(of: "}", with: "")
        s = s.replacingOccurrences(of: "\\", with: "")
        return collapseSpaces(s)
    }

    // MARK: - Helpers

    private static func needsParensInFraction(_ part: String) -> Bool {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        return trimmed.contains(" + ") || trimmed.contains(" - ") || trimmed.contains(" ")
    }

    private static func replaceEnvironments(in text: String) -> String {
        var s = text
        let envNames = ["cases", "pmatrix", "bmatrix", "vmatrix", "matrix", "aligned", "array"]
        for env in envNames {
            s = s.replacingOccurrences(of: "\\begin{\(env)}", with: "")
            s = s.replacingOccurrences(of: "\\end{\(env)}", with: "")
        }
        s = s.replacingOccurrences(of: "\\\\", with: "; ")
        s = s.replacingOccurrences(of: "&", with: " ")
        return s
    }

    private static func replaceWordCommand(_ command: String, with replacement: String, in text: String) -> String {
        let chars = Array(text)
        let cmd = Array(command)
        guard cmd.count <= chars.count else { return text }
        var out = ""
        out.reserveCapacity(text.count)
        var i = 0
        while i < chars.count {
            if i + cmd.count <= chars.count && Array(chars[i..<(i + cmd.count)]) == cmd {
                let after = i + cmd.count
                let followedByLetter = after < chars.count && chars[after].isLetter
                if !followedByLetter {
                    out += replacement
                    i = after
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }

    private static func replaceUnaryCommand(_ command: String, in text: String, transform: (String) -> String) -> String {
        var s = text
        while let range = s.range(of: command) {
            let afterCmd = skipSpaces(in: s, from: range.upperBound)
            guard let (arg, end) = readBraceGroup(in: s, from: afterCmd) else {
                s.replaceSubrange(range, with: "")
                continue
            }
            s.replaceSubrange(range.lowerBound..<end, with: transform(arg))
        }
        return s
    }

    private static func replaceBinaryCommand(_ command: String, in text: String, transform: (String, String) -> String) -> String {
        var s = text
        while let range = s.range(of: command) {
            let afterCmd = skipSpaces(in: s, from: range.upperBound)
            guard let (first, afterFirst) = readBraceOrAtom(in: s, from: afterCmd) else {
                s.replaceSubrange(range, with: "")
                continue
            }
            let beforeSecond = skipSpaces(in: s, from: afterFirst)
            guard let (second, afterSecond) = readBraceOrAtom(in: s, from: beforeSecond) else {
                s.replaceSubrange(range.lowerBound..<afterFirst, with: first)
                continue
            }
            s.replaceSubrange(range.lowerBound..<afterSecond, with: transform(first, second))
        }
        return s
    }

    private static func replaceSqrt(in text: String) -> String {
        var s = text
        while let range = s.range(of: "\\sqrt") {
            var cursor = skipSpaces(in: s, from: range.upperBound)
            var indexStr: String? = nil
            if cursor < s.endIndex, s[cursor] == "[" {
                if let close = s[cursor...].firstIndex(of: "]") {
                    indexStr = String(s[s.index(after: cursor)..<close]).trimmingCharacters(in: .whitespaces)
                    cursor = skipSpaces(in: s, from: s.index(after: close))
                }
            }
            guard let (radicand, end) = readBraceOrAtom(in: s, from: cursor) else {
                s.replaceSubrange(range, with: "√")
                continue
            }
            let body = formatFormula(radicand)
            let radical: String
            switch indexStr {
            case nil, "2": radical = "√"
            case "3": radical = "∛"
            case "4": radical = "∜"
            case let idx?: radical = "\(toSuperscript(idx) ?? idx)√"
            }
            let simple = body.count <= 2 && !body.contains(" ")
            let rendered = simple ? "\(radical)\(body)" : "\(radical)(\(body))"
            s.replaceSubrange(range.lowerBound..<end, with: rendered)
        }
        return s
    }

    private static func replaceScripts(in text: String) -> String {
        let chars = Array(text)
        var out = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if (c == "^" || c == "_"), i + 1 < chars.count {
                let isSuper = c == "^"
                var j = i + 1
                var content = ""
                if chars[j] == "{" {
                    var depth = 1
                    j += 1
                    while j < chars.count && depth > 0 {
                        if chars[j] == "{" { depth += 1 }
                        else if chars[j] == "}" { depth -= 1; if depth == 0 { j += 1; break } }
                        content.append(chars[j])
                        j += 1
                    }
                } else {
                    content.append(chars[j])
                    j += 1
                }
                let trimmed = content.trimmingCharacters(in: .whitespaces)
                if isSuper, let sup = toSuperscript(trimmed) {
                    out += sup
                } else if !isSuper, let sub = toSubscript(trimmed) {
                    out += sub
                } else if isSuper {
                    out += "^(\(trimmed))"
                } else {
                    out += "_\(trimmed)"
                }
                i = j
                continue
            }
            out.append(c)
            i += 1
        }
        return out
    }

    private static func toSuperscript(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        var out = ""
        for ch in text {
            guard let mapped = superscripts[ch] else { return nil }
            out.append(mapped)
        }
        return out
    }

    private static func toSubscript(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        var out = ""
        for ch in text {
            guard let mapped = subscripts[ch] else { return nil }
            out.append(mapped)
        }
        return out
    }

    private static func skipSpaces(in s: String, from index: String.Index) -> String.Index {
        var i = index
        while i < s.endIndex, s[i].isWhitespace { i = s.index(after: i) }
        return i
    }

    private static func readBraceGroup(in s: String, from start: String.Index) -> (String, String.Index)? {
        guard start < s.endIndex, s[start] == "{" else { return nil }
        var i = s.index(after: start)
        var depth = 1
        let bodyStart = i
        while i < s.endIndex && depth > 0 {
            if s[i] == "\\" {
                i = s.index(after: i)
                if i < s.endIndex { i = s.index(after: i) }
                continue
            }
            if s[i] == "{" { depth += 1 }
            else if s[i] == "}" {
                depth -= 1
                if depth == 0 {
                    return (String(s[bodyStart..<i]), s.index(after: i))
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private static func readBraceOrAtom(in s: String, from start: String.Index) -> (String, String.Index)? {
        if let group = readBraceGroup(in: s, from: start) { return group }
        guard start < s.endIndex else { return nil }
        return (String(s[start]), s.index(after: start))
    }

    private static func collapseSpaces(_ s: String) -> String {
        var out = ""
        var prevSpace = false
        for ch in s {
            if ch == " " || ch == "\t" {
                if !prevSpace { out.append(" ") }
                prevSpace = true
            } else {
                out.append(ch)
                prevSpace = false
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
