// OpenVision - VoiceCommandService.swift
// Wake word detection, voice command capture, and voice playback control (PLAN.md §4.4, T5.3, T8.1-T8.3).
// Preserves Lesson 1 (single shared mic tap) and Lesson 3 (Vietnamese phonetic wake word variants).

import Foundation
import Speech
import AVFoundation
import QuartzCore

// MARK: - Concurrency Trackers (Top-level Module Scope)

final class RouteChangeTracker: @unchecked Sendable {
    static let shared = RouteChangeTracker()
    private let lock = NSLock()
    private var _lastTime: TimeInterval = 0

    func mark() {
        lock.lock()
        _lastTime = CACurrentMediaTime()
        lock.unlock()
    }

    func isWithinStabilizationWindow(duration: TimeInterval = 1.0) -> Bool {
        lock.lock()
        let elapsed = CACurrentMediaTime() - _lastTime
        lock.unlock()
        return elapsed < duration
    }
}

final class VoiceCaptureTracker: @unchecked Sendable {
    static let shared = VoiceCaptureTracker()
    private let lock = NSLock()
    private var _isCapturing: Bool = false

    func set(_ val: Bool) {
        lock.lock()
        _isCapturing = val
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        let val = _isCapturing
        lock.unlock()
        return val
    }
}

/// Voice command service with wake word detection, on-device speech recognition, and reading controls.
@MainActor
final class VoiceCommandService: ObservableObject {
    // MARK: - Singleton

    static let shared = VoiceCommandService()

    // MARK: - Published State

    @Published var state: ListeningState = .idle
    @Published var isListening: Bool = false
    @Published var currentTranscription: String = ""
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    /// True when the active locale uses on-device speech recognition (T8.1, shown on Mic status chip).
    @Published private(set) var isOnDeviceRecognition: Bool = false

    // MARK: - Listening State

    enum ListeningState: Equatable {
        /// Waiting for wake word
        case idle
        /// Wake word detected, capturing command
        case listening
        /// In conversation mode, waiting for follow-up
        case conversationMode
        /// Processing captured command / assistant is reading
        case processing
    }

    // MARK: - Configuration

    var wakeWord: String { SettingsManager.shared.settings.wakeWord }
    var isWakeWordEnabled: Bool { SettingsManager.shared.settings.wakeWordEnabled }
    var playActivationSound: Bool { SettingsManager.shared.settings.playActivationSound }

    // MARK: - Callbacks

    var onWakeWordDetected: (() -> Void)?
    var onStopCommand: (() -> Void)?
    var onCommandCaptured: ((String) -> Void)?
    var onReadingCommand: ((ReadingCommand) -> Void)?
    var onInterruption: (() -> Void)?
    var onConversationTimeout: (() -> Void)?

    // MARK: - Barge-in & Playback Control Hooks

    /// When true, barge-in detection is paused (e.g. while TTS audio is playing).
    var isBargeInPaused: Bool = false

    /// Returns true while assistant is speaking or thinking (allows wake-word interrupt / reading commands).
    var shouldAllowInterrupt: (() -> Bool)?

    /// Returns true when ReadingEngine is paused or waiting for "tiếp" in dictation mode:
    /// app is silent, so bare reading commands work WITHOUT wake word (PLAN.md §4.4, T5.3).
    var isPausedOrWaitingForNext: (() -> Bool)?

    /// Returns true while ReadingEngine is active so conversation timeout never cuts off playback (N7).
    var shouldSuppressConversationTimeout: (() -> Bool)?

    // MARK: - Speech Recognition

    private var loggedOnDeviceLocales: Set<String> = []
    private var cachedRecognizer: (identifier: String, recognizer: SFSpeechRecognizer?)?

    private var speechRecognizer: SFSpeechRecognizer? {
        let identifier = Self.recognitionLocaleIdentifier(SettingsManager.shared.settings.recognitionLanguage)
        if let cached = cachedRecognizer, cached.identifier == identifier { return cached.recognizer }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        cachedRecognizer = (identifier, recognizer)
        let supportsOnDevice = recognizer?.supportsOnDeviceRecognition ?? false
        isOnDeviceRecognition = supportsOnDevice
        if loggedOnDeviceLocales.insert(identifier).inserted {
            AppLog.info(.voice, "Speech recognizer locale: \(identifier) (on-device: \(supportsOnDevice ? "yes" : "server"))")
        }
        return recognizer
    }

