// OpenVision - VietMathSpeechTests.swift
// VietMathSpeech readings (PLAN.md §4.3, tasks T3.2/T3.3): every row of the reading table in both
// verbosities and both letter styles, the 15 samples of H13, the pronunciation dictionary, the
// reading style settings and the output constraints.

import XCTest
@testable import OpenVision

final class VietMathSpeechTests: XCTestCase {

    // MARK: - Helpers

    private let asWritten = MathReadingStyle(letterStyle: .asWritten)
    private let explicitAsWritten = MathReadingStyle(verbosity: .explicit, letterStyle: .asWritten)
    private let explicitNames = MathReadingStyle(verbosity: .explicit, letterStyle: .vietnameseNames)

    /// Words joined by spaces; a pause is shown as "|".
    private func reading(_ text: String, _ style: MathReadingStyle = .default, vietnamese: Bool = true) -> String {
        VietMathSpeech.render(text, vietnamese: vietnamese, style: style).map { piece -> String in
            switch piece {
            case .words(let words, _): return words
            case .pause: return "|"
            }
        }.joined(separator: " ")
    }

    /// The letter names of PLAN.md §4.3 (written out here, independent of PronunciationDictionary).
    private static let planLetterNames: [String: String] = [
        "a": "a", "b": "bê", "c": "xê", "d": "đê", "e": "e", "f": "ép", "g": "giê", "h": "hát", "i": "i",
        "j": "gi", "k": "ca", "l": "lờ", "m": "mờ", "n": "nờ", "o": "o", "p": "pê", "q": "quy", "r": "rờ",
        "s": "ét", "t": "tê", "u": "u", "v": "vê", "w": "vê kép", "x": "ích", "y": "i", "z": "dét",
    ]

    /// The table writes variables as letters; with `vietnameseNames` each single letter becomes its name.
    private func withLetterNames(_ expected: String) -> String {
        expected.split(separator: " ", omittingEmptySubsequences: false).map { token -> String in
            var core = String(token)
            var tail = ""
            while let last = core.last, [",", ";", ":"].contains(last) {
                tail = String(last) + tail
                core.removeLast()
            }
            guard core.count == 1, let name = Self.planLetterNames[core.lowercased()] else { return String(token) }
            return name + tail
        }.joined(separator: " ")
    }

    private struct Row {
        let input: String
        /// Natural reading with letters as written (the table's notation).
        let natural: String
        /// Explicit reading when it differs.
        let explicit: String?
        let line: UInt
    }

    private func row(_ input: String, _ natural: String, explicit: String? = nil, line: UInt = #line) -> Row {
        Row(input: input, natural: natural, explicit: explicit, line: line)
    }

    private func check(_ rows: [Row]) {
        for r in rows {
            XCTAssertEqual(reading(r.input, asWritten), r.natural, "natural, asWritten: \(r.input)", line: r.line)
            XCTAssertEqual(reading(r.input, .default), withLetterNames(r.natural),
                           "natural, vietnameseNames: \(r.input)", line: r.line)
            let explicit = r.explicit ?? r.natural
            XCTAssertEqual(reading(r.input, explicitAsWritten), explicit, "explicit, asWritten: \(r.input)", line: r.line)
            XCTAssertEqual(reading(r.input, explicitNames), withLetterNames(explicit),
                           "explicit, vietnameseNames: \(r.input)", line: r.line)
        }
    }

    // MARK: - Reading table (PLAN.md §4.3), one group per row

