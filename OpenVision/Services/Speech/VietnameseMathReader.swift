// OpenVision - VietnameseMathReader.swift
// MathNode → Vietnamese words, the way formulas are read in Vietnamese classrooms (PLAN.md §2.5, §4.3).
// Pure Swift, Foundation only.

import Foundation

struct VietnameseMathReader {
    let style: MathReadingStyle
    let dictionary: PronunciationDictionary

    init(style: MathReadingStyle) {
        self.style = style
        self.dictionary = PronunciationDictionary(overrides: style.pronunciationOverrides)
    }

    private var explicit: Bool { style.verbosity == .explicit }

    // MARK: - Entry points

    /// A formula as speech pieces (all `isMath: true`, separated by pauses where needed).
    func pieces(for node: MathNode) -> [SpeechPiece] {
        VietMathSpeech.pieces(from: items(for: node), isMath: true)
    }

    /// The reading of one node.
    func items(for node: MathNode) -> [MathReadingItem] {
        read(node)
    }

    // MARK: - Words

    private func w(_ s: String) -> MathReadingItem { .word(s) }

    private func op(_ op: BinaryOperator) -> String {
        let spoken: String
        switch op {
        case .plus: spoken = "cộng"
        case .minus: spoken = "trừ"
        case .times: spoken = "nhân"
        case .divide: spoken = "chia"
        case .slash: spoken = style.symbolicFraction.word
        case .equals: spoken = "bằng"
        case .notEqual: spoken = "khác"
        case .less: spoken = "nhỏ hơn"
        case .greater: spoken = "lớn hơn"
        case .lessEqual: spoken = "nhỏ hơn hoặc bằng"
        case .greaterEqual: spoken = "lớn hơn hoặc bằng"
        case .approx: spoken = "xấp xỉ"
        case .plusMinus: spoken = "cộng trừ"
        case .minusPlus: spoken = "trừ cộng"
        case .elementOf: spoken = "thuộc"
        case .notElementOf: spoken = "không thuộc"
        case .subset: spoken = "là tập con của"
        case .superset: spoken = "chứa"
        case .union: spoken = "hợp"
        case .intersection: spoken = "giao"
        case .setMinus: spoken = "trừ"
        case .perpendicular: spoken = "vuông góc với"
        case .parallel: spoken = "song song với"
        case .similar: spoken = "đồng dạng với"
        case .congruent: spoken = "bằng"
        case .equivalent: spoken = "đồng dư với"
        case .implies: spoken = "suy ra"
        case .iff: spoken = "tương đương"
        case .tendsTo: spoken = "tiến tới"
        case .and: spoken = "và"
        case .or: spoken = "hoặc"
        case .compose: spoken = "hợp"
        case .suchThat: spoken = "sao cho"
        }
        return dictionary.word(op.rawValue, default: spoken)
    }

    private var negative: String { style.negativeWord.word }

    // MARK: - Shape of a node (shared with EnglishMathReader, see MathNode.swift)

    func isAtomic(_ node: MathNode) -> Bool { node.isAtomicTerm }
    func isSimple(_ node: MathNode) -> Bool { node.isSimpleTerm }
    private func isSimplePower(_ node: MathNode) -> Bool { node.isSimplePower }
    private func isProductOfAtoms(_ node: MathNode) -> Bool { node.isProductOfAtoms }
    private func integerValue(_ node: MathNode) -> Int? { node.integerValue }
    private func isCompoundGroup(_ node: MathNode) -> Bool { node.isCompoundGroup }

    // MARK: - Reading

