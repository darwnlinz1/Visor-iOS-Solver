// OpenVision - MathParser.swift
// Recursive-descent parser: MathLexer tokens → MathNode (PLAN.md §4.3). Never throws, never traps:
// unknown commands become `.unknown`, stray tokens are skipped, nesting is capped.

import Foundation

struct MathParser {
    /// The tree and what the reader could not interpret (for the debug screen).
    struct Result: Equatable {
        var node: MathNode
        /// Unknown or unsupported command names, without the backslash ("foo", "partial").
        var warnings: [String]
    }

    static func parse(_ source: String, decimalComma: Bool = true) -> MathNode {
        parseWithDiagnostics(source, decimalComma: decimalComma).node
    }

    static func parseWithDiagnostics(_ source: String, decimalComma: Bool = true) -> Result {
        var parser = MathParser(tokens: MathLexer.tokenize(source, decimalComma: decimalComma))
        let node = parser.parseTop()
        return Result(node: node, warnings: parser.warnings)
    }

    // MARK: - Tables shared with the splitter and the readers

    /// Function names that may be written without a backslash ("sin x", "lnx"), longest first.
    static let functionNames: [String] = [
        "arccotg", "arcsin", "arccos", "arctan", "arccot", "arctg", "cotg", "sinh", "cosh", "tanh", "sin",
        "cos", "tan", "cot", "sec", "csc", "log", "exp", "max", "min", "gcd", "lcm", "det", "sgn", "lim",
        "tg", "ln", "lg",
    ]
    static let functionNameSet = Set(functionNames)

    /// Letters that name a function when "(" follows without a space: f(x), g(t), P(A).
    /// Other lowercase letters multiply: x(x+1), m(x-1). Every uppercase letter is a function or a
    /// point: F(x), A(1; 3).
    static let functionLetters: Set<Character> = ["f", "g", "h", "p", "q", "u", "v", "s", "y"]

    /// Unit symbols recognised after a number. Compounds are built from these: "km/h", "m/s^2", "cm^2".
    static let unitSymbols: Set<String> = [
        "mm", "cm", "dm", "m", "km", "mg", "g", "kg", "ml", "mL", "l", "L", "s", "ms", "min", "h", "ha",
        "N", "kN", "J", "kJ", "W", "kW", "kWh", "Wh", "V", "mV", "kV", "A", "mA", "Hz", "kHz", "Pa", "kPa",
        "atm", "mol", "K", "cal", "kcal", "rad", "Ω",
    ]
    /// Units that can be squared or cubed (area, volume).
    static let lengthUnits: Set<String> = ["mm", "cm", "dm", "m", "km"]
    /// Single-letter units need a space before them and nothing math-like after them ("5 m").
    static let singleLetterUnits: Set<String> = ["m", "g", "s", "l", "L", "h", "N", "J", "W", "V", "A", "K"]

    static let maxDepth = 40

    // MARK: - State

    private enum Closer: Equatable {
        case brace, paren, abs, setBrace, environment
    }

    private let tokens: [MathToken]
    private var pos = 0
    private var depth = 0
    private var closers: [Closer] = []
    private var stopAtDifferential = 0
    private(set) var warnings: [String] = []

    private init(tokens: [MathToken]) {
        self.tokens = tokens
    }

    // MARK: - Token helpers

    private var atEnd: Bool { pos >= tokens.count }

    private func token(_ offset: Int = 0) -> MathToken? {
        let j = pos + offset
        return j >= 0 && j < tokens.count ? tokens[j] : nil
    }

    private func kind(_ offset: Int = 0) -> MathToken.Kind? { token(offset)?.kind }

    private func isSymbol(_ c: Character, _ offset: Int = 0) -> Bool {
        if case .symbol(let s)? = kind(offset) { return s == c }
        return false
    }

    private func isCommand(_ name: String, _ offset: Int = 0) -> Bool {
        if case .command(let n)? = kind(offset) { return n == name }
        return false
    }

    private func commandName(_ offset: Int = 0) -> String? {
        if case .command(let n)? = kind(offset) { return n }
        return nil
    }

    private mutating func advance() { if pos < tokens.count { pos += 1 } }

    private func closes(_ kind: MathToken.Kind, _ closer: Closer) -> Bool {
        switch (closer, kind) {
        case (.brace, .symbol("}")): return true
        case (.paren, .symbol(")")), (.paren, .symbol("]")): return true
        case (.abs, .symbol("|")): return true
        case (.setBrace, .command("rbrace")), (.setBrace, .command("rightdot")): return true
        case (.environment, .rowBreak), (.environment, .symbol("&")): return true
        case (.environment, .command(let n)): return n.hasPrefix("end:")
        default: return false
        }
    }

