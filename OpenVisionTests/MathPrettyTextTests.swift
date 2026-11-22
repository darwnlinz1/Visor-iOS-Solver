// OpenVision - MathPrettyTextTests.swift
// Pure Foundation unit tests for MathPrettyText native Unicode formatter (PLAN.md §4.5, T6.1).
// Runs on Linux via scripts/swift-local/run.sh and in OpenVisionTests on iOS simulator.

import XCTest
@testable import OpenVision

final class MathPrettyTextTests: XCTestCase {

    func testPowersAndSubscripts() {
        XCTAssertEqual(MathPrettyText.format("$x^2 - 5x + 6 = 0$"), "x² - 5x + 6 = 0")
        XCTAssertEqual(MathPrettyText.format("$x_1 = 2, x_2 = 3$"), "x₁ = 2, x₂ = 3")
        XCTAssertEqual(MathPrettyText.format("$30^\\circ$"), "30°")
    }

    func testFractionsAndRoots() {
        XCTAssertEqual(MathPrettyText.format(#"$\frac{3}{4}$"#), "3/4")
        XCTAssertEqual(MathPrettyText.format(#"$\frac{x + 1}{x - 1}$"#), "(x + 1)/(x - 1)")
        XCTAssertEqual(MathPrettyText.format(#"$\sqrt{2}$"#), "√2")
        XCTAssertEqual(MathPrettyText.format(#"$\sqrt{x^2 + 1}$"#), "√(x² + 1)")
        XCTAssertEqual(MathPrettyText.format(#"$\sqrt[3]{8}$"#), "∛8")
    }

    func testGreekSymbolsAndRelations() {
        XCTAssertEqual(MathPrettyText.format(#"Ta có $\Delta = b^2 - 4ac \ge 0$."#), "Ta có Δ = b² - 4ac ≥ 0.")
        XCTAssertEqual(MathPrettyText.format(#"$x \in \mathbb{R} \Rightarrow x^2 \ge 0$"#), "x ∈ ℝ ⇒ x² ≥ 0")
        XCTAssertEqual(MathPrettyText.format(#"$\overrightarrow{AB} \perp \overrightarrow{CD}$"#), "→AB ⊥ →CD")
        let formatted = MathPrettyText.format(#"$\lim_{x \to 0} \frac{\sin x}{x} = 1$"#)
        XCTAssertFalse(formatted.contains("\\"))
        XCTAssertFalse(formatted.contains("$"))
        XCTAssertTrue(formatted.contains("→"))
    }

    func testPlainProsePassesThroughUnchanged() {
        XCTAssertEqual(MathPrettyText.format("Câu 1: A"), "Câu 1: A")
        XCTAssertEqual(MathPrettyText.format("Đây là tháp Eiffel ở Paris."), "Đây là tháp Eiffel ở Paris.")
    }
}
