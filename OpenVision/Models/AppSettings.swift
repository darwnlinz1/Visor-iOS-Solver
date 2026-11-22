// OpenVision - AppSettings.swift
// Settings data model with Codable support for JSON persistence.
//
// One brain (Gemini), one glasses workflow — so only the settings that workflow uses live here.
// Older settings.json files with extra fields (other backends, Kokoro, telemetry…) still load:
// unknown keys are ignored and missing ones fall back to the defaults (see SettingsManager).
// All v2 enum-like preferences are stored as raw Strings with safe fallback getters (PLAN.md N18).

import Foundation

/// What a press of the glasses' capture button does (Meta DAT Inputs, experimental).
enum GlassesButtonAction: String, Codable, CaseIterable, Identifiable {
    /// Take a full-resolution photo; it becomes the context for the next question.
    case capture
    /// Take a photo and solve it right away — no need to speak.
    case captureAndSolve
    /// Read the last answer again.
    case repeatAnswer
    /// Do nothing.
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .capture: return "Chụp ảnh (chờ câu hỏi)"
        case .captureAndSolve: return "Chụp và giải ngay"
        case .repeatAnswer: return "Đọc lại câu trả lời"
        case .none: return "Không làm gì"
        }
    }
}

/// App settings persisted to Documents/settings.json (the API key goes to the Keychain; see SettingsSecrets)
struct AppSettings: Codable, Equatable {
    // MARK: - Gemini

    /// Google Gemini API key(s) — several may be entered, comma-separated (GeminiLiveService.parseKeys).
    var geminiAPIKey: String = ""

    // MARK: - Voice input

    /// Wake word phrase (default: "Ok Vision")
    var wakeWord: String = "Ok Vision"

    /// Whether wake word detection is enabled
    var wakeWordEnabled: Bool = true

    /// Play activation chime on wake word detection
    var playActivationSound: Bool = true

    /// Conversation timeout in seconds (auto-end after silence)
    var conversationTimeout: TimeInterval = 30

    /// Language the speech recognizer listens for: "auto" (the iPhone's language), "vi-VN" or
    /// "en-US". iOS recognizes one language at a time; answers always follow the question's language.
    var recognitionLanguage: String = "auto"

    /// Prefer the glasses' Bluetooth microphone for voice input when they're the connected audio
    /// device — true hands-free. Falls back to the phone mic automatically when the glasses aren't
    /// the audio route. Turn off to always use the phone. (Glasses mic uses more battery.)
    var preferGlassesMic: Bool = true

    // MARK: - Glasses (Meta DAT)

    /// Receive the glasses' capture-button presses in the app (photos go straight to Gemini at full
    /// resolution, no Camera Roll import). Experimental in the Meta SDK: needs the glasses in
    /// Developer Mode; falls back to the Camera Roll workflow when unavailable.
    var captureButtonEnabled: Bool = true
    var shortPressAction: GlassesButtonAction = .capture
    var holdAction: GlassesButtonAction = .captureAndSolve
    var doublePressAction: GlassesButtonAction = .repeatAnswer
    /// Also route the touchpad to the app — only if button presses never arrive (a known SDK
    /// quirk); while on, the temple touchpad no longer controls music/volume.
    var captureButtonIncludeTouchpad: Bool = false
    /// Photos taken through the SDK: full sensor resolution (~12 MP, 30-60 s over Bluetooth) or
    /// fast stream still (~1-2 s, default per PLAN.md T7.4).
    var fullResolutionPhotos: Bool = false

    // MARK: - Voice output (Apple system voices, one per language)

    /// English voice identifier (nil = best installed en-US voice)
    var selectedVoiceIdentifier: String? = nil

    /// Vietnamese voice identifier (nil = best installed vi-VN voice)
    var selectedVietnameseVoiceIdentifier: String? = nil

    /// Speaking rate for plain OTHER answers & notices, 0.35 … 0.6. Apple's default is 0.5.
    var speechRate: Float = 0.5

    // MARK: - Reading engine v2 (PLAN.md §4.6)

