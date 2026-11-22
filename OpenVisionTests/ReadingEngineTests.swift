// OpenVision - ReadingEngineTests.swift
// Pure Foundation unit tests for ReadingMachine (PLAN.md §4.4, T5.2).
// Runs on Linux via scripts/swift-local/run.sh and in OpenVisionTests on iOS simulator.

import XCTest
@testable import OpenVision

final class ReadingEngineTests: XCTestCase {

    private func makePlan(_ raw: String, language: String = "vi", isComplete: Bool = true) -> ReadingPlan {
        let parsed = AnswerFormat.parse(raw)
        var plan = ReplyAssembler(languageCode: language).plan(turnID: UUID(), parsed: parsed)
        plan.isComplete = isComplete
        return plan
    }

    private func spokenUtterances(in effects: [ReadingEffect]) -> [ScheduledUtterance] {
        effects.compactMap {
            if case .speak(let u) = $0 { return u }
            return nil
        }
    }

    func testMCQUsesMcqRateAndPauseBetweenAnswers() {
        var config = ReadingConfig.default
        config.mcqRate = 0.55
        config.pauseBetweenAnswers = 0.7
        config.bluetoothLeadIn = 0.3

        let plan = makePlan("TYPE: MCQ\nQ1: A\nQ2: C")
        var machine = ReadingMachine(config: config)
        let firstEffects = machine.start(plan: plan)
        let first = spokenUtterances(in: firstEffects).first

        XCTAssertEqual(machine.state, .reading)
        XCTAssertEqual(first?.rate, 0.55)
        XCTAssertEqual(first?.preDelay, 0.3)
        XCTAssertEqual(first?.postDelay ?? 0, 0.7, accuracy: 0.001)

        let secondEffects = machine.utteranceFinished()
        let second = spokenUtterances(in: secondEffects).first
        XCTAssertEqual(second?.segmentIndex, 1)
        XCTAssertEqual(second?.preDelay, 0.0)
        XCTAssertEqual(second?.rate, 0.55)

        let doneEffects = machine.utteranceFinished()
        XCTAssertEqual(machine.state, .finished)
        XCTAssertTrue(doneEffects.contains(.didFinish))
    }