    /// True when the current token ends an enclosing construct (so this level must stop).
    private func atTerminator() -> Bool {
        guard let k = kind() else { return true }
        if case .symbol("|") = k {
            // A bar closes only the innermost absolute value (or a set-builder bar).
            if let top = closers.last { return top == .abs || top == .setBrace }
            return false
        }
        if case .command("mid") = k, closers.contains(.setBrace) { return true }
        if case .symbol(":") = k, closers.last == .setBrace { return true }
        return closers.contains { closes(k, $0) }
    }

    /// Tokens that can never start an operand and only make sense after one.
    private func isStrayToken(_ k: MathToken.Kind) -> Bool {
        switch k {
        case .rowBreak: return true
        case .symbol(let c): return [")", "]", "}", "&", "!", "'", "%", ".", "|", "^", "_"].contains(c)
        case .command(let n):
            return n.hasPrefix("end:") || ["rbrace", "rightdot", "choose", "mid"].contains(n)
        default: return false
        }
    }

    // MARK: - Entry

    private mutating func parseTop() -> MathNode {
        var items: [MathNode] = []
        while !atEnd {
            let start = pos
            let node = parseList()
            if node != .empty { items.append(node) }
            if !atEnd && pos == start { advance() }  // stray token: skip it
            else if !atEnd, let k = kind(), isStrayToken(k) { advance() }
        }
        switch items.count {
        case 0: return .empty
        case 1: return items[0]
        default: return .juxtaposition(items)
        }
    }

    // MARK: - Precedence levels

    private mutating func parseList() -> MathNode {
        let first = parseLogic()
        var items = first == .empty ? [] : [first]
        var separator: Character?
        while let k = kind(), case .symbol(let c) = k, c == "," || c == ";", !atTerminator() {
            if separator == nil { separator = c }
            advance()
            let item = parseLogic()
            if item != .empty { items.append(item) }
        }
        if let separator, items.count > 1 { return .list(items, separator: separator) }
        return items.first ?? .empty
    }

    private func logicOperator() -> BinaryOperator? {
        switch commandName() {
        case "Rightarrow": return .implies
        case "Leftrightarrow": return .iff
        case "land": return .and
        case "lor": return .or
        default: return nil
        }
    }

    private mutating func parseLogic() -> MathNode {
        var left = parseRelation()
        while let op = logicOperator() {
            advance()
            let right = parseRelation()
            left = .binary(op, left, right)
        }
        return left
    }

    private func relationOperator() -> BinaryOperator? {
        guard let k = kind() else { return nil }
        switch k {
        case .symbol("="): return .equals
        case .symbol("<"): return .less
        case .symbol(">"): return .greater
        case .command(let n):
            switch n {
            case "neq": return .notEqual
            case "le": return .lessEqual
            case "ge": return .greaterEqual
            case "approx": return .approx
            case "in": return .elementOf
            case "notin": return .notElementOf
            case "subset": return .subset
            case "supset": return .superset
            case "perp": return .perpendicular
            case "parallel": return .parallel
            case "sim": return .similar
            case "cong": return .congruent
            case "equiv": return .equivalent
            case "to": return .tendsTo
            case "mid": return closers.contains(.setBrace) ? nil : .suchThat
            default: return nil
            }
        default: return nil
        }
    }

    private mutating func parseRelation() -> MathNode {
        var left = parseEvaluated()
        while let op = relationOperator() {
            advance()
            var right = parseEvaluated()
            if op == .equals, case .interval(false, let a, let b, false) = left,
               case .interval(false, let c, let d, false) = right {
                // (x; y) = (1; 2): a solution pair, not two intervals.
                left = .tuple([a, b])
                right = .tuple([c, d])
            }
            left = .binary(op, left, right)
        }
        return left
    }

    /// An additive expression, optionally followed by an evaluation bar `\Big|_a^b`.
    private mutating func parseEvaluated() -> MathNode {
        let node = parseAdditive()
        guard isSymbol("|"), closers.last != .abs, isSymbol("_", 1) || isSymbol("^", 1) else { return node }
        advance()
        let (lower, upper) = parseScripts()
        return .evaluation(node, lower: lower, upper: upper)
    }

    private func additiveOperator() -> BinaryOperator? {
        guard let k = kind() else { return nil }
        switch k {
        case .symbol("+"): return .plus
        case .symbol("-"): return .minus
        case .command("pm"): return .plusMinus
        case .command("mp"): return .minusPlus
        case .command("cup"): return .union
        case .command("cap"): return .intersection
        case .command("setminus"): return .setMinus
        default: return nil
        }
    }

    private mutating func parseAdditive() -> MathNode {
        var left = parseMultiplicative()
        while let op = additiveOperator() {
            advance()
            let right = parseMultiplicative()
            left = .binary(op, left, right)
        }
        return left
    }

