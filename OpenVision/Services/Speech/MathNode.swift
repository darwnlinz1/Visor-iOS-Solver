// OpenVision - MathNode.swift
// Syntax tree for the LaTeX subset Gemini writes in answers (PLAN.md §4.3). Pure Swift, Foundation only.

import Foundation

/// One parsed formula. Built by `MathParser` (which never fails: anything it cannot read becomes
/// `.unknown` or `.text`) and turned into words by `VietnameseMathReader` / `EnglishMathReader`.
///
/// Conventions:
/// - `.identifier` holds ONE Latin letter ("x", "A") or a Greek letter name ("alpha", "Delta", "pi").
/// - `.number` holds digits with "." as the decimal separator, whatever the source used
///   ("2,5", "2{,}5" and "2.5" all become "2.5"); thousands separators are removed.
/// - `.symbol` holds a canonical name: "infty", "emptyset", "forall", "exists", "nexists", "neg",
///   "therefore", "because", "dots", "partial", or a number set "ℝ", "ℕ", "ℤ", "ℚ", "ℂ".
indirect enum MathNode: Equatable {
    /// Nothing (empty input, a missing argument such as `\frac{1}{}`).
    case empty
    case number(String)
    case identifier(String)
    case symbol(String)
    /// A unit after a quantity: "cm", "km/h", "m/s^2" (exponent written with ^).
    case unit(String)
    /// Words that are not math: `\text{nếu }`, or a Vietnamese word that slipped into a formula.
    case text(String)
    case binary(BinaryOperator, MathNode, MathNode)
    /// Prefix (minus, plus, ±) and postfix (factorial, degree, percent) operators.
    case unary(UnaryOperator, MathNode)
    /// Implicit multiplication / juxtaposition: `2x`, `ab`, `2(x+1)`, `\sin x \cos x`.
    case juxtaposition([MathNode])
    case fraction(MathNode, MathNode)
    case power(MathNode, MathNode)
    case `subscript`(MathNode, MathNode)
    case root(index: MathNode?, MathNode)
    /// `\sin^2 x`, `\log_2 8`, `f'(x)`, `f(x; y)`. The argument is nil for a bare `y'`.
    case function(MathFunction, MathNode?)
    /// Round brackets around a single expression.
    case group(MathNode)
    case abs(MathNode)
    case integral(kind: IntegralKind, lower: MathNode?, upper: MathNode?, body: MathNode, variable: MathNode?)
    case limit(variable: MathNode?, target: MathNode?, body: MathNode?)
    case sum(from: MathNode?, to: MathNode?, body: MathNode)
    case product(from: MathNode?, to: MathNode?, body: MathNode)
    /// `C_n^k` / `\binom{n}{k}`.
    case combination(n: MathNode, k: MathNode)
    /// `A_n^k`.
    case arrangement(n: MathNode, k: MathNode)
    case vector(MathNode)
    case angle(MathNode)
    case triangle(MathNode)
    /// `\{a; b\}`.
    case set([MathNode])
    /// `\{x \in \mathbb{R} \mid x > 0\}`.
    case setBuilder(MathNode, MathNode)
    /// `[a; b]`, `(a; b)`, `[a; b)`, `(a; b]`.
    case interval(lowerClosed: Bool, MathNode, MathNode, upperClosed: Bool)
    /// Coordinates or a solution pair: `(x; y) = (1; 2)`, the arguments of `A(1; 3)`.
    case tuple([MathNode])
    /// Top-level items separated by "," or ";": `x_1 = 2, x_2 = 3`. Also a name and its equation,
    /// separated by ":" (`d: x + 2y - 3 = 0`), and a `\forall` clause and its statement, by ",".
    case list([MathNode], separator: Character)
    /// `\begin{cases}` (or `\left\{ \begin{array} … \right.`): one entry per row, one node per column.
    case cases([[MathNode]])
    /// `\left[ \begin{array} … \right.`: rows joined by "or".
    case alternatives([[MathNode]])
    case matrix([[MathNode]], style: MatrixStyle)
    /// `F(x) \Big|_0^1`: evaluate between two bounds.
    case evaluation(MathNode, lower: MathNode?, upper: MathNode?)
    /// An unknown command: its name is dropped when reading, its arguments are read.
    case unknown(String, [MathNode])
}