    func testArithmeticSignsAndNegatives() {
        check([
            row("$a + b$", "a cộng b"),
            row("$a - b$", "a trừ b"),
            row("$a = b$", "a bằng b"),
            row("$-3$", "âm 3"),
            row("$-x$", "âm x"),
            row("$x = -3$", "x bằng âm 3"),
            row("$(-x)$", "âm x"),
            row("$2x$", "2 x"),
            row("$ab$", "a b"),
            row("$2(x+1)$", "2 nhân x cộng 1", explicit: "2 nhân mở ngoặc x cộng 1 đóng ngoặc"),
            row("$2(x+1) + 3$", "2 nhân x cộng 1 | cộng 3", explicit: "2 nhân mở ngoặc x cộng 1 đóng ngoặc cộng 3"),
            row("$a \\cdot b$", "a nhân b"),
            row("$a \\times b$", "a nhân b"),
            row("$a : b$", "a chia b"),
            row("$a \\div b$", "a chia b"),
        ])
    }

    func testRelations() {
        check([
            row("$a \\neq b$", "a khác b"),
            row("$a < b$", "a nhỏ hơn b"),
            row("$a > b$", "a lớn hơn b"),
            row("$a \\le b$", "a nhỏ hơn hoặc bằng b"),
            row("$a \\ge b$", "a lớn hơn hoặc bằng b"),
            row("$a \\approx b$", "a xấp xỉ b"),
            row("$a \\pm b$", "a cộng trừ b"),
        ])
    }

    func testPowers() {
        check([
            row("$x^2$", "x bình phương"),
            row("$x^3$", "x lập phương"),
            row("$x^n$", "x mũ n"),
            row("$x^{-1}$", "x mũ âm 1"),
            row("$e^{2x+1}$", "e mũ 2 x cộng 1", explicit: "e mũ 2 x cộng 1, hết mũ"),
            row("$e^{2x+1} - 1$", "e mũ 2 x cộng 1 | trừ 1", explicit: "e mũ 2 x cộng 1, hết mũ trừ 1"),
            row("$(x+1)^2$", "x cộng 1, tất cả bình phương"),
            row("$(x+1)^3$", "x cộng 1, tất cả lập phương"),
        ])
    }

    func testFractions() {
        check([
            row("$\\frac{1}{2}$", "một phần hai"),
            row("$\\frac{3}{4}$", "ba phần tư"),
            row("$\\frac{1}{10}$", "một phần mười"),
            row("$\\frac{5}{12}$", "năm phần mười hai"),
            row("$-\\frac{1}{2}$", "âm một phần hai"),
            row("$\\frac{a}{b}$", "a trên b"),
            row("$\\frac{x}{2}$", "x trên 2"),
            row("$\\frac{x+1}{x-1}$", "x cộng 1, trên x trừ 1",
                explicit: "phân số, tử số x cộng 1, mẫu số x trừ 1, hết phân số"),
            row("$3/4$", "ba phần tư"),
            row("$a/b$", "a trên b"),
        ])
    }

    func testRoots() {
        check([
            row("$\\sqrt{x}$", "căn x", explicit: "căn bậc hai của x"),
            row("$\\sqrt{2}$", "căn 2", explicit: "căn bậc hai của 2"),
            row("$\\sqrt[3]{x}$", "căn bậc ba của x"),
            row("$\\sqrt{x^2+1}$", "căn của x bình phương cộng 1", explicit: "căn của x bình phương cộng 1, hết căn"),
            row("$\\sqrt{x+1} + 2$", "căn của x cộng 1 | cộng 2", explicit: "căn của x cộng 1, hết căn cộng 2"),
            row("$√x$", "căn x", explicit: "căn bậc hai của x"),
        ])
    }

    func testAbsoluteValueAndFactorial() {
        check([
            row("$|x|$", "giá trị tuyệt đối của x"),
            row("$\\lvert x \\rvert$", "giá trị tuyệt đối của x"),
            row("$\\left\\lvert x \\right\\rvert$", "giá trị tuyệt đối của x"),
            row("$n!$", "n giai thừa"),
        ])
    }