    static func recognitionLocaleIdentifier(_ setting: String) -> String {
        switch setting {
        case "vi-VN", "en-US": return setting
        default: return Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        }
    }

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionGeneration = 0

    // MARK: - Audio Engine

    private var audioEngine: AVAudioEngine?
    private var lastRecognizerRestart = Date.distantPast
    private var wakeWordRestartScheduled = false
    private let minRestartInterval: TimeInterval = 0.6

    // MARK: - Timers

    private var silenceTimer: Timer?
    private var commandTimeoutTimer: Timer?
    private var conversationTimeoutTimer: Timer?
    private var wakeWordCooldownActive: Bool = false

    // MARK: - Voice activity detection

    private let speechDetector = SpeechActivityDetector()
    private var vadCommitPending = false
    private var hasSpokenThisTurn: Bool = false

    // MARK: - Audio Feedback

    private var activationSound: AVAudioPlayer?

    // MARK: - Route change and stabilization tracking

    nonisolated func markRouteChange() {
        RouteChangeTracker.shared.mark()
    }

    nonisolated func isInStabilizationWindow() -> Bool {
        RouteChangeTracker.shared.isWithinStabilizationWindow()
    }

    nonisolated static func isSilentOrZeroBuffer(_ buffer: AVAudioPCMBuffer) -> Bool {
        if let channels = buffer.floatChannelData {
            let frames = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            for ch in 0..<channelCount {
                let data = channels[ch]
                for i in 0..<frames {
                    if abs(data[i]) > 0.001 { return false }
                }
            }
            return true
        } else if let channels = buffer.int16ChannelData {
            let frames = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            for ch in 0..<channelCount {
                let data = channels[ch]
                for i in 0..<frames {
                    if abs(data[i]) > 32 { return false }
                }
            }
            return true
        }
        return false
    }

    // MARK: - Wake Word Variations & Stripping (T8.3 / B12 cleaned; Lesson 3 preserved)

    static let wakeWordVariations: [String] = [
        // English
        "ok vision", "okay vision", "o.k. vision", "o k vision",
        "hey vision", "hi vision", "oak vision",
        // Vietnamese phonetic transcriptions
        "ô kê vi dơn", "ô kê vi giừn", "ô kê vision",
        "ok vi dơn", "ok vi giừn",
        "ốc vi dơn", "ốc vi giừn",
        "ê vi dơn",
        "vi dơn", "vi giừn",
        "oke vision", "oke vi dơn", "oke vi giừn"
    ]

    static func stripWakeWord(from text: String, defaultWakeWord: String) -> String {
        var variations = wakeWordVariations
        let def = defaultWakeWord.lowercased()
        if !variations.contains(def) { variations.append(def) }
        variations.sort { $0.count > $1.count }

        let lower = text.lowercased()
        for v in variations {
            if let r = lower.range(of: v) {
                if lower.distance(from: lower.startIndex, to: r.lowerBound) <= 15 {
                    return String(text[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Initialization

    private init() {
        setupActivationSound()
        setupSpeechDetector()
    }

    private func setupSpeechDetector() {
        speechDetector.onSpeechStart = { [weak self] in
            guard let self else { return }
            self.vadCommitPending = false
            self.silenceTimer?.invalidate()
            self.silenceTimer = nil
        }
        speechDetector.onSpeechEnd = { [weak self] in
            self?.handleSpeechEnded()
        }
        Task { await speechDetector.start() }
    }

    private func handleSpeechEnded() {
        guard !isBargeInPaused else { return }
        guard state == .listening || state == .conversationMode else { return }
        guard hasSpokenThisTurn, !currentTranscription.isEmpty else { return }

        AppLog.debug(.voice, "VAD end-of-speech -> committing in \(Constants.Voice.vadCommitGrace)s: '\(currentTranscription)'", sensitive: true)
        MetricsCollector.shared.markSpeechEnd()
        vadCommitPending = true
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.Voice.vadCommitGrace, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.vadCommitPending else { return }
                self.vadCommitPending = false
                self.handleSilenceTimeout()
            }
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.authorizationStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    // MARK: - Start/Stop

    func startListening() throws {
        guard authorizationStatus == .authorized else {
            throw VoiceCommandError.notAuthorized
        }

        guard !isListening else { return }

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw VoiceCommandError.audioEngineUnavailable
        }

        if SessionRecorder.shared.isRecording {
            SessionRecorder.shared.switchToSharedMic()
        }

        state = isWakeWordEnabled ? .idle : .listening

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw VoiceCommandError.requestCreationFailed
        }

        configureRecognitionRequest(recognitionRequest)

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            AppLog.warning(.voice, "Input unavailable (format \(recordingFormat.sampleRate)Hz/\(recordingFormat.channelCount)ch) — skipping listen")
            self.recognitionRequest = nil
            self.audioEngine = nil
            throw VoiceCommandError.audioEngineUnavailable
        }

        markRouteChange()
        let detector = speechDetector
        if let reason = OVCatchException({
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                if let self, self.isInStabilizationWindow() && Self.isSilentOrZeroBuffer(buffer) {
                    return
                }
                recognitionRequest.append(buffer)
                detector.feed(buffer)
                SessionRecorder.shared.appendMicAudio(buffer)
            }
        }) {
            AppLog.error(.voice, "installTap failed: \(reason)")
            self.recognitionRequest = nil
            self.audioEngine = nil
            throw VoiceCommandError.audioEngineUnavailable
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            if SessionRecorder.shared.isRecording {
                SessionRecorder.shared.switchToSharedMic()
            }
        } catch {
            AppLog.error(.voice, "Failed to start audio engine: \(error.localizedDescription)")
            audioEngine.inputNode.removeTap(onBus: 0)
            self.recognitionRequest = nil
            self.audioEngine = nil
            throw VoiceCommandError.audioEngineUnavailable
        }

        recognitionGeneration += 1
        let generation = recognitionGeneration
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self, generation == self.recognitionGeneration else { return }
                self.handleRecognitionResult(result: result, error: error)
                self.restartIfRecognizerEnded(result: result, error: error)
            }
        }

        isListening = true
        VoiceCaptureTracker.shared.set(true)
        AppLog.info(.voice, "Started listening - audio engine running")
    }