    private func multiplicativeOperator() -> BinaryOperator? {
        guard let k = kind() else { return nil }
        switch k {
        case .symbol("*"): return .times
        case .symbol("/"): return .slash
        case .symbol(":"): return closers.last == .setBrace ? nil : .divide
        case .command("times"): return .times
        case .command("div"): return .divide
        case .command("circ"): return .compose
        default: return nil
        }
    }

    private mutating func parseMultiplicative() -> MathNode {
        var left = parseUnary()
        while let op = multiplicativeOperator() {
            advance()
            let right = parseUnary()
            left = .binary(op, left, right)
        }
        return left
    }

    private mutating func parseUnary() -> MathNode {
        let op: UnaryOperator?
        switch kind() {
        case .symbol("-")?: op = .minus
        case .symbol("+")?: op = .plus
        case .command("pm")?: op = .plusMinus
        case .command("mp")?: op = .minusPlus
        default: op = nil
        }
        guard let op else { return parseJuxtaposition() }
        advance()
        guard depth < Self.maxDepth else { return .unary(op, .empty) }
        depth += 1
        defer { depth -= 1 }
        return .unary(op, parseUnary())
    }

    // MARK: - Juxtaposition (implicit multiplication)

    private func isFunctionCommand(_ name: String) -> Bool {
        Self.functionNameSet.contains(name) || ["int", "iint", "iiint", "oint", "sum", "prod"].contains(name)
    }

    /// Whether the current token can begin an operand. `continuing` is true after another factor.
    private func canStartPrimary(continuing: Bool) -> Bool {
        guard let k = kind() else { return false }
        if case .symbol("|") = k {
            if isSymbol("_", 1) || isSymbol("^", 1) { return false }  // evaluation bar
            // In operand position a bar always opens |…|; after an operand it may close one.
            return continuing ? !atTerminator() : true
        }
        guard !atTerminator() else { return false }
        switch k {
        case .number, .letter, .greek, .word, .text: return true
        case .rowBreak: return false
        case .symbol(let c):
            switch c {
            case "(", "[", "{": return true
            default: return false
            }
        case .command(let n):
            if n.hasPrefix("end:") { return false }
            if ["rbrace", "rightdot", "choose", "mid", "times", "div", "circ", "pm", "mp", "cup", "cap",
                "setminus", "neq", "le", "ge", "approx", "in", "notin", "subset", "supset", "perp", "parallel",
                "sim", "cong", "equiv", "to", "Rightarrow", "Leftrightarrow", "land", "lor"].contains(n) {
                return false
            }
            return true
        }
    }

    private mutating func parseJuxtaposition(stopAtFunctions: Bool = false) -> MathNode {
        var factors: [MathNode] = []
        while canStartPrimary(continuing: !factors.isEmpty) {
            if stopAtDifferential > 0, isDifferentialAhead() { break }
            if stopAtFunctions, !factors.isEmpty, startsFunction() { break }
            let start = pos
            let factor = parsePostfix()
            if pos == start { advance(); continue }  // never loop without progress
            if factor != .empty { factors.append(factor) }
            if case .number = factor, let unit = parseUnitAfterNumber() {
                factors.append(unit)
            }
        }
        switch factors.count {
        case 0: return .empty
        case 1: return factors[0]
        default: return .juxtaposition(factors)
        }
    }

    /// True when the next operand is a named function or a big operator (\sin, \int, "cos").
    private func startsFunction() -> Bool {
        if let n = commandName() { return isFunctionCommand(n) || n == "lim" }
        if case .letter = kind() { return letterRunFunctionName() != nil }
        return false
    }

    /// The adjacent letters starting at `pos` ("sinx" → ["s","i","n","x"]), at most 8: enough for
    /// the longest function name, and linear on long runs of letters.
    private func letterRun() -> [Character] {
        var run: [Character] = []
        var j = pos
        while j < tokens.count, run.count < 8, case .letter(let c) = tokens[j].kind, j == pos || !tokens[j].spaceBefore {
            run.append(c)
            j += 1
        }
        return run
    }

    /// The longest function name at the start of the letter run, if any.
    private func letterRunFunctionName() -> String? {
        let run = String(letterRun())
        return Self.functionNames.first { run.hasPrefix($0) }
    }

