// OpenVision - GlassesWorkflowTests.swift
// Unit tests for UsageMode, GlassesWorkflowPolicy, ActionButtonPressDetector,
// GlassesInputDeduplicator, GlassesReconnectPolicy, and PromptV2 mode hints.

import XCTest
@testable import OpenVision

final class GlassesWorkflowTests: XCTestCase {

    func testStudyModeButtonPolicyDefaults() {
        var settings = AppSettings()
        settings.usageMode = .study
        settings.useCustomButtonMapping = false

        XCTAssertEqual(GlassesWorkflowPolicy.action(for: .shortPress, settings: settings), .captureAndSolve)
        XCTAssertEqual(GlassesWorkflowPolicy.action(for: .doublePress, settings: settings), .repeatAnswer)
        XCTAssertEqual(GlassesWorkflowPolicy.action(for: .hold, settings: settings), .captureAndListen)
    }

    func testGeneralModeButtonPolicyDefaults() {
        var settings = AppSettings()
        settings.usageMode = .general
        settings.useCustomButtonMapping = false

        XCTAssertEqual(GlassesWorkflowPolicy.action(for: .shortPress, settings: settings), .captureAndListen)
        XCTAssertEqual(GlassesWorkflowPolicy.action(for: .doublePress, settings: settings), .repeatAnswer)
        XCTAssertEqual(GlassesWorkflowPolicy.action(for: .hold, settings: settings), .captureAndSolve)
    }

    func testCustomButtonMappingOverridesModePreset() {
        var settings = AppSettings()
        settings.usageMode = .study
        settings.useCustomButtonMapping = true
        settings.shortPressAction = .capture
        settings.doublePressAction = .none
        settings.holdAction = .repeatAnswer

        XCTAssertEqual(GlassesWorkflowPolicy.action(for: .shortPress, settings: settings), .capture)
        XCTAssertEqual(GlassesWorkflowPolicy.action(for: .doublePress, settings: settings), .none)
        XCTAssertEqual(GlassesWorkflowPolicy.action(for: .hold, settings: settings), .repeatAnswer)
    }

    func testResolvedStudySolvePromptFallsBackAndTrims() {
        XCTAssertEqual(
            UsageMode.resolvedSolvePrompt(customPrompt: "", speaksVietnamese: true),
            "Giải bài trong ảnh này."
        )
        XCTAssertEqual(
            UsageMode.resolvedSolvePrompt(customPrompt: "   \n ", speaksVietnamese: false),
            "Solve the problem in this photo."
        )
        XCTAssertEqual(
            UsageMode.resolvedSolvePrompt(customPrompt: "  Chỉ đọc đáp án ngắn gọn. \n", speaksVietnamese: true),
            "Chỉ đọc đáp án ngắn gọn."
        )
    }

    func testInputDeduplicatorFiltersDuplicateTimestampsPerChannel() {
        var dedup = GlassesInputDeduplicator()
        XCTAssertTrue(dedup.shouldAccept(channel: "capture-cb", timestampMs: 1000))
        XCTAssertFalse(dedup.shouldAccept(channel: "capture-cb", timestampMs: 1000))
        XCTAssertTrue(dedup.shouldAccept(channel: "button-ab", timestampMs: 1000))
        XCTAssertTrue(dedup.shouldAccept(channel: "capture-cb", timestampMs: 1200))
        // Synthetic timestamp 0 always passes
        XCTAssertTrue(dedup.shouldAccept(channel: "capture-cb", timestampMs: 0))
        XCTAssertTrue(dedup.shouldAccept(channel: "capture-cb", timestampMs: 0))

        dedup.reset()
        XCTAssertTrue(dedup.shouldAccept(channel: "capture-cb", timestampMs: 1200))
    }

    @MainActor
    func testActionButtonDetectorClassifiesSingleAndDoublePress() async {
        let detector = ActionButtonPressDetector(doublePressWindow: 0.12)
        var received: [GlassesButtonPress] = []
        detector.onPressClassified = { received.append($0) }

        // Single press fires after window
        let t0 = Date()
        detector.registerPress(at: t0)
        try? await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertEqual(received, [.shortPress])

        // Double press fires immediately and suppresses stray single press
        received.removeAll()
        let t1 = Date()
        detector.registerPress(at: t1)
        detector.registerPress(at: t1.addingTimeInterval(0.05))
        XCTAssertEqual(received, [.doublePress])
        try? await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertEqual(received, [.doublePress])
    }

    func testReconnectPolicyBackoffAndGateConditions() {
        var policy = GlassesReconnectPolicy()
        XCTAssertEqual(policy.nextDelaySeconds(), 2)
        XCTAssertEqual(policy.nextDelaySeconds(), 4)
        XCTAssertEqual(policy.nextDelaySeconds(), 8)
        XCTAssertEqual(policy.nextDelaySeconds(), 15)
        XCTAssertEqual(policy.nextDelaySeconds(), 30)
        XCTAssertEqual(policy.nextDelaySeconds(), 60)
        XCTAssertEqual(policy.nextDelaySeconds(), 60)
        XCTAssertEqual(policy.attemptCount, 7)

        policy.reset()
        XCTAssertEqual(policy.attemptCount, 0)
        XCTAssertEqual(policy.nextDelaySeconds(), 2)

        XCTAssertTrue(policy.canAttemptReconnect(
            wantsLink: true, isSDKAvailable: true, isRegistered: true,
            hasConnectedDevice: true, permissionDenied: false
        ))
        XCTAssertFalse(policy.canAttemptReconnect(
            wantsLink: true, isSDKAvailable: true, isRegistered: true,
            hasConnectedDevice: false, permissionDenied: false
        ))
        XCTAssertFalse(policy.canAttemptReconnect(
            wantsLink: true, isSDKAvailable: true, isRegistered: true,
            hasConnectedDevice: true, permissionDenied: true
        ))
    }

    func testPromptV2RespectsGeneralModeHintWithoutBreakingStudyPrompt() throws {
        let now = Date(timeIntervalSince1970: 1_795_276_020)
        let tz = try XCTUnwrap(TimeZone(secondsFromGMT: 7 * 3600))
        let base = PromptV2.systemPrompt(now: now, timeZone: tz, userPrompt: "", memories: [:])
        let study = PromptV2.systemPrompt(now: now, timeZone: tz, userPrompt: "", memories: [:], modeHint: UsageMode.study.systemPromptHint)
        let general = PromptV2.systemPrompt(now: now, timeZone: tz, userPrompt: "", memories: [:], modeHint: UsageMode.general.systemPromptHint)

        XCTAssertEqual(base, study)
        XCTAssertTrue(general.contains("ACTIVE MODE: Everyday assistant"))
        XCTAssertTrue(general.contains("TYPE: OTHER"))
    }

    func testClampedEssayRateAllowsSlowCopyingDownToFiftyPercent() {
        var settings = AppSettings()
        settings.essayRate = 0.25
        XCTAssertEqual(settings.clampedEssayRate, 0.25, accuracy: 0.001)
        settings.essayRate = 0.1
        XCTAssertEqual(settings.clampedEssayRate, 0.25, accuracy: 0.001)
    }
}
