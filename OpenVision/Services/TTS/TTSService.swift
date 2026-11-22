// OpenVision - TTSService.swift
// Text-to-speech service using AVSpeechSynthesizer + VietMathSpeech (PLAN.md T3.3, T5.1, N4, N5).

import AVFoundation
import Foundation

/// Abstraction over `AVSpeechSynthesizer` so `ReadingEngine` can be tested deterministically
/// without hardware audio output (PLAN.md §4.4, T5.2).
@MainActor
protocol SpeechSynthesizing: AnyObject {
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }
    var onUtteranceFinished: (() -> Void)? { get set }
    var onWordRange: ((NSRange, String) -> Void)? { get set }
    var onPauseChanged: ((Bool) -> Void)? { get set }

    func speakPiece(_ utterance: ScheduledUtterance)
    func pause()
    func continueSpeaking()
    func stop()
}

/// Speaks replies through the glasses or phone speaker: converts math via `VietMathSpeech`
/// BEFORE safety-net cleaning (fixing N4), keeps one voice language across an entire reply
/// (fixing N5), and guards against stalled AudioQueue initialization (`-66680`).
@MainActor
final class TTSService: NSObject, ObservableObject, SpeechSynthesizing {
    // MARK: - Singleton

    static let shared = TTSService()

    // MARK: - Published State

    @Published var isSpeaking: Bool = false
    @Published var isPaused: Bool = false

    // MARK: - Callbacks

    /// Called when speech starts
    var onSpeechStarted: (() -> Void)?

    /// Called when all queued speech finishes or is stopped
    var onSpeechEnded: (() -> Void)?

    /// Called after each individual `ReadingEngine` utterance finishes (T5.1 / T5.2)
    var onUtteranceFinished: (() -> Void)?

    /// Called as each word is spoken (for live UI highlight, T5.1)
    var onWordRange: ((NSRange, String) -> Void)?

    /// Called when pause state transitions via `didPause` / `didContinue` (T5.1)
    var onPauseChanged: ((Bool) -> Void)?

    // MARK: - Speech Synthesizer

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Queue state

    /// Utterances enqueued but not yet finished. `isSpeaking` only drops to false when this
    /// hits 0 AND no more chunks are coming — so it doesn't flap between queued pieces.
    var pendingUtterances: Int { activeUtterances.count }

    private var activeUtterances = Set<ObjectIdentifier>()
    /// Utterances driven by `ReadingEngine` (each reports completion via `onUtteranceFinished`).
    private var pieceUtterances = Set<ObjectIdentifier>()
    /// Watchdog tasks that recover if `didStart` never fires (e.g. AudioQueue `-66680` / speechd stall).
    private var startWatchdogs: [ObjectIdentifier: Task<Void, Never>] = [:]

    /// The language of the reply being spoken (locked for the whole reply, fixing N5).
    private var replyIsVietnamese: Bool?

    private var streamingActive = false

    /// Lead-in silence before the first piece of a reply: Bluetooth speakers drop the first
    /// few hundred milliseconds of audio after silence, which clipped the start of answers.
    static let bluetoothLeadIn: TimeInterval = 0.3

    /// Maximum wait for `AVSpeechSynthesizer` to fire `didStart` on an utterance before treating
    /// the audio device as stalled (prevents permanent `isSpeaking = true` deadlock on AudioQueue error).
    static let startWatchdogSeconds: TimeInterval = 12.0

    // MARK: - Voice Selection

    /// Auto-detect Vietnamese characters or math keywords in the text
    nonisolated static func containsVietnamese(_ text: String) -> Bool {
        let vietnamesePattern = "[àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬÈÉẺẼẸÊỀẾỂỄỆÌÍỈĨỊÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢÙÚỦŨỤƯỪỨỬỮỰỲÝỶỸỴĐ]"
        if text.range(of: vietnamesePattern, options: .regularExpression) != nil {
            return true
        }
        let lower = text.lowercased()
        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let viWords: Set<String> = ["nghiem", "bang", "chia", "nhan", "cong", "tru"]
        let viPhrases = ["phuong trinh", "ket qua", "dap an", "chup anh", "giai giup", "giai bai"]
        return !words.isDisjoint(with: viWords) || viPhrases.contains { lower.contains($0) }
    }