    /// "dx", "\,dt", "\mathrm{d}x", "d\theta" at the end of an integral body.
    private func isDifferentialAhead() -> Bool {
        let isD: Bool
        switch kind() {
        case .letter("d")?: isD = true
        case .text(let t, _)? where t.trimmingCharacters(in: .whitespaces) == "d": isD = true
        default: isD = false
        }
        guard isD, let next = token(1) else { return false }
        switch next.kind {
        case .letter, .greek: break
        default: return false
        }
        // What follows the variable must end the body.
        guard let after = token(2) else { return true }
        switch after.kind {
        case .letter("d"): return true  // dx dy
        case .symbol(let c): return ["=", "<", ">", "+", "-", ",", ";", ")", "]", "}", "|", "&"].contains(c)
        case .rowBreak: return true
        case .command(let n):
            return n.hasPrefix("end:") || relationCommands.contains(n) || n == "rightdot" || n == "rbrace"
        case .text(let t, _): return t.trimmingCharacters(in: .whitespaces) == "d" || after.spaceBefore
        default: return after.spaceBefore && (token(0)?.spaceBefore ?? false)
        }
    }

    private let relationCommands: Set<String> = [
        "neq", "le", "ge", "approx", "in", "notin", "subset", "supset", "perp", "parallel", "sim", "cong",
        "equiv", "to", "Rightarrow", "Leftrightarrow", "pm", "mp",
    ]

    // MARK: - Postfix

    private mutating func parsePostfix() -> MathNode {
        var base = parsePrimary()
        while let k = kind() {
            if case .symbol("^") = k {
                advance()
                base = makePower(base, parseScriptArgument())
            } else if case .symbol("_") = k {
                advance()
                base = .subscript(base, parseScriptArgument())
            } else if case .symbol("!") = k {
                advance()
                base = .unary(.factorial, base)
            } else if case .symbol("%") = k {
                advance()
                base = .unary(.percent, base)
            } else if case .symbol("'") = k {
                var primes = 0
                while isSymbol("'") { primes += 1; advance() }
                base = makePrime(base, primes)
            } else if case .command("prime") = k {
                advance()
                base = makePrime(base, 1)
            } else {
                break
            }
        }
        return combinationIfAny(base)
    }

    private mutating func makePower(_ base: MathNode, _ exponent: MathNode) -> MathNode {
        switch exponent {
        case .symbol("circ"):
            return .unary(.degree, base)
        case .identifier("o") where isNumber(base):
            return .unary(.degree, base)  // "30^o", common in Vietnamese typing
        case .symbol("prime"):
            return makePrime(base, 1)
        default:
            return .power(base, exponent)
        }
    }

    private func isNumber(_ node: MathNode) -> Bool {
        if case .number = node { return true }
        return false
    }

    private mutating func makePrime(_ base: MathNode, _ primes: Int) -> MathNode {
        switch base {
        case .identifier(let name):
            let f = MathFunction(name: name, primes: primes)
            if isSymbol("("), !(token()?.spaceBefore ?? true) {
                return .function(f, parseCallArguments())
            }
            return .function(f, nil)
        case .function(var f, let arg) where f.power == nil && f.base == nil && f.name.count == 1:
            f.primes += primes
            return .function(f, arg)
        case .number:
            return base  // 30' (minutes): not read
        default:
            return .function(MathFunction(name: "", primes: primes), base)
        }
    }

    private func combinationIfAny(_ node: MathNode) -> MathNode {
        if case .power(.subscript(.identifier(let name), let n), let k) = node {
            if name == "C" { return .combination(n: n, k: k) }
            if name == "A" { return .arrangement(n: n, k: k) }
        }
        if case .subscript(.power(.identifier(let name), let k), let n) = node {
            if name == "C" { return .combination(n: n, k: k) }
            if name == "A" { return .arrangement(n: n, k: k) }
        }
        return node
    }

    /// The argument of ^ or _: a braced group, a sign and one operand, a whole number, one letter.
    private mutating func parseScriptArgument() -> MathNode {
        guard let k = kind() else { return .empty }
        switch k {
        case .symbol("{"):
            // ^{\circ}, ^{\prime}
            if isSymbol("}", 2), let name = commandName(1), name == "circ" || name == "prime" {
                pos += 3
                return .symbol(name)
            }
            return parseBraced()
        case .symbol("-"), .symbol("+"):
            let op: UnaryOperator = isSymbol("-") ? .minus : .plus
            advance()
            if canStartPrimary(continuing: false) { return .unary(op, parsePrimary()) }
            return .unary(op, .empty)
        case .command("circ"):
            advance()
            return .symbol("circ")
        case .command("prime"), .symbol("'"):
            advance()
            return .symbol("prime")
        case .symbol("*"):
            advance()
            return .symbol("*")
        case .number(let n):
            advance()
            return .number(n)
        case .letter(let c):
            advance()
            return .identifier(String(c))
        case .greek(let g):
            advance()
            return .identifier(g)
        default:
            if canStartPrimary(continuing: false) { return parsePrimary() }
            return .empty
        }
    }