    func testEssayAppliesMathRateFactorAndFormulaPause() {
        var config = ReadingConfig.default
        config.essayRate = 0.40
        config.mathRateFactor = 0.8
        config.pauseAfterFormula = 0.35
        config.pauseBetweenLines = 1.5

        let plan = makePlan(#"TYPE: ESSAY"# + "\n" + #"L1: Ta có $x^2 = 4$."#)
        var machine = ReadingMachine(config: config)
        var utterances: [ScheduledUtterance] = []
        utterances += spokenUtterances(in: machine.start(plan: plan))
        while machine.state == .reading {
            utterances += spokenUtterances(in: machine.utteranceFinished())
        }

        XCTAssertEqual(machine.state, .finished)
        let prosePieces = utterances.filter { !$0.isMath }
        let mathPieces = utterances.filter { $0.isMath }
        XCTAssertFalse(prosePieces.isEmpty)
        XCTAssertFalse(mathPieces.isEmpty)
        XCTAssertEqual(prosePieces[0].rate, 0.40, accuracy: 0.001)
        XCTAssertEqual(mathPieces[0].rate, 0.32, accuracy: 0.001)
        // Last piece is math, so it carries both pauseAfterFormula and pauseBetweenLines.
        XCTAssertEqual(mathPieces.last?.postDelay ?? 0, 1.85, accuracy: 0.01)
    }

    func testPauseResumeAndLiveRateChangeReSpeaksCurrentPiece() {
        let plan = makePlan("TYPE: MCQ\nQ1: A\nQ2: B")
        var machine = ReadingMachine()
        _ = machine.start(plan: plan)

        let pauseEffects = machine.pause()
        XCTAssertEqual(machine.state, .paused)
        XCTAssertTrue(pauseEffects.contains(.pauseSpeech))

        let resumeEffects = machine.resume()
        XCTAssertEqual(machine.state, .reading)
        XCTAssertTrue(resumeEffects.contains(.resumeSpeech))

        let rateEffects = machine.setRateMultiplier(1.25)
        XCTAssertEqual(machine.liveRateMultiplier, 1.25)
        XCTAssertTrue(rateEffects.contains(.stopSpeech))
        let resaid = spokenUtterances(in: rateEffects).first
        XCTAssertEqual(resaid?.rate ?? 0, 0.5 * 1.25, accuracy: 0.001)
    }

    func testNavigationNextPreviousRepeatJumpAndStopKeepsPlan() {
        let plan = makePlan("TYPE: MCQ\nQ1: A\nQ2: B\nQ3: C")
        var machine = ReadingMachine()
        _ = machine.start(plan: plan)

        // Previous at index 0 stays clamped at 0.
        _ = machine.previous()
        XCTAssertEqual(machine.currentSegmentIndex, 0)

        _ = machine.next()
        XCTAssertEqual(machine.currentSegmentIndex, 1)

        _ = machine.jump(toNumber: 3)
        XCTAssertEqual(machine.currentSegmentIndex, 2)

        _ = machine.repeatCurrent()
        XCTAssertEqual(machine.currentSegmentIndex, 2)

        let stopEffects = machine.stop()
        XCTAssertEqual(machine.state, .idle)
        XCTAssertNotNil(machine.plan, "stop() must preserve plan for later 'đọc lại'")
        XCTAssertTrue(stopEffects.contains(.stopSpeech))

        _ = machine.restartFromBeginning()
        XCTAssertEqual(machine.state, .reading)
        XCTAssertEqual(machine.currentSegmentIndex, 0)
    }

    func testDictationModePausesAfterEssayLineAndSupportsAutoContinue() {
        var config = ReadingConfig.default
        config.dictationMode = true
        config.dictationAutoContinue = 5.0
        config.repeatFormulaInDictation = true

        let plan = makePlan("TYPE: ESSAY\nL1: $x = 2$\nL2: $y = 3$\nFINAL: Xong.")
        var machine = ReadingMachine(config: config)
        var line1Utterances = spokenUtterances(in: machine.start(plan: plan))
        var waitEffects: [ReadingEffect] = []
        while machine.state == .reading {
            let eff = machine.utteranceFinished()
            line1Utterances += spokenUtterances(in: eff)
            waitEffects = eff
        }

        // Math formula repeated twice in dictation mode.
        XCTAssertEqual(line1Utterances.filter { $0.isMath }.count, 2)
        XCTAssertEqual(machine.state, .waitingForNext)
        XCTAssertTrue(waitEffects.contains(.startAutoContinueTimer(seconds: 5.0)))

        let nextEffects = machine.resume()
        XCTAssertEqual(machine.state, .reading)
        XCTAssertEqual(machine.currentSegmentIndex, 1)
        XCTAssertTrue(nextEffects.contains(.cancelAutoContinueTimer))
    }

    func testAppendingSegmentsWhileStreamingResumesFromWait() {
        let assembler = ReplyAssembler(languageCode: "vi")
        let empty = assembler.emptyPlan(turnID: UUID(), answerType: .mcq)
        var machine = ReadingMachine()
        _ = machine.start(plan: empty)
        XCTAssertEqual(machine.state, .reading)

        let seg0 = ReadingSegment(id: 0, kind: .mcq(1), title: "Câu 1", displayText: "Câu 1: A", speechText: "Câu 1: A.")
        let appendEffects = machine.append([seg0], answerType: .mcq)
        XCTAssertEqual(spokenUtterances(in: appendEffects).count, 1)

        // Finish seg0 while stream still open -> waits instead of finishing.
        _ = machine.utteranceFinished()
        XCTAssertEqual(machine.state, .reading)

        let finishEffects = machine.finishAppending(answerType: .mcq)
        XCTAssertEqual(machine.state, .finished)
        XCTAssertTrue(finishEffects.contains(.didFinish))
    }
}
