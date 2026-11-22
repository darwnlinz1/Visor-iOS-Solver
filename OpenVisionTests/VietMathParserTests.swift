// OpenVision - VietMathParserTests.swift
// MathSpanSplitter, MathLexer and MathParser (PLAN.md §4.3, task T3.1): every structure of the reading
// table parses into the expected tree, and broken input never crashes.

import XCTest
@testable import OpenVision

final class VietMathParserTests: XCTestCase {

    // MARK: - Tree helpers

    private func parse(_ source: String) -> MathNode { MathParser.parse(source) }
    private func id(_ name: String) -> MathNode { .identifier(name) }
    private func num(_ digits: String) -> MathNode { .number(digits) }
    private func bin(_ op: BinaryOperator, _ l: MathNode, _ r: MathNode) -> MathNode { .binary(op, l, r) }
    private func neg(_ x: MathNode) -> MathNode { .unary(.minus, x) }
    private func juxt(_ xs: MathNode...) -> MathNode { .juxtaposition(xs) }
    private func fn(_ name: String, primes: Int = 0, power: MathNode? = nil, base: MathNode? = nil,
                    _ arg: MathNode?) -> MathNode {
        .function(MathFunction(name: name, primes: primes, power: power, base: base), arg)
    }
    private var x: MathNode { id("x") }

    private func assertParses(_ cases: [(String, MathNode)], file: StaticString = #filePath, line: UInt = #line) {
        for (source, expected) in cases {
            XCTAssertEqual(parse(source), expected, "parse(\(source))", file: file, line: line)
        }
    }

    // MARK: - Table rows (PLAN.md §4.3)

    func testArithmeticAndEquality() {
        assertParses([
            ("a + b", bin(.plus, id("a"), id("b"))),
            ("a - b", bin(.minus, id("a"), id("b"))),
            ("a = b", bin(.equals, id("a"), id("b"))),
            ("a + b - c", bin(.minus, bin(.plus, id("a"), id("b")), id("c"))),
        ])
    }

    func testUnaryMinusAtStartAfterEqualsAndAfterBracket() {
        assertParses([
            ("-3", neg(num("3"))),
            ("-x", neg(x)),
            ("x = -3", bin(.equals, x, neg(num("3")))),
            ("(-x)", .group(neg(x))),
            ("-2x + 4 = 0", bin(.equals, bin(.plus, neg(juxt(num("2"), x)), num("4")), num("0"))),
        ])
    }

    func testImplicitMultiplication() {
        assertParses([
            ("2x", juxt(num("2"), x)),
            ("ab", juxt(id("a"), id("b"))),
            ("2(x+1)", juxt(num("2"), .group(bin(.plus, x, num("1"))))),
            ("4ac", juxt(num("4"), id("a"), id("c"))),
        ])
    }

    func testMultiplicationAndDivisionSigns() {
        assertParses([
            ("a \\cdot b", bin(.times, id("a"), id("b"))),
            ("a \\times b", bin(.times, id("a"), id("b"))),
            ("a : b", bin(.divide, id("a"), id("b"))),
            ("a \\div b", bin(.divide, id("a"), id("b"))),
            ("2*3*4", bin(.times, bin(.times, num("2"), num("3")), num("4"))),
            ("a × b", bin(.times, id("a"), id("b"))),
        ])
    }

    func testRelations() {
        assertParses([
            ("a \\neq b", bin(.notEqual, id("a"), id("b"))),
            ("a < b", bin(.less, id("a"), id("b"))),
            ("a > b", bin(.greater, id("a"), id("b"))),
            ("a \\le b", bin(.lessEqual, id("a"), id("b"))),
            ("a \\leq b", bin(.lessEqual, id("a"), id("b"))),
            ("a \\ge b", bin(.greaterEqual, id("a"), id("b"))),
            ("a \\approx b", bin(.approx, id("a"), id("b"))),
            ("a \\pm b", bin(.plusMinus, id("a"), id("b"))),
            ("a ≤ b", bin(.lessEqual, id("a"), id("b"))),
            ("-3 < x \\le 2", bin(.lessEqual, bin(.less, neg(num("3")), x), num("2"))),
        ])
    }

