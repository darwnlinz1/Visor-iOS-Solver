// OpenVision - EnglishMathReader.swift
// Minimal English reading of a MathNode for answers in English (PLAN.md §4.3). Takes over the
// English words of TTSService's SpokenMath. Pure Swift, Foundation only.

import Foundation

struct EnglishMathReader {
    /// A formula as speech pieces (all `isMath: true`).
    func pieces(for node: MathNode) -> [SpeechPiece] {
        VietMathSpeech.pieces(from: items(for: node), isMath: true)
    }

    func items(for node: MathNode) -> [MathReadingItem] {
        read(node)
    }

    // MARK: - Words

    private func w(_ s: String) -> MathReadingItem { .word(s) }

    static func word(for op: BinaryOperator) -> String {
        switch op {
        case .plus: return "plus"
        case .minus: return "minus"
        case .times: return "times"
        case .divide: return "divided by"
        case .slash: return "over"
        case .equals: return "equals"
        case .notEqual: return "is not equal to"
        case .less: return "is less than"
        case .greater: return "is greater than"
        case .lessEqual: return "is less than or equal to"
        case .greaterEqual: return "is greater than or equal to"
        case .approx: return "is approximately"
        case .plusMinus: return "plus or minus"
        case .minusPlus: return "minus or plus"
        case .elementOf: return "is in"
        case .notElementOf: return "is not in"
        case .subset: return "is a subset of"
        case .superset: return "is a superset of"
        case .union: return "union"
        case .intersection: return "intersect"
        case .setMinus: return "minus"
        case .perpendicular: return "is perpendicular to"
        case .parallel: return "is parallel to"
        case .notParallel: return "is not parallel to"
        case .similar: return "is similar to"
        case .congruent: return "is congruent to"
        case .equivalent: return "is equivalent to"
        case .implies: return "implies"
        case .iff: return "if and only if"
        case .tendsTo: return "approaches"
        case .and: return "and"
        case .or: return "or"
        case .compose: return "composed with"
        case .suchThat: return "such that"
        }
    }

    static let functionNames: [String: String] = [
        "sin": "sine", "cos": "cosine", "tan": "tangent", "tg": "tangent", "cot": "cotangent",
        "cotg": "cotangent", "sec": "secant", "csc": "cosecant", "arcsin": "arc sine", "arccos": "arc cosine",
        "arctan": "arc tangent", "arctg": "arc tangent", "arccot": "arc cotangent", "arccotg": "arc cotangent",
        "sinh": "hyperbolic sine", "cosh": "hyperbolic cosine", "tanh": "hyperbolic tangent", "log": "log",
        "ln": "the natural log", "lg": "log", "exp": "e to the", "max": "the maximum", "min": "the minimum",
        "gcd": "the greatest common divisor", "lcm": "the least common multiple", "det": "the determinant",
        "sgn": "the sign",
    ]

    static let symbols: [String: String] = [
        "infty": "infinity", "emptyset": "the empty set", "forall": "for all", "exists": "there exists",
        "nexists": "there is no", "neg": "not", "therefore": "therefore", "because": "because",
        "dots": "and so on", "partial": "partial", "ℝ": "the real numbers", "ℕ": "the natural numbers",
        "ℤ": "the integers", "ℚ": "the rational numbers", "ℂ": "the complex numbers", "circ": "degrees",
        "prime": "prime",
    ]

