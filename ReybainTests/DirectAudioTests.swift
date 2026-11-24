// Reybain - DirectAudioTests.swift
// Unit tests for DirectAudioRecorder (WAV encoding, RMS metering, shared-tap PCM capture),
// GeminiLiveService multimodal audio userTurn payloads, Reybain wake-word variants, and PromptV2.

import AVFoundation
import XCTest
@testable import Reybain

@MainActor
final class DirectAudioTests: XCTestCase {

    // MARK: - DirectAudioRecorder WAV Encoding & Metering

    func testEncodeWAVProducesValid44ByteRIFFHeaderAndSamples() {
        let samples: [Int16] = [0, 1234, -1234, Int16.max, Int16.min]
        let wav = DirectAudioRecorder.encodeWAV(samples: samples, sampleRate: 16_000)

        let expectedDataBytes = samples.count * MemoryLayout<Int16>.size
        XCTAssertEqual(wav.count, 44 + expectedDataBytes)

        // RIFF / WAVE / fmt / data ASCII tags
        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: wav[12..<16], as: UTF8.self), "fmt ")
        XCTAssertEqual(String(decoding: wav[36..<40], as: UTF8.self), "data")

        // Canonical 16 kHz mono 16-bit PCM header fields
        XCTAssertEqual(readUInt32LE(wav, offset: 4), UInt32(36 + expectedDataBytes))
        XCTAssertEqual(readUInt32LE(wav, offset: 16), 16)       // PCM fmt chunk size
        XCTAssertEqual(readUInt16LE(wav, offset: 20), 1)        // AudioFormat = PCM
        XCTAssertEqual(readUInt16LE(wav, offset: 22), 1)        // Channels = mono
        XCTAssertEqual(readUInt32LE(wav, offset: 24), 16_000)   // SampleRate = 16 kHz
        XCTAssertEqual(readUInt32LE(wav, offset: 28), 32_000)   // ByteRate = 16000 * 2
        XCTAssertEqual(readUInt16LE(wav, offset: 32), 2)        // BlockAlign = 2 bytes
        XCTAssertEqual(readUInt16LE(wav, offset: 34), 16)       // BitsPerSample = 16
        XCTAssertEqual(readUInt32LE(wav, offset: 40), UInt32(expectedDataBytes))

        // Verify exact little-endian Int16 sample round-trip
        for (index, expected) in samples.enumerated() {
            let decoded = Int16(bitPattern: readUInt16LE(wav, offset: 44 + index * 2))
            XCTAssertEqual(decoded, expected, "sample mismatch at index \(index)")
        }
    }

    func testNormalizedRMSDistinguishesSilenceFromSpeechSignal() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))

        let silent = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        silent.frameLength = 1024
        XCTAssertEqual(DirectAudioRecorder.normalizedRMS(from: silent), 0, accuracy: 0.0001)

        let soft = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        soft.frameLength = 1024
        let loud = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        loud.frameLength = 1024

        let softData = try XCTUnwrap(soft.floatChannelData?[0])
        let loudData = try XCTUnwrap(loud.floatChannelData?[0])
        for i in 0..<1024 {
            let phase = Float(sin(2.0 * Double.pi * 440.0 * Double(i) / 16_000.0))
            softData[i] = 0.04 * phase
            loudData[i] = 0.40 * phase
        }

        let softRMS = DirectAudioRecorder.normalizedRMS(from: soft)
        let loudRMS = DirectAudioRecorder.normalizedRMS(from: loud)
        XCTAssertGreaterThan(softRMS, 0)
        XCTAssertLessThanOrEqual(loudRMS, 1.0)
        XCTAssertGreaterThan(loudRMS, softRMS)
    }

    func testSharedTapCaptureBuildsValidWAVAndTracksDuration() throws {
        let recorder = DirectAudioRecorder()
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let frameCount: AVAudioFrameCount = 8_000 // 0.5 seconds at 16 kHz
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let channel = try XCTUnwrap(buffer.int16ChannelData?[0])
        for i in 0..<Int(frameCount) {
            let wave = sin(2.0 * Double.pi * 440.0 * Double(i) / 16_000.0)
            channel[i] = Int16(wave * 12_000.0)
        }

        recorder.beginTapCapture()
        XCTAssertEqual(recorder.currentMode, .sharedTap)
        recorder.appendBuffer(buffer)
        let wav = try XCTUnwrap(recorder.finishTapCapture())

        XCTAssertEqual(recorder.currentMode, .idle)
        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(wav.count, 44 + Int(frameCount) * 2)
        XCTAssertEqual(recorder.lastCapturedDuration, 0.5, accuracy: 0.01)
        XCTAssertGreaterThan(recorder.lastCapturedPeakLevel, DirectAudioRecorder.minAudibleRMS)
    }

    // MARK: - GeminiLiveService Multimodal Audio Turn

    func testUserTurnIncludesAudioImageAndTextCleanly() throws {
        let fakeJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let wavAudio = DirectAudioRecorder.encodeWAV(samples: [100, -100, 200, -200], sampleRate: 16_000)

        // 1. Combined image + audio + text with ultra-high mediaResolution ONLY on image
        let combined = GeminiLiveService.userTurn(
            text: "Giải câu này giúp mình",
            imageData: fakeJPEG,
            audioData: wavAudio,
            audioMimeType: "audio/wav",
            perPartMediaResolution: true
        )
        XCTAssertEqual(combined["role"] as? String, "user")
        let parts = try XCTUnwrap(combined["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 3)

        let imageInline = try XCTUnwrap(parts[0]["inlineData"] as? [String: Any])
        XCTAssertEqual(imageInline["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(imageInline["data"] as? String, fakeJPEG.base64EncodedString())
        XCTAssertEqual((parts[0]["mediaResolution"] as? [String: Any])?["level"] as? String, "MEDIA_RESOLUTION_ULTRA_HIGH")

        let audioInline = try XCTUnwrap(parts[1]["inlineData"] as? [String: Any])
        XCTAssertEqual(audioInline["mimeType"] as? String, "audio/wav")
        XCTAssertEqual(audioInline["data"] as? String, wavAudio.base64EncodedString())
        XCTAssertNil(parts[1]["mediaResolution"], "mediaResolution should apply to images only, never audio")

        XCTAssertEqual(parts[2]["text"] as? String, "Giải câu này giúp mình")

        // 2. Audio + text only (Chat voice note without attached photo)
        let audioOnly = GeminiLiveService.userTurn(
            text: "Nghe đoạn ghi âm",
            imageData: nil,
            audioData: wavAudio
        )
        let audioOnlyParts = try XCTUnwrap(audioOnly["parts"] as? [[String: Any]])
        XCTAssertEqual(audioOnlyParts.count, 2)
        XCTAssertEqual((audioOnlyParts[0]["inlineData"] as? [String: Any])?["mimeType"] as? String, "audio/wav")
        XCTAssertEqual(audioOnlyParts[1]["text"] as? String, "Nghe đoạn ghi âm")
    }

    // MARK: - AppSettings & Reybain Wake Word Variants

    func testAppSettingsDirectAudioDefaultIsEnabled() {
        let settings = AppSettings()
        XCTAssertTrue(settings.directAudioToGemini)
        XCTAssertTrue(settings.fullResolutionPhotos)
        XCTAssertTrue(settings.spokenStatusUpdates)
    }

    func testReybainWakeWordVariantsAreRecognizedAndStripped() {
        let requiredReybain = [
            "ok reybain", "okay reybain", "hey reybain",
            "ô kê rây bên", "ok rây bên", "rây bên",
            "ok rayban", "hey rayban"
        ]
        for variant in requiredReybain {
            XCTAssertTrue(VoiceCommandService.wakeWordVariations.contains(variant), "missing wake word variant: \(variant)")
        }

        XCTAssertEqual(
            VoiceCommandService.stripWakeWord(from: "ok reybain giải bài này", defaultWakeWord: "Ok Vision"),
            "giải bài này"
        )
        XCTAssertEqual(
            VoiceCommandService.stripWakeWord(from: "ô kê rây bên câu 2", defaultWakeWord: "Ok Vision"),
            "câu 2"
        )
        XCTAssertEqual(
            VoiceCommandService.stripWakeWord(from: "Hey Rayban what does this say", defaultWakeWord: "Ok Vision"),
            "what does this say"
        )

        // Lesson 3 variants preserved and banned noisy variants remain excluded
        for legacy in ["ô kê vi dơn", "ok vi dơn", "vi dơn", "ok vision"] {
            XCTAssertTrue(VoiceCommandService.wakeWordVariations.contains(legacy), "Lesson 3 variant missing: \(legacy)")
        }
        for banned in ["a vision", "heavy vision", "have vision", "obey vision"] {
            XCTAssertFalse(VoiceCommandService.wakeWordVariations.contains(banned), "banned noisy variant re-added: \(banned)")
        }
    }

    func testPromptV2IncludesDirectAudioGuidance() throws {
        let tz = try XCTUnwrap(TimeZone(secondsFromGMT: 7 * 3600))
        let prompt = PromptV2.systemPrompt(now: Date(timeIntervalSince1970: 1_795_276_020), timeZone: tz, userPrompt: "", memories: [:])
        XCTAssertTrue(prompt.contains("DIRECT AUDIO:"))
        XCTAssertTrue(prompt.contains("mixed Vietnamese and English"))
        XCTAssertTrue(prompt.contains(PromptV2.noScreenRule))
        XCTAssertTrue(prompt.contains("TYPE:"))
    }

    // MARK: - Little-Endian Readers

    private func readUInt16LE(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