    func testPowers() {
        assertParses([
            ("x^2", .power(x, num("2"))),
            ("x^3", .power(x, num("3"))),
            ("x^n", .power(x, id("n"))),
            ("x^{-1}", .power(x, neg(num("1")))),
            ("e^{2x+1}", .power(id("e"), bin(.plus, juxt(num("2"), x), num("1")))),
            ("(x+1)^2", .power(.group(bin(.plus, x, num("1"))), num("2"))),
            ("x²", .power(x, num("2"))),
            ("x⁻¹", .power(x, neg(num("1")))),
        ])
    }

    func testFractions() {
        assertParses([
            ("\\frac{1}{2}", .fraction(num("1"), num("2"))),
            ("\\frac{3}{4}", .fraction(num("3"), num("4"))),
            ("\\frac{a}{b}", .fraction(id("a"), id("b"))),
            ("\\frac{x+1}{x-1}", .fraction(bin(.plus, x, num("1")), bin(.minus, x, num("1")))),
            ("\\dfrac{x}{2}", .fraction(x, num("2"))),
            ("\\frac12", .fraction(num("1"), num("2"))),
            ("3/4", bin(.slash, num("3"), num("4"))),
        ])
    }

    func testRoots() {
        assertParses([
            ("\\sqrt{x}", .root(index: nil, x)),
            ("\\sqrt{2}", .root(index: nil, num("2"))),
            ("\\sqrt[3]{x}", .root(index: num("3"), x)),
            ("\\sqrt{x^2+1}", .root(index: nil, bin(.plus, .power(x, num("2")), num("1")))),
            ("√x", .root(index: nil, x)),
            ("∛x", .root(index: num("3"), x)),
        ])
    }

    func testAbsoluteValue() {
        for source in ["|x|", "\\lvert x \\rvert", "\\left\\lvert x \\right\\rvert", "\\left| x \\right|"] {
            XCTAssertEqual(parse(source), .abs(x), source)
        }
        XCTAssertEqual(parse("|x - 1|"), .abs(bin(.minus, x, num("1"))))
        XCTAssertEqual(parse("||x| - 1|"), .abs(bin(.minus, .abs(x), num("1"))))
    }

    func testFactorialAndFunctions() {
        assertParses([
            ("n!", .unary(.factorial, id("n"))),
            ("f(x)", fn("f", x)),
            ("f'(x)", fn("f", primes: 1, x)),
            ("f''(x)", fn("f", primes: 2, x)),
            ("f(x; y)", fn("f", .tuple([x, id("y")]))),
            ("y'", fn("y", primes: 1, nil)),
            ("x(x+1)", juxt(x, .group(bin(.plus, x, num("1"))))),
        ])
    }

    func testTrigonometryAndLogarithms() {
        assertParses([
            ("\\sin x", fn("sin", x)),
            ("\\cos x", fn("cos", x)),
            ("\\tan x", fn("tan", x)),
            ("\\cot x", fn("cot", x)),
            ("\\sin^2 x", fn("sin", power: num("2"), x)),
            ("\\sin 2x", fn("sin", juxt(num("2"), x))),
            ("\\sin x \\cos x", juxt(fn("sin", x), fn("cos", x))),
            ("\\sin(x+1)", fn("sin", bin(.plus, x, num("1")))),
            ("sin x", fn("sin", x)),
            ("\\log_2 8", fn("log", base: num("2"), num("8"))),
            ("\\log x", fn("log", x)),
            ("\\ln x", fn("ln", x)),
            ("e^x", .power(id("e"), x)),
        ])
    }

    func testIntegrals() {
        let fx = fn("f", x)
        assertParses([
            ("\\int_0^1 f(x)\\,dx", .integral(kind: .single, lower: num("0"), upper: num("1"), body: fx, variable: x)),
            ("\\int f(x)\\,dx", .integral(kind: .single, lower: nil, upper: nil, body: fx, variable: x)),
            ("\\int_0^1 x e^x\\,dx", .integral(kind: .single, lower: num("0"), upper: num("1"),
                                               body: juxt(x, .power(id("e"), x)), variable: x)),
            ("\\int_{0}^{\\pi} \\sin x \\, dx", .integral(kind: .single, lower: num("0"), upper: id("pi"),
                                                       body: fn("sin", x), variable: x)),
            ("\\int x^2 dx", .integral(kind: .single, lower: nil, upper: nil, body: .power(x, num("2")), variable: x)),
        ])
    }