    /// Configures partial results, on-device recognition (T8.1), dynamic taskHint (T8.2), and contextual phrases.
    private func configureRecognitionRequest(_ request: SFSpeechAudioBufferRecognitionRequest) {
        request.shouldReportPartialResults = true
        let supportsOnDevice = speechRecognizer?.supportsOnDeviceRecognition ?? false
        isOnDeviceRecognition = supportsOnDevice
        if supportsOnDevice {
            request.requiresOnDeviceRecognition = true
        }
        // T8.2: `.search` for short wake words / reading commands; `.dictation` for full questions.
        request.taskHint = (state == .listening || state == .conversationMode) ? .dictation : .search

        var phrases = [
            "Ok Vision", "Okay Vision", "Hey Vision", "Vision",
            "ô kê vi dơn", "ô kê vi giừn", "ô kê vision",
            "ok vi dơn", "ok vi giừn",
            "ốc vi dơn", "ốc vi giừn",
            "ê vi dơn", "vi dơn", "vi giừn",
            "oke vision", "oke vi dơn", "oke vi giừn",
            "tạm dừng", "tiếp tục", "tiếp", "đọc lại", "dòng tiếp", "dòng trước",
            "câu tiếp", "câu trước", "chậm lại", "nhanh lên", "dừng lại", "thôi", "dừng",
            "chụp ảnh", "giải bài này", "giải tiếp", "tính cái này", "bài toán"
        ]
        if !wakeWord.isEmpty { phrases.insert(wakeWord, at: 0) }
        request.contextualStrings = phrases
    }

    /// Clears accumulated echo buffer at the start of each new ReadingEngine segment so wake-word
    /// reading controls stay near the start of the recognizer transcript (PLAN.md N6).
    func resetBufferForNewSegment() {
        guard isListening, state == .processing else { return }
        guard Date().timeIntervalSince(lastRecognizerRestart) >= minRestartInterval else { return }
        lastRecognizerRestart = Date()
        restartRecognition()
    }

    private func needsAlwaysOnRecognizer() -> Bool {
        if state == .idle && isWakeWordEnabled { return true }
        if state == .conversationMode { return true }
        // N6: keep recognizer alive across ~1 minute SFSpeechRecognizer timeout during long essay reading.
        if state == .processing && ((shouldAllowInterrupt?() == true) || (isPausedOrWaitingForNext?() == true)) {
            return true
        }
        return false
    }