    private func read(_ node: MathNode) -> [MathReadingItem] {
        switch node {
        case .empty:
            return []
        case .number(let digits):
            return readNumber(digits)
        case .identifier(let name):
            return [w(readIdentifier(name))]
        case .symbol(let name):
            let spoken = dictionary.symbol(name)
            return spoken.isEmpty ? [] : [w(spoken)]
        case .unit(let symbol):
            return [w(dictionary.unit(symbol))]
        case .text(let text):
            let spoken = normalizeProse(text).trimmingCharacters(in: .whitespacesAndNewlines)
            return spoken.isEmpty ? [] : [w(spoken)]
        case .binary(let o, let l, let r):
            return readBinary(o, l, r)
        case .unary(let o, let x):
            return readUnary(o, x)
        case .juxtaposition(let xs):
            return readJuxtaposition(xs)
        case .fraction(let n, let d):
            return readFraction(n, d)
        case .power(let b, let e):
            return readPower(b, e)
        case .subscript(let b, let s):
            return readSubscript(b, s)
        case .root(let index, let x):
            return readRoot(index, x)
        case .function(let f, let arg):
            return readFunction(f, arg)
        case .group(let x):
            return readGroup(x)
        case .abs(let x):
            return [w("giá trị tuyệt đối của")] + read(x) + (isAtomic(x) ? [] : [.pause])
        case .integral(let kind, let lower, let upper, let body, let variable):
            return readIntegral(kind, lower, upper, body, variable)
        case .limit(let variable, let target, let body):
            var out: [MathReadingItem] = [w(dictionary.function("lim"))]
            if let variable {
                if let target {
                    out += [w("khi")] + read(variable) + [w(op(.tendsTo))] + read(target)
                } else {
                    out += [w("theo")] + read(variable)
                }
            }
            out.append(w("của"))
            if let body { out += read(body) }
            return out
        case .sum(let from, let to, let body):
            return readBigOperator("tổng", from, to, body)
        case .product(let from, let to, let body):
            return readBigOperator("tích", from, to, body)
        case .combination(let n, let k):
            return [w("tổ hợp chập")] + read(k) + [w("của")] + read(n)
        case .arrangement(let n, let k):
            return [w("chỉnh hợp chập")] + read(k) + [w("của")] + read(n)
        case .vector(let x):
            return [w("véc-tơ")] + read(x)
        case .angle(let x):
            return [w("góc")] + read(x)
        case .triangle(let x):
            return [w("tam giác")] + read(x)
        case .set(let elements):
            guard !elements.isEmpty else { return [w(dictionary.symbol("emptyset"))] }
            var out: [MathReadingItem] = [w("tập hợp gồm")]
            for (n, element) in elements.enumerated() {
                if n > 0 { out += n == elements.count - 1 ? [w("và")] : [.punct(",")] }
                out += read(element)
            }
            return out
        case .setBuilder(let subject, let condition):
            return [w("tập hợp các")] + read(subject) + [w("sao cho")] + read(condition)
        case .interval(let lowerClosed, let a, let b, let upperClosed):
            let name = lowerClosed && upperClosed ? "đoạn" : (!lowerClosed && !upperClosed ? "khoảng" : "nửa khoảng")
            return [w(name), w("từ")] + read(a) + [w("đến")] + read(b)
        case .tuple(let xs):
            return joined(xs.map { read($0) }, by: .punct(","))
        case .list(let xs, let separator):
            return joined(xs.map { read($0) }, by: .punct(String(separator)))
        case .cases(let rows):
            return readCases(rows)
        case .alternatives(let rows):
            return joined(rows.map { readRow($0) }, by: w("hoặc"))
        case .matrix(let rows, let matrixStyle):
            return readMatrix(rows, matrixStyle)
        case .evaluation(let x, let lower, let upper):
            var out = read(x) + [.punct(","), w("cận")]
            if let lower { out += [w("từ")] + read(lower) }
            if let upper { out += [w("đến")] + read(upper) }
            return out
        case .unknown(_, let args):
            return args.flatMap { read($0) }
        }
    }

    private func joined(_ parts: [[MathReadingItem]], by separator: MathReadingItem) -> [MathReadingItem] {
        var out: [MathReadingItem] = []
        for part in parts where !part.isEmpty {
            if !out.isEmpty { out.append(separator) }
            out += part
        }
        return out
    }