    func testLimitsAndSums() {
        assertParses([
            ("\\lim_{x \\to 0} \\frac{\\sin x}{x}",
             .limit(variable: x, target: num("0"), body: .fraction(fn("sin", x), x))),
            ("\\lim_{x \\to 0}", .limit(variable: x, target: num("0"), body: nil)),
            ("x \\to +\\infty", bin(.tendsTo, x, .unary(.plus, .symbol("infty")))),
            ("\\sum_{i=1}^{n} a_i", .sum(from: bin(.equals, id("i"), num("1")), to: id("n"), body: .subscript(id("a"), id("i")))),
            ("\\prod_{i=1}^{n} a_i", .product(from: bin(.equals, id("i"), num("1")), to: id("n"), body: .subscript(id("a"), id("i")))),
        ])
    }

    func testSubscripts() {
        assertParses([
            ("x_1", .subscript(x, num("1"))),
            ("u_{n+1}", .subscript(id("u"), bin(.plus, id("n"), num("1")))),
            ("x₁", .subscript(x, num("1"))),
            ("x_1^2", .power(.subscript(x, num("1")), num("2"))),
        ])
    }

    func testGeometry() {
        let ab = juxt(id("A"), id("B"))
        let abc = juxt(id("A"), id("B"), id("C"))
        assertParses([
            ("\\overrightarrow{AB}", .vector(ab)),
            ("\\vec{a}", .vector(id("a"))),
            ("\\widehat{ABC}", .angle(abc)),
            ("\\angle ABC", .angle(abc)),
            ("\\triangle ABC", .triangle(abc)),
            ("AB \\perp CD", bin(.perpendicular, ab, juxt(id("C"), id("D")))),
            ("AB \\parallel CD", bin(.parallel, ab, juxt(id("C"), id("D")))),
            ("\\triangle ABC \\sim \\triangle DEF", bin(.similar, .triangle(abc), .triangle(juxt(id("D"), id("E"), id("F"))))),
            ("A(1; 3)", fn("A", .tuple([num("1"), num("3")]))),
        ])
    }

    func testTextbookTriangleAndSimilarityNotation() {
        // Review B6: "∽" (U+223D), \backsim, and Δ / ∆ + three point letters.
        let similar = bin(.similar, .triangle(juxt(id("A"), id("B"), id("C"))), .triangle(juxt(id("D"), id("E"), id("F"))))
        assertParses([
            ("ΔABC ∽ ΔDEF", similar),
            ("∆ABC ∽ ∆DEF", similar),
            ("△ABC ∽ △DEF", similar),
            ("\\triangle ABC \\backsim \\triangle DEF", similar),
            ("\\Delta ABC \\sim \\Delta DEF", similar),
            // Not three capital letters: the Greek letter stays.
            ("\\Delta x", juxt(id("Delta"), x)),
            ("\\Delta AB", juxt(id("Delta"), id("A"), id("B"))),
            ("\\Delta ABCD", juxt(id("Delta"), id("A"), id("B"), id("C"), id("D"))),
            ("\\Delta = 0", bin(.equals, id("Delta"), num("0"))),
        ])
        XCTAssertEqual(PronunciationDictionary.normalizedKey("∽"), "sim")
    }

    func testSetsAndNumberSets() {
        assertParses([
            ("x \\in A", bin(.elementOf, x, id("A"))),
            ("x \\notin A", bin(.notElementOf, x, id("A"))),
            ("A \\subset B", bin(.subset, id("A"), id("B"))),
            ("A \\cup B", bin(.union, id("A"), id("B"))),
            ("A \\cap B", bin(.intersection, id("A"), id("B"))),
            ("\\emptyset", .symbol("emptyset")),
            ("\\mathbb{R}", .symbol("ℝ")),
            ("\\mathbb{N}", .symbol("ℕ")),
            ("\\mathbb{Z}", .symbol("ℤ")),
            ("\\mathbb{Q}", .symbol("ℚ")),
            ("ℝ", .symbol("ℝ")),
            ("S = \\{\\frac{1}{2}; 2\\}", bin(.equals, id("S"), .set([.fraction(num("1"), num("2")), num("2")]))),
            ("\\{x \\in \\mathbb{R} \\mid x > 0\\}",
             .setBuilder(bin(.elementOf, x, .symbol("ℝ")), bin(.greater, x, num("0")))),
        ])
    }