    static let units: [String: (plural: String, singular: String)] = [
        "mm": ("millimeters", "millimeter"), "cm": ("centimeters", "centimeter"), "dm": ("decimeters", "decimeter"),
        "m": ("meters", "meter"), "km": ("kilometers", "kilometer"), "mg": ("milligrams", "milligram"),
        "g": ("grams", "gram"), "kg": ("kilograms", "kilogram"), "ml": ("milliliters", "milliliter"),
        "mL": ("milliliters", "milliliter"), "l": ("liters", "liter"), "L": ("liters", "liter"),
        "s": ("seconds", "second"), "ms": ("milliseconds", "millisecond"), "min": ("minutes", "minute"),
        "h": ("hours", "hour"), "ha": ("hectares", "hectare"), "N": ("newtons", "newton"),
        "kN": ("kilonewtons", "kilonewton"), "J": ("joules", "joule"), "kJ": ("kilojoules", "kilojoule"),
        "W": ("watts", "watt"), "kW": ("kilowatts", "kilowatt"), "kWh": ("kilowatt hours", "kilowatt hour"),
        "Wh": ("watt hours", "watt hour"), "V": ("volts", "volt"), "mV": ("millivolts", "millivolt"),
        "kV": ("kilovolts", "kilovolt"), "A": ("amperes", "ampere"), "mA": ("milliamperes", "milliampere"),
        "Hz": ("hertz", "hertz"), "kHz": ("kilohertz", "kilohertz"), "Pa": ("pascals", "pascal"),
        "kPa": ("kilopascals", "kilopascal"), "atm": ("atmospheres", "atmosphere"), "mol": ("moles", "mole"),
        "K": ("kelvin", "kelvin"), "cal": ("calories", "calorie"), "kcal": ("kilocalories", "kilocalorie"),
        "rad": ("radians", "radian"), "Ω": ("ohms", "ohm"),
    ]

    /// "km/h" → "kilometers per hour", "cm^2" → "square centimeters", "m/s^2" → "meters per second squared".
    static func unit(_ symbol: String) -> String {
        let parts = symbol.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return parts.enumerated().map { index, part -> String in
            var base = part
            var power = 0
            if part.hasSuffix("^2") || part.hasSuffix("^3") {
                base = String(part.dropLast(2))
                power = part.hasSuffix("^2") ? 2 : 3
            }
            let names = units[base] ?? (base, base)
            let name = index == 0 ? names.plural : names.singular
            let isLength = MathParser.lengthUnits.contains(base)
            switch (power, isLength) {
            case (2, true): return (index == 0 ? "" : "per ") + "square " + name
            case (3, true): return (index == 0 ? "" : "per ") + "cubic " + name
            case (2, false): return (index == 0 ? "" : "per ") + name + " squared"
            case (3, false): return (index == 0 ? "" : "per ") + name + " cubed"
            default: return (index == 0 ? "" : "per ") + name
            }
        }.joined(separator: " ")
    }

    // MARK: - Reading

