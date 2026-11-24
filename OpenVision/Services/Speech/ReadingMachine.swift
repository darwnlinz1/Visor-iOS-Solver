// OpenVision - ReadingMachine.swift
// Pure Foundation state machine for structured answer playback (PLAN.md §4.4, T5.2).
// Compiles on Linux (scripts/swift-local/run.sh) and iOS without AVFoundation/Combine/UIKit.
// `ReadingEngine` (Services/TTS/) bridges this state machine to `TTSService`.

import Foundation

/// Playback configuration derived from `AppSettings` (PLAN.md §4.6).
struct ReadingConfig: Equatable, Sendable {
    var speechRate: Float = 0.5
    var mcqRate: Float = 0.5
    var essayRate: Float = 0.42
    var pauseBetweenAnswers: TimeInterval = 0.5
    var pauseBetweenLines: TimeInterval = 1.2
    var readLineNumbers: Bool = true
    var mathRateFactor: Double = 0.85
    var pauseAfterFormula: TimeInterval = 0.3
    var dictationMode: Bool = false
    var dictationAutoContinue: TimeInterval = 0
    var repeatFormulaInDictation: Bool = false
    var mathStyle: MathReadingStyle = .default
    /// Lead-in silence on the first utterance of a turn so Bluetooth speakers don't clip the start.
    var bluetoothLeadIn: TimeInterval = 0.3

    static let `default` = ReadingConfig()
}

/// Lifecycle state of structured playback.
enum ReadingState: Equatable, Sendable {
    case idle
    case reading
    case paused
    /// Dictation mode: paused after an essay line, waiting for "tiếp" / button / auto-continue.
    case waitingForNext
    case finished

    var isActive: Bool {
        switch self {
        case .reading, .paused, .waitingForNext: return true
        case .idle, .finished: return false
        }
    }
}

/// One concrete utterance emitted by `ReadingMachine` for `SpeechSynthesizing` to speak.
struct ScheduledUtterance: Equatable, Sendable {
    let segmentID: Int
    let segmentIndex: Int
    let pieceIndex: Int
    let text: String
    let isMath: Bool
    let languageCode: String
    let rate: Float
    let preDelay: TimeInterval
    let postDelay: TimeInterval
}

/// Side effects requested by `ReadingMachine`, executed by `ReadingEngine` (or recorded in tests).
enum ReadingEffect: Equatable, Sendable {
    case speak(ScheduledUtterance)
    case stopSpeech
    case pauseSpeech
    case resumeSpeech
    case startAutoContinueTimer(seconds: TimeInterval)
    case cancelAutoContinueTimer
    case segmentChanged(index: Int)
    case didFinish
}

