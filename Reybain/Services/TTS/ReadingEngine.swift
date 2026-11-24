// Reybain - ReadingEngine.swift
// @MainActor ObservableObject connecting pure `ReadingMachine` + `VietMathSpeech` to `TTSService`
// (PLAN.md §4.4, T5.2, T5.5). Drives the PlaybackBar, segment highlight, dictation auto-continue,
// voice playback commands, and offline History replay.

import Foundation
import Combine

struct SpokenPieceLog: Identifiable, Equatable {
    let id = UUID()
    let segmentID: Int
    let text: String
    let isMath: Bool
    let rate: Float
}

@MainActor
final class ReadingEngine: ObservableObject {
    static let shared = ReadingEngine()

    // MARK: - Published UI state

    @Published private(set) var state: ReadingState = .idle
    @Published private(set) var plan: ReadingPlan?
    @Published private(set) var currentSegmentIndex: Int = 0
    @Published private(set) var currentPieceText: String = ""
    @Published private(set) var currentWordRange: NSRange?
    @Published private(set) var liveRateMultiplier: Float = 1.0
    @Published private(set) var lastWarnings: [String] = []
    @Published private(set) var spokenLog: [SpokenPieceLog] = []

    // MARK: - Callbacks

    /// Fired right before a new segment begins (VoiceAgentViewModel clears recognizer buffer here, N6).
    var onSegmentStarted: ((Int) -> Void)?

    /// Fired when dictation mode pauses after an essay line waiting for "tiếp" or Next.
    var onWaitingForNext: (() -> Void)?

    /// Fired when the active plan finishes reading or is stopped.
    var onReadingFinished: (() -> Void)?

    /// Fired before playback starts so ViewModel can ensure audio route + `.speaking` + `isBargeInPaused = true`.
    var onWillStartSpeaking: (() -> Void)?

    // MARK: - Dependencies

    private let synthesizer: SpeechSynthesizing
    private var machine = ReadingMachine()
    private var autoContinueTask: Task<Void, Never>?
    private var pendingLeadIn: String?

    init(synthesizer: SpeechSynthesizing = TTSService.shared) {
        self.synthesizer = synthesizer
        wireSynthesizer()
    }

    private func wireSynthesizer() {
        synthesizer.onUtteranceFinished = { [weak self] in
            self?.handleUtteranceFinished()
        }
        synthesizer.onWordRange = { [weak self] range, text in
            guard let self, self.state == .reading else { return }
            self.currentPieceText = text
            self.currentWordRange = range
        }
        synthesizer.onPauseChanged = { [weak self] paused in
            guard let self else { return }
            self.machine.syncExternalPause(paused)
            self.state = self.machine.state
        }
    }

    // MARK: - Computed helpers

    var isActive: Bool { state.isActive }

    var currentSegment: ReadingSegment? {
        machine.currentSegment
    }

    var progressLabel: String? {
        guard let plan, !plan.segments.isEmpty else { return nil }
        let current = min(currentSegmentIndex + 1, plan.segments.count)
        return "\(current)/\(plan.segments.count)"
    }