    private func restartIfRecognizerEnded(result: SFSpeechRecognitionResult?, error: Error?) {
        let ended = (error != nil) || (result?.isFinal ?? false)
        guard ended, isListening, needsAlwaysOnRecognizer() else { return }
        if let error {
            AppLog.debug(.voice, "Recognizer ended (\(error.localizedDescription)) — scheduling relaunch")
        }
        scheduleWakeWordRestart()
    }

    private func scheduleWakeWordRestart() {
        guard !wakeWordRestartScheduled else { return }
        wakeWordRestartScheduled = true
        let delay = max(0, minRestartInterval - Date().timeIntervalSince(lastRecognizerRestart))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.wakeWordRestartScheduled = false
            guard self.isListening, self.needsAlwaysOnRecognizer() else { return }
            self.lastRecognizerRestart = Date()
            self.restartRecognition()
        }
    }

    func stopListening() {
        recognitionGeneration += 1
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        speechDetector.reset()
        vadCommitPending = false

        silenceTimer?.invalidate()
        silenceTimer = nil
        commandTimeoutTimer?.invalidate()
        commandTimeoutTimer = nil
        conversationTimeoutTimer?.invalidate()
        conversationTimeoutTimer = nil

        isListening = false
        VoiceCaptureTracker.shared.set(false)
        state = .idle
        currentTranscription = ""
        hasSpokenThisTurn = false
        AppLog.info(.voice, "Stopped listening")
    }

    /// Enter conversation mode (no wake word needed for follow-ups).
    /// T8.2: updates `state` BEFORE calling `restartRecognition()` so `taskHint` switches to `.dictation`.
    func enterConversationMode() {
        state = .conversationMode
        hasSpokenThisTurn = false
        currentTranscription = ""
        restartRecognition()
        startConversationTimeout()
        AppLog.info(.voice, "Entered conversation mode")
    }

    /// Enters processing state (e.g. while reading from History / typed turn with active mic).
    func enterProcessingState() {
        guard isListening else { return }
        state = .processing
        conversationTimeoutTimer?.invalidate()
        conversationTimeoutTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        currentTranscription = ""
        hasSpokenThisTurn = false
    }

    private func restartRecognition() {
        guard isListening else { return }

        recognitionGeneration += 1
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        audioEngine?.inputNode.removeTap(onBus: 0)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        configureRecognitionRequest(recognitionRequest)

        guard let audioEngine = audioEngine else { return }

        if !audioEngine.isRunning {
            audioEngine.prepare()
            do {
                try audioEngine.start()
                AppLog.info(.voice, "Engine had stopped (route change) — restarted in place")
            } catch {
                AppLog.error(.voice, "Engine restart failed: \(error.localizedDescription)")
            }
        }

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            AppLog.warning(.voice, "Input unavailable on reinstall — skipping tap")
            self.recognitionRequest = nil
            return
        }

        markRouteChange()
        speechDetector.reset()
        let detector = speechDetector
        if let reason = OVCatchException({
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                if let self, self.isInStabilizationWindow() && Self.isSilentOrZeroBuffer(buffer) {
                    return
                }
                recognitionRequest.append(buffer)
                detector.feed(buffer)
                SessionRecorder.shared.appendMicAudio(buffer)
            }
        }) {
            AppLog.error(.voice, "installTap (reinstall) failed: \(reason)")
            self.recognitionRequest = nil
            return
        }

        recognitionGeneration += 1
        let generation = recognitionGeneration
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self, generation == self.recognitionGeneration else { return }
                self.handleRecognitionResult(result: result, error: error)
                self.restartIfRecognizerEnded(result: result, error: error)
            }
        }

        AppLog.debug(.voice, "Restarted recognition (cleared buffer)")
        MetricsCollector.shared.count("recognition_restart")
    }

    func exitConversationMode() {
        state = isWakeWordEnabled ? .idle : .listening
        vadCommitPending = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        conversationTimeoutTimer?.invalidate()
        conversationTimeoutTimer = nil
        hasSpokenThisTurn = false
        restartRecognition()
        AppLog.info(.voice, "Exited conversation mode")
    }

    private func startConversationTimeout() {
        conversationTimeoutTimer?.invalidate()
        if shouldSuppressConversationTimeout?() == true { return }
        let configured = SettingsManager.shared.settings.conversationTimeout
        let timeout = configured > 0 ? configured : Constants.Voice.conversationTimeout
        conversationTimeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleConversationTimeout()
            }
        }
    }

    private func handleConversationTimeout() {
        guard state == .conversationMode else { return }
        // N7: never cut off an active reading/paused/dictation session.
        if shouldSuppressConversationTimeout?() == true {
            AppLog.debug(.voice, "Conversation timeout suppressed while reading is active")
            return
        }

        if hasSpokenThisTurn {
            AppLog.debug(.voice, "User is speaking, extending conversation")
        } else {
            AppLog.info(.voice, "Conversation timeout - no speech detected")
            exitConversationMode()
            onConversationTimeout?()
        }
    }

    // MARK: - Recognition Handling

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        guard isListening else { return }

        guard let result = result else {
            if let error = error {
                let errorMsg = error.localizedDescription
                if !errorMsg.contains("No speech detected") && !errorMsg.contains("canceled") {
                    AppLog.warning(.voice, "Recognition error: \(errorMsg)")
                }
            }
            return
        }

        let transcription = result.bestTranscription.formattedString
        AppLog.debug(.voice, "heard(\(state)): \"\(transcription)\"", sensitive: true)

        switch state {
        case .idle:
            currentTranscription = transcription
            if detectWakeWord(in: transcription) {
                handleWakeWordDetected()
            }

        case .listening, .conversationMode:
            if isBargeInPaused { return }

            let command = Self.stripWakeWord(from: transcription, defaultWakeWord: wakeWord)
            currentTranscription = command

            if command.count > 3 {
                hasSpokenThisTurn = true
                conversationTimeoutTimer?.invalidate()
            }

            resetSilenceTimer()

            if result.isFinal && !command.isEmpty {
                handleCommandComplete(command)
            }

        case .processing:
            // 1. Paused or dictation waitingForNext: app is silent, so bare reading commands work WITHOUT wake word (§4.4).
            if isPausedOrWaitingForNext?() == true {
                let candidate = Self.stripWakeWord(from: transcription, defaultWakeWord: wakeWord)
                if let readingCmd = ReadingCommand.parse(candidate) {
                    AppLog.info(.voice, "Bare reading command while silent: \(readingCmd)")
                    currentTranscription = ""
                    onReadingCommand?(readingCmd)
                    restartRecognition()
                    return
                }
            }

            let allowInterrupt = shouldAllowInterrupt?() ?? false

            // 2. Wake word + reading command or new question during active reading / thinking.
            if allowInterrupt && detectWakeWord(in: transcription, bypassCooldown: true)
                && (wakeWordAtStart(transcription) || !isBargeInPaused) {
                let command = extractCommandAfterWakeWord(transcription)
                guard !command.isEmpty else { return }

                // Check reading commands first ("Ok Vision tạm dừng", "Ok Vision đọc lại câu 3", "Ok Vision dừng lại")
                if let readingCmd = ReadingCommand.parse(command) {
                    AppLog.info(.voice, "Wake-word reading command: \(readingCmd)")
                    currentTranscription = ""
                    hasSpokenThisTurn = false
                    silenceTimer?.invalidate(); silenceTimer = nil
                    onReadingCommand?(readingCmd)
                    restartRecognition()
                    return
                }

                // Legacy stop phrase fallback (e.g. "Ok Vision cancel")
                if isStopPhrase(transcription) {
                    AppLog.info(.voice, "Stop phrase during TTS — halting")
                    onStopCommand?()
                    currentTranscription = ""
                    hasSpokenThisTurn = false
                    silenceTimer?.invalidate(); silenceTimer = nil
                    state = isWakeWordEnabled ? .idle : .listening
                    restartRecognition()
                    return
                }

                // Genuine new question mid-reading (N9): stop TTS + cancel Gemini and capture verbatim.
                AppLog.info(.voice, "Wake word + new question during TTS — interrupting")
                AppLog.debug(.voice, "Interrupt question: '\(command)'", sensitive: true)
                onWakeWordDetected?()

                state = .listening
                currentTranscription = command
                hasSpokenThisTurn = true
                resetSilenceTimer()

                if result.isFinal {
                    handleCommandComplete(command)
                }
                return
            }
        }
    }

    private func isStopPhrase(_ text: String) -> Bool {
        guard detectWakeWord(in: text, bypassCooldown: true) else { return false }
        let lower = text.lowercased()
        if lower.contains("video") || lower.contains("stream") { return false }
        let stopWords = [
            "stop", "be quiet", "shut up", "silence", "quiet", "enough", "cancel",
            "dừng lại", "thôi", "dừng", "dừng đi", "thôi đi"
        ]
        return stopWords.contains { lower.contains($0) }
    }

    private func wakeWordAtStart(_ text: String) -> Bool {
        let lower = text.lowercased()
        var variations = Self.wakeWordVariations
        let wakeWordLower = wakeWord.lowercased()
        if !variations.contains(wakeWordLower) {
            variations.insert(wakeWordLower, at: 0)
        }
        for v in variations {
            if let r = lower.range(of: v) {
                if lower.distance(from: lower.startIndex, to: r.lowerBound) <= 15 { return true }
            }
        }
        return false
    }

    private func detectWakeWord(in text: String, bypassCooldown: Bool = false) -> Bool {
        guard bypassCooldown || !wakeWordCooldownActive else { return false }

        let lowercased = text.lowercased()
        var variations = Self.wakeWordVariations
        let wakeWordLower = wakeWord.lowercased()
        if !variations.contains(wakeWordLower) {
            variations.insert(wakeWordLower, at: 0)
        }

        let detected = variations.contains { lowercased.contains($0) }
        if detected {
            AppLog.debug(.voice, "Detected wake word in: '\(text)'", sensitive: true)
        }
        return detected
    }

    private func extractCommandAfterWakeWord(_ text: String) -> String {
        Self.stripWakeWord(from: text, defaultWakeWord: wakeWord)
    }

    private func handleWakeWordDetected() {
        AppLog.info(.voice, "Wake word detected")
        MetricsCollector.shared.count("wake_word_detected")

        wakeWordCooldownActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Voice.wakeWordCooldown) { [weak self] in
            self?.wakeWordCooldownActive = false
        }

        if playActivationSound {
            playActivation()
        }

        state = .listening
        currentTranscription = ""
        startCommandTimeout()
        onWakeWordDetected?()
    }

    private func handleCommandComplete(_ text: String) {
        guard !isBargeInPaused else {
            AppLog.debug(.voice, "Ignoring handleCommandComplete because barge-in is paused (TTS active)")
            return
        }

        let command = Self.stripWakeWord(from: text, defaultWakeWord: wakeWord)
        guard !command.isEmpty else { return }

        AppLog.info(.voice, "Command captured (\(command.count) chars)")
        AppLog.debug(.voice, "Command text: \(command)", sensitive: true)
        MetricsCollector.shared.count("command_captured")

        state = .processing
        silenceTimer?.invalidate()
        commandTimeoutTimer?.invalidate()
        vadCommitPending = false
        currentTranscription = ""

        restartRecognition()
        onCommandCaptured?(command)
    }

    // MARK: - Timers

    private func resetSilenceTimer() {
        guard !speechDetector.isAvailable else { return }
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: Constants.Voice.silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleSilenceTimeout()
            }
        }
    }

    private func handleSilenceTimeout() {
        guard !isBargeInPaused else { return }
        guard state == .listening || state == .conversationMode else { return }

        MetricsCollector.shared.markSpeechEnd()

        if !currentTranscription.isEmpty {
            handleCommandComplete(currentTranscription)
        } else if state == .conversationMode {
            exitConversationMode()
        }
    }

    private func startCommandTimeout() {
        commandTimeoutTimer?.invalidate()
        commandTimeoutTimer = Timer.scheduledTimer(withTimeInterval: Constants.Voice.commandTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleCommandTimeout()
            }
        }
    }

    private func handleCommandTimeout() {
        guard state == .listening else { return }
        AppLog.info(.voice, "Command timeout")

        if !currentTranscription.isEmpty {
            handleCommandComplete(currentTranscription)
        } else {
            state = .idle
            currentTranscription = ""
        }
    }

    // MARK: - Audio Feedback

    private func setupActivationSound() {
        if let soundURL = Bundle.main.url(forResource: "activation_chime", withExtension: "wav") {
            activationSound = try? AVAudioPlayer(contentsOf: soundURL)
            activationSound?.prepareToPlay()
        }
    }

    private func playActivation() {
        activationSound?.currentTime = 0
        activationSound?.play()
    }
}

// MARK: - Errors

enum VoiceCommandError: LocalizedError {
    case notAuthorized
    case audioEngineUnavailable
    case requestCreationFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Chưa được cấp quyền nhận dạng giọng nói"
        case .audioEngineUnavailable: return "Micro đang bận hoặc không khả dụng"
        case .requestCreationFailed: return "Không tạo được yêu cầu nhận dạng giọng nói"
        }
    }
}
