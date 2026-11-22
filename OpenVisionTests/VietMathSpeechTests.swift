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

    func testVectorCoordinatesAreNotAnInterval() {
        // Review B3: only a vector on the left of "=" makes (a; b) coordinates.
        check([
            row("$\\vec{u} = (1; 2)$", "véc-tơ u bằng 1, 2"),
            row("$\\overrightarrow{AB} = (3; -4)$", "véc-tơ A B bằng 3, âm 4"),
            row("$\\vec{u} = (1; 2; 3)$", "véc-tơ u bằng 1, 2, 3"),
            row("$S = (2; +\\infty)$", "S bằng khoảng từ 2 đến dương vô cùng"),
            row("$D = (1; +\\infty)$", "D bằng khoảng từ 1 đến dương vô cùng"),
            row("$x \\in (1; 2)$", "x thuộc khoảng từ 1 đến 2"),
            row("$M = (1; 2)$", "M bằng khoảng từ 1 đến 2"),
            row("$\\vec{u} = (1; +\\infty)$", "véc-tơ u bằng khoảng từ 1 đến dương vô cùng"),
        ])
        XCTAssertEqual(reading("$\\vec{u} = (1; 2)$", .default, vietnamese: false), "vector u equals 1, 2")
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

    func testColonsThatAreNotDivision() {
        // Review B2: the name of a line, plane or circle, and a quantifier condition.
        check([
            row("$d: x + 2y - 3 = 0$", "d: x cộng 2 y trừ 3 bằng 0"),
            row("$(P): 2x - y + z = 0$", "P: 2 x trừ y cộng z bằng 0"),
            row("$\\Delta: x - y + 1 = 0$", "đen-ta: x trừ y cộng 1 bằng 0"),
            row("$d_1: x = 1$", "d một: x bằng 1", explicit: "d chỉ số 1: x bằng 1"),
            row("$d': x = 1$", "d phẩy: x bằng 1"),
            row("$(C): (x-1)^2 + (y+2)^2 = 9$",
                "C: x trừ 1, tất cả bình phương cộng y cộng 2, tất cả bình phương bằng 9"),
            row("$\\exists x \\in \\mathbb{R}: x^2 < 0$", "tồn tại x thuộc tập số thực sao cho x bình phương nhỏ hơn 0"),
            row("$\\forall x \\in \\mathbb{R}: x^2 \\ge 0$",
                "với mọi x thuộc tập số thực, x bình phương lớn hơn hoặc bằng 0"),
            row("∃x ∈ ℝ: x² < 0", "tồn tại x thuộc tập số thực sao cho x bình phương nhỏ hơn 0"),
            // Every other colon is still division.
            row("$a : b$", "a chia b"),
            row("$6 : 2 = 3$", "6 chia 2 bằng 3"),
            row("$a : b = 2 : 3$", "a chia b bằng 2 chia 3"),
            row("$x : 3 = 4$", "x chia 3 bằng 4"),
            row("$d : x + 1$", "d chia x cộng 1"),
        ])
        let en = { (text: String) in self.reading(text, .default, vietnamese: false) }
        XCTAssertEqual(en("$d: x + 2y - 3 = 0$"), "d: x plus 2 y minus 3 equals 0")
        XCTAssertEqual(en("$\\exists x \\in \\mathbb{R}: x^2 < 0$"),
                       "there exists x is in the real numbers such that x squared is less than 0")
        XCTAssertEqual(en("$\\forall x \\in \\mathbb{R}: x^2 \\ge 0$"),
                       "for all x is in the real numbers, x squared is greater than or equal to 0")
        XCTAssertEqual(en("$6 : 2 = 3$"), "6 divided by 2 equals 3")
    }

    func testGreekLettersWithPrimes() {
        // Δ' is the reduced discriminant (review B1): a variable with a prime, not a function name.
        check([
            row("$\\Delta'$", "đen-ta phẩy"),
            row("$\\Delta' = b'^2 - ac$", "đen-ta phẩy bằng b phẩy bình phương trừ a c"),
            row("Δ' > 0", "đen-ta phẩy lớn hơn 0"),
            row("$\\Delta^{\\prime}$", "đen-ta phẩy"),
            row("$\\Delta''$", "đen-ta hai phẩy"),
            row("$\\alpha' = 30^\\circ$", "an-pha phẩy bằng 30 độ"),
        ])
        XCTAssertEqual(reading("$\\Delta'$", MathReadingStyle(pronunciationOverrides: ["\\Delta": "đen ta"])),
                       "đen ta phẩy", "the dictionary entry of the letter still applies")
        XCTAssertEqual(reading("$\\Delta' = 0$", .default, vietnamese: false), "delta prime equals 0")
        XCTAssertEqual(reading("$\\alpha' = 30^\\circ$", .default, vietnamese: false), "alpha prime equals 30 degrees")
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

    func testTextAndRomanUnitsTakeTheirExponent() {
        // Review B4: the way Gemini writes units.
        check([
            row("$S = 12\\text{ cm}^2$", "S bằng 12 xen-ti-mét vuông"),
            row("$8 \\text{ cm}^3$", "8 xen-ti-mét khối"),
            row("$12\\ \\mathrm{cm}^2$", "12 xen-ti-mét vuông"),
            row("$12\\text{cm}^{2}$", "12 xen-ti-mét vuông"),
            row("$9{,}8\\,\\text{m/s}^2$", "9 phẩy 8 mét trên giây bình phương"),
            row("$V = 8\\,\\mathrm{dm}^3$", "V bằng 8 đề-xi-mét khối"),
        ])
        let en = { (text: String) in self.reading(text, .default, vietnamese: false) }
        XCTAssertEqual(en("$12\\text{ cm}^2$"), "12 square centimeters")
        XCTAssertEqual(en("$9{,}8\\,\\text{m/s}^2$"), "9.8 meters per second squared")
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

    func testSpeechPieceIsCodable() throws {
        let pieces: [SpeechPiece] = [.words("ích bình phương", isMath: true), .pause(milliseconds: 200),
                                     .words("Ta có", isMath: false)]
        let data = try JSONEncoder().encode(pieces)
        XCTAssertEqual(try JSONDecoder().decode([SpeechPiece].self, from: data), pieces)
    }

    func testEmptyRootIndexIsASquareRoot() {
        XCTAssertEqual(reading("$\\sqrt[]{x}$"), "căn ích")
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

    // MARK: - Labels before a bare formula (review X1)

    private func prose(_ text: String) -> SpeechPiece { .words(text, isMath: false) }
    private func math(_ text: String) -> SpeechPiece { .words(text, isMath: true) }

    func testShortAnswerAndStepLabelsStayProse() {
        // The short answers ReplyAssembler speaks ("Câu N: <value>.") and step labels: the label and its
        // colon are prose, so the colon is never read as division ("Câu 12 chia 3, trên 4").
        let cases: [(String, [SpeechPiece])] = [
            ("Câu 12: 3/4.", [prose("Câu 12:"), math("ba phần tư")]),
            ("Câu 12: -1/2.", [prose("Câu 12:"), math("âm một phần hai")]),
            ("Câu 12: √2.", [prose("Câu 12:"), math("căn 2")]),
            ("Câu 12: 2√3.", [prose("Câu 12:"), math("2 căn 3")]),
            ("Câu 12: x = 2.", [prose("Câu 12:"), math("ích bằng 2")]),
            ("Câu 12: −3.", [prose("Câu 12:"), math("âm 3")]),
            ("Câu 12: x².", [prose("Câu 12:"), math("ích bình phương")]),
            ("Câu 12: 10^3.", [prose("Câu 12:"), math("10 lập phương")]),
            ("Bước 1: x = 2.", [prose("Bước 1:"), math("ích bằng 2")]),
            ("Ví dụ 2: x = 2.", [prose("Ví dụ 2:"), math("ích bằng 2")]),
            ("TH1: x ≥ 0.", [prose("TH1:"), math("ích lớn hơn hoặc bằng 0")]),
            ("Dòng 100. x = 2.", [prose("Dòng 100."), math("ích bằng 2")]),
            ("b) x = 2.", [prose("bê)"), math("ích bằng 2")]),
            ("1) x = 2.", [prose("1)"), math("ích bằng 2")]),
            // Unchanged.
            ("Câu 4: -2,5.", [prose("Câu 4: âm 2 phẩy 5.")]),
            ("Câu 12: $x = 2$.", [prose("Câu 12:"), math("ích bằng 2")]),
            ("Đáp số: 3/4.", [prose("Đáp số:"), math("ba phần tư")]),
            ("Lúc 10:30 sáng.", [prose("Lúc 10:30 sáng.")]),
            ("Tỉ số 3:2.", [prose("Tỉ số 3:2.")]),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(VietMathSpeech.render(input, vietnamese: true, style: .default), expected, input)
        }
        XCTAssertEqual(VietMathSpeech.render("Question 12: 3/4.", vietnamese: false, style: .default),
                       [prose("Question 12:"), math("3 over 4")])
        check([
            row("Câu 12: 3/4.", "Câu 12: ba phần tư"),
            row("Câu 12: -1/2.", "Câu 12: âm một phần hai"),
            row("Câu 12: √2.", "Câu 12: căn 2", explicit: "Câu 12: căn bậc hai của 2"),
            row("Câu 12: 2√3.", "Câu 12: 2 căn 3", explicit: "Câu 12: 2 căn bậc hai của 3"),
            row("Câu 12: x = 2.", "Câu 12: x bằng 2"),
            row("Câu 12: −3.", "Câu 12: âm 3"),
            row("Câu 12: x².", "Câu 12: x bình phương"),
            row("Bước 1: x = 2.", "Bước 1: x bằng 2"),
            row("Dòng 100. x = 2.", "Dòng 100. x bằng 2"),
            row("Câu 4: -2,5.", "Câu 4: âm 2 phẩy 5."),
        ])
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

    // MARK: - N4 regressions (T3.3): math meaning survives, nothing is glued together

    func testN4FormulasAreReadNotStripped() {
        // Old cleanSpokenAudio: "\frac{1}{2}" → "12", "\sqrt{x}" → "x", "x \le 2" → "x 2".
        XCTAssertEqual(reading("$\\frac{1}{2}$"), "một phần hai")
        XCTAssertEqual(reading("\\frac{1}{2}"), "một phần hai", "bare LaTeX in prose")
        XCTAssertEqual(reading("$\\sqrt{x}$"), "căn ích")
        XCTAssertEqual(reading("\\sqrt{x}"), "căn ích")
        XCTAssertEqual(reading("$x \\le 2$"), "ích nhỏ hơn hoặc bằng 2")
        XCTAssertEqual(reading("Vì x \\le 2 nên"), "Vì ích nhỏ hơn hoặc bằng 2 nên")
        // Old: the leading "-" was dropped ("-2x+4=0" → "2x+4=0") and "2*3*4" became "234".
        XCTAssertEqual(reading("-2x + 4 = 0"), "âm 2 ích cộng 4 bằng 0")
        XCTAssertEqual(reading("-2x+4=0"), "âm 2 ích cộng 4 bằng 0")
        XCTAssertEqual(reading("2*3*4"), "2 nhân 3 nhân 4")
        XCTAssertEqual(reading("2 * 3 = 6"), "2 nhân 3 bằng 6")
        XCTAssertEqual(reading("Ta có $\\frac{1}{2}$ cộng $\\sqrt{4}$ bằng **2,5** và ## Hết"),
                       "Ta có một phần hai cộng căn 4 bằng 2 phẩy 5 và Hết")
    }

    // MARK: - Prose: numbers, units, symbols (T3.3)

    func testProseNumbers() {
        XCTAssertEqual(reading("Câu 4: 2,5."), "Câu 4: 2 phẩy 5.")
        XCTAssertEqual(reading("Lấy 3.14 làm pi."), "Lấy 3 phẩy 14 làm pi.")
        XCTAssertEqual(reading("Xác suất 0.125 thôi."), "Xác suất 0 phẩy 125 thôi.")
        XCTAssertEqual(reading("Giá 2.500 đồng, dân số 1.000.000 người."), "Giá 2.500 đồng, dân số 1.000.000 người.",
                       "dot thousands separators are left to the voice")
        XCTAssertEqual(reading("Được 1.000.000,5 đồng."), "Được 1.000.000 phẩy 5 đồng.")
        XCTAssertEqual(reading("Bản 2.14.0 và dãy 1,2,3."), "Bản 2.14.0 và dãy 1,2,3.")
        XCTAssertEqual(reading("Đáp số: -3."), "Đáp số: âm 3.")
        XCTAssertEqual(reading("Nhiệt độ (-5) độ."), "Nhiệt độ (âm 5) độ.")
        XCTAssertEqual(reading("Đáp số: -3.", MathReadingStyle(negativeWord: .tru)), "Đáp số: trừ 3.")
        XCTAssertEqual(reading("Làm câu 1-5 trước."), "Làm câu 1-5 trước.", "a range keeps its dash")
    }

    func testProseUnitsPercentAndDegrees() {
        XCTAssertEqual(reading("Dài 5cm."), "Dài 5 xen-ti-mét.")
        XCTAssertEqual(reading("Diện tích 5 cm2."), "Diện tích 5 xen-ti-mét vuông.")
        // "²" makes the quantity a formula: its own piece, the formula pause replaces ", " and ".".
        XCTAssertEqual(VietMathSpeech.render("Diện tích 10 m², thể tích 2 cm³.", vietnamese: true, style: .default), [
            .words("Diện tích", isMath: false), .words("10 mét vuông", isMath: true),
            .words("thể tích", isMath: false), .words("2 xen-ti-mét khối", isMath: true),
        ])
        XCTAssertEqual(reading("Gia tốc 9,8 m/s²."), "Gia tốc 9 phẩy 8 mét trên giây bình phương")
        XCTAssertEqual(reading("Đi 2 h rồi nghỉ 30 min."), "Đi 2 giờ rồi nghỉ 30 phút.")
        XCTAssertEqual(reading("Lực 10 N."), "Lực 10 niu-tơn.")
        XCTAssertEqual(reading("Giảm 50% rồi 20 %."), "Giảm 50 phần trăm rồi 20 phần trăm.")
        XCTAssertEqual(reading("Nước sôi ở 100°C."), "Nước sôi ở 100 độ xê.")
        XCTAssertEqual(reading("Nước sôi ở 100°C.", asWritten), "Nước sôi ở 100 độ C.")
        XCTAssertEqual(reading("Câu 2 A đúng."), "Câu 2 a đúng.", "a capital A after a number is an answer, not amperes")
        XCTAssertEqual(reading("Giấy A4 và vitamin C."), "Giấy A4 và vitamin xê.")
    }

    func testUnicodeMathInProse() {
        XCTAssertEqual(reading("Ta có x² + 1 > 0 với mọi x."), "Ta có ích bình phương cộng 1 lớn hơn 0 với mọi ích.")
        XCTAssertEqual(reading("Góc bằng π/2 rad."), "Góc bằng pi trên 2 ra-đi-an")
        XCTAssertEqual(reading("Vì Δ ≥ 0 nên có nghiệm."), "Vì đen-ta lớn hơn hoặc bằng 0 nên có nghiệm.")
        XCTAssertEqual(reading("√2 ≈ 1,41"), "căn 2 xấp xỉ 1 phẩy 41")
        XCTAssertEqual(reading("**Đáp án:** C"), "Đáp án: xê")
    }

    // MARK: - English answers (EnglishMathReader, T3.3)

    func testEnglishReaderUsesTheSpokenMathWords() {
        let en = { (text: String) in self.reading(text, .default, vietnamese: false) }
        XCTAssertEqual(en("$x^2 + 1 = 5$"), "x squared plus 1 equals 5")
        XCTAssertEqual(en("$x^3 - 1$"), "x cubed minus 1")
        XCTAssertEqual(en("$2^{10}$"), "2 to the power of 10")
        XCTAssertEqual(en("$\\sqrt{x}$"), "the square root of x")
        XCTAssertEqual(en("$\\frac{a}{b}$"), "a over b")
        XCTAssertEqual(en("$3/4$"), "3 over 4")
        XCTAssertEqual(en("$a \\times b \\div c$"), "a times b divided by c")
        XCTAssertEqual(en("$a \\neq b$"), "a is not equal to b")
        XCTAssertEqual(en("$a \\le b$"), "a is less than or equal to b")
        XCTAssertEqual(en("$a \\ge b$"), "a is greater than or equal to b")
        XCTAssertEqual(en("$\\pi \\approx 3.14$"), "pi is approximately 3.14")
        XCTAssertEqual(en("$-3 < x$"), "negative 3 is less than x")
        XCTAssertEqual(en("$x > 0$"), "x is greater than 0")
        XCTAssertEqual(en("$50\\%$"), "50 percent")
    }

    func testEnglishReaderStructures() {
        let en = { (text: String) in self.reading(text, .default, vietnamese: false) }
        XCTAssertEqual(en("$\\frac{x+1}{x-1}$"), "x plus 1, over x minus 1")
        XCTAssertEqual(en("$f'(x) = 3x^2$"), "f prime of x equals 3 x squared")
        XCTAssertEqual(en("$\\sin^2 x + \\cos^2 x = 1$"), "sine squared of x plus cosine squared of x equals 1")
        XCTAssertEqual(en("$\\log_2 8 = 3$"), "log base 2 of 8 equals 3")
        XCTAssertEqual(en("$\\int_0^1 x\\,dx$"), "the integral from 0 to 1 of x, d x")
        XCTAssertEqual(en("$\\lim_{x \\to 0} \\frac{\\sin x}{x}$"), "the limit as x approaches 0 of sine of x over x")
        XCTAssertEqual(en("$x \\in [1; 3]$"), "x is in the closed interval from 1 to 3")
        XCTAssertEqual(en("$C_5^2 = 10$"), "5 choose 2 equals 10")
        XCTAssertEqual(en("$v = 60 km/h$"), "v equals 60 kilometers per hour")
        XCTAssertEqual(en("$30^\\circ$"), "30 degrees")
        XCTAssertEqual(en("$2{,}5$"), "2.5")
        XCTAssertEqual(en("$\\Delta = b^2 - 4ac$"), "delta equals b squared minus 4 a c")
    }

    func testEnglishArticlesStayOutOfBareFormulas() {
        XCTAssertEqual(VietMathSpeech.render("Is x = 2 a solution?", vietnamese: false, style: .default), [
            .words("Is", isMath: false),
            .words("x equals 2", isMath: true),
            .words("a solution?", isMath: false),
        ])
        XCTAssertEqual(reading("Vậy a = 2 và b = 3."), "Vậy a bằng 2 và bê bằng 3", "Vietnamese keeps single letters")
    }

    func testEnglishAnswersKeepProseAndIgnoreTheVietnameseDictionary() {
        let style = MathReadingStyle(pronunciationOverrides: ["cos": "cô-sin", "x": "ích-xì"])
        XCTAssertEqual(VietMathSpeech.render("The answer is $\\cos x = 1$. Option C.", vietnamese: false, style: style), [
            .words("The answer is", isMath: false),
            .words("cosine of x equals 1", isMath: true),
            .words("Option C.", isMath: false),
        ])
        XCTAssertEqual(reading("It costs 2,500 dollars, -3 degrees.", .default, vietnamese: false),
                       "It costs 2,500 dollars, -3 degrees.")
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