    func readNumber(_ digits: String) -> [MathReadingItem] {
        let parts = digits.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            let integer = parts[0].isEmpty ? "0" : String(parts[0])
            return [w(integer), w("phẩy"), w(String(parts[1]))]
        }
        return [w(digits)]
    }

    func readIdentifier(_ name: String) -> String {
        if name.count == 1 { return dictionary.letter(name, style: style.letterStyle) }
        return dictionary.greekLetter(name)
    }

    private func readBinary(_ o: BinaryOperator, _ l: MathNode, _ r: MathNode) -> [MathReadingItem] {
        if o == .slash { return readFraction(l.unwrappingGroups, r.unwrappingGroups) }
        return read(l) + [w(op(o))] + read(r)
    }

    private func readUnary(_ o: UnaryOperator, _ x: MathNode) -> [MathReadingItem] {
        switch o {
        case .minus:
            return x == .empty ? [w("trừ")] : [w(negative)] + read(x)
        case .plus:
            return x == .empty ? [w("cộng")] : [w("dương")] + read(x)
        case .plusMinus:
            return [w(op(.plusMinus))] + read(x)
        case .minusPlus:
            return [w(op(.minusPlus))] + read(x)
        case .factorial:
            if isCompoundGroup(x) { return read(x.unwrappingGroups) + [.punct(","), w("tất cả giai thừa")] }
            return read(x) + [w("giai thừa")]
        case .degree:
            return read(x) + [w(dictionary.symbol("°"))]
        case .percent:
            return read(x) + [w(dictionary.symbol("%"))]
        }
    }

    private func readJuxtaposition(_ xs: [MathNode]) -> [MathReadingItem] {
        // Flatten nested products first.
        var factors: [MathNode] = []
        for x in xs {
            if case .juxtaposition(let inner) = x { factors += inner } else { factors.append(x) }
        }
        var out: [MathReadingItem] = []
        for (n, factor) in factors.enumerated() {
            if n > 0 {
                let previous = factors[n - 1]
                let bothNumbers: Bool = {
                    if case .number = previous, case .number = factor { return true }
                    return false
                }()
                if factor.isGroupedBase || previous.isGroupedBase || bothNumbers {
                    out.append(w(op(.times)))
                }
            }
            out += read(factor)
        }
        return out
    }

    private func readGroup(_ x: MathNode) -> [MathReadingItem] {
        if isAtomic(x) { return read(x) }
        if explicit { return [w("mở ngoặc")] + read(x) + [w("đóng ngoặc")] }
        return read(x) + [.pause]
    }

    private func readFraction(_ n: MathNode, _ d: MathNode) -> [MathReadingItem] {
        // Numeric: "một phần hai", "ba phần tư", "âm một phần hai".
        var numerator = n
        var sign: [MathReadingItem] = []
        if case .unary(.minus, let inner) = n, integerValue(inner) != nil {
            numerator = inner
            sign = [w(negative)]
        }
        if let a = integerValue(numerator), let b = integerValue(d), b != 0 {
            let denominator = b == 4 ? "tư" : Self.spell(b)
            return sign + [w(Self.spell(a)), w("phần"), w(denominator)]
        }
        let word = w(style.symbolicFraction.word)
        let nested = containsFraction(n) || containsFraction(d)
        let simple = isSimple(n) && isSimple(d)
        if explicit, !simple || nested {
            return [w("phân số"), .punct(","), w("tử số")] + read(n) + [.punct(","), w("mẫu số")] + read(d)
                + [.punct(","), w("hết phân số")]
        }
        if simple { return read(n) + [word] + read(d) }
        let comma: [MathReadingItem] = isSimple(n) ? [] : [.punct(",")]
        return read(n) + comma + [word] + read(d) + [.pause]
    }

    private func containsFraction(_ node: MathNode) -> Bool {
        if case .fraction = node { return true }
        if case .binary(.slash, _, _) = node { return true }
        return node.children.contains { containsFraction($0) }
    }

    private func readPower(_ base: MathNode, _ exponent: MathNode) -> [MathReadingItem] {
        // Lone signs: 0⁺, ℝ⁺, ℕ*.
        if case .unary(let sign, .empty) = exponent, sign == .plus || sign == .minus {
            if case .symbol(let set) = base, ["ℝ", "ℕ", "ℤ", "ℚ"].contains(set) {
                return read(base) + [w(sign == .plus ? "dương" : "âm")]
            }
            return read(base) + [w(sign == .plus ? "cộng" : "trừ")]
        }
        if case .symbol("*") = exponent {
            if case .symbol(let set) = base, ["ℝ", "ℕ", "ℤ", "ℚ"].contains(set) {
                return read(base) + [w("khác 0")]
            }
            return read(base) + [w("sao")]
        }
        let exponentWords: [MathReadingItem]
        switch integerValue(exponent) {
        case 2?: exponentWords = [w("bình phương")]
        case 3?: exponentWords = [w("lập phương")]
        default: exponentWords = [w("mũ")] + read(exponent)
        }
        var out: [MathReadingItem]
        if base.isGroupedBase {
            out = read(base.unwrappingGroups) + [.punct(","), w("tất cả")] + exponentWords
        } else {
            out = read(base) + exponentWords
        }
        if !isAtomic(exponent) {
            out += explicit ? [.punct(","), w("hết mũ")] : [.pause]
        }
        return out
    }

    private func readSubscript(_ base: MathNode, _ sub: MathNode) -> [MathReadingItem] {
        if explicit { return read(base) + [w("chỉ số")] + read(sub) }
        if let value = integerValue(sub) { return read(base) + [w(Self.spell(value))] }
        return read(base) + read(sub) + (isAtomic(sub) ? [] : [.pause])
    }

    private func readRoot(_ index: MathNode?, _ radicand: MathNode) -> [MathReadingItem] {
        let x = radicand.unwrappingGroups
        let simple = isAtomic(x) || isProductOfAtoms(x) && !isSimplePower(x)
        let square = index == nil || index == .empty || integerValue(index!) == 2
        var out: [MathReadingItem]
        if square {
            if simple {
                return explicit ? [w("căn bậc hai của")] + read(x) : [w("căn")] + read(x)
            }
            out = [w("căn của")] + read(x)
        } else {
            let indexWords: [MathReadingItem] = integerValue(index!).map { [w(Self.spell($0))] } ?? read(index!)
            out = [w("căn bậc")] + indexWords + [w("của")] + read(x)
            if simple { return out }
        }
        return out + (explicit ? [.punct(","), w("hết căn")] : [.pause])
    }

    private func readFunction(_ f: MathFunction, _ arg: MathNode?) -> [MathReadingItem] {
        if f.name.isEmpty {
            // (x² + 1)' : the derivative of an expression.
            guard let arg else { return [] }
            return [w("đạo hàm của")] + read(arg.unwrappingGroups) + (isAtomic(arg) ? [] : [.pause])
        }
        if f.name.count == 1 || MathLexer.greekLetterNames.contains(f.name) {
            // A variable: f'(x), y'', and Greek letters with primes (Δ' "đen-ta phẩy", α' "an-pha phẩy").
            var out: [MathReadingItem] = [w(readIdentifier(f.name))]
            switch f.primes {
            case 0: break
            case 1: out.append(w("phẩy"))
            default: out += [w(Self.spell(f.primes)), w("phẩy")]
            }
            if let power = f.power { out += [w("mũ")] + read(power) }
            guard let arg else { return out }
            if case .tuple(let xs) = arg {
                let isPoint = f.name.first?.isUppercase == true && f.primes == 0
                out.append(w(isPoint ? "tọa độ" : "của"))
                return out + joined(xs.map { read($0) }, by: .punct(isPoint ? ";" : ","))
            }
            if isAtomic(arg) {
                return out + (explicit ? [w("của")] : []) + read(arg)
            }
            return out + [w("của")] + read(arg) + [.pause]
        }

        var out: [MathReadingItem]
        if f.name == "log", let base = f.base {
            out = [w(dictionary.function("logarit"))] + powerWords(f.power) + [w("cơ số")] + read(base)
            guard let arg else { return out }
            return out + [w("của")] + read(arg) + (isAtomic(arg) ? [] : [.pause])
        }
        out = [w(dictionary.function(f.name))] + powerWords(f.power)
        if let base = f.base { out += [w("trên")] + read(base) }
        guard let arg else { return out }
        let alwaysOf: Set<String> = ["ln", "gcd", "lcm", "det", "sgn"]
        if alwaysOf.contains(f.name) || f.base != nil {
            return out + [w("của")] + read(arg) + (isSimple(arg) ? [] : [.pause])
        }
        if isAtomic(arg) || isProductOfAtoms(arg) || isSimple(arg) && !isFunction(arg) || isSimpleFraction(arg) {
            return out + read(arg)
        }
        return out + [w("của")] + read(arg) + [.pause]
    }

    /// π/3, x/2: a fraction with simple parts.
    private func isSimpleFraction(_ node: MathNode) -> Bool {
        if case .fraction(let n, let d) = node { return isSimple(n) && isSimple(d) }
        return false
    }

    private func isFunction(_ node: MathNode) -> Bool {
        if case .function = node { return true }
        return false
    }

    private func powerWords(_ power: MathNode?) -> [MathReadingItem] {
        guard let power else { return [] }
        switch integerValue(power) {
        case 2?: return [w("bình phương")]
        case 3?: return [w("lập phương")]
        default: return [w("mũ")] + read(power)
        }
    }

    private func readIntegral(_ kind: IntegralKind, _ lower: MathNode?, _ upper: MathNode?, _ body: MathNode,
                              _ variable: MathNode?) -> [MathReadingItem] {
        let definite = lower != nil || upper != nil
        var out: [MathReadingItem]
        switch kind {
        case .single: out = [w(definite ? "tích phân" : "nguyên hàm")]
        case .double: out = [w("tích phân kép")]
        case .triple: out = [w("tích phân bội ba")]
        case .contour: out = [w("tích phân đường")]
        }
        switch (lower, upper) {
        case let (l?, u?): out += [w("từ")] + read(l) + [w("đến")] + read(u)
        case let (l?, nil): out += [w("trên")] + read(l)
        case let (nil, u?): out += [w("đến")] + read(u)
        default: break
        }
        out.append(w("của"))
        out += read(body)
        if let variable {
            let variables: [MathNode]
            if case .juxtaposition(let vs) = variable { variables = vs } else { variables = [variable] }
            out.append(.punct(","))
            for v in variables { out += [w("đê")] + read(v) }
        }
        return out
    }

    private func readBigOperator(_ name: String, _ from: MathNode?, _ to: MathNode?, _ body: MathNode) -> [MathReadingItem] {
        var out: [MathReadingItem] = [w(name)]
        switch (from, to) {
        case let (f?, t?): out += [w("từ")] + read(f) + [w("đến")] + read(t)
        case let (f?, nil): out += [w("theo")] + read(f)
        case let (nil, t?): out += [w("đến")] + read(t)
        default: break
        }
        return out + [w("của")] + read(body)
    }

    private func readRow(_ cells: [MathNode]) -> [MathReadingItem] {
        cells.flatMap { read($0) }
    }

    /// A row of a piecewise definition: the value, "nếu", the condition (`x & x \ge 0` → "x nếu x lớn hơn
    /// hoặc bằng 0"). A condition written with words (`\text{nếu } x \ge 0`, `\text{khi } …`) is read as is.
    private func readPiece(_ cells: [MathNode]) -> [MathReadingItem] {
        guard cells.count >= 2, !cells[1].startsWithWordsOrNothing else { return readRow(cells) }
        return read(cells[0]) + [w("nếu")] + readRow(Array(cells.dropFirst()))
    }

    private func readCases(_ rows: [[MathNode]]) -> [MathReadingItem] {
        guard !rows.isEmpty else { return [] }
        let piecewise = rows.allSatisfy { $0.count >= 2 && $0[0].topRelation == nil }
        let relations = rows.map { $0.lazy.compactMap { $0.topRelation }.first }
        let kind: String
        if piecewise {
            kind = "trường hợp"
        } else if relations.allSatisfy({ $0 == .equals }) {
            kind = "phương trình"
        } else if relations.allSatisfy({ $0?.isInequality == true }) {
            kind = "bất phương trình"
        } else {
            kind = "dòng"
        }
        let readings = rows.map { piecewise ? readPiece($0) : readRow($0) }
        if explicit {
            var out: [MathReadingItem] = [w(piecewise ? "gồm" : "hệ gồm"), w("\(rows.count)"), w(kind), .punct(":")]
            for (n, reading) in readings.enumerated() {
                if n > 0 { out.append(.punct(";")) }
                out += [w("thứ " + Self.ordinal(n + 1)), .punct(",")] + reading
            }
            return out
        }
        var out: [MathReadingItem] = []
        if !piecewise {
            out = [w(kind == "dòng" ? "hệ" : "hệ " + kind), .punct(":")]
        }
        return out + joined(readings, by: .punct(";"))
    }

    private func readMatrix(_ rows: [[MathNode]], _ matrixStyle: MatrixStyle) -> [MathReadingItem] {
        guard !rows.isEmpty else { return [] }
        if matrixStyle == .rows { return joined(rows.map { readRow($0) }, by: .punct(";")) }
        let columns = rows.map(\.count).max() ?? 0
        var out: [MathReadingItem] = [w(matrixStyle == .determinant ? "định thức" : "ma trận"),
                                      w("\(rows.count) hàng \(columns) cột"), .punct(":")]
        for (n, row) in rows.enumerated() {
            if n > 0 { out.append(.punct(";")) }
            out += [w("hàng \(n + 1)"), .punct(":")] + joined(row.map { read($0) }, by: .punct(","))
        }
        return out
    }

    // MARK: - Vietnamese numbers

    private static let digitWords = ["không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"]

    /// 0…999 999 999 in words: 21 → "hai mươi mốt", 105 → "một trăm linh năm", 15 → "mười lăm".
    /// Larger numbers stay digits.
    static func spell(_ value: Int) -> String {
        guard value >= 0 else { return "âm " + spell(-value) }
        guard value < 1_000_000_000 else { return String(value) }
        if value == 0 { return "không" }
        var groups: [Int] = []
        var rest = value
        while rest > 0 {
            groups.append(rest % 1000)
            rest /= 1000
        }
        let scales = ["", "nghìn", "triệu"]
        var words: [String] = []
        for index in stride(from: groups.count - 1, through: 0, by: -1) {
            let group = groups[index]
            if group == 0 { continue }
            let isLeading = index == groups.count - 1
            words.append(spellHundreds(group, full: !isLeading))
            if !scales[index].isEmpty { words.append(scales[index]) }
        }
        return words.joined(separator: " ")
    }

    /// 1…999. `full` reads leading zeros of an inner group: 1 005 → "một nghìn không trăm linh năm".
    private static func spellHundreds(_ n: Int, full: Bool) -> String {
        let hundreds = n / 100
        let tens = (n / 10) % 10
        let units = n % 10
        var words: [String] = []
        if hundreds > 0 || full {
            words += [digitWords[hundreds], "trăm"]
        }
        if tens == 0 {
            if units > 0 {
                if !words.isEmpty { words.append("linh") }
                words.append(digitWords[units])
            }
        } else if tens == 1 {
            words.append("mười")
            if units > 0 { words.append(units == 5 ? "lăm" : digitWords[units]) }
        } else {
            words += [digitWords[tens], "mươi"]
            switch units {
            case 0: break
            case 1: words.append("mốt")
            case 5: words.append("lăm")
            default: words.append(digitWords[units])
            }
        }
        return words.joined(separator: " ")
    }

    /// 1 → "nhất", 4 → "tư", other → spelled number ("thứ hai", "thứ mười").
    static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "nhất"
        case 4: return "tư"
        default: return spell(n)
        }
    }

    // MARK: - Prose

    /// Normalises a Vietnamese prose span: decimal commas ("2,5" → "2 phẩy 5"), units after numbers
    /// ("5 cm" → "5 xen-ti-mét"), "%", "°", a minus before a number ("-3" → "âm 3"), single Latin
    /// letters (letter names) and the user's dictionary (whole words). Everything else is unchanged.
    func normalizeProse(_ text: String) -> String {
        ProseNormalizer(reader: self).normalize(text)
    }
}