    func testFunctions() {
        check([
            row("$f(x)$", "f x", explicit: "f của x"),
            row("$f'(x)$", "f phẩy x", explicit: "f phẩy của x"),
            row("$f''(x)$", "f hai phẩy x", explicit: "f hai phẩy của x"),
            row("$\\sin x$", "sin x"),
            row("$\\cos x$", "cốt x"),
            row("$\\tan x$", "tang x"),
            row("$\\cot x$", "cô-tang x"),
            row("$\\sin^2 x$", "sin bình phương x"),
            row("$\\log_2 8$", "lô-ga-rít cơ số 2 của 8"),
            row("$\\log x$", "lốc x"),
            row("$\\ln x$", "lốc nê-pe của x"),
            row("$e^x$", "e mũ x"),
        ])
    }

    func testIntegralsLimitsAndSums() {
        check([
            row("$\\int_0^1 f(x)\\,dx$", "tích phân từ 0 đến 1 của f x, đê x",
                explicit: "tích phân từ 0 đến 1 của f của x, đê x"),
            row("$\\int f(x)\\,dx$", "nguyên hàm của f x, đê x", explicit: "nguyên hàm của f của x, đê x"),
            row("$\\lim_{x \\to 0}$", "giới hạn khi x tiến tới 0 của"),
            row("$x \\to +\\infty$", "x tiến tới dương vô cùng"),
            row("$\\sum_{i=1}^{n} a_i$", "tổng từ i bằng 1 đến n của a i",
                explicit: "tổng từ i bằng 1 đến n của a chỉ số i"),
        ])
    }

    func testSubscripts() {
        check([
            row("$x_1$", "x một", explicit: "x chỉ số 1"),
            row("$u_{n+1}$", "u n cộng 1", explicit: "u chỉ số n cộng 1"),
        ])
    }

    func testGeometry() {
        check([
            row("$\\overrightarrow{AB}$", "véc-tơ A B"),
            row("$\\vec{a}$", "véc-tơ a"),
            row("$\\widehat{ABC}$", "góc A B C"),
            row("$\\angle ABC$", "góc A B C"),
            row("$\\triangle ABC$", "tam giác A B C"),
            row("$AB \\perp CD$", "A B vuông góc với C D"),
            row("$AB \\parallel CD$", "A B song song với C D"),
            row("$\\triangle ABC \\sim \\triangle DEF$", "tam giác A B C đồng dạng với tam giác D E F"),
        ])
    }

    func testSets() {
        check([
            row("$x \\in A$", "x thuộc A"),
            row("$x \\notin A$", "x không thuộc A"),
            row("$A \\subset B$", "A là tập con của B"),
            row("$A \\cup B$", "A hợp B"),
            row("$A \\cap B$", "A giao B"),
            row("$\\emptyset$", "tập rỗng"),
            row("$\\mathbb{R}$", "tập số thực"),
            row("$\\mathbb{N}$", "tập số tự nhiên"),
            row("$\\mathbb{Z}$", "tập số nguyên"),
            row("$\\mathbb{Q}$", "tập số hữu tỉ"),
            row("$[1; 3]$", "đoạn từ 1 đến 3"),
            row("$(1; 3)$", "khoảng từ 1 đến 3"),
            row("$[1; 3)$", "nửa khoảng từ 1 đến 3"),
        ])
    }

    func testLogicAndGreekLetters() {
        check([
            row("$\\forall x$", "với mọi x"),
            row("$\\exists x$", "tồn tại x"),
            row("$a \\Rightarrow b$", "a suy ra b"),
            row("$a \\Leftrightarrow b$", "a tương đương b"),
            row("$\\infty$", "vô cùng"),
            row("$\\Delta$", "đen-ta"),
            row("$\\alpha$", "an-pha"),
            row("$\\beta$", "bê-ta"),
            row("$\\pi$", "pi"),
        ])
    }

    func testDegreesPercentAndDecimals() {
        check([
            row("$30^\\circ$", "30 độ"),
            row("30°", "30 độ"),
            row("$50\\%$", "50 phần trăm"),
            row("$2.5$", "2 phẩy 5"),
            row("$2,5$", "2 phẩy 5"),
            row("$2{,}5$", "2 phẩy 5"),
        ])
    }

