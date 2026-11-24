// Reybain - SettingsSecretsTests.swift
// The Gemini API key lives in the Keychain, never in settings.json — and is not lost on the way.

import XCTest
@testable import Reybain

final class SettingsSecretsTests: XCTestCase {

    func testTheGeminiKeyIsTheSecretField() {
        let accounts = SettingsSecrets.fields.map(\.account)
        XCTAssertEqual(Set(accounts).count, accounts.count, "one Keychain account per field")
        XCTAssertEqual(accounts, ["geminiAPIKey"])
    }

    func testFileIsWrittenWithoutTheKey() throws {
        var settings = AppSettings()
        settings.geminiAPIKey = "AQ.secret-key"
        settings.wakeWord = "Ok Vision test"
        let json = String(decoding: try JSONEncoder().encode(SettingsSecrets.forFile(settings, keepInFile: [])), as: UTF8.self)
        XCTAssertFalse(json.contains("AQ.secret-key"))
        XCTAssertTrue(json.contains("Ok Vision test"), "other settings stay in the file")
    }

    func testAFailedKeychainWriteKeepsTheKeyInTheFile() {
        var settings = AppSettings()
        settings.geminiAPIKey = "AQ.secret-key"
        let file = SettingsSecrets.forFile(settings, keepInFile: ["geminiAPIKey"])
        XCTAssertEqual(file.geminiAPIKey, "AQ.secret-key")
    }

    func testLoadingTakesTheKeyFromTheKeychain() {
        let merged = SettingsSecrets.merge(file: AppSettings(), keychain: ["geminiAPIKey": .value("from-keychain")])
        XCTAssertEqual(merged.settings.geminiAPIKey, "from-keychain")
        XCTAssertTrue(merged.unreadable.isEmpty)
    }

    func testAnOlderFilesKeyWinsSoItCanBeMoved() {
        var file = AppSettings()
        file.geminiAPIKey = "from-old-file"
        let merged = SettingsSecrets.merge(file: file, keychain: ["geminiAPIKey": .value("stale")])
        XCTAssertEqual(merged.settings.geminiAPIKey, "from-old-file")
    }

    func testAnUnreadableKeychainIsRememberedNotTreatedAsEmpty() {
        let merged = SettingsSecrets.merge(file: AppSettings(), keychain: ["geminiAPIKey": .unreadable])
        XCTAssertEqual(merged.settings.geminiAPIKey, "")
        XCTAssertEqual(merged.unreadable, ["geminiAPIKey"], "so a save can't delete the stored key")
    }

    /// A settings.json from before the clean-up (other backends, Kokoro, telemetry) still loads,
    /// and all new v2 §4.6 settings fall back to their defaults without wiping saved fields (N18).
    func testOlderSettingsFilesStillDecode() throws {
        let old = #"{"aiBackend":"local_gemma","ttsEngine":"kokoro","telemetryURL":"http://x","wakeWord":"Hey Vision","showTranscripts":false}"#
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any] ?? [:]
        let onDisk = try JSONSerialization.jsonObject(with: Data(old.utf8)) as? [String: Any] ?? [:]
        let merged = defaults.merging(onDisk) { _, disk in disk }
        let settings = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: merged))
        XCTAssertEqual(settings.wakeWord, "Hey Vision")
        XCTAssertFalse(settings.showTranscripts)
        XCTAssertEqual(settings.mcqRate, 0.5)
        XCTAssertEqual(settings.essayRate, 0.42)
        XCTAssertEqual(settings.pauseBetweenAnswers, 0.5)
        XCTAssertEqual(settings.pauseBetweenLines, 1.2)
        XCTAssertTrue(settings.readLineNumbers)
        XCTAssertEqual(settings.mathRateFactor, 0.85)
        XCTAssertEqual(settings.pauseAfterFormula, 0.3)
        XCTAssertFalse(settings.dictationMode)
        XCTAssertEqual(settings.dictationAutoContinue, 0)
        XCTAssertFalse(settings.repeatFormulaInDictation)
        XCTAssertEqual(settings.mathVerbosity, "natural")
        XCTAssertEqual(settings.symbolicFractionWord, "tren")
        XCTAssertEqual(settings.negativeWord, "am")
        XCTAssertEqual(settings.letterStyle, "vietnameseNames")
        XCTAssertEqual(settings.pronunciationOverrides, [:])
        XCTAssertFalse(settings.hideTextSpeakOnly)
        XCTAssertFalse(settings.debugOverlay)
        XCTAssertFalse(settings.verboseLogging)
        XCTAssertFalse(settings.fullResolutionPhotos)
    }

    func testKeychainRoundTrip() {
        // A test-only account, so the app's real keys on the device are never touched.
        let account = "test-\(UUID().uuidString)"
        defer { SettingsSecrets.write("", account: account) }
        XCTAssertEqual(SettingsSecrets.read(account), .none)
        XCTAssertTrue(SettingsSecrets.write("first", account: account))
        XCTAssertEqual(SettingsSecrets.read(account), .value("first"))
        XCTAssertTrue(SettingsSecrets.write("second", account: account))
        XCTAssertEqual(SettingsSecrets.read(account), .value("second"))
        XCTAssertTrue(SettingsSecrets.write("", account: account), "clearing a key deletes it")
        XCTAssertEqual(SettingsSecrets.read(account), .none)
    }
}