    var rateBadgeText: String {
        let rounded = (liveRateMultiplier * 100).rounded() / 100
        if abs(rounded - rounded.rounded()) < 0.005 {
            return "\(Int(rounded.rounded()))×"
        }
        let formatted = String(format: "%.2f", rounded)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: ".", with: ",")
        return "\(formatted)×"
    }

    // MARK: - Configuration from Settings

    static func config(from settings: AppSettings) -> ReadingConfig {
        ReadingConfig(
            speechRate: settings.clampedSpeechRate,
            mcqRate: settings.clampedMcqRate,
            essayRate: settings.clampedEssayRate,
            pauseBetweenAnswers: settings.clampedPauseBetweenAnswers,
            pauseBetweenLines: settings.clampedPauseBetweenLines,
            readLineNumbers: settings.readLineNumbers,
            mathRateFactor: settings.clampedMathRateFactor,
            pauseAfterFormula: settings.clampedPauseAfterFormula,
            dictationMode: settings.dictationMode,
            dictationAutoContinue: settings.clampedDictationAutoContinue,
            repeatFormulaInDictation: settings.repeatFormulaInDictation,
            mathStyle: settings.mathReadingStyle,
            bluetoothLeadIn: TTSService.bluetoothLeadIn
        )
    }

    func refreshConfigFromSettings() {
        let settings = SettingsManager.shared.settings
        machine.updateConfig(Self.config(from: settings))
        // If user turns off dictation mode in Settings while waiting on a line, resume right away.
        if !settings.dictationMode && state == .waitingForNext {
            resume()
        }
    }

    // MARK: - Plan lifecycle

    func start(plan: ReadingPlan, startingAt index: Int = 0, leadIn: String? = nil) {
        spokenLog.removeAll()
        currentPieceText = ""
        currentWordRange = nil
        pendingLeadIn = leadIn
        let cfg = Self.config(from: SettingsManager.shared.settings)
        AppLog.info(.reading, "Start plan type=\(plan.answerType.rawValue) lang=\(plan.languageCode) segments=\(plan.segments.count) complete=\(plan.isComplete) startAt=\(index)")
        if !plan.segments.isEmpty {
            onWillStartSpeaking?()
        }
        let effects = machine.start(plan: plan, config: cfg, startingAt: index)
        syncAndRun(effects)
    }

    func append(_ segments: [ReadingSegment], answerType: AnswerType? = nil) {
        if !segments.isEmpty && !state.isActive {
            onWillStartSpeaking?()
        }
        let effects = machine.append(segments, answerType: answerType)
        syncAndRun(effects)
    }

    func finishAppending(answerType: AnswerType? = nil) {
        let effects = machine.finishAppending(answerType: answerType)
        syncAndRun(effects)
    }

    /// Replays a stored History answer offline using current math & speed settings (T5.5).
    /// Optional `startingAt` starts directly at the tapped segment after audio routing is ready.
    func replay(record: ReadingRecord, startingAt index: Int = 0) {
        let plan = ReadingPlan(record: record)
        Task { @MainActor in
            await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                preferGlasses: SettingsManager.shared.settings.preferGlassesMic
            )
            self.start(plan: plan, startingAt: index)
        }
    }

    // MARK: - Controls

    func pause() {
        AppLog.info(.reading, "Pause")
        syncAndRun(machine.pause())
    }

    func resume() {
        AppLog.info(.reading, "Resume")
        machine.updateConfig(Self.config(from: SettingsManager.shared.settings))
        onWillStartSpeaking?()
        syncAndRun(machine.resume())
    }

    func togglePauseResume() {
        switch state {
        case .reading: pause()
        case .paused, .waitingForNext, .finished: resume()
        case .idle:
            if plan != nil { restartFromBeginning() }
        }
    }

    func next() {
        AppLog.info(.reading, "Next segment")
        onWillStartSpeaking?()
        syncAndRun(machine.next())
    }

    func previous() {
        AppLog.info(.reading, "Previous segment")
        onWillStartSpeaking?()
        syncAndRun(machine.previous())
    }

    func repeatCurrent() {
        AppLog.info(.reading, "Repeat current segment")
        machine.updateConfig(Self.config(from: SettingsManager.shared.settings))
        onWillStartSpeaking?()
        syncAndRun(machine.repeatCurrent())
    }

    func restartFromBeginning(leadIn: String? = nil) {
        AppLog.info(.reading, "Restart from beginning")
        pendingLeadIn = leadIn
        machine.updateConfig(Self.config(from: SettingsManager.shared.settings))
        onWillStartSpeaking?()
        syncAndRun(machine.restartFromBeginning())
    }

    func jump(to index: Int) {
        AppLog.info(.reading, "Jump to segment index \(index)")
        onWillStartSpeaking?()
        syncAndRun(machine.jump(to: index))
    }

    func jump(toNumber number: Int, scope: ReadingCommand.JumpScope = .any) {
        AppLog.info(.reading, "Jump to item #\(number) (\(scope))")
        onWillStartSpeaking?()
        syncAndRun(machine.jump(toNumber: number, scope: scope))
    }

    func stop() {
        AppLog.info(.reading, "Stop reading (plan preserved)")
        pendingLeadIn = nil
        syncAndRun(machine.stop())
    }

    func setRateMultiplier(_ multiplier: Float) {
        AppLog.info(.reading, "Set rate multiplier \(multiplier)x")
        syncAndRun(machine.setRateMultiplier(multiplier))
    }

    func cycleRate() {
        let presets = ReadingMachine.ratePresets
        if let idx = presets.firstIndex(where: { abs($0 - liveRateMultiplier) < 0.01 }) {
            let next = presets[(idx + 1) % presets.count]
            setRateMultiplier(next)
        } else {
            setRateMultiplier(1.0)
        }
    }

    func stepRate(faster: Bool) {
        syncAndRun(machine.stepRate(faster: faster))
    }

    func toggleDictationMode() {
        SettingsManager.shared.settings.dictationMode.toggle()
        refreshConfigFromSettings()
        // If user turns off dictation mode while waiting for "tiếp", continue reading right away.
        if !SettingsManager.shared.settings.dictationMode && state == .waitingForNext {
            resume()
        }
    }

    /// Dispatches a parsed voice command (PLAN.md §4.4, T5.3).
    func apply(_ command: ReadingCommand) {
        switch command {
        case .pause: pause()
        case .resume: resume()
        case .next: next()
        case .previous: previous()
        case .jump(let n, let scope): jump(toNumber: n, scope: scope)
        case .repeatCurrent: repeatCurrent()
        case .restart: restartFromBeginning()
        case .slower: stepRate(faster: false)
        case .faster: stepRate(faster: true)
        case .stop: stop()
        }
    }

    // MARK: - Effect execution

    private func handleUtteranceFinished() {
        guard state == .reading else { return }
        currentWordRange = nil
        syncAndRun(machine.utteranceFinished())
    }

    private func syncAndRun(_ effects: [ReadingEffect]) {
        let previousState = state
        state = machine.state
        plan = machine.plan
        currentSegmentIndex = machine.currentSegmentIndex
        liveRateMultiplier = machine.liveRateMultiplier
        lastWarnings = machine.lastWarnings

        if previousState != .waitingForNext && state == .waitingForNext {
            onWaitingForNext?()
        }

        for effect in effects {
            switch effect {
            case .speak(let utterance):
                if let announcement = pendingLeadIn {
                    pendingLeadIn = nil
                    (synthesizer as? TTSService)?.speakStatusCue(announcement, interruptCurrent: false)
                }
                currentPieceText = utterance.text
                currentWordRange = nil
                spokenLog.append(SpokenPieceLog(
                    segmentID: utterance.segmentID,
                    text: utterance.text,
                    isMath: utterance.isMath,
                    rate: utterance.rate
                ))
                MetricsCollector.shared.markTTSRequested()
                synthesizer.speakPiece(utterance)

            case .stopSpeech:
                currentWordRange = nil
                synthesizer.stop()

            case .pauseSpeech:
                synthesizer.pause()

            case .resumeSpeech:
                synthesizer.continueSpeaking()

            case .startAutoContinueTimer(let seconds):
                autoContinueTask?.cancel()
                autoContinueTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    guard !Task.isCancelled, let self, self.state == .waitingForNext else { return }
                    self.resume()
                }

            case .cancelAutoContinueTimer:
                autoContinueTask?.cancel()
                autoContinueTask = nil

            case .segmentChanged(let index):
                onSegmentStarted?(index)

            case .didFinish:
                currentWordRange = nil
                onReadingFinished?()
            }
        }
    }
}