    /// Speaking rate for multiple-choice answers (0.35 … 0.6).
    var mcqRate: Float = 0.5

    /// Speaking rate for essay / worked solutions (0.3 … 0.6; slower so the student can write).
    var essayRate: Float = 0.42

    /// Pause between MCQ answers in seconds (0 … 2).
    var pauseBetweenAnswers: Double = 0.5

    /// Pause between essay lines in seconds (0 … 5).
    var pauseBetweenLines: Double = 1.2

    /// Read "Dòng 1", "Dòng 2" before each essay line.
    var readLineNumbers: Bool = true

    /// Multiplier applied to rate for math formula pieces (0.6 … 1.0).
    var mathRateFactor: Double = 0.85

    /// Extra pause after each math formula piece in seconds (0 … 1.5).
    var pauseAfterFormula: Double = 0.3

    /// Dictation mode (Đọc chép): pause after each essay line and wait for "tiếp" / button tap.
    var dictationMode: Bool = false

    /// Auto-continue delay in dictation mode in seconds (0 = wait for command, up to 30 s).
    var dictationAutoContinue: Double = 0

    /// Repeat every math formula twice while in dictation mode.
    var repeatFormulaInDictation: Bool = false

    // MARK: - Vietnamese math speech (stored as Strings for forward-compatible decoding, N18)

    /// "natural" or "explicit"
    var mathVerbosity: String = "natural"

    /// "tren" ("a trên b") or "phan" ("a phần b")
    var symbolicFractionWord: String = "tren"

    /// "am" ("âm 3") or "tru" ("trừ 3")
    var negativeWord: String = "am"

    /// "vietnameseNames" ("ích", "bê", D3) or "asWritten"
    var letterStyle: String = "vietnameseNames"

    /// Custom pronunciation overrides: token -> spoken words.
    var pronunciationOverrides: [String: String] = [:]

    // MARK: - AI Customization

    /// Custom instructions appended to AI system prompt
    var userPrompt: String = ""

    /// Key-value memories the AI can read and manage
    var memories: [String: String] = [:]

    // MARK: - Display & Debug

    /// Legacy key kept for backward-compatible decoding of older settings.json files.
    var showTranscripts: Bool = true

    /// Hide text on the Live screen (audio-only mode).
    var hideTextSpeakOnly: Bool = false

    /// Show live state/route debug overlay on the Live screen.
    var debugOverlay: Bool = false

    /// Log detailed diagnostics including user speech/text transcripts (kept on-device only).
    var verboseLogging: Bool = false

    // MARK: - Computed Properties

    /// Whether at least one Gemini key is set (keys are never compiled into the app).
    var isGeminiConfigured: Bool {
        !GeminiLiveService.parseKeys(geminiAPIKey).isEmpty
    }

    /// Label for the status pill.
    var backendDisplayName: String { "Gemini" }

    var clampedSpeechRate: Float { min(max(speechRate, 0.35), 0.6) }
    var clampedMcqRate: Float { min(max(mcqRate, 0.35), 0.6) }
    var clampedEssayRate: Float { min(max(essayRate, 0.3), 0.6) }
    var clampedPauseBetweenAnswers: Double { min(max(pauseBetweenAnswers, 0), 2.0) }
    var clampedPauseBetweenLines: Double { min(max(pauseBetweenLines, 0), 5.0) }
    var clampedMathRateFactor: Double { min(max(mathRateFactor, 0.6), 1.0) }
    var clampedPauseAfterFormula: Double { min(max(pauseAfterFormula, 0), 1.5) }
    var clampedDictationAutoContinue: Double { min(max(dictationAutoContinue, 0), 30.0) }

    var mathReadingStyle: MathReadingStyle {
        MathReadingStyle(
            mathVerbosity: mathVerbosity,
            symbolicFractionWord: symbolicFractionWord,
            negativeWord: negativeWord,
            letterStyle: letterStyle,
            pronunciationOverrides: pronunciationOverrides
        )
    }
}