    /// `_a^b` / `^b_a` in either order.
    private mutating func parseScripts() -> (MathNode?, MathNode?) {
        var lower: MathNode?
        var upper: MathNode?
        while true {
            if isSymbol("_"), lower == nil {
                advance()
                lower = parseScriptArgument()
            } else if isSymbol("^"), upper == nil {
                advance()
                upper = parseScriptArgument()
            } else {
                break
            }
        }
        return (lower, upper)
    }

    // MARK: - Primary

    private mutating func parsePrimary() -> MathNode {
        guard let k = kind() else { return .empty }
        guard depth < Self.maxDepth else {
            advance()
            return .empty
        }
        depth += 1
        defer { depth -= 1 }

        switch k {
        case .number(let n):
            advance()
            return .number(n)
        case .letter:
            return parseLetters()
        case .greek(let g):
            advance()
            return .identifier(g)
        case .word(let w):
            advance()
            return .text(w)
        case .text(let content, let style):
            advance()
            return textNode(content, style)
        case .symbol("("), .symbol("["):
            return parseParenthesized()
        case .symbol("{"):
            return parseBraced()
        case .symbol("|"):
            return parseAbs()
        case .command(let name):
            return parseCommand(name)
        default:
            advance()
            return .empty
        }
    }

    private mutating func textNode(_ content: String, _ style: MathToken.TextStyle) -> MathNode {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        switch style {
        case .words:
            return .text(content)
        case .roman:
            if trimmed.count == 1, let c = trimmed.first, MathLexer.isASCIILetter(c) { return .identifier(trimmed) }
            if Self.unitSymbols.contains(trimmed) { return .unit(trimmed) }
            return .text(trimmed)
        case .operatorName:
            return parseFunctionTail(MathFunction(name: trimmed))
        }
    }

    private mutating func parseLetters() -> MathNode {
        if let name = letterRunFunctionName() {
            for _ in 0..<name.count { advance() }
            if name == "lim" { return parseLimitTail() }
            return parseFunctionTail(MathFunction(name: name))
        }
        guard case .letter(let c)? = kind() else { advance(); return .empty }
        advance()
        let identifier = MathNode.identifier(String(c))
        // f(x), g(t), A(1; 3): a call when "(" follows without a space.
        if isSymbol("("), !(token()?.spaceBefore ?? true), Self.functionLetters.contains(c) || c.isUppercase {
            return .function(MathFunction(name: String(c)), parseCallArguments())
        }
        return identifier
    }

    /// `(x)`, `(x; y)`: a single argument, or a tuple of them.
    private mutating func parseCallArguments() -> MathNode {
        let node = parseParenthesized()
        switch node {
        case .group(let inner): return inner
        case .interval(_, let a, let b, _): return .tuple([a, b])
        default: return node
        }
    }

    private mutating func parseBraced() -> MathNode {
        // Current token is "{".
        advance()
        let savedStop = stopAtDifferential
        stopAtDifferential = 0
        closers.append(.brace)
        defer {
            closers.removeLast()
            stopAtDifferential = savedStop
        }
        var parts: [MathNode] = []
        while !atEnd {
            if isSymbol("}") { advance(); break }
            var node = parseList()
            if isCommand("choose") {
                advance()
                node = .combination(n: node, k: parseList())
            }
            if node != .empty { parts.append(node) }
            if isSymbol("}") { advance(); break }
            if atEnd || leaveOrSkipStray() { break }
        }
        switch parts.count {
        case 0: return .empty
        case 1: return parts[0]
        default: return .juxtaposition(parts)
        }
    }

    /// A sub-parse stopped on a token the current construct (top of `closers`) does not own.
    /// Returns true when an enclosing construct owns it (leave it there); otherwise skips it.
    private mutating func leaveOrSkipStray() -> Bool {
        guard let k = kind() else { return true }
        if closers.dropLast().contains(where: { closes(k, $0) }) { return true }
        advance()
        return false
    }

    private mutating func parseAbs() -> MathNode {
        advance()  // "|"
        closers.append(.abs)
        let content = parseList()
        closers.removeLast()
        if isSymbol("|") { advance() }
        return .abs(content)
    }