    func testCombinatorics() {
        check([
            row("$C_5^2$", "tổ hợp chập 2 của 5"),
            row("$\\binom{5}{2}$", "tổ hợp chập 2 của 5"),
            row("$A_5^2$", "chỉnh hợp chập 2 của 5"),
        ])
    }

    func testSystemsAndMatrices() {
        check([
            row("$\\begin{cases} x+y=3 \\\\ x-y=1 \\end{cases}$", "hệ phương trình: x cộng y bằng 3; x trừ y bằng 1",
                explicit: "hệ gồm 2 phương trình: thứ nhất, x cộng y bằng 3; thứ hai, x trừ y bằng 1"),
            row("$\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}$", "ma trận 2 hàng 2 cột: hàng 1: 1, 2; hàng 2: 3, 4"),
        ])
    }

    func testUnitsTextAndUnknownCommands() {
        check([
            row("5 cm", "5 xen-ti-mét"),
            row("3 m/s", "3 mét trên giây"),
            row("60 km/h", "60 ki-lô-mét trên giờ"),
            row("2 kg", "2 ki-lô-gam"),
            row("$5\\,\\text{cm}$", "5 xen-ti-mét"),
            row("$v = 3 m/s$", "v bằng 3 mét trên giây"),
            row("$\\text{nếu }$", "nếu"),
            row("$\\foo{x}$", "x"),
        ])
        let rendering = VietMathSpeech.renderWithDiagnostics("$\\foo{x}$", vietnamese: true, style: .default)
        XCTAssertEqual(rendering.warnings, ["foo"], "unknown commands are reported for the debug screen")
    }

    // MARK: - H13 samples (PLAN.md §7), both letter styles

    private let h13: [(input: String, asWritten: String, names: String)] = [
        ("$x^2 - 5x + 6 = 0$", "x bình phương trừ 5 x cộng 6 bằng 0", "ích bình phương trừ 5 ích cộng 6 bằng 0"),
        ("$\\frac{3}{4}$", "ba phần tư", "ba phần tư"),
        ("$\\sqrt{x^2+1}$", "căn của x bình phương cộng 1", "căn của ích bình phương cộng 1"),
        ("$\\int_0^1 x e^x\\,dx$", "tích phân từ 0 đến 1 của x e mũ x, đê x",
         "tích phân từ 0 đến 1 của ích e mũ ích, đê ích"),
        ("$\\lim_{x \\to 0} \\frac{\\sin x}{x} = 1$", "giới hạn khi x tiến tới 0 của sin x trên x bằng 1",
         "giới hạn khi ích tiến tới 0 của sin ích trên ích bằng 1"),
        ("$\\log_2 8 = 3$", "lô-ga-rít cơ số 2 của 8 bằng 3", "lô-ga-rít cơ số 2 của 8 bằng 3"),
        ("$f'(x) = 3x^2 - 3$", "f phẩy x bằng 3 x bình phương trừ 3", "ép phẩy ích bằng 3 ích bình phương trừ 3"),
        ("$\\overrightarrow{AB} \\perp \\overrightarrow{CD}$", "véc-tơ A B vuông góc với véc-tơ C D",
         "véc-tơ a bê vuông góc với véc-tơ xê đê"),
        ("$x \\in [1; 3]$", "x thuộc đoạn từ 1 đến 3", "ích thuộc đoạn từ 1 đến 3"),
        ("$\\Delta = b^2 - 4ac$", "đen-ta bằng b bình phương trừ 4 a c", "đen-ta bằng bê bình phương trừ 4 a xê"),
        ("Cạnh dài 2,5 cm.", "Cạnh dài 2 phẩy 5 xen-ti-mét.", "Cạnh dài 2 phẩy 5 xen-ti-mét."),
        ("$(x+1)^2$", "x cộng 1, tất cả bình phương", "ích cộng 1, tất cả bình phương"),
        ("$\\begin{cases} x+y=3 \\\\ x-y=1 \\end{cases}$", "hệ phương trình: x cộng y bằng 3; x trừ y bằng 1",
         "hệ phương trình: ích cộng i bằng 3; ích trừ i bằng 1"),
        ("$C_5^2 = 10$", "tổ hợp chập 2 của 5 bằng 10", "tổ hợp chập 2 của 5 bằng 10"),
        ("$-3 < x \\le 2$", "âm 3 nhỏ hơn x nhỏ hơn hoặc bằng 2", "âm 3 nhỏ hơn ích nhỏ hơn hoặc bằng 2"),
    ]