/// Pure deterministic reading state machine.
struct ReadingMachine: Equatable {
    static let ratePresets: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5]
    static let minUtteranceRate: Float = 0.1
    static let maxUtteranceRate: Float = 0.75

    private(set) var state: ReadingState = .idle
    private(set) var plan: ReadingPlan?
    private(set) var config: ReadingConfig = .default
    private(set) var currentSegmentIndex: Int = 0
    private(set) var currentPieceIndex: Int = 0
    private(set) var liveRateMultiplier: Float = 1.0
    private(set) var lastWarnings: [String] = []

    /// Utterances prepared for the currently active segment (rebuilt from `VietMathSpeech` when
    /// entering a segment, so changes to math settings / dictionary take effect immediately).
    private(set) var currentSegmentPieces: [PieceItem] = []

    /// True once the first utterance of the current turn has been scheduled.
    private var hasSpokenFirstUtterance = false
    /// True when the machine is currently waiting for a streamed segment to arrive while `plan.isComplete == false`.
    private var waitingForStreamedSegment = false

    struct PieceItem: Equatable, Sendable {
        let text: String
        let isMath: Bool
        let extraPauseAfter: TimeInterval
    }

    init(config: ReadingConfig = .default) {
        self.config = config
    }

    var currentSegment: ReadingSegment? {
        guard let plan, plan.segments.indices.contains(currentSegmentIndex) else { return nil }
        return plan.segments[currentSegmentIndex]
    }

    // MARK: - Plan lifecycle

    @discardableResult
    mutating func start(plan: ReadingPlan, config: ReadingConfig? = nil, startingAt index: Int = 0) -> [ReadingEffect] {
        if let config { self.config = config }
        var effects: [ReadingEffect] = [.cancelAutoContinueTimer, .stopSpeech]
        self.plan = plan
        self.currentSegmentIndex = 0
        self.currentPieceIndex = 0
        self.currentSegmentPieces = []
        self.lastWarnings = []
        self.hasSpokenFirstUtterance = false
        self.waitingForStreamedSegment = false

        if plan.segments.isEmpty {
            if plan.isComplete {
                state = .finished
                effects.append(.didFinish)
            } else {
                state = .reading
                waitingForStreamedSegment = true
            }
            return effects
        }

        let startIndex = plan.segments.indices.contains(index) ? index : 0
        state = .reading
        effects += beginSegment(at: startIndex)
        return effects
    }

    /// Appends newly streamed segments to the active plan. Starts speaking immediately if waiting.
    @discardableResult
    mutating func append(_ segments: [ReadingSegment], answerType: AnswerType? = nil) -> [ReadingEffect] {
        guard var currentPlan = plan, !currentPlan.isComplete else { return [] }
        if let answerType { currentPlan.answerType = answerType }
        guard !segments.isEmpty else {
            plan = currentPlan
            return []
        }
        currentPlan.segments.append(contentsOf: segments)
        plan = currentPlan

        guard waitingForStreamedSegment, state == .reading else { return [] }
        waitingForStreamedSegment = false
        return beginSegment(at: currentSegmentIndex)
    }

    /// Marks the plan complete (stream finished). If we were waiting for more segments, finishes playback.
    @discardableResult
    mutating func finishAppending(answerType: AnswerType? = nil) -> [ReadingEffect] {
        guard var currentPlan = plan else { return [] }
        if let answerType { currentPlan.answerType = answerType }
        currentPlan.isComplete = true
        plan = currentPlan

        if waitingForStreamedSegment && state == .reading {
            waitingForStreamedSegment = false
            state = .finished
            return [.cancelAutoContinueTimer, .didFinish]
        }
        return []
    }

    // MARK: - Utterance progress

    @discardableResult
    mutating func utteranceFinished() -> [ReadingEffect] {
        guard state == .reading, let plan else { return [] }
        let nextPiece = currentPieceIndex + 1
        if nextPiece < currentSegmentPieces.count {
            currentPieceIndex = nextPiece
            return [makeSpeakEffect()]
        }

        // Segment completed.
        let completedSegment = plan.segments.indices.contains(currentSegmentIndex) ? plan.segments[currentSegmentIndex] : nil
        let nextSegment = currentSegmentIndex + 1
        let hasMoreSegments = nextSegment < plan.segments.count || !plan.isComplete

        // Dictation mode pauses after each essay line when there is more to read.
        if config.dictationMode, let completedSegment, case .line = completedSegment.kind, hasMoreSegments {
            state = .waitingForNext
            if config.dictationAutoContinue > 0 {
                return [.startAutoContinueTimer(seconds: config.dictationAutoContinue)]
            }
            return []
        }

        if nextSegment < plan.segments.count {
            return beginSegment(at: nextSegment)
        }
        if !plan.isComplete {
            currentSegmentIndex = nextSegment
            currentPieceIndex = 0
            currentSegmentPieces = []
            waitingForStreamedSegment = true
            return []
        }

        state = .finished
        return [.cancelAutoContinueTimer, .didFinish]
    }

    // MARK: - Playback controls

    @discardableResult
    mutating func pause() -> [ReadingEffect] {
        guard state == .reading else { return [] }
        state = .paused
        return [.cancelAutoContinueTimer, .pauseSpeech]
    }

    @discardableResult
    mutating func resume() -> [ReadingEffect] {
        switch state {
        case .paused:
            state = .reading
            return [.resumeSpeech]
        case .waitingForNext:
            return advanceFromDictationWait()
        case .finished:
            return restartFromBeginning()
        case .idle, .reading:
            return []
        }
    }

    @discardableResult
    mutating func next() -> [ReadingEffect] {
        guard let plan, !plan.segments.isEmpty else { return [] }
        let target = currentSegmentIndex + 1
        if target < plan.segments.count {
            state = .reading
            waitingForStreamedSegment = false
            return [.cancelAutoContinueTimer, .stopSpeech] + beginSegment(at: target)
        }
        if !plan.isComplete {
            state = .reading
            currentSegmentIndex = target
            currentPieceIndex = 0
            currentSegmentPieces = []
            waitingForStreamedSegment = true
            return [.cancelAutoContinueTimer, .stopSpeech]
        }
        // At the last segment: finish cleanly.
        state = .finished
        return [.cancelAutoContinueTimer, .stopSpeech, .didFinish]
    }

    @discardableResult
    mutating func previous() -> [ReadingEffect] {
        guard let plan, !plan.segments.isEmpty else { return [] }
        let target = max(0, min(currentSegmentIndex - 1, plan.segments.count - 1))
        state = .reading
        waitingForStreamedSegment = false
        return [.cancelAutoContinueTimer, .stopSpeech] + beginSegment(at: target)
    }

    @discardableResult
    mutating func repeatCurrent() -> [ReadingEffect] {
        guard let plan, !plan.segments.isEmpty else { return [] }
        let clamped = min(max(0, currentSegmentIndex), plan.segments.count - 1)
        state = .reading
        waitingForStreamedSegment = false
        return [.cancelAutoContinueTimer, .stopSpeech] + beginSegment(at: clamped)
    }

    @discardableResult
    mutating func restartFromBeginning() -> [ReadingEffect] {
        guard let plan, !plan.segments.isEmpty else { return [] }
        state = .reading
        waitingForStreamedSegment = false
        hasSpokenFirstUtterance = false
        return [.cancelAutoContinueTimer, .stopSpeech] + beginSegment(at: 0)
    }

    @discardableResult
    mutating func jump(to index: Int) -> [ReadingEffect] {
        guard let plan, plan.segments.indices.contains(index) else { return [] }
        state = .reading
        waitingForStreamedSegment = false
        return [.cancelAutoContinueTimer, .stopSpeech] + beginSegment(at: index)
    }

    /// Jumps to a numbered MCQ question, essay line, or problem (for voice "đọc lại câu 3" / "dòng 5").
    /// When `scope` is specified (e.g. `.line`), matches that segment kind first so "dòng 1" on a MIXED
    /// answer jumps to L1 instead of Q1.
    @discardableResult
    mutating func jump(toNumber number: Int, scope: ReadingCommand.JumpScope = .any) -> [ReadingEffect] {
        guard let plan else { return [] }
        if scope != .any,
           let idx = plan.segments.firstIndex(where: { Self.matchesScope($0.kind, scope: scope, number: number) }) {
            return jump(to: idx)
        }
        if let idx = plan.segments.firstIndex(where: { $0.kind.number == number }) {
            return jump(to: idx)
        }
        // Fallback: 1-based segment position.
        let oneBased = number - 1
        if plan.segments.indices.contains(oneBased) {
            return jump(to: oneBased)
        }
        return []
    }

    private static func matchesScope(_ kind: ReadingSegment.Kind, scope: ReadingCommand.JumpScope, number: Int) -> Bool {
        switch (scope, kind) {
        case (.question, .mcq(let n)): return n == number
        case (.line, .line(let n)): return n == number
        case (.problem, .problem(let n)): return n == number
        case (.any, _): return kind.number == number
        default: return false
        }
    }

    /// Keeps machine state aligned when AVSpeechSynthesizer is paused/continued externally (e.g. audio interruption).
    mutating func syncExternalPause(_ paused: Bool) {
        if paused && state == .reading {
            state = .paused
        } else if !paused && state == .paused {
            state = .reading
        }
    }

    /// Stops playback while KEEPING `plan` intact so "đọc lại" works afterwards (PLAN.md §4.4).
    @discardableResult
    mutating func stop() -> [ReadingEffect] {
        let wasActive = state.isActive
        state = .idle
        waitingForStreamedSegment = false
        var effects: [ReadingEffect] = [.cancelAutoContinueTimer, .stopSpeech]
        if wasActive {
            effects.append(.didFinish)
        }
        return effects
    }

    /// Changes live speed multiplier; if currently reading, restarts the current piece at the new rate.
    @discardableResult
    mutating func setRateMultiplier(_ multiplier: Float) -> [ReadingEffect] {
        let clamped = min(max(multiplier, 0.5), 2.0)
        guard clamped != liveRateMultiplier else { return [] }
        liveRateMultiplier = clamped
        guard state == .reading, currentSegmentPieces.indices.contains(currentPieceIndex) else {
            return []
        }
        return [.stopSpeech, makeSpeakEffect()]
    }

    @discardableResult
    mutating func stepRate(faster: Bool) -> [ReadingEffect] {
        let presets = Self.ratePresets
        if faster {
            let next = presets.first(where: { $0 > liveRateMultiplier + 0.01 }) ?? presets.last ?? 1.5
            return setRateMultiplier(next)
        } else {
            let prev = presets.last(where: { $0 < liveRateMultiplier - 0.01 }) ?? presets.first ?? 0.75
            return setRateMultiplier(prev)
        }
    }

    mutating func updateConfig(_ newConfig: ReadingConfig) {
        self.config = newConfig
    }

    // MARK: - Internal helpers

    private mutating func advanceFromDictationWait() -> [ReadingEffect] {
        guard let plan else { return [] }
        let nextSegment = currentSegmentIndex + 1
        if nextSegment < plan.segments.count {
            state = .reading
            return [.cancelAutoContinueTimer] + beginSegment(at: nextSegment)
        }
        if !plan.isComplete {
            state = .reading
            currentSegmentIndex = nextSegment
            currentPieceIndex = 0
            currentSegmentPieces = []
            waitingForStreamedSegment = true
            return [.cancelAutoContinueTimer]
        }
        state = .finished
        return [.cancelAutoContinueTimer, .didFinish]
    }

    private mutating func beginSegment(at index: Int) -> [ReadingEffect] {
        guard let plan else { return [] }
        var idx = index
        while idx < plan.segments.count {
            let segment = plan.segments[idx]
            let built = buildPieces(for: segment, languageCode: plan.languageCode)
            if !built.isEmpty {
                currentSegmentIndex = idx
                currentPieceIndex = 0
                currentSegmentPieces = built
                return [.segmentChanged(index: idx), makeSpeakEffect()]
            }
            idx += 1
        }

        if !plan.isComplete {
            currentSegmentIndex = idx
            currentPieceIndex = 0
            currentSegmentPieces = []
            waitingForStreamedSegment = true
            return []
        }

        state = .finished
        return [.cancelAutoContinueTimer, .didFinish]
    }

    private mutating func buildPieces(for segment: ReadingSegment, languageCode: String) -> [PieceItem] {
        let vietnamese = languageCode.lowercased().hasPrefix("vi")
        let effectiveSpeechText: String
        if case .line(let n) = segment.kind {
            effectiveSpeechText = Self.applyLineNumberPreference(
                segment.speechText,
                lineNumber: n,
                vietnamese: vietnamese,
                readLineNumbers: config.readLineNumbers
            )
        } else {
            effectiveSpeechText = segment.speechText
        }
        let rendered = VietMathSpeech.renderWithDiagnostics(effectiveSpeechText, vietnamese: vietnamese, style: config.mathStyle)
        if !rendered.warnings.isEmpty {
            lastWarnings.append(contentsOf: rendered.warnings)
        }
        var items: [PieceItem] = []
        let repeatMath: Bool
        if case .line = segment.kind {
            repeatMath = config.dictationMode && config.repeatFormulaInDictation
        } else {
            repeatMath = false
        }

        for piece in rendered.pieces {
            switch piece {
            case .words(let text, let isMath):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                items.append(PieceItem(text: trimmed, isMath: isMath, extraPauseAfter: 0))
                if repeatMath && isMath {
                    items.append(PieceItem(text: trimmed, isMath: true, extraPauseAfter: 0.25))
                }
            case .pause(let ms):
                guard ms > 0, !items.isEmpty else { continue }
                let last = items[items.count - 1]
                let pauseSec = TimeInterval(ms) / 1000.0
                items[items.count - 1] = PieceItem(
                    text: last.text,
                    isMath: last.isMath,
                    extraPauseAfter: last.extraPauseAfter + pauseSec
                )
            }
        }
        return items
    }

    /// Dynamically honors `config.readLineNumbers` at playback time so toggling "Đọc số dòng"
    /// takes effect immediately even when repeating the previous answer or replaying History records.
    static func applyLineNumberPreference(
        _ speechText: String,
        lineNumber: Int,
        vietnamese: Bool,
        readLineNumbers: Bool
    ) -> String {
        let trimmed = speechText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let pattern = #"^(?:Dòng|Line)\s+"# + "\(lineNumber)" + #"\s*[\.:]?\s*"#
        if readLineNumbers {
            if trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return trimmed
            }
            let prefix = vietnamese ? "Dòng \(lineNumber). " : "Line \(lineNumber). "
            return prefix + trimmed
        } else {
            let stripped = trimmed.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stripped.isEmpty ? trimmed : stripped
        }
    }

    private mutating func makeSpeakEffect() -> ReadingEffect {
        let segment = plan!.segments[currentSegmentIndex]
        let piece = currentSegmentPieces[currentPieceIndex]
        let isLastPieceInSegment = currentPieceIndex == currentSegmentPieces.count - 1

        let baseRate: Float
        let interSegmentPause: TimeInterval
        switch segment.kind {
        case .mcq:
            baseRate = config.mcqRate
            interSegmentPause = config.pauseBetweenAnswers
        case .problem, .line, .final:
            baseRate = config.essayRate
            interSegmentPause = config.pauseBetweenLines
        case .answer, .notice:
            baseRate = config.speechRate
            interSegmentPause = 0.25
        }

        let mathFactor: Float = piece.isMath ? Float(config.mathRateFactor) : 1.0
        let rawRate = baseRate * mathFactor * liveRateMultiplier
        let clampedRate = min(max(rawRate, Self.minUtteranceRate), Self.maxUtteranceRate)

        var postDelay = piece.extraPauseAfter
        if piece.isMath {
            postDelay += config.pauseAfterFormula
        }
        if isLastPieceInSegment {
            postDelay += interSegmentPause
        }

        let preDelay: TimeInterval = hasSpokenFirstUtterance ? 0 : config.bluetoothLeadIn
        hasSpokenFirstUtterance = true

        let utterance = ScheduledUtterance(
            segmentID: segment.id,
            segmentIndex: currentSegmentIndex,
            pieceIndex: currentPieceIndex,
            text: piece.text,
            isMath: piece.isMath,
            languageCode: plan!.languageCode,
            rate: clampedRate,
            preDelay: preDelay,
            postDelay: postDelay
        )
        return .speak(utterance)
    }
}