/// Function application details. `name` is canonical: "sin", "cos", "tan", "cot", "log", "ln",
/// "exp", "arcsin", … or a single letter for `f(x)`.
struct MathFunction: Equatable {
    var name: String
    /// Number of primes: 1 for `f'`, 2 for `f''`.
    var primes: Int = 0
    /// `\sin^2 x` → 2.
    var power: MathNode? = nil
    /// `\log_2 8` → 2.
    var base: MathNode? = nil
}

enum IntegralKind: String, Equatable {
    case single, double, triple, contour
}

enum MatrixStyle: String, Equatable {
    /// pmatrix, bmatrix, Bmatrix, matrix
    case matrix
    /// vmatrix, Vmatrix
    case determinant
    /// array, aligned, gathered and similar: rows of a layout, not a matrix
    case rows
}

/// Binary operators. The raw value is the canonical command name; `PronunciationDictionary`
/// overrides can use it as a key ("le" → "bé hơn hoặc bằng").
enum BinaryOperator: String, Equatable, CaseIterable {
    case plus = "+"
    case minus = "-"
    case times = "times"
    case divide = "div"
    /// Inline `a/b`: read like a fraction.
    case slash = "/"
    case equals = "="
    case notEqual = "neq"
    case less = "<"
    case greater = ">"
    case lessEqual = "le"
    case greaterEqual = "ge"
    case approx = "approx"
    case plusMinus = "pm"
    case minusPlus = "mp"
    case elementOf = "in"
    case notElementOf = "notin"
    case subset = "subset"
    case superset = "supset"
    case union = "cup"
    case intersection = "cap"
    case setMinus = "setminus"
    case perpendicular = "perp"
    case parallel = "parallel"
    case similar = "sim"
    case congruent = "cong"
    case equivalent = "equiv"
    case implies = "Rightarrow"
    case iff = "Leftrightarrow"
    case tendsTo = "to"
    case and = "land"
    case or = "lor"
    case compose = "circ"
    case suchThat = "mid"

    /// Relations bind looser than arithmetic: `a + b = c`.
    var isRelation: Bool {
        switch self {
        case .equals, .notEqual, .less, .greater, .lessEqual, .greaterEqual, .approx, .elementOf,
             .notElementOf, .subset, .superset, .perpendicular, .parallel, .similar, .congruent,
             .equivalent, .tendsTo, .suchThat:
            return true
        default:
            return false
        }
    }

    var isInequality: Bool {
        switch self {
        case .less, .greater, .lessEqual, .greaterEqual, .notEqual: return true
        default: return false
        }
    }
}

enum UnaryOperator: String, Equatable, CaseIterable {
    case minus = "-"
    case plus = "+"
    case plusMinus = "pm"
    case minusPlus = "mp"
    case factorial = "!"
    case degree = "circ"
    case percent = "%"
}

extension MathNode {
    /// The node without surrounding round brackets.
    var unwrappingGroups: MathNode {
        var node = self
        while case .group(let inner) = node { node = inner }
        return node
    }

    /// Every unknown command name in the tree, in reading order (for the debug screen).
    var unknownCommandNames: [String] {
        var names: [String] = []
        collectUnknown(into: &names)
        return names
    }

    private func collectUnknown(into names: inout [String]) {
        if case .unknown(let name, _) = self { names.append(name) }
        for child in children { child.collectUnknown(into: &names) }
    }

    /// Direct children in reading order.
    var children: [MathNode] {
        switch self {
        case .empty, .number, .identifier, .symbol, .unit, .text:
            return []
        case .binary(_, let l, let r), .fraction(let l, let r), .power(let l, let r), .subscript(let l, let r),
             .setBuilder(let l, let r), .combination(let l, let r), .arrangement(let l, let r):
            return [l, r]
        case .unary(_, let x), .group(let x), .abs(let x), .vector(let x), .angle(let x), .triangle(let x):
            return [x]
        case .juxtaposition(let xs), .set(let xs), .tuple(let xs), .list(let xs, _), .unknown(_, let xs):
            return xs
        case .root(let index, let x):
            return (index.map { [$0] } ?? []) + [x]
        case .function(let f, let arg):
            return [f.power, f.base, arg].compactMap { $0 }
        case .integral(_, let lower, let upper, let body, let variable):
            return [lower, upper, body, variable].compactMap { $0 }
        case .limit(let variable, let target, let body):
            return [variable, target, body].compactMap { $0 }
        case .sum(let from, let to, let body), .product(let from, let to, let body):
            return [from, to, body].compactMap { $0 }
        case .interval(_, let a, let b, _):
            return [a, b]
        case .cases(let rows), .alternatives(let rows), .matrix(let rows, _):
            return rows.flatMap { $0 }
        case .evaluation(let x, let lower, let upper):
            return [x, lower, upper].compactMap { $0 }
        }
    }
}