    func testH13SamplesAsWritten() {
        XCTAssertEqual(h13.count, 15)
        for sample in h13 {
            XCTAssertEqual(reading(sample.input, asWritten), sample.asWritten, sample.input)
        }
    }

    func testH13SamplesWithVietnameseLetterNames() {
        for sample in h13 {
            XCTAssertEqual(reading(sample.input, .default), sample.names, sample.input)
        }
    }

    func testH13Sample11IsProseAndTheFormulasAreMath() {
        XCTAssertEqual(VietMathSpeech.render("Cạnh dài 2,5 cm.", vietnamese: true, style: .default),
                       [.words("Cạnh dài 2 phẩy 5 xen-ti-mét.", isMath: false)])
        for sample in h13 where sample.input.hasPrefix("$") {
            let pieces = VietMathSpeech.render(sample.input, vietnamese: true, style: .default)
            XCTAssertTrue(pieces.allSatisfy { if case .words(_, let isMath) = $0 { return isMath } else { return true } },
                          sample.input)
        }
    }

    // MARK: - Pieces

    func testAnEssayLineBecomesOnePiecePerSentenceAndFormula() {
        XCTAssertEqual(VietMathSpeech.render("Dòng 1. Ta có $\\Delta = b^2 - 4ac = 9$.", vietnamese: true, style: .default), [
            .words("Dòng 1.", isMath: false),
            .words("Ta có", isMath: false),
            .words("đen-ta bằng bê bình phương trừ 4 a xê bằng 9", isMath: true),
        ])
        XCTAssertEqual(VietMathSpeech.render("Vì $\\Delta > 0$ nên phương trình có hai nghiệm phân biệt.",
                                             vietnamese: true, style: .default), [
            .words("Vì", isMath: false),
            .words("đen-ta lớn hơn 0", isMath: true),
            .words("nên phương trình có hai nghiệm phân biệt.", isMath: false),
        ])
        XCTAssertEqual(VietMathSpeech.render("$x_1 = 2$, $x_2 = \\frac{1}{2}$.", vietnamese: true, style: .default), [
            .words("ích một bằng 2", isMath: true),
            .words("ích hai bằng một phần hai", isMath: true),
        ])
    }

    func testCompoundExponentPausesOnlyWhenTheFormulaGoesOn() {
        XCTAssertEqual(VietMathSpeech.render("$e^{2x+1} - 1$", vietnamese: true, style: asWritten), [
            .words("e mũ 2 x cộng 1", isMath: true),
            .pause(milliseconds: VietMathSpeech.shortPauseMilliseconds),
            .words("trừ 1", isMath: true),
        ])
        XCTAssertEqual(VietMathSpeech.render("$e^{2x+1}$", vietnamese: true, style: asWritten),
                       [.words("e mũ 2 x cộng 1", isMath: true)])
    }