    /// `( … )` or `[ … ]`: a group, an interval, a tuple, a matrix or a `\left[` alternative.
    private mutating func parseParenthesized() -> MathNode {
        let opensSquare = isSymbol("[")
        advance()
        let savedStop = stopAtDifferential
        stopAtDifferential = 0
        defer { stopAtDifferential = savedStop }

        if let env = commandName(), env.hasPrefix("begin:") {
            let rows = parseEnvironmentRows()
            if isCommand("rightdot") {
                advance()
                return opensSquare ? .alternatives(rows) : .matrix(rows, style: .matrix)
            }
            if isSymbol(")") || isSymbol("]") { advance() }
            return .matrix(rows, style: .matrix)
        }

        closers.append(.paren)
        var elements: [MathNode] = []
        var separator: Character?
        while true {
            let element = parseLogic()
            elements.append(element)
            if let k = kind(), case .symbol(let c) = k, c == ";" || c == "," {
                if separator == nil { separator = c }
                advance()
                continue
            }
            if atEnd || isSymbol(")") || isSymbol("]") || leaveOrSkipStray() { break }
        }
        closers.removeLast()

        var closesSquare = false
        if isSymbol(")") { advance() } else if isSymbol("]") { closesSquare = true; advance() }
        let items = elements.filter { $0 != .empty }

        if items.count <= 1 {
            let inner = items.first ?? .empty
            if opensSquare, closesSquare, isSymbol("_") || isSymbol("^") {
                let (lower, upper) = parseScripts()
                return .evaluation(inner, lower: lower, upper: upper)
            }
            return .group(inner)
        }
        if items.count == 2, separator == ";" || opensSquare || closesSquare {
            return .interval(lowerClosed: opensSquare, items[0], items[1], upperClosed: closesSquare)
        }
        return .tuple(items)
    }

    /// `\{ … \}`: a set, a set-builder, or (with an environment and `\right.`) a system.
    private mutating func parseSetLiteral() -> MathNode {
        advance()  // \{
        let savedStop = stopAtDifferential
        stopAtDifferential = 0
        defer { stopAtDifferential = savedStop }

        if let env = commandName(), env.hasPrefix("begin:") {
            let rows = parseEnvironmentRows()
            if isCommand("rightdot") || isCommand("rbrace") { advance() }
            return .cases(rows)
        }

        closers.append(.setBrace)
        var elements: [MathNode] = []
        var builder: MathNode?
        while !atEnd {
            let element = parseLogic()
            if element != .empty { elements.append(element) }
            if isSymbol(";") || isSymbol(",") { advance(); continue }
            if isCommand("mid") || isSymbol("|") || isSymbol(":") {
                advance()
                builder = parseList()
                break
            }
            if isCommand("rbrace") || isCommand("rightdot") || atEnd || leaveOrSkipStray() { break }
        }
        closers.removeLast()
        if isCommand("rbrace") || isCommand("rightdot") { advance() }
        if let builder {
            let subject: MathNode = elements.count == 1 ? elements[0] : .juxtaposition(elements)
            return .setBuilder(subject, builder)
        }
        return .set(elements)
    }

    /// Rows and columns of `\begin{…} … \end{…}` (current token: the begin command).
    private mutating func parseEnvironmentRows() -> [[MathNode]] {
        advance()  // begin:…
        closers.append(.environment)
        defer { closers.removeLast() }
        var rows: [[MathNode]] = [[]]
        while !atEnd {
            let cell = parseList()
            rows[rows.count - 1].append(cell)
            guard let k = kind() else { break }
            if case .symbol("&") = k {
                advance()
            } else if case .rowBreak = k {
                advance()
                rows.append([])
            } else if case .command(let n) = k, n.hasPrefix("end:") {
                advance()
                break
            } else if leaveOrSkipStray() {
                break
            }
        }
        return rows
            .map { row in row.filter { $0 != .empty } }
            .filter { !$0.isEmpty }
    }

    // MARK: - Commands

    private mutating func parseArgument() -> MathNode {
        guard let k = kind(), !atTerminator() else { return .empty }
        switch k {
        case .symbol("{"):
            return parseBraced()
        case .number(let n):
            advance()
            return .number(n)
        case .letter(let c):
            advance()
            return .identifier(String(c))
        case .greek(let g):
            advance()
            return .identifier(g)
        default:
            if canStartPrimary(continuing: false) { return parsePostfix() }
            return .empty
        }
    }