    func testIntervalsAndTuples() {
        assertParses([
            ("[1; 3]", .interval(lowerClosed: true, num("1"), num("3"), upperClosed: true)),
            ("(1; 3)", .interval(lowerClosed: false, num("1"), num("3"), upperClosed: false)),
            ("[1; 3)", .interval(lowerClosed: true, num("1"), num("3"), upperClosed: false)),
            ("(1; 3]", .interval(lowerClosed: false, num("1"), num("3"), upperClosed: true)),
            ("x \\in [1; 3]", bin(.elementOf, x, .interval(lowerClosed: true, num("1"), num("3"), upperClosed: true))),
            ("(x; y) = (1; 2)", bin(.equals, .tuple([x, id("y")]), .tuple([num("1"), num("2")]))),
            // Review B3: the coordinates of a vector; a solution set or a domain stays an interval.
            ("\\vec{u} = (1; 2)", bin(.equals, .vector(id("u")), .tuple([num("1"), num("2")]))),
            ("\\overrightarrow{AB} = (3; -4)",
             bin(.equals, .vector(juxt(id("A"), id("B"))), .tuple([num("3"), neg(num("4"))]))),
            ("S = (2; +\\infty)", bin(.equals, id("S"), .interval(lowerClosed: false, num("2"),
                                                                 .unary(.plus, .symbol("infty")), upperClosed: false))),
            ("M = (1; 2)", bin(.equals, id("M"), .interval(lowerClosed: false, num("1"), num("2"), upperClosed: false))),
        ])
    }

    func testLogicAndSymbols() {
        assertParses([
            ("\\forall x", juxt(.symbol("forall"), x)),
            ("\\exists x", juxt(.symbol("exists"), x)),
            ("a \\Rightarrow b", bin(.implies, id("a"), id("b"))),
            ("a \\Leftrightarrow b", bin(.iff, id("a"), id("b"))),
            ("\\infty", .symbol("infty")),
            ("\\Delta", id("Delta")),
            ("\\alpha", id("alpha")),
            ("\\beta", id("beta")),
            ("\\pi", id("pi")),
            ("Δ", id("Delta")),
            ("\\Rightarrow x = 2", bin(.implies, .empty, bin(.equals, x, num("2")))),
        ])
    }

    func testColonsAfterANameOrAQuantifier() {
        let line = bin(.equals, bin(.minus, bin(.plus, x, juxt(num("2"), id("y"))), num("3")), num("0"))
        let real = MathNode.symbol("ℝ")
        assertParses([
            ("d: x + 2y - 3 = 0", .list([id("d"), line], separator: ":")),
            ("(P): x + 2y - 3 = 0", .list([.group(id("P")), line], separator: ":")),
            ("\\Delta_2: x + 2y - 3 = 0", .list([.subscript(id("Delta"), num("2")), line], separator: ":")),
            ("(\\alpha): x + 2y - 3 = 0", .list([.group(id("alpha")), line], separator: ":")),
            ("\\exists x \\in \\mathbb{R}: x^2 < 0",
             bin(.suchThat, bin(.elementOf, juxt(.symbol("exists"), x), real), bin(.less, .power(x, num("2")), num("0")))),
            ("\\forall x \\in \\mathbb{R}: x^2 \\ge 0",
             .list([bin(.elementOf, juxt(.symbol("forall"), x), real), bin(.greaterEqual, .power(x, num("2")), num("0"))],
                   separator: ",")),
            // Division: no relation after the name, a name that is not d / Δ / (…), a colon inside braces.
            ("d : x + 1", bin(.plus, bin(.divide, id("d"), x), num("1"))),
            ("x : 3 = 4", bin(.equals, bin(.divide, x, num("3")), num("4"))),
            ("(x+1) : 2 = 3", bin(.equals, bin(.divide, .group(bin(.plus, x, num("1"))), num("2")), num("3"))),
            ("\\{x \\in \\mathbb{R} : x > 0\\}", .setBuilder(bin(.elementOf, x, real), bin(.greater, x, num("0")))),
        ])
        XCTAssertEqual(MathParser.parseWithDiagnostics("\\exists x: \\foo{x} = 1").warnings, ["foo"],
                       "warnings of both sides of a quantifier colon are kept")
    }