    func testMultipleChoiceAnswersReadLetterNames() {
        XCTAssertEqual(reading("Câu 1: A."), "Câu 1: a.")
        XCTAssertEqual(reading("Câu 2: C."), "Câu 2: xê.")
        XCTAssertEqual(reading("Câu 3: a đúng, b sai, c đúng, d sai."), "Câu 3: a đúng, bê sai, xê đúng, đê sai.")
        XCTAssertEqual(reading("Câu 2: C.", asWritten), "Câu 2: C.")
        XCTAssertEqual(reading("Vậy tập nghiệm là $S = \\{\\frac{1}{2}; 2\\}$."),
                       "Vậy tập nghiệm là ét bằng tập hợp gồm một phần hai và 2")
    }

    // MARK: - Letter style

    func testEveryLetterNameMatchesThePlan() {
        for (letter, name) in Self.planLetterNames {
            XCTAssertEqual(reading("$\(letter)$"), name, letter)
            XCTAssertEqual(reading("$\(letter.uppercased())$"), name, "capital \(letter) reads like the small letter")
            XCTAssertEqual(reading("$\(letter)$", asWritten), letter)
            XCTAssertEqual(reading("$\(letter.uppercased())$", asWritten), letter.uppercased())
        }
    }

    // MARK: - Pronunciation dictionary

    func testUserOverridesApplyToWholeTokens() {
        let southern = MathReadingStyle(pronunciationOverrides: ["cos": "cô-sin", "x": "ích-xì", "\\Delta": "đen ta"])
        XCTAssertEqual(reading("$\\cos x$", southern), "cô-sin ích-xì")
        XCTAssertEqual(reading("$X + \\Delta$", southern), "ích-xì cộng đen ta", "capital X falls back to the x entry")
        XCTAssertEqual(reading("$Δ$", southern), "đen ta", "Unicode Δ and \\Delta share one key")
        // Whole tokens only: "co" must not change "cos", "cộng" or "cốt".
        let partial = MathReadingStyle(pronunciationOverrides: ["co": "XX", "c": "cờ"])
        XCTAssertEqual(reading("$\\cos x + c$", partial), "cốt ích cộng cờ")
        // Operators by their command name or symbol.
        let soft = MathReadingStyle(pronunciationOverrides: ["≤": "bé hơn hoặc bằng", "\\in": "nằm trong"])
        XCTAssertEqual(reading("$x \\le 2$", soft), "ích bé hơn hoặc bằng 2")
        XCTAssertEqual(reading("$x \\leq 2$", soft), "ích bé hơn hoặc bằng 2")
        XCTAssertEqual(reading("$x \\in A$", soft), "ích nằm trong a")
        // Units, number sets and prose words.
        let custom = MathReadingStyle(pronunciationOverrides: ["cm": "phân", "\\mathbb{R}": "R", "Ray-Ban": "rây ban"])
        XCTAssertEqual(reading("Dài 5 cm.", custom), "Dài 5 phân.")
        XCTAssertEqual(reading("$x \\in \\mathbb{R}$", custom), "ích thuộc R")
        XCTAssertEqual(reading("Kính Ray-Ban Meta.", custom), "Kính rây ban Meta.")
        // An empty reading is ignored rather than silencing the token.
        XCTAssertEqual(reading("$x$", MathReadingStyle(pronunciationOverrides: ["x": "  "])), "ích")
    }

    func testDictionaryKeyNormalisation() {
        XCTAssertEqual(PronunciationDictionary.normalizedKey(" \\cos "), "cos")
        XCTAssertEqual(PronunciationDictionary.normalizedKey("Δ"), "Delta")
        XCTAssertEqual(PronunciationDictionary.normalizedKey("\\leq"), "le")
        XCTAssertEqual(PronunciationDictionary.normalizedKey("≤"), "le")
        XCTAssertEqual(PronunciationDictionary.normalizedKey("\\mathbb{R}"), "ℝ")
        XCTAssertEqual(PronunciationDictionary.normalizedKey("\\varepsilon"), "epsilon")
        XCTAssertFalse(PronunciationDictionary.defaultEntries.isEmpty)
        for category in PronunciationDictionary.Category.allCases {
            XCTAssertTrue(PronunciationDictionary.defaultEntries.contains { $0.category == category }, "\(category)")
        }
    }