    private func read(_ node: MathNode) -> [MathReadingItem] {
        switch node {
        case .empty:
            return []
        case .number(let digits):
            return [w(digits)]
        case .identifier(let name):
            return [w(name.count == 1 ? name : name.lowercased())]
        case .symbol(let name):
            return Self.symbols[name].map { [w($0)] } ?? []
        case .unit(let symbol):
            return [w(Self.unit(symbol))]
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [w(trimmed)]
        case .binary(let op, let l, let r):
            if op == .slash { return readFraction(l.unwrappingGroups, r.unwrappingGroups) }
            return read(l) + [w(Self.word(for: op))] + read(r)
        case .unary(let op, let x):
            return readUnary(op, x)
        case .juxtaposition(let xs):
            var out: [MathReadingItem] = []
            for (n, x) in xs.enumerated() {
                if n > 0 {
                    let previous = xs[n - 1]
                    let bothNumbers: Bool = {
                        if case .number = previous, case .number = x { return true }
                        return false
                    }()
                    if x.isGroupedBase || previous.isGroupedBase || bothNumbers { out.append(w("times")) }
                }
                out += read(x)
            }
            return out
        case .fraction(let n, let d):
            return readFraction(n, d)
        case .power(let b, let e):
            return readPower(b, e)
        case .subscript(let b, let s):
            return read(b) + [w("sub")] + read(s) + (s.isAtomicTerm ? [] : [.pause])
        case .root(let index, let x):
            let radicand = x.unwrappingGroups
            let name: String
            switch index?.integerValue {
            case nil, 2?: name = "the square root of"
            case 3?: name = "the cube root of"
            case let n?: name = "the \(n)th root of"
            }
            if let index, index.integerValue == nil {
                return [w("the root of order")] + read(index) + [w("of")] + read(radicand) + pauseUnlessAtomic(radicand)
            }
            return [w(name)] + read(radicand) + pauseUnlessAtomic(radicand)
        case .function(let f, let arg):
            return readFunction(f, arg)
        case .group(let x):
            return read(x) + pauseUnlessAtomic(x)
        case .abs(let x):
            return [w("the absolute value of")] + read(x) + pauseUnlessAtomic(x)
        case .integral(_, let lower, let upper, let body, let variable):
            var out: [MathReadingItem] = [w("the integral")]
            if let lower { out += [w("from")] + read(lower) }
            if let upper { out += [w("to")] + read(upper) }
            out += [w("of")] + read(body)
            if let variable {
                let variables: [MathNode]
                if case .juxtaposition(let vs) = variable { variables = vs } else { variables = [variable] }
                out.append(.punct(","))
                for v in variables { out += [w("d")] + read(v) }
            }
            return out
        case .limit(let variable, let target, let body):
            var out: [MathReadingItem] = [w("the limit")]
            if let variable {
                out += [w("as")] + read(variable)
                if let target { out += [w("approaches")] + read(target) }
            }
            out.append(w("of"))
            if let body { out += read(body) }
            return out
        case .sum(let from, let to, let body), .product(let from, let to, let body):
            var out: [MathReadingItem]
            if case .sum = node { out = [w("the sum")] } else { out = [w("the product")] }
            if let from { out += [w("from")] + read(from) }
            if let to { out += [w("to")] + read(to) }
            return out + [w("of")] + read(body)
        case .combination(let n, let k):
            return read(n) + [w("choose")] + read(k)
        case .arrangement(let n, let k):
            return [w("the arrangements of")] + read(k) + [w("out of")] + read(n)
        case .vector(let x):
            return [w("vector")] + read(x)
        case .angle(let x):
            return [w("angle")] + read(x)
        case .triangle(let x):
            return [w("triangle")] + read(x)
        case .set(let elements):
            guard !elements.isEmpty else { return [w("the empty set")] }
            var out: [MathReadingItem] = [w("the set of")]
            for (n, element) in elements.enumerated() {
                if n > 0 { out += n == elements.count - 1 ? [w("and")] : [.punct(",")] }
                out += read(element)
            }
            return out
        case .setBuilder(let subject, let condition):
            return [w("the set of")] + read(subject) + [w("such that")] + read(condition)
        case .interval(let lowerClosed, let a, let b, let upperClosed):
            let kind = lowerClosed && upperClosed ? "closed" : (!lowerClosed && !upperClosed ? "open" : "half-open")
            return [w("the \(kind) interval from")] + read(a) + [w("to")] + read(b)
        case .tuple(let xs):
            return joined(xs.map { read($0) }, by: .punct(","))
        case .list(let xs, let separator):
            return joined(xs.map { read($0) }, by: .punct(String(separator)))
        case .cases(let rows):
            // A piecewise row reads "value if condition", unless the condition has its own words.
            let conditional = rows.allSatisfy { $0.count >= 2 && $0[0].topRelation == nil }
            let readings = rows.map { row -> [MathReadingItem] in
                guard conditional, !row[1].startsWithWordsOrNothing else { return row.flatMap { read($0) } }
                return read(row[0]) + [w("if")] + row.dropFirst().flatMap { read($0) }
            }
            let piecewise = rows.allSatisfy { $0.count >= 2 }
            return (piecewise ? [] : [w("the system"), .punct(":")]) + joined(readings, by: .punct(";"))
        case .alternatives(let rows):
            return joined(rows.map { $0.flatMap { read($0) } }, by: w("or"))
        case .matrix(let rows, let style):
            if style == .rows { return joined(rows.map { $0.flatMap { read($0) } }, by: .punct(";")) }
            let columns = rows.map(\.count).max() ?? 0
            var out: [MathReadingItem] = [w(style == .determinant ? "the determinant of the" : "the"),
                                          w("\(rows.count) by \(columns) matrix"), .punct(":")]
            for (n, row) in rows.enumerated() {
                if n > 0 { out.append(.punct(";")) }
                out += [w("row \(n + 1)"), .punct(":")] + joined(row.map { read($0) }, by: .punct(","))
            }
            return out
        case .evaluation(let x, let lower, let upper):
            var out = read(x) + [.punct(","), w("evaluated")]
            if let lower { out += [w("from")] + read(lower) }
            if let upper { out += [w("to")] + read(upper) }
            return out
        case .unknown(_, let args):
            return args.flatMap { read($0) }
        }
    }