// MARK: - Shape, as the readers see it

extension MathNode {
    /// One word-ish thing: a number, a letter, a symbol, a signed number, x₁.
    var isAtomicTerm: Bool {
        switch self {
        case .empty, .number, .identifier, .symbol, .unit:
            return true
        case .text(let t):
            return !t.trimmingCharacters(in: .whitespaces).contains(" ")
        case .unary(let o, let x):
            return [.minus, .plus, .degree, .percent].contains(o) && x.isAtomicTerm
        case .group(let x):
            return x.isAtomicTerm
        case .subscript(let b, let s):
            return b.isAtomicTerm && s.isAtomicTerm
        default:
            return false
        }
    }

    /// Short enough to need no "of"/"của", no comma and no pause: atoms, 2x, x², sin x, √2.
    var isSimpleTerm: Bool {
        if isAtomicTerm { return true }
        switch self {
        case .juxtaposition(let xs):
            return xs.allSatisfy { $0.isAtomicTerm || $0.isSimplePower }
        case .power:
            return isSimplePower
        case .function(let f, let arg):
            return f.base == nil && (arg.map { $0.isAtomicTerm || $0.isProductOfAtoms } ?? true)
        case .root(nil, let x):
            return x.isAtomicTerm
        case .unary(.factorial, let x):
            return x.isAtomicTerm
        case .vector, .angle, .triangle:
            return true
        default:
            return false
        }
    }

    /// The relation at the top of a cell (x + y = 3 → =), if any.
    var topRelation: BinaryOperator? {
        switch self {
        case .binary(let o, let l, _):
            if o.isRelation { return o }
            return [.implies, .iff, .and, .or].contains(o) ? nil : l.topRelation
        case .juxtaposition(let xs):
            return xs.lazy.compactMap { $0.topRelation }.first
        default:
            return nil
        }
    }

    /// Reading starts with words or with nothing: `\text{nếu } x \ge 0`, or the `= 3` of an aligned
    /// `x + y &= 3`. Such a cases cell needs no "nếu" / "if" in front.
    var startsWithWordsOrNothing: Bool {
        switch self {
        case .text, .empty:
            return true
        case .binary(_, let l, _):
            return l.startsWithWordsOrNothing
        case .juxtaposition(let xs), .list(let xs, _):
            return xs.first?.startsWithWordsOrNothing ?? true
        default:
            return false
        }
    }

    /// x², xⁿ: an atom to an atomic power.
    var isSimplePower: Bool {
        if case .power(let b, let e) = self { return b.isAtomicTerm && e.isAtomicTerm }
        return false
    }

    /// 2x, ab, 3x²: atoms side by side.
    var isProductOfAtoms: Bool {
        if case .juxtaposition(let xs) = self { return xs.allSatisfy { $0.isAtomicTerm || $0.isSimplePower } }
        return isSimplePower
    }

    /// Round brackets around more than an atom: (x + 1).
    var isCompoundGroup: Bool {
        if case .group(let x) = self { return !x.isAtomicTerm }
        return false
    }

    /// Round brackets around a compound expression OR a signed term: `(x + 1)`, `(-5)`, `(-x)`.
    /// Used for power bases, factorials and implicit multiplication so `(-5)^2` reads
    /// "âm 5, tất cả bình phương" instead of colliding with `-5^2` ("âm 5 bình phương").
    var isGroupedBase: Bool {
        if case .group(let x) = self {
            if !x.isAtomicTerm { return true }
            if case .unary(let op, _) = x, [.minus, .plus, .plusMinus, .minusPlus].contains(op) {
                return true
            }
        }
        return false
    }

    /// The value of a plain integer literal (up to 9 digits).
    var integerValue: Int? {
        if case .number(let s) = self, !s.contains("."), s.count <= 9 { return Int(s) }
        return nil
    }
}