    private mutating func parseCommand(_ name: String) -> MathNode {
        switch name {
        case "frac":
            advance()
            let numerator = parseArgument()
            let denominator = parseArgument()
            return .fraction(numerator, denominator)
        case "sqrt":
            advance()
            var index: MathNode?
            if isSymbol("[") {
                advance()
                closers.append(.paren)
                index = parseList()
                closers.removeLast()
                if isSymbol("]") { advance() }
            }
            return .root(index: index, parseArgument())
        case "binom":
            advance()
            let n = parseArgument()
            let k = parseArgument()
            return .combination(n: n, k: k)
        case "vec":
            advance()
            return .vector(parseArgument())
        case "widehat":
            advance()
            return .angle(parseArgument())
        case "overline", "mathbf":
            advance()
            return parseArgument()
        case "angle":
            advance()
            return .angle(parsePointNames())
        case "triangle":
            advance()
            return .triangle(parsePointNames())
        case "mathbb":
            advance()
            let arg = parseArgument()
            if case .identifier(let letter) = arg, let set = ["R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ"][letter] {
                return .symbol(set)
            }
            return arg
        case "infty", "emptyset", "forall", "exists", "nexists", "neg", "therefore", "because", "dots":
            advance()
            return .symbol(name)
        case "partial":
            advance()
            warnings.append(name)
            return .symbol(name)
        case "circ":
            advance()
            return .symbol("circ")
        case "prime":
            advance()
            return .symbol("prime")
        case "lbrace":
            return parseSetLiteral()
        case "leftdot":
            advance()
            return .empty
        case "int", "iint", "iiint", "oint":
            advance()
            return parseIntegralTail(name)
        case "sum", "prod":
            advance()
            let (from, to) = parseScripts()
            let body = parseTerm()
            return name == "sum" ? .sum(from: from, to: to, body: body) : .product(from: from, to: to, body: body)
        case "lim":
            advance()
            return parseLimitTail()
        default:
            if name.hasPrefix("begin:") {
                let env = String(name.dropFirst("begin:".count))
                let rows = parseEnvironmentRows()
                switch env {
                case "cases", "dcases", "rcases": return .cases(rows)
                case "pmatrix", "bmatrix", "Bmatrix", "matrix", "smallmatrix": return .matrix(rows, style: .matrix)
                case "vmatrix", "Vmatrix": return .matrix(rows, style: .determinant)
                default: return .matrix(rows, style: .rows)
                }
            }
            if Self.functionNameSet.contains(name) {
                advance()
                return parseFunctionTail(MathFunction(name: name))
            }
            return parseUnknownCommand(name)
        }
    }

    private mutating func parseUnknownCommand(_ name: String) -> MathNode {
        advance()
        warnings.append(name)
        var args: [MathNode] = []
        while isSymbol("{") || (isSymbol("[") && !(token()?.spaceBefore ?? true)) {
            if isSymbol("{") {
                args.append(parseBraced())
            } else {
                advance()
                closers.append(.paren)
                let optional = parseList()
                closers.removeLast()
                if isSymbol("]") { advance() }
                if optional != .empty { args.append(optional) }
            }
        }
        return .unknown(name, args.filter { $0 != .empty })
    }

    /// `\angle ABC`, `\triangle ABC`: the adjacent capital letters (or a braced group).
    private mutating func parsePointNames() -> MathNode {
        if isSymbol("{") { return parseBraced() }
        var names: [MathNode] = []
        while case .letter(let c)? = kind(), names.isEmpty || !(token()?.spaceBefore ?? true) {
            names.append(.identifier(String(c)))
            advance()
            if !c.isUppercase { break }
        }
        if names.isEmpty, case .greek(let g)? = kind() {
            advance()
            return .identifier(g)
        }
        switch names.count {
        case 0: return .empty
        case 1: return names[0]
        default: return .juxtaposition(names)
        }
    }

    /// The operand of \sum, \prod, \lim: one term (stops at + - and relations).
    private mutating func parseTerm() -> MathNode {
        guard depth < Self.maxDepth else { return .empty }
        depth += 1
        defer { depth -= 1 }
        return parseUnary()
    }

    private mutating func parseFunctionTail(_ start: MathFunction) -> MathNode {
        var f = start
        while true {
            if isSymbol("^"), f.power == nil {
                advance()
                f.power = parseScriptArgument()
            } else if isSymbol("_"), f.base == nil {
                advance()
                f.base = parseScriptArgument()
            } else {
                break
            }
        }
        if isSymbol("(") {
            return .function(f, parseCallArguments())
        }
        guard depth < Self.maxDepth else { return .function(f, nil) }
        depth += 1
        defer { depth -= 1 }
        var argument = parseJuxtaposition(stopAtFunctions: true)
        if argument == .empty, isSymbol("-") {
            argument = parseUnary()  // \sin -x
        }
        return .function(f, argument == .empty ? nil : argument)
    }

    private mutating func parseLimitTail() -> MathNode {
        var variable: MathNode?
        var target: MathNode?
        if isSymbol("_") {
            advance()
            let sub = parseScriptArgument()
            if case .binary(.tendsTo, let v, let t) = sub {
                variable = v
                target = t
            } else if sub != .empty {
                variable = sub
            }
        }
        let body = parseTerm()
        return .limit(variable: variable, target: target, body: body == .empty ? nil : body)
    }

    private mutating func parseIntegralTail(_ name: String) -> MathNode {
        let integralKind: IntegralKind
        switch name {
        case "iint": integralKind = .double
        case "iiint": integralKind = .triple
        case "oint": integralKind = .contour
        default: integralKind = .single
        }
        let (lower, upper) = parseScripts()
        stopAtDifferential += 1
        let body = depth < Self.maxDepth ? parseAdditive() : MathNode.empty
        stopAtDifferential -= 1
        var variables: [MathNode] = []
        while isDifferentialAhead() {
            advance()  // d
            switch kind() {
            case .letter(let c)?: variables.append(.identifier(String(c)))
            case .greek(let g)?: variables.append(.identifier(g))
            default: break
            }
            advance()
        }
        let variable: MathNode?
        switch variables.count {
        case 0: variable = nil
        case 1: variable = variables[0]
        default: variable = .juxtaposition(variables)
        }
        return .integral(kind: integralKind, lower: lower, upper: upper, body: body, variable: variable)
    }