    func testDegreesPercentAndDecimals() {
        assertParses([
            ("30^\\circ", .unary(.degree, num("30"))),
            ("30^{\\circ}", .unary(.degree, num("30"))),
            ("30°", .unary(.degree, num("30"))),
            ("50\\%", .unary(.percent, num("50"))),
            ("2.5", num("2.5")),
            ("2,5", num("2.5")),
            ("2{,}5", num("2.5")),
            ("1.000.000", num("1000000")),
        ])
        // In English answers a comma is not a decimal separator.
        XCTAssertEqual(MathParser.parse("2,5", decimalComma: false), .list([num("2"), num("5")], separator: ","))
        XCTAssertEqual(MathParser.parse("1,000", decimalComma: false), num("1000"))
    }

    func testCombinatorics() {
        assertParses([
            ("C_5^2", .combination(n: num("5"), k: num("2"))),
            ("C^2_5", .combination(n: num("5"), k: num("2"))),
            ("\\binom{5}{2}", .combination(n: num("5"), k: num("2"))),
            ("A_5^2", .arrangement(n: num("5"), k: num("2"))),
        ])
    }

    func testCasesAndMatrices() {
        let system = MathNode.cases([
            [bin(.equals, bin(.plus, x, id("y")), num("3"))],
            [bin(.equals, bin(.minus, x, id("y")), num("1"))],
        ])
        XCTAssertEqual(parse("\\begin{cases} x+y=3 \\\\ x-y=1 \\end{cases}"), system)
        XCTAssertEqual(parse("\\left\\{ \\begin{array}{l} x+y=3 \\\\ x-y=1 \\end{array} \\right."), system)
        XCTAssertEqual(parse("\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}"),
                       .matrix([[num("1"), num("2")], [num("3"), num("4")]], style: .matrix))
        XCTAssertEqual(parse("\\left[ \\begin{array}{l} x=1 \\\\ x=2 \\end{array} \\right."),
                       .alternatives([[bin(.equals, x, num("1"))], [bin(.equals, x, num("2"))]]))
        XCTAssertEqual(parse("\\begin{cases} x^2 & \\text{nếu } x \\ge 0 \\\\ -x & \\text{nếu } x < 0 \\end{cases}"),
                       .cases([
                           [.power(x, num("2")), bin(.greaterEqual, juxt(.text("nếu "), x), num("0"))],
                           [neg(x), bin(.less, juxt(.text("nếu "), x), num("0"))],
                       ]))
    }

    func testUnits() {
        assertParses([
            ("5 cm", juxt(num("5"), .unit("cm"))),
            ("3 m/s", juxt(num("3"), .unit("m/s"))),
            ("60 km/h", juxt(num("60"), .unit("km/h"))),
            ("2 kg", juxt(num("2"), .unit("kg"))),
            ("12 cm^2", juxt(num("12"), .unit("cm^2"))),
            ("5\\,\\text{cm}", juxt(num("5"), .unit("cm"))),
            ("AB = 5 m", bin(.equals, juxt(id("A"), id("B")), juxt(num("5"), .unit("m")))),
            // A letter glued to a number is a variable, not a unit.
            ("2m", juxt(num("2"), id("m"))),
            // Review B4: a text or roman unit takes its exponent.
            ("12\\text{ cm}^2", juxt(num("12"), .unit("cm^2"))),
            ("12\\ \\mathrm{cm}^{2}", juxt(num("12"), .unit("cm^2"))),
            ("9{,}8\\,\\text{m/s}^2", juxt(num("9.8"), .unit("m/s^2"))),
        ])
    }