    private func pauseUnlessAtomic(_ node: MathNode) -> [MathReadingItem] {
        node.isAtomicTerm ? [] : [.pause]
    }

    private func joined(_ parts: [[MathReadingItem]], by separator: MathReadingItem) -> [MathReadingItem] {
        var out: [MathReadingItem] = []
        for part in parts where !part.isEmpty {
            if !out.isEmpty { out.append(separator) }
            out += part
        }
        return out
    }

    private func readUnary(_ op: UnaryOperator, _ x: MathNode) -> [MathReadingItem] {
        switch op {
        case .minus: return x == .empty ? [w("minus")] : [w("negative")] + read(x)
        case .plus: return x == .empty ? [w("plus")] : [w("positive")] + read(x)
        case .plusMinus: return [w("plus or minus")] + read(x)
        case .minusPlus: return [w("minus or plus")] + read(x)
        case .factorial:
            if x.isCompoundGroup { return read(x.unwrappingGroups) + [.punct(","), w("all factorial")] }
            return read(x) + [w("factorial")]
        case .degree: return read(x) + [w("degrees")]
        case .percent: return read(x) + [w("percent")]
        }
    }

    private func readFraction(_ n: MathNode, _ d: MathNode) -> [MathReadingItem] {
        if n.isSimpleTerm && d.isSimpleTerm { return read(n) + [w("over")] + read(d) }
        let comma: [MathReadingItem] = n.isSimpleTerm ? [] : [.punct(",")]
        return read(n) + comma + [w("over")] + read(d) + [.pause]
    }

    private func readPower(_ base: MathNode, _ exponent: MathNode) -> [MathReadingItem] {
        if case .unary(let sign, .empty) = exponent, sign == .plus || sign == .minus {
            return read(base) + [w(sign == .plus ? "plus" : "minus")]
        }
        if case .symbol("*") = exponent { return read(base) + [w("star")] }
        let exponentWords: [MathReadingItem]
        switch exponent.integerValue {
        case 2?: exponentWords = [w("squared")]
        case 3?: exponentWords = [w("cubed")]
        default: exponentWords = [w("to the power of")] + read(exponent)
        }
        let out: [MathReadingItem]
        if base.isGroupedBase {
            out = read(base.unwrappingGroups) + [.punct(","), w("all")] + exponentWords
        } else {
            out = read(base) + exponentWords
        }
        return out + pauseUnlessAtomic(exponent)
    }

    private func readFunction(_ f: MathFunction, _ arg: MathNode?) -> [MathReadingItem] {
        if f.name.isEmpty {
            guard let arg else { return [] }
            return [w("the derivative of")] + read(arg.unwrappingGroups) + pauseUnlessAtomic(arg)
        }
        var out: [MathReadingItem]
        if f.name.count == 1 || MathLexer.greekLetterNames.contains(f.name) {
            // A variable: f'(x), y'', Δ' ("delta prime").
            out = [w(f.name.count == 1 ? f.name : f.name.lowercased())]
            switch f.primes {
            case 0: break
            case 1: out.append(w("prime"))
            case 2: out.append(w("double prime"))
            case 3: out.append(w("triple prime"))
            default: out.append(w("\(f.primes) primes"))
            }
            if let power = f.power { out += [w("to the power of")] + read(power) }
        } else if f.name == "log", let base = f.base {
            out = [w("log base")] + read(base)
            if let power = f.power { out += [w("to the power of")] + read(power) }
        } else {
            out = [w(Self.functionNames[f.name] ?? f.name)]
            switch f.power?.integerValue {
            case nil: if let power = f.power { out += [w("to the power of")] + read(power) }
            case 2?: out.append(w("squared"))
            case 3?: out.append(w("cubed"))
            default: if let power = f.power { out += [w("to the power of")] + read(power) }
            }
            if let base = f.base { out += [w("over")] + read(base) }
        }
        guard let arg else { return out }
        if case .tuple(let xs) = arg { return out + [w("of")] + joined(xs.map { read($0) }, by: .punct(",")) }
        let connector: [MathReadingItem] = f.name == "exp" ? [] : [w("of")]
        return out + connector + read(arg) + pauseUnlessAtomic(arg)
    }
}