    // MARK: - Units

    /// A unit right after a number: "5 cm", "3 m/s", "60 km/h", "12 cm^2", "5\,\text{cm}".
    private mutating func parseUnitAfterNumber() -> MathNode? {
        guard let first = token() else { return nil }
        switch first.kind {
        case .text(let content, _):
            let trimmed = content.trimmingCharacters(in: .whitespaces)
            if Self.unitSymbols.contains(trimmed) || compoundUnitIsValid(trimmed) {
                advance()
                return .unit(trimmed)
            }
            return nil
        case .greek("Omega") where first.spaceBefore:
            advance()
            return .unit("Ω")
        case .letter:
            break
        default:
            return nil
        }
        // Collect a candidate: letters, optionally "/" letters, optionally ^2 / ^3.
        var candidates: [(text: String, count: Int)] = []
        let (text, afterHead) = adjacentLetters(at: pos)
        let j = afterHead
        candidates.append((text, j - pos))
        if let (e, used) = unitExponent(at: j) {
            candidates.append((text + "^" + e, j + used - pos))
        }
        if j + 1 < tokens.count, case .symbol("/") = tokens[j].kind, !tokens[j].spaceBefore {
            let (tail, afterTail) = adjacentLetters(at: j + 1)
            if !tail.isEmpty {
                let compound = text + "/" + tail
                candidates.append((compound, afterTail - pos))
                if let (e, used) = unitExponent(at: afterTail) {
                    candidates.append((compound + "^" + e, afterTail + used - pos))
                }
            }
        }
        for candidate in candidates.reversed() where compoundUnitIsValid(candidate.text) {
            let after = token(candidate.count)
            if let after, after.kind.isLetterLike, !after.spaceBefore { continue }
            let isSingle = candidate.text.count == 1
            if isSingle {
                guard first.spaceBefore, Self.singleLetterUnits.contains(candidate.text) else { continue }
                if let after, !after.kind.endsQuantity { continue }
            }
            for _ in 0..<candidate.count { advance() }
            return .unit(candidate.text)
        }
        return nil
    }

    /// "^2", "^{2}" (also what "²" lexes to) right after a unit: the exponent and the tokens used.
    private func unitExponent(at j: Int) -> (String, Int)? {
        guard j < tokens.count, case .symbol("^") = tokens[j].kind else { return nil }
        if j + 1 < tokens.count, case .number(let e) = tokens[j + 1].kind, e == "2" || e == "3" { return (e, 2) }
        if j + 3 < tokens.count, case .symbol("{") = tokens[j + 1].kind, case .number(let e) = tokens[j + 2].kind,
           e == "2" || e == "3", case .symbol("}") = tokens[j + 3].kind {
            return (e, 4)
        }
        return nil
    }

    private func adjacentLetters(at start: Int) -> (String, Int) {
        var s = ""
        var k = start
        while k < tokens.count, case .letter(let c) = tokens[k].kind, k == start || !tokens[k].spaceBefore {
            s.append(c)
            k += 1
        }
        return (s, k)
    }

    /// "cm", "km/h", "m/s^2", "cm^3".
    private func compoundUnitIsValid(_ text: String) -> Bool {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(parts.count) else { return false }
        for (n, part) in parts.enumerated() {
            var base = part
            if part.hasSuffix("^2") || part.hasSuffix("^3") {
                base = String(part.dropLast(2))
                guard Self.lengthUnits.contains(base) || (n == 1 && base == "s") else { return false }
            }
            guard Self.unitSymbols.contains(base) else { return false }
        }
        return true
    }
}

private extension MathToken.Kind {
    var isLetterLike: Bool {
        switch self {
        case .letter, .greek, .number, .word: return true
        default: return false
        }
    }

    /// Tokens after which "5 m" is a quantity: end of the formula, a relation, a separator, a bracket.
    var endsQuantity: Bool {
        switch self {
        case .symbol(let c): return ["=", "<", ">", ",", ";", ")", "]", "}", "+", "-", "|", "&", "."].contains(c)
        case .command(let n):
            return n.hasPrefix("end:") || ["neq", "le", "ge", "approx", "Rightarrow", "Leftrightarrow", "rbrace",
                                          "rightdot", "times", "pm", "to"].contains(n)
        case .rowBreak, .text: return true
        default: return false
        }
    }
}
