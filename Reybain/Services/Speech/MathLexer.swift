// Reybain - MathLexer.swift
// Turns a formula (LaTeX subset, Unicode math, plain ASCII) into tokens for MathParser. Pure Swift.

import Foundation

struct MathToken: Equatable {
    enum TextStyle: Equatable {
        /// `\text{…}`, `\mbox{…}`: words.
        case words
        /// `\mathrm{…}`: upright letters (a unit, the "d" of dx).
        case roman
        /// `\operatorname{…}`: a function name.
        case operatorName
    }

    enum Kind: Equatable {
        /// Digits with "." as the decimal separator ("2,5" and "2{,}5" become "2.5").
        case number(String)
        /// One ASCII letter.
        case letter(Character)
        /// A Greek letter, by name: "alpha", "Delta".
        case greek(String)
        /// A run of letters that contains a non-ASCII letter: a Vietnamese word inside a formula.
        case word(String)
        /// A LaTeX command without the backslash, aliases resolved ("leq" → "le", "dfrac" → "frac").
        /// Environments come as "begin:cases" / "end:cases"; `\left.` / `\right.` as "leftdot" / "rightdot".
        case command(String)
        /// Raw content of `\text{…}`, `\mathrm{…}`, `\operatorname{…}`.
        case text(String, TextStyle)
        /// One of + - * / = < > ( ) [ ] { } | ! ' , ; : . ^ _ & %
        case symbol(Character)
        /// `\\` (row break in environments).
        case rowBreak
    }

    var kind: Kind
    /// Whitespace (or explicit spacing) right before this token in the source.
    var spaceBefore: Bool
}

enum MathLexer {
    /// - Parameter decimalComma: true for Vietnamese answers, where "2,5" is two and a half.
    ///   `{,}` is a decimal comma in both languages.
    static func tokenize(_ source: String, decimalComma: Bool = true) -> [MathToken] {
        var lexer = Scanner(chars: Array(source), decimalComma: decimalComma)
        lexer.run()
        return lexer.tokens
    }

    // MARK: - Tables