    func testTextAndUnknownCommands() {
        XCTAssertEqual(parse("\\text{nếu }"), .text("nếu "))
        let result = MathParser.parseWithDiagnostics("\\foo{x}")
        XCTAssertEqual(result.node, .unknown("foo", [x]))
        XCTAssertEqual(result.warnings, ["foo"])
        XCTAssertEqual(MathParser.parseWithDiagnostics("\\partial f").warnings, ["partial"])
        XCTAssertEqual(parse("x = 2 hoặc x = 3"),
                       bin(.equals, bin(.equals, x, juxt(num("2"), .text("hoặc"), x)), num("3")))
    }

    func testH13SamplesParse() {
        assertParses([
            ("x^2 - 5x + 6 = 0", bin(.equals, bin(.plus, bin(.minus, .power(x, num("2")), juxt(num("5"), x)), num("6")), num("0"))),
            ("\\log_2 8 = 3", bin(.equals, fn("log", base: num("2"), num("8")), num("3"))),
            ("f'(x) = 3x^2 - 3", bin(.equals, fn("f", primes: 1, x), bin(.minus, juxt(num("3"), .power(x, num("2"))), num("3")))),
            ("\\Delta = b^2 - 4ac", bin(.equals, id("Delta"), bin(.minus, .power(id("b"), num("2")), juxt(num("4"), id("a"), id("c"))))),
            ("C_5^2 = 10", bin(.equals, .combination(n: num("5"), k: num("2")), num("10"))),
            ("\\overrightarrow{AB} \\perp \\overrightarrow{CD}",
             bin(.perpendicular, .vector(juxt(id("A"), id("B"))), .vector(juxt(id("C"), id("D"))))),
        ])
    }

    // MARK: - Robustness

    func testBrokenInputNeverCrashes() {
        let broken = [
            "", " ", "\\", "{", "}", "}}}", "(((x", "x)))", "\\frac", "\\frac{1}{", "\\frac{1", "\\sqrt", "\\sqrt[",
            "|x", "||||", "x^", "_", "^^^", "\\begin{cases} x", "\\end{cases}", "\\left(", "\\right)", "\\left.",
            "$", "&&&", "\\\\\\\\", "[1;", "(1; 3", "\\lim_", "\\int", "\\int_0^", "\\sum^", "a/", "/b", "=", "==",
            "\\{", "\\}", "\\{1; 2", "\\mathbb{}", "\\vec", "\\text{", "\\operatorname{", "\\left[ \\begin{array}",
            "C_", "A^", "f(", "f'", "''", "!!", "%%", "2{,}", "2,", ".5", "1.2.3", "x \\to", "\\binom{1}",
            String(repeating: "(", count: 500), String(repeating: "{", count: 500), String(repeating: "|", count: 300),
            String(repeating: "-", count: 300) + "x", String(repeating: "\\sqrt{", count: 200),
            String(repeating: "x^", count: 200), String(repeating: "\\frac{", count: 150),
        ]
        for source in broken {
            _ = MathParser.parseWithDiagnostics(source)
            _ = MathSpanSplitter.split(source)
        }
        XCTAssertEqual(parse(""), .empty)
        XCTAssertEqual(parse("   "), .empty)
        XCTAssertEqual(parse("\\frac{1}{"), .fraction(num("1"), .empty))
        XCTAssertEqual(parse("(x+1"), .group(bin(.plus, x, num("1"))))
        XCTAssertEqual(parse("x)"), x)
    }

    // MARK: - Splitter

    func testDelimitedSpans() {
        XCTAssertEqual(MathSpanSplitter.split("Ta có $x = 2$."), [.prose("Ta có "), .math("x = 2"), .prose(".")])
        XCTAssertEqual(MathSpanSplitter.split("\\(a+b\\) và \\[c\\]"), [.math("a+b"), .prose(" và "), .math("c")])
        XCTAssertEqual(MathSpanSplitter.split("$$x^2$$"), [.math("x^2")])
        XCTAssertEqual(MathSpanSplitter.split("Giá 5 \\$ thôi"), [.prose("Giá 5   thôi")])
        // A lone dollar is dropped; the rest stays prose.
        XCTAssertEqual(MathSpanSplitter.split("có $5 đồng"), [.prose("có 5 đồng")])
    }