    // MARK: - Spoken Audio Cleaning (Safety net AFTER VietMathSpeech — fixes N4)

    /// Safety-net sanitizer run AFTER `VietMathSpeech.render`: removes lingering markdown markers
    /// (`**`, `#`, backticks) and stray forbidden markup (`$ { } \ ^ _`), while NEVER stripping
    /// math semantics, leading minus signs, or multiplication asterisks (PLAN.md N4, T3.3).
    /// `@inline(never)`: Blueprint checklist test 6 verifies this symbol is present in the
    /// Release Mach-O; with a single caller the optimizer would otherwise inline it away.
    @inline(never)
    static func cleanSpokenAudio(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        s = s.replacingOccurrences(of: #"\*{1,3}([^*]+)\*{1,3}"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"`{1,3}([^`]*)`{1,3}"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"#{1,6}\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[\$\{\}\\\^_]"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pure pipeline (T3.3): runs `VietMathSpeech.render` FIRST, passes every `.words` piece
    /// through `cleanSpokenAudio`, and attaches `.pause(ms)` to the preceding piece's `delayAfter`
    /// (never emitting empty utterances).
    static func spokenPieces(
        for text: String,
        vietnamese: Bool,
        style: MathReadingStyle = .default
    ) -> [(text: String, delayAfter: TimeInterval)] {
        let rendered = VietMathSpeech.render(text, vietnamese: vietnamese, style: style)
        var result: [(text: String, delayAfter: TimeInterval)] = []
        for piece in rendered {
            switch piece {
            case .words(let raw, _):
                let cleaned = cleanSpokenAudio(raw)
                guard !cleaned.isEmpty else { continue }
                result.append((text: cleaned, delayAfter: 0))
            case .pause(let ms):
                guard ms > 0, !result.isEmpty else { continue }
                result[result.count - 1].delayAfter += TimeInterval(ms) / 1000.0
            }
        }
        return result
    }

    /// True when a sentence says nothing about its language: no Vietnamese and fewer than two
    /// real words ("x = 2.", "B.", "3,5 cm."). Such sentences follow the reply's language.
    nonisolated static func isLanguageNeutral(_ text: String) -> Bool {
        guard !containsVietnamese(text) else { return false }
        let words = text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 3 }
        return words.count < 2
    }

    /// Voice for one language — the chosen voice, else the best installed one.
    private func voice(vietnamese: Bool) -> AVSpeechSynthesisVoice? {
        let settings = SettingsManager.shared.settings
        if vietnamese {
            if let id = settings.selectedVietnameseVoiceIdentifier,
               let chosen = AVSpeechSynthesisVoice(identifier: id), chosen.language.hasPrefix("vi") { return chosen }
            if let best = Self.bestVoice(for: "vi-VN") { return best }
        }
        if let id = settings.selectedVoiceIdentifier,
           let chosen = AVSpeechSynthesisVoice(identifier: id), !chosen.language.hasPrefix("vi") { return chosen }
        return Self.bestVoice(for: "en-US")
    }

    /// The voice for one text snippet: the chosen (or best installed) voice of its language.
    static func voice(forText text: String, vietnamese: AVSpeechSynthesisVoice? = nil,
                      english: AVSpeechSynthesisVoice? = nil) -> AVSpeechSynthesisVoice? {
        if containsVietnamese(text) {
            if let vietnamese, vietnamese.language.hasPrefix("vi") { return vietnamese }
            if let viVoice = bestVoice(for: "vi-VN") { return viVoice }
        }
        if let english, !english.language.hasPrefix("vi") { return english }
        return bestVoice(for: "en-US")
    }

    /// Highest-quality installed voice for a language (Premium > Enhanced > Default).
    static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        if let cached = bestVoiceCache[language] { return cached }
        let upgraded = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == language && $0.quality != .default && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        let voice = upgraded.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: language)
        bestVoiceCache[language] = voice
        return voice
    }

    private static var bestVoiceCache: [String: AVSpeechSynthesisVoice] = [:]

    /// Get all available voices for a language
    static func availableVoices(for languageCode: String = "en") -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languageCode) }
            .sorted { v1, v2 in
                if v1.quality != v2.quality {
                    return v1.quality.rawValue > v2.quality.rawValue
                }
                return v1.name < v2.name
            }
    }

    /// Get display name for a voice quality
    static func qualityDisplayName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .default: return "Mặc định"
        case .enhanced: return "Nâng cao (Enhanced)"
        case .premium: return "Cao cấp (Premium)"
        @unknown default: return "Không rõ"
        }
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Speak (single-shot for notices, errors, short replies)

    /// Speak text (single-shot: replaces anything currently playing). Uses one voice language
    /// for the entire reply (fixing N5) and converts formulas through `VietMathSpeech` first (fixing N4).
    func speak(_ text: String, languageCode: String? = nil) {
        stop()
        let cleaned = Self.cleanSpokenAudio(text)
        guard !cleaned.isEmpty else { return }
        if let languageCode {
            replyIsVietnamese = languageCode.lowercased().hasPrefix("vi")
        } else if !Self.isLanguageNeutral(cleaned) {
            replyIsVietnamese = Self.containsVietnamese(cleaned)
        } else {
            replyIsVietnamese = SolverIntent.speaksVietnamese
        }
        let sentences = TextChunking.sentences(text)
        for sentence in sentences.isEmpty ? [text] : sentences {
            enqueue(sentence)
        }
    }

    // MARK: - Streaming (sentence-by-sentence)

    func beginStreaming(languageCode: String? = nil) {
        stop()
        if let languageCode {
            replyIsVietnamese = languageCode.lowercased().hasPrefix("vi")
        }
        streamingActive = true
        isSpeaking = true
        onSpeechStarted?()
    }

    func speakChunk(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        enqueue(trimmed)
    }

    func endStreaming() {
        streamingActive = false
        if pendingUtterances == 0 {
            isSpeaking = false
            onSpeechEnded?()
        }
    }

    // MARK: - ReadingEngine per-piece playback (T5.1)

    func speakPiece(_ scheduled: ScheduledUtterance) {
        let text = scheduled.text
        let safeText = Self.cleanSpokenAudio(text)
        guard !safeText.isEmpty else {
            onUtteranceFinished?()
            return
        }
        let vietnamese = scheduled.languageCode.lowercased().hasPrefix("vi")
        replyIsVietnamese = vietnamese
        let utterance = AVSpeechUtterance(string: safeText)
        utterance.voice = voice(vietnamese: vietnamese)
        utterance.rate = min(max(scheduled.rate, AVSpeechUtteranceMinimumSpeechRate),
                             AVSpeechUtteranceMaximumSpeechRate)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = max(0, scheduled.preDelay)
        utterance.postUtteranceDelay = max(0, scheduled.postDelay)

        let id = ObjectIdentifier(utterance)
        let wasIdle = !isSpeaking
        activeUtterances.insert(id)
        pieceUtterances.insert(id)
        isSpeaking = true
        isPaused = false
        if wasIdle { onSpeechStarted?() }
        armStartWatchdog(for: id, preDelay: utterance.preUtteranceDelay)
        synthesizer.speak(utterance)
    }

    // MARK: - Internal enqueue (VietMathSpeech -> cleanSpokenAudio -> AVSpeechUtterance)

    private func enqueue(_ text: String) {
        let vietnamese: Bool
        if let locked = replyIsVietnamese {
            vietnamese = locked
        } else if !Self.isLanguageNeutral(text) {
            let detected = Self.containsVietnamese(text)
            replyIsVietnamese = detected
            vietnamese = detected
        } else {
            vietnamese = SolverIntent.speaksVietnamese
        }

        let settings = SettingsManager.shared.settings
        let pieces = Self.spokenPieces(for: text, vietnamese: vietnamese, style: settings.mathReadingStyle)
        guard !pieces.isEmpty else { return }

        let baseRate = min(max(settings.clampedSpeechRate, AVSpeechUtteranceMinimumSpeechRate),
                           AVSpeechUtteranceMaximumSpeechRate)

        for piece in pieces {
            let utterance = AVSpeechUtterance(string: piece.text)
            utterance.voice = voice(vietnamese: vietnamese)
            utterance.rate = baseRate
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0
            if activeUtterances.isEmpty {
                utterance.preUtteranceDelay = Self.bluetoothLeadIn
            }
            if piece.delayAfter > 0 {
                utterance.postUtteranceDelay = piece.delayAfter
            }
            let id = ObjectIdentifier(utterance)
            activeUtterances.insert(id)
            isSpeaking = true
            isPaused = false
            armStartWatchdog(for: id, preDelay: utterance.preUtteranceDelay)
            synthesizer.speak(utterance)
        }
    }

    private func armStartWatchdog(for id: ObjectIdentifier, preDelay: TimeInterval) {
        let waitSeconds = Self.startWatchdogSeconds + max(0, preDelay)
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.activeUtterances.contains(id) else { return }
            AppLog.error(.tts, "AVSpeechSynthesizer didStart watchdog fired after \(Int(waitSeconds))s — recovering stuck audio queue")
            self.recoverStalledUtterance(id)
        }
        startWatchdogs[id] = task
    }

    private func cancelWatchdog(for id: ObjectIdentifier) {
        startWatchdogs.removeValue(forKey: id)?.cancel()
    }

    private func cancelAllWatchdogs() {
        for (_, task) in startWatchdogs { task.cancel() }
        startWatchdogs.removeAll()
    }

    private func recoverStalledUtterance(_ id: ObjectIdentifier) {
        cancelWatchdog(for: id)
        let wasPiece = pieceUtterances.remove(id) != nil
        activeUtterances.remove(id)
        if activeUtterances.isEmpty && !streamingActive {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            isPaused = false
            onSpeechEnded?()
        }
        if wasPiece {
            onUtteranceFinished?()
        }
    }

    // MARK: - Playback control

    /// Stop speaking and clear the queue.
    func stop() {
        let wasSpeaking = isSpeaking || !activeUtterances.isEmpty
        cancelAllWatchdogs()
        activeUtterances.removeAll()
        pieceUtterances.removeAll()
        replyIsVietnamese = nil
        streamingActive = false
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        if wasSpeaking { onSpeechEnded?() }
    }

    /// Pause speaking
    func pause() {
        guard isSpeaking, !isPaused else { return }
        if synthesizer.pauseSpeaking(at: .word) {
            isPaused = true
            onPauseChanged?(true)
        }
    }

    /// Continue speaking
    func continueSpeaking() {
        guard isPaused else { return }
        if synthesizer.continueSpeaking() {
            isPaused = false
            onPauseChanged?(false)
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.cancelWatchdog(for: id)
            MetricsCollector.shared.markFirstAudio()
            if !self.isSpeaking {
                self.isSpeaking = true
                self.onSpeechStarted?()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let spoken = utterance.speechString
        Task { @MainActor in
            self.onWordRange?(characterRange, spoken)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPaused = true
            self.onPauseChanged?(true)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPaused = false
            self.onPauseChanged?(false)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.cancelWatchdog(for: id)
            guard self.activeUtterances.remove(id) != nil else { return }
            let wasPiece = self.pieceUtterances.remove(id) != nil
            if wasPiece {
                self.onUtteranceFinished?()
            }
            if self.activeUtterances.isEmpty && !self.streamingActive {
                self.isSpeaking = false
                self.isPaused = false
                self.onSpeechEnded?()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.cancelWatchdog(for: id)
            guard self.activeUtterances.remove(id) != nil else { return }
            self.pieceUtterances.remove(id)
            if self.activeUtterances.isEmpty {
                self.streamingActive = false
                self.isSpeaking = false
                self.isPaused = false
                self.onSpeechEnded?()
            }
        }
    }
}