    static let greekNames: [String: String] = {
        var names: [String: String] = [:]
        for name in ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa",
                     "lambda", "mu", "nu", "xi", "omicron", "pi", "rho", "sigma", "tau", "upsilon", "phi",
                     "chi", "psi", "omega", "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma",
                     "Upsilon", "Phi", "Psi", "Omega"] {
            names[name] = name
        }
        for (variant, name) in ["varepsilon": "epsilon", "varphi": "phi", "vartheta": "theta", "varrho": "rho",
                                "varsigma": "sigma", "varpi": "pi", "varkappa": "kappa"] {
            names[variant] = name
        }
        return names
    }()

    static let greekCharacters: [Character: String] = [
        "α": "alpha", "β": "beta", "γ": "gamma", "δ": "delta", "ε": "epsilon", "ϵ": "epsilon", "ζ": "zeta",
        "η": "eta", "θ": "theta", "ϑ": "theta", "ι": "iota", "κ": "kappa", "λ": "lambda", "μ": "mu", "µ": "mu",
        "ν": "nu", "ξ": "xi", "ο": "omicron", "π": "pi", "ϖ": "pi", "ρ": "rho", "ϱ": "rho", "σ": "sigma",
        "ς": "sigma", "τ": "tau", "υ": "upsilon", "φ": "phi", "ϕ": "phi", "χ": "chi", "ψ": "psi", "ω": "omega",
        "Γ": "Gamma", "Δ": "Delta", "∆": "Delta", "Θ": "Theta", "Λ": "Lambda", "Ξ": "Xi", "Υ": "Upsilon",
        "Φ": "Phi", "Ψ": "Psi", "Ω": "Omega", "Α": "Alpha", "Β": "Beta", "Ε": "Epsilon", "Ζ": "Zeta",
        "Η": "Eta", "Ι": "Iota", "Κ": "Kappa", "Μ": "Mu", "Ν": "Nu", "Ο": "Omicron", "Ρ": "Rho", "Τ": "Tau",
        "Χ": "Chi",
    ]

    /// Every Greek letter name an identifier can hold ("alpha", "Delta", "Alpha").
    static let greekLetterNames: Set<String> = Set(greekNames.values).union(greekCharacters.values)

    /// Command aliases → canonical name.
    static let aliases: [String: String] = [
        "leq": "le", "leqslant": "le", "leqq": "le", "geq": "ge", "geqslant": "ge", "geqq": "ge",
        "ne": "neq", "rightarrow": "to", "longrightarrow": "to", "Longrightarrow": "Rightarrow",
        "implies": "Rightarrow", "iff": "Leftrightarrow", "Longleftrightarrow": "Leftrightarrow",
        "leftrightarrow": "Leftrightarrow", "cdot": "times", "ast": "times", "bullet": "times",
        "dfrac": "frac", "tfrac": "frac", "cfrac": "frac", "varnothing": "emptyset", "wedge": "land",
        "vee": "lor", "lnot": "neg", "ldots": "dots", "cdots": "dots", "dotsc": "dots", "dotsb": "dots",
        "vdots": "dots", "subseteq": "subset", "subseteqq": "subset", "subsetneq": "subset",
        "supseteq": "supset", "hat": "widehat", "overrightarrow": "vec", "overleftrightarrow": "vec",
        "bar": "overline", "bigtriangleup": "triangle", "vartriangle": "triangle", "measuredangle": "angle",
        "bot": "perp", "simeq": "cong", "backsim": "sim", "thickapprox": "approx", "backslash": "setminus",
        "degree": "circ",
        "dbinom": "binom", "tbinom": "binom", "Bbb": "mathbb", "bm": "mathbf", "boldsymbol": "mathbf",
        "mathit": "mathbf", "mathcal": "mathbf", "mathscr": "mathbf", "mathsf": "mathbf", "mathtt": "mathbf",
    ]

    /// Commands that only change spacing or size: skipped.
    static let ignoredCommands: Set<String> = [
        "displaystyle", "textstyle", "scriptstyle", "scriptscriptstyle", "limits", "nolimits", "nonumber",
        "notag", "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr", "biggl", "biggr", "Biggl",
        "Biggr", "middle", "hfill", "centering", "phantom", "boxed", "color", "mathstrut", "strut",
        "cancel", "underline", "underbrace", "overbrace",
    ]

    static let spacingCommands: Set<String> = ["quad", "qquad", "enspace", "thinspace", "medspace", "thickspace", "space"]

    static let textCommands: [String: MathToken.TextStyle] = [
        "text": .words, "textrm": .words, "textit": .words, "textbf": .words, "mbox": .words,
        "textnormal": .words, "textsf": .words, "texttt": .words, "hbox": .words, "textup": .words,
        "mathrm": .roman, "rm": .roman, "operatorname": .operatorName,
    ]

    /// Commands whose single braced argument is dropped with them (they only style the output).
    static let commandsWithIgnoredArgument: Set<String> = ["color", "label", "tag", "phantom", "hspace", "vspace"]

    /// Unicode math characters → the equivalent LaTeX source (lexed again).
    static let unicodeReplacements: [Character: String] = [
        "≤": "\\le ", "⩽": "\\le ", "≥": "\\ge ", "⩾": "\\ge ", "≠": "\\neq ", "≈": "\\approx ",
        "×": "\\times ", "÷": "\\div ", "±": "\\pm ", "∓": "\\mp ", "∞": "\\infty ", "∫": "\\int ",
        "∬": "\\iint ", "∭": "\\iiint ", "∮": "\\oint ", "∑": "\\sum ", "Σ": "\\sum ", "∏": "\\prod ",
        "Π": "\\prod ", "→": "\\to ", "⟶": "\\to ", "⇒": "\\Rightarrow ", "⟹": "\\Rightarrow ",
        "⇔": "\\Leftrightarrow ", "⟺": "\\Leftrightarrow ", "↔": "\\Leftrightarrow ", "∈": "\\in ",
        "∉": "\\notin ", "⊂": "\\subset ", "⊆": "\\subset ", "⊃": "\\supset ", "⊇": "\\supset ",
        "∪": "\\cup ", "∩": "\\cap ", "∅": "\\emptyset ", "∖": "\\setminus ", "°": "^\\circ ",
        "º": "^\\circ ", "·": "\\times ", "⋅": "\\times ", "∙": "\\times ", "∗": "*", "−": "-", "–": "-",
        "′": "'", "″": "''", "‴": "'''", "∠": "\\angle ", "△": "\\triangle ", "⊥": "\\perp ",
        "∥": "\\parallel ", "∦": "\\nparallel ", "∼": "\\sim ", "∽": "\\sim ", "≅": "\\cong ", "≡": "\\equiv ", "∀": "\\forall ",
        "∃": "\\exists ", "∄": "\\nexists ", "¬": "\\neg ", "∧": "\\land ", "∨": "\\lor ", "∘": "\\circ ",
        "…": "\\dots ", "⋯": "\\dots ", "∂": "\\partial ", "ℝ": "\\mathbb{R}", "ℕ": "\\mathbb{N}",
        "ℤ": "\\mathbb{Z}", "ℚ": "\\mathbb{Q}", "ℂ": "\\mathbb{C}", "∣": "\\mid ", "√": "\\sqrt ",
        "∛": "\\sqrt[3]", "∜": "\\sqrt[4]", "½": "\\frac{1}{2}", "⅓": "\\frac{1}{3}", "⅔": "\\frac{2}{3}",
        "¼": "\\frac{1}{4}", "¾": "\\frac{3}{4}", "⅕": "\\frac{1}{5}", "⅙": "\\frac{1}{6}",
        "⅛": "\\frac{1}{8}", "⟨": "(", "⟩": ")", "：": ":", "；": ";", "，": ",",
    ]

    static let superscripts: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
        "⁺": "+", "⁻": "-", "⁼": "=", "⁽": "(", "⁾": ")", "ⁿ": "n", "ⁱ": "i", "ˣ": "x", "ᵏ": "k",
    ]

    static let subscripts: [Character: Character] = [
        "₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4", "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9",
        "₊": "+", "₋": "-", "₌": "=", "₍": "(", "₎": ")", "ₙ": "n", "ᵢ": "i", "ₓ": "x", "ₖ": "k", "ₘ": "m",
    ]

    static let symbolCharacters: Set<Character> = [
        "+", "-", "*", "/", "=", "<", ">", "(", ")", "[", "]", "{", "}", "|", "!", "'", ",", ";", ":", ".",
        "^", "_", "&", "%",
    ]

    static func isASCIILetter(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return (a >= 65 && a <= 90) || (a >= 97 && a <= 122)
    }

    static func isDigit(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return a >= 48 && a <= 57
    }

    // MARK: - Scanner

    private struct Scanner {
        let chars: [Character]
        let decimalComma: Bool
        var i = 0
        var tokens: [MathToken] = []
        var spacePending = false
        /// Guards the re-lexing of Unicode replacements (they never contain themselves, but be safe).
        var replacementDepth = 0

        init(chars: [Character], decimalComma: Bool) {
            self.chars = chars
            self.decimalComma = decimalComma
        }

        mutating func emit(_ kind: MathToken.Kind) {
            tokens.append(MathToken(kind: kind, spaceBefore: spacePending))
            spacePending = false
        }

        func peek(_ offset: Int = 0) -> Character? {
            let j = i + offset
            return j < chars.count ? chars[j] : nil
        }

        mutating func run() {
            while i < chars.count {
                let c = chars[i]
                if c.isWhitespace || c == "~" {
                    spacePending = true
                    i += 1
                } else if c == "\\" {
                    lexBackslash()
                } else if MathLexer.isDigit(c) {
                    lexNumber()
                } else if MathLexer.superscripts[c] != nil {
                    // Checked before letters: "ⁿ" and "ₙ" are letters to Unicode.
                    lexScript(table: MathLexer.superscripts, marker: "^")
                } else if MathLexer.subscripts[c] != nil {
                    lexScript(table: MathLexer.subscripts, marker: "_")
                } else if let replacement = MathLexer.unicodeReplacements[c] {
                    // Also before letters: "ℝ", "º", "Σ" are letters to Unicode.
                    i += 1
                    relex(replacement)
                } else if let greek = MathLexer.greekCharacters[c] {
                    emit(.greek(greek))
                    i += 1
                } else if c.isLetter {
                    lexLetters()
                } else if MathLexer.symbolCharacters.contains(c) {
                    lexSymbol(c)
                } else {
                    // Quotes, "?", "#", emoji…: not math. Keep a word boundary.
                    spacePending = true
                    i += 1
                }
            }
        }

        /// Lex a replacement string in place, keeping the pending space for its first token.
        mutating func relex(_ source: String) {
            guard replacementDepth < 4 else { return }
            var inner = Scanner(chars: Array(source), decimalComma: decimalComma)
            inner.replacementDepth = replacementDepth + 1
            inner.run()
            for (n, token) in inner.tokens.enumerated() {
                var t = token
                if n == 0 { t.spaceBefore = t.spaceBefore || spacePending }
                tokens.append(t)
            }
            if !inner.tokens.isEmpty { spacePending = false }
            if inner.spacePending { spacePending = true }
        }

        mutating func lexSymbol(_ c: Character) {
            let next = peek(1)
            let next2 = peek(2)
            switch (c, next) {
            case ("!", "="), ("<", ">"):
                emit(.command("neq")); i += 2
            case ("<", "="):
                if next2 == ">" { emit(.command("Leftrightarrow")); i += 3 } else { emit(.command("le")); i += 2 }
            case (">", "="):
                emit(.command("ge")); i += 2
            case ("=", ">"):
                emit(.command("Rightarrow")); i += 2
            case ("-", ">"):
                emit(.command("to")); i += 2
            case ("+", "-"):
                emit(.command("pm")); i += 2
            case ("/", "/"):
                emit(.command("parallel")); i += 2
            case ("=", "="):
                emit(.symbol("=")); i += 2
            default:
                emit(.symbol(c)); i += 1
            }
        }

        mutating func lexScript(table: [Character: Character], marker: Character) {
            emit(.symbol(marker))
            emit(.symbol("{"))
            var inner = ""
            while i < chars.count, let mapped = table[chars[i]] {
                inner.append(mapped)
                i += 1
            }
            relex(inner)
            emit(.symbol("}"))
        }

        mutating func lexLetters() {
            // A run of letters (Greek excluded). ASCII-only runs become single letters; a run with
            // a Vietnamese letter is one word ("nếu", "hoặc").
            var j = i
            var hasNonASCII = false
            while j < chars.count, chars[j].isLetter, MathLexer.greekCharacters[chars[j]] == nil {
                if !MathLexer.isASCIILetter(chars[j]) { hasNonASCII = true }
                j += 1
            }
            if hasNonASCII {
                emit(.word(String(chars[i..<j])))
            } else {
                for k in i..<j { emit(.letter(chars[k])) }
            }
            i = j
        }

        mutating func lexNumber() {
            var groups: [String] = []
            var separators: [String] = []
            var j = i
            func digits(from start: Int) -> (String, Int) {
                var k = start
                while k < chars.count, MathLexer.isDigit(chars[k]) { k += 1 }
                return (String(chars[start..<k]), k)
            }
            let (first, afterFirst) = digits(from: j)
            groups.append(first)
            j = afterFirst
            while j < chars.count {
                if (chars[j] == "." || chars[j] == ","), j + 1 < chars.count, MathLexer.isDigit(chars[j + 1]) {
                    let (group, end) = digits(from: j + 1)
                    separators.append(String(chars[j]))
                    groups.append(group)
                    j = end
                } else if chars[j] == "{", j + 3 < chars.count, chars[j + 1] == ",", chars[j + 2] == "}",
                          MathLexer.isDigit(chars[j + 3]) {
                    let (group, end) = digits(from: j + 3)
                    separators.append("{,}")
                    groups.append(group)
                    j = end
                } else {
                    break
                }
            }
            let (canonical, used) = MathLexer.canonicalNumber(groups: groups, separators: separators,
                                                              decimalComma: decimalComma)
            emit(.number(canonical))
            // Re-scan whatever the canonical form did not use (e.g. "1,2,3" → "1" then ", 2, 3").
            if used < groups.count {
                var k = i + groups[0].count
                for n in 1..<used { k += separators[n - 1].count + groups[n].count }
                i = k
            } else {
                i = j
            }
        }

        mutating func lexBackslash() {
            guard let d = peek(1) else { i += 1; return }
            if MathLexer.isASCIILetter(d) {
                var j = i + 1
                while j < chars.count, MathLexer.isASCIILetter(chars[j]) { j += 1 }
                let name = String(chars[(i + 1)..<j])
                i = j
                handleCommand(name)
                return
            }
            i += 2
            switch d {
            case "\\": emit(.rowBreak)
            case ",", ";", ":", "!", " ", ">": spacePending = true
            case "{": emit(.command("lbrace"))
            case "}": emit(.command("rbrace"))
            case "|": emit(.command("parallel"))
            case "%": emit(.symbol("%"))
            default: spacePending = true  // \$ \# \& \_ \( \) \[ \] and anything else
            }
        }

        mutating func skipSpaces() {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
        }

        /// Raw content of a balanced {…} group starting at `i` (nil when there is none).
        mutating func readRawGroup() -> String? {
            skipSpaces()
            guard i < chars.count, chars[i] == "{" else { return nil }
            var depth = 0
            var j = i
            var content: [Character] = []
            while j < chars.count {
                let c = chars[j]
                if c == "\\", j + 1 < chars.count { // keep escaped braces as text
                    if depth >= 1 { content.append(chars[j + 1]) }
                    j += 2
                    continue
                }
                if c == "{" {
                    depth += 1
                    if depth > 1 { content.append(c) }
                } else if c == "}" {
                    depth -= 1
                    if depth == 0 { j += 1; break }
                    content.append(c)
                } else {
                    content.append(c)
                }
                j += 1
            }
            i = j
            return String(content)
        }

        mutating func handleCommand(_ rawName: String) {
            let name = MathLexer.aliases[rawName] ?? rawName
            if name == "left" || name == "right" {
                skipSpaces()
                if i < chars.count, chars[i] == "." {
                    i += 1
                    emit(.command(name == "left" ? "leftdot" : "rightdot"))
                }
                return  // the delimiter itself is lexed next
            }
            if MathLexer.commandsWithIgnoredArgument.contains(name) {
                _ = readRawGroup()
                return
            }
            if MathLexer.ignoredCommands.contains(name) { return }
            if MathLexer.spacingCommands.contains(name) {
                spacePending = true
                return
            }
            if let style = MathLexer.textCommands[name] {
                let content = readRawGroup() ?? ""
                emit(.text(content, style))
                return
            }
            if let greek = MathLexer.greekNames[name] {
                emit(.greek(greek))
                return
            }
            if name == "begin" || name == "end" {
                let env = (readRawGroup() ?? "").trimmingCharacters(in: .whitespaces)
                let base = env.hasSuffix("*") ? String(env.dropLast()) : env
                emit(.command("\(name):\(base)"))
                if name == "begin", base == "array" || base == "tabular" {
                    _ = readRawGroup()  // column spec {l}, {cc}, {c|c}
                }
                return
            }
            switch name {
            case "lvert", "rvert", "vert", "lVert", "rVert", "Vert":
                emit(.symbol("|"))
            case "lbrack":
                emit(.symbol("["))
            case "rbrack":
                emit(.symbol("]"))
            case "percent":
                emit(.symbol("%"))
            default:
                emit(.command(name))
                if name == "frac" || name == "binom" { lexShorthandDigits() }
            }
        }

        /// `\frac12` is \frac{1}{2} in LaTeX: up to two single-digit arguments.
        mutating func lexShorthandDigits() {
            var j = i
            while j < chars.count, chars[j].isWhitespace { j += 1 }
            var count = 0
            while count < 2, j < chars.count, MathLexer.isDigit(chars[j]) {
                i = j + 1
                emit(.number(String(chars[j])))
                j += 1
                count += 1
            }
        }
    }

    /// Canonical number text and how many digit groups it used.
    static func canonicalNumber(groups: [String], separators: [String], decimalComma: Bool) -> (String, Int) {
        guard !separators.isEmpty else { return (groups[0], 1) }
        let isThousands = { (index: Int) -> Bool in groups[index].count == 3 }
        let leadOK = groups[0].count <= 3 && !(groups[0].count > 1 && groups[0].hasPrefix("0"))

        if separators.count == 1 {
            switch separators[0] {
            case "{,}", ".":
                return (groups[0] + "." + groups[1], 2)
            default: // ","
                if decimalComma { return (groups[0] + "." + groups[1], 2) }
                if leadOK && isThousands(1) { return (groups[0] + groups[1], 2) }
                return (groups[0], 1)
            }
        }
        // Several separators: thousands groups, optionally ending with a decimal part
        // ("1.000.000", "1,000,000", "1.000,5", "1,000.5").
        let thousandsSeparator = separators[0]
        guard thousandsSeparator != "{,}", leadOK else { return (groups[0], 1) }
        var integer = groups[0]
        var used = 1
        for n in 0..<separators.count {
            let sep = separators[n]
            if sep == thousandsSeparator, isThousands(n + 1) {
                integer += groups[n + 1]
                used = n + 2
            } else if sep != thousandsSeparator, n == separators.count - 1 {
                return (integer + "." + groups[n + 1], n + 2)
            } else {
                break
            }
        }
        if used == 1 { return (groups[0], 1) }
        return (integer, used)
    }
}