    func testBareFormulasInProse() {
        XCTAssertEqual(MathSpanSplitter.split("Ta có x² - 5x + 6 = 0 nên"), [.prose("Ta có "), .math("x² - 5x + 6 = 0"), .prose(" nên")])
        XCTAssertEqual(MathSpanSplitter.split("tính x^2 nhé"), [.prose("tính "), .math("x^2"), .prose(" nhé")])
        XCTAssertEqual(MathSpanSplitter.split("lấy 3/4 số kẹo"), [.prose("lấy "), .math("3/4"), .prose(" số kẹo")])
        XCTAssertEqual(MathSpanSplitter.split("Vậy f(x) = 2x + 1."), [.prose("Vậy "), .math("f(x) = 2x + 1"), .prose(".")])
        XCTAssertEqual(MathSpanSplitter.split("-2x + 4 = 0"), [.math("-2x + 4 = 0")])
        XCTAssertEqual(MathSpanSplitter.split("2*3*4"), [.math("2*3*4")])
        XCTAssertEqual(MathSpanSplitter.split("Vì x \\le 2 nên"), [.prose("Vì "), .math("x \\le 2"), .prose(" nên")])
        XCTAssertEqual(MathSpanSplitter.split("Đáp án A. 2x + 1"), [.prose("Đáp án A. "), .math("2x + 1")])
    }

    func testLabelsNeverStartABareFormula() {
        // A chunk ending with ":" is a label (review X1), like "1.", "100." and "b)".
        XCTAssertEqual(MathSpanSplitter.split("Câu 12: 3/4."), [.prose("Câu 12: "), .math("3/4"), .prose(".")])
        XCTAssertEqual(MathSpanSplitter.split("Câu 12: x = 2."), [.prose("Câu 12: "), .math("x = 2"), .prose(".")])
        XCTAssertEqual(MathSpanSplitter.split("TH1: x ≥ 0."), [.prose("TH1: "), .math("x ≥ 0"), .prose(".")])
        XCTAssertEqual(MathSpanSplitter.split("Question 12: 3/4.", vietnamese: false),
                       [.prose("Question 12: "), .math("3/4"), .prose(".")])
        XCTAssertEqual(MathSpanSplitter.split("Dòng 100. x = 2."), [.prose("Dòng 100. "), .math("x = 2"), .prose(".")])
        XCTAssertEqual(MathSpanSplitter.split("b) x = 2"), [.prose("b) "), .math("x = 2")])
        XCTAssertEqual(MathSpanSplitter.split("12) x = 2"), [.prose("12) "), .math("x = 2")])
        // A chunk with math before its colon stays in the formula.
        XCTAssertEqual(MathSpanSplitter.split("Δ: x - y + 1 = 0"), [.math("Δ: x - y + 1 = 0")])
        // A label inside a formula is not cut out; four digits are not a label.
        XCTAssertEqual(MathSpanSplitter.split("x = 100. y = 2"), [.math("x = 100. y = 2")])
        XCTAssertEqual(MathSpanSplitter.split("1000. x = 2"), [.math("1000. x = 2")])
        for prose in ["Câu 4: -2,5.", "Lúc 10:30 sáng.", "Tỉ số 3:2.", "Câu 12: 5."] {
            XCTAssertEqual(MathSpanSplitter.split(prose), [.prose(prose)], prose)
        }
    }

    func testProseThatIsNotAFormula() {
        for prose in ["Câu 1-5 làm trước.", "Kính Ray-Ban Meta", "Ngày 12/5/2026 thi", "Lúc 10:30 sáng",
                      "Câu 3: a đúng, b sai.", "Dài 2,5 cm", "Giảm 50%", "Góc 30°", "Đáp số: -3",
                      "COVID-19", "phiên bản 2.14.0", "ngày 12/5 có lịch"] {
            XCTAssertEqual(MathSpanSplitter.split(prose), [.prose(prose)], prose)
        }
    }

    func testMarkdownEmphasisIsNotMultiplication() {
        XCTAssertEqual(MathSpanSplitter.split("Đáp số **2,5**"), [.prose("Đáp số 2,5")])
        XCTAssertEqual(MathSpanSplitter.split("*Chú ý*: x = 2"), [.prose("Chú ý: "), .math("x = 2")])
        XCTAssertEqual(MathSpanSplitter.stripMarkdown("a * b và 2*3"), "a * b và 2*3")
    }
}