    func testEveryUnitAndGreekLetterHasAVietnameseReading() {
        for unit in MathParser.unitSymbols {
            XCTAssertNotNil(PronunciationDictionary.units[unit], unit)
        }
        for name in Set(MathLexer.greekNames.values) {
            XCTAssertNotNil(PronunciationDictionary.greek[name], name)
        }
        XCTAssertEqual(reading("$\\gamma + \\theta + \\lambda + \\mu + \\sigma + \\omega + \\Omega$"),
                       "gam-ma cộng tê-ta cộng lam-đa cộng muy cộng xích-ma cộng ô-mê-ga cộng ô-mê-ga")
    }

    // MARK: - Reading style

    func testStyleOptions() {
        let phan = MathReadingStyle(symbolicFraction: .phan)
        XCTAssertEqual(reading("$\\frac{a}{b}$", phan), "a phần bê")
        XCTAssertEqual(reading("$\\frac{1}{2}$", phan), "một phần hai", "numeric fractions always say phần")
        XCTAssertEqual(reading("$\\frac{x+1}{x-1}$", phan), "ích cộng 1, phần ích trừ 1")
        let tru = MathReadingStyle(negativeWord: .tru)
        XCTAssertEqual(reading("$-3 < x$", tru), "trừ 3 nhỏ hơn ích")
        XCTAssertEqual(reading("$x - 3$", tru), "ích trừ 3")
    }

    func testStyleFromRawSettings() {
        XCTAssertEqual(MathReadingStyle.default, MathReadingStyle(verbosity: .natural, symbolicFraction: .tren,
                                                                 negativeWord: .am, letterStyle: .vietnameseNames))
        let parsed = MathReadingStyle(mathVerbosity: "explicit", symbolicFractionWord: "phan", negativeWord: "tru",
                                      letterStyle: "asWritten", pronunciationOverrides: ["x": "ích-xì"])
        XCTAssertEqual(parsed, MathReadingStyle(verbosity: .explicit, symbolicFraction: .phan, negativeWord: .tru,
                                                letterStyle: .asWritten, pronunciationOverrides: ["x": "ích-xì"]))
        let unknown = MathReadingStyle(mathVerbosity: "loud", symbolicFractionWord: "", negativeWord: "minus",
                                       letterStyle: "emoji")
        XCTAssertEqual(unknown, .default, "unknown values fall back to the defaults (N18)")
        let lenient = MathReadingStyle(mathVerbosity: " Natural ", symbolicFractionWord: "phần", negativeWord: "trừ",
                                       letterStyle: "VIETNAMESENAMES")
        XCTAssertEqual(lenient, MathReadingStyle(symbolicFraction: .phan, negativeWord: .tru))
    }

    // MARK: - Vietnamese numbers

    func testSpelledNumbers() {
        let expected: [Int: String] = [
            0: "không", 1: "một", 4: "bốn", 5: "năm", 10: "mười", 11: "mười một", 15: "mười lăm", 20: "hai mươi",
            21: "hai mươi mốt", 24: "hai mươi bốn", 25: "hai mươi lăm", 100: "một trăm", 105: "một trăm linh năm",
            110: "một trăm mười", 999: "chín trăm chín mươi chín", 1000: "một nghìn",
            1005: "một nghìn không trăm linh năm", 2024: "hai nghìn không trăm hai mươi bốn",
            1_000_000: "một triệu", 1_200_000: "một triệu hai trăm nghìn",
        ]
        for (value, words) in expected {
            XCTAssertEqual(VietnameseMathReader.spell(value), words, "\(value)")
        }
        XCTAssertEqual(reading("$\\frac{1}{100}$"), "một phần một trăm")
        XCTAssertEqual(reading("$\\frac{7}{15}$"), "bảy phần mười lăm")
        XCTAssertEqual(reading("$x_{12}$"), "ích mười hai")
        XCTAssertEqual(reading("$\\sqrt[4]{x}$"), "căn bậc bốn của ích")
    }