// MARK: - Prose normalizer

private struct ProseNormalizer {
    let reader: VietnameseMathReader
    private var dictionary: PronunciationDictionary { reader.dictionary }

    init(reader: VietnameseMathReader) {
        self.reader = reader
    }

    private enum Token: Equatable {
        case space(String)
        case word(String)
        case number(String)
        case other(Character)
    }

    private func tokenize(_ text: String) -> [Token] {
        let chars = Array(text)
        var tokens: [Token] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                var j = i
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                tokens.append(.space(String(chars[i..<j])))
                i = j
            } else if MathLexer.isDigit(c) {
                var j = i
                while j < chars.count {
                    if MathLexer.isDigit(chars[j]) {
                        j += 1
                    } else if (chars[j] == "," || chars[j] == "."), j + 1 < chars.count, MathLexer.isDigit(chars[j + 1]) {
                        j += 1
                    } else {
                        break
                    }
                }
                tokens.append(.number(String(chars[i..<j])))
                i = j
            } else if c.isLetter {
                var j = i
                while j < chars.count {
                    if chars[j].isLetter {
                        j += 1
                    } else if chars[j] == "-" || chars[j] == "'", j + 1 < chars.count, chars[j + 1].isLetter {
                        j += 1
                    } else {
                        break
                    }
                }
                tokens.append(.word(String(chars[i..<j])))
                i = j
            } else {
                tokens.append(.other(c))
                i += 1
            }
        }
        return tokens
    }

    func normalize(_ text: String) -> String {
        let tokens = tokenize(text)
        var out = ""
        var i = 0
        func token(_ j: Int) -> Token? { j >= 0 && j < tokens.count ? tokens[j] : nil }
        while i < tokens.count {
            switch tokens[i] {
            case .space(let s):
                out += s
                i += 1
            case .other(let c):
                // "-3" at the start, after a space or "(": a negative number. "1-5" stays a range.
                if c == "-" || c == "−", case .number? = token(i + 1) {
                    let before = token(i - 1)
                    let startsNumber: Bool
                    switch before {
                    case nil, .space?: startsNumber = true
                    case .other(let b)?: startsNumber = b == "(" || b == "[" || b == ":"
                    default: startsNumber = false
                    }
                    if startsNumber {
                        out += reader.style.negativeWord.word + " "
                        i += 1
                        continue
                    }
                }
                out.append(c)
                i += 1
            case .number(let raw):
                out += isSectionNumber(raw, tokens, at: i) ? raw.split(separator: ".").joined(separator: " chấm ")
                    : spokenNumber(raw)
                i += 1
                if let (spoken, used) = unitAfterNumber(tokens, from: i) {
                    out += " " + spoken
                    i += used
                }
            case .word(let word):
                if let (spoken, used) = compoundUnit(tokens, at: i) {
                    out += spoken
                    i += used
                    continue
                }
                out += spokenWord(word, before: token(i - 1), after: token(i + 1))
                i += 1
            }
        }
        return out
    }

    /// Words before a section number ("Bài 2.15", "Định lí 1.2"), with a small first letter.
    private static let headingWords: Set<String> = ["bài", "câu", "hình", "mục", "bảng", "trang", "chương", "phần"]
    private static let twoWordHeadings: Set<String> = ["ví dụ", "định lí", "định lý"]

    /// "2.15" right after a heading word: a section number, read "2 chấm 15" rather than as a decimal.
    private func isSectionNumber(_ raw: String, _ tokens: [Token], at i: Int) -> Bool {
        guard raw.contains("."), !raw.contains(",") else { return false }
        guard case .space? = tokens[safe: i - 1], case .word(let last)? = tokens[safe: i - 2] else { return false }
        let smallFirst = { (word: String) in word.prefix(1).lowercased() + word.dropFirst() }
        if Self.headingWords.contains(smallFirst(last)) { return true }
        guard case .space? = tokens[safe: i - 3], case .word(let first)? = tokens[safe: i - 4] else { return false }
        return Self.twoWordHeadings.contains(smallFirst(first) + " " + last)
    }

    /// "2,5" → "2 phẩy 5"; "2.5" → "2 phẩy 5"; "1.000.000" and "2.500" (thousands) unchanged.
    private func spokenNumber(_ raw: String) -> String {
        let groups = raw.split(whereSeparator: { $0 == "," || $0 == "." }).map(String.init)
        let separators = raw.filter { $0 == "," || $0 == "." }
        guard !separators.isEmpty else { return raw }
        let leadOK = groups[0].count <= 3 && !(groups[0].count > 1 && groups[0].hasPrefix("0"))
        if separators.count == 1 {
            if separators == ".", leadOK, groups[1].count == 3, groups[0] != "0" { return raw }  // 2.500 đồng
            return groups[0] + " phẩy " + groups[1]
        }
        let seps = Array(separators)
        // 1.000.000 / 1.000.000,5
        if leadOK, seps.dropLast().allSatisfy({ $0 == "." }), groups.dropFirst().dropLast().allSatisfy({ $0.count == 3 }) {
            if seps.last == ".", groups.last?.count == 3 { return raw }
            if seps.last == "," {
                return groups.dropLast().joined(separator: ".") + " phẩy " + (groups.last ?? "")
            }
        }
        return raw  // versions, lists: leave to the voice
    }

    /// A unit right after a number: "5 cm", "5cm", "3 m/s", "60 km/h", "10 m²", "5 cm2", "50 %", "30°C".
    private func unitAfterNumber(_ tokens: [Token], from start: Int) -> (String, Int)? {
        var j = start
        if case .space(let s)? = tokens[safe: j], s == " " { j += 1 }
        guard let first = tokens[safe: j] else { return nil }
        switch first {
        case .other("%"):
            return (dictionary.symbol("%"), j + 1 - start)
        case .other("°"), .other("º"):
            var spoken = dictionary.symbol("°")
            var used = j + 1 - start
            if case .word(let scale)? = tokens[safe: j + 1], scale == "C" || scale == "F" {
                spoken += " " + dictionary.letter(scale, style: reader.style.letterStyle)
                used += 1
            }
            return (spoken, used)
        case .word(let head):
            var symbol = head
            var end = j + 1
            if case .other("/")? = tokens[safe: end], case .word(let tail)? = tokens[safe: end + 1] {
                let compound = head + "/" + tail
                if isUnit(compound) || (isUnit(head) && isUnit(tail)) {
                    symbol = compound
                    end += 2
                }
            }
            if case .other(let mark)? = tokens[safe: end], mark == "²" || mark == "³" {
                symbol += mark == "²" ? "^2" : "^3"
                end += 1
            } else if case .number(let n)? = tokens[safe: end], n == "2" || n == "3",
                      MathParser.lengthUnits.contains(symbol) {
                symbol += "^" + n  // "5 cm2", as typed on phones
                end += 1
            }
            guard isUnit(symbol) else { return nil }
            // Must end there: "5 cmx" is not a unit; a single letter needs a clear boundary.
            if let after = tokens[safe: end] {
                switch after {
                case .word, .number: return nil
                default: break
                }
            }
            if head.count == 1 && !symbol.contains("/") {
                guard proseSingleLetterUnits.contains(head) else { return nil }
            }
            return (dictionary.unit(symbol), end - start)
        default:
            return nil
        }
    }

    private let proseSingleLetterUnits: Set<String> = ["m", "g", "s", "l", "h", "N", "J", "W", "V", "K"]
    private let timeUnits: Set<String> = ["h", "s", "min", "ms"]

    /// "km/h", "m/s" without a number ("Đổi ra km/h."): the unit, not two words and a letter name.
    /// Two time units ("h/s", shorthand for "học sinh") and anything glued to more letters stay as written.
    private func compoundUnit(_ tokens: [Token], at j: Int) -> (String, Int)? {
        guard case .word(let head)? = tokens[safe: j], case .other("/")? = tokens[safe: j + 1],
              case .word(let tail)? = tokens[safe: j + 2] else { return nil }
        let symbol = head + "/" + tail
        guard isUnit(symbol), !(timeUnits.contains(head) && timeUnits.contains(tail)) else { return nil }
        for neighbour in [tokens[safe: j - 1], tokens[safe: j + 3]] {
            switch neighbour {
            case .word?, .number?, .other("/")?: return nil  // "a/km/h", "km/h2"
            default: break
            }
        }
        return (dictionary.unit(symbol), 3)
    }

    private func isUnit(_ symbol: String) -> Bool {
        let parts = symbol.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(parts.count) else { return false }
        return parts.allSatisfy { part in
            let base = part.hasSuffix("^2") || part.hasSuffix("^3") ? String(part.dropLast(2)) : part
            return MathParser.unitSymbols.contains(base)
        }
    }

    private func spokenWord(_ word: String, before: Token?, after: Token?) -> String {
        if let custom = dictionary.override(for: word) { return custom }
        guard word.count == 1, let c = word.first, MathLexer.isASCIILetter(c) else { return word }
        // A letter standing alone ("Câu 2: B.", "với x là"), not part of "A4" or "x-ray".
        let glued: (Token?) -> Bool = { token in
            switch token {
            case .number?, .word?: return true
            case .other(let o)?: return o == "-" || o == "'" || o == "’"
            default: return false
            }
        }
        if glued(before) || glued(after) { return word }
        return dictionary.letter(word, style: reader.style.letterStyle)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}