    // MARK: - Constraints (PLAN.md §4.3)

    func testOutputNeverContainsLatexCharacters() {
        let samples = h13.map(\.input) + [
            "$\\frac{1}{2}$ và $\\sqrt{x}$", "\\[ x = 2 \\]", "$\\boxed{B}$", "$\\{1; 2\\}$", "$a_{i,j}^{2}$",
            "$\\left\\{ \\begin{array}{l} x=1 \\\\ y=2 \\end{array} \\right.$", "$x^{y^{z}}$", "$\\$5$", "\\$",
            "$\\text{\\{a\\}}$", "a_b ^ c {d} \\e $", "$\\unknown_{x}^{y}$",
        ]
        for sample in samples {
            for style in [MathReadingStyle.default, explicitAsWritten] {
                for piece in VietMathSpeech.render(sample, vietnamese: true, style: style) {
                    guard case .words(let text, _) = piece else { continue }
                    XCTAssertFalse(text.contains { VietMathSpeech.forbiddenCharacters.contains($0) }, "\(sample) → \(text)")
                }
            }
        }
    }

    func testEveryPieceIsAtMost200Characters() {
        let longProse = String(repeating: "Phương trình này có hai nghiệm phân biệt, ", count: 12)
        let longFormula = "$" + (1...60).map { "x_{\($0)}" }.joined(separator: " + ") + "$"
        let noSpaces = String(repeating: "a", count: 450)
        for text in [longProse, longFormula, noSpaces, longProse + longFormula] {
            let pieces = VietMathSpeech.render(text, vietnamese: true, style: .default)
            XCTAssertFalse(pieces.isEmpty)
            for piece in pieces {
                if case .words(let words, _) = piece {
                    XCTAssertLessThanOrEqual(words.count, VietMathSpeech.maxPieceLength, words)
                    XCTAssertFalse(words.isEmpty)
                }
            }
        }
        // Long prose is cut at a comma, not in the middle of a word.
        let pieces = VietMathSpeech.render(longProse, vietnamese: true, style: .default)
        if case .words(let first, _)? = pieces.first { XCTAssertTrue(first.hasSuffix(","), first) }
    }

    func testVietnameseProseWithoutFormulasPassesThroughUnchanged() {
        for prose in ["Phương trình có hai nghiệm phân biệt.", "Vậy đáp án đúng là câu này.",
                      "Kính Ray-Ban Meta đọc câu trả lời.", "Câu 1-5 làm trước, ngày 12/5/2026 thi.",
                      "Lúc 10:30 sáng, mình gửi đáp án."] {
            XCTAssertEqual(VietMathSpeech.render(prose, vietnamese: true, style: .default), [.words(prose, isMath: false)])
        }
        XCTAssertEqual(VietMathSpeech.render("", vietnamese: true, style: .default), [])
        XCTAssertEqual(VietMathSpeech.render("  \n ", vietnamese: true, style: .default), [])
    }

    func testTypicalStepTakesLessThanFiveMilliseconds() {
        let step = "Dòng 2. Vì $\\Delta = b^2 - 4ac = 25 > 0$ nên phương trình có hai nghiệm phân biệt "
            + "$x_1 = \\frac{-b + \\sqrt{\\Delta}}{2a} = 3$ và $x_2 = \\frac{1}{2}$."
        _ = VietMathSpeech.render(step, vietnamese: true, style: .default)  // warm up static tables
        let runs = 200
        let start = Date()
        for _ in 0..<runs { _ = VietMathSpeech.render(step, vietnamese: true, style: .default) }
        let average = Date().timeIntervalSince(start) / Double(runs)
        XCTAssertLessThan(average, 0.005, "average \(average * 1000) ms per step")
        measure { _ = VietMathSpeech.render(step, vietnamese: true, style: .default) }
    }
}
