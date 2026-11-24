// Reybain - DirectAudioRecorder.swift
// Dual-mode direct audio capture (16 kHz, 16-bit mono WAV) for Gemini multimodal audio turns:
//   1. Shared-tap PCM mode: receives AVAudioPCMBuffer callbacks from VoiceCommandService's single
//      shared microphone tap (strictly obeys Blueprint Lesson 1 — never installs its own AVAudioEngine tap).
//   2. Standalone AVAudioRecorder fallback: records directly to a temporary 16 kHz PCM .wav file when
//      VoiceCommandService's tap is not active (e.g. wake word disabled or deferred during music).

import AVFoundation
import CoreGraphics
import Foundation

enum DirectAudioRecorderError: LocalizedError {
    case failedToStartRecorder
    case invalidRecordingFile

    var errorDescription: String? {
        switch self {
        case .failedToStartRecorder:
            return "Không thể khởi động trình ghi âm trực tiếp."
        case .invalidRecordingFile:
            return "Tệp ghi âm không hợp lệ hoặc bị trống."
        }
    }
}

/// Captures 16 kHz, 16-bit signed mono PCM audio and encodes standard 44-byte RIFF/WAVE payloads.
/// Thread-safe: `appendBuffer(_:)` is called on the Core Audio render thread while lifecycle and
/// meter queries run on the MainActor.
final class DirectAudioRecorder: @unchecked Sendable {

    // MARK: - Constants

    static let targetSampleRate: Int = 16_000
    static let maxDurationSeconds: TimeInterval = 60.0
    static let maxSamples: Int = Int(maxDurationSeconds) * targetSampleRate
    /// Minimum normalized RMS level (`0.0 ... 1.0`) to treat a capture as containing audible speech.
    static let minAudibleRMS: CGFloat = 0.015

    enum CaptureMode: Equatable, Sendable {
        case idle
        case sharedTap
        case standaloneRecorder
    }

    // MARK: - State (guarded by `lock`)

    private let lock = NSLock()
    private var mode: CaptureMode = .idle
    private var pcmSamples: [Int16] = []
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var startedAt: Date?
    private var latestRMS: CGFloat = 0
    private var peakRMS: CGFloat = 0
    private var _lastCapturedDuration: TimeInterval = 0
    private var _lastCapturedPeakLevel: CGFloat = 0

    private var standaloneRecorder: AVAudioRecorder?
    private var standaloneFileURL: URL?

    private let targetPCMFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(DirectAudioRecorder.targetSampleRate),
        channels: 1,
        interleaved: true
    )

    deinit {
        cancel()
    }

    // MARK: - Read-only Telemetry

    var currentMode: CaptureMode {
        lock.lock()
        defer { lock.unlock() }
        return mode
    }

    var isCapturing: Bool {
        currentMode != .idle
    }

    var lastCapturedDuration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return _lastCapturedDuration
    }

    var lastCapturedPeakLevel: CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return _lastCapturedPeakLevel
    }

    var currentDuration: TimeInterval {
        lock.lock()
        let activeMode = mode
        let sampleCount = pcmSamples.count
        let start = startedAt
        let recorder = standaloneRecorder
        lock.unlock()

        switch activeMode {
        case .idle:
            return 0
        case .sharedTap:
            if sampleCount > 0 {
                return min(Self.maxDurationSeconds, Double(sampleCount) / Double(Self.targetSampleRate))
            }
            return start.map { min(Self.maxDurationSeconds, max(0, Date().timeIntervalSince($0))) } ?? 0
        case .standaloneRecorder:
            if let recorder, recorder.currentTime > 0 {
                return min(Self.maxDurationSeconds, recorder.currentTime)
            }
            return start.map { min(Self.maxDurationSeconds, max(0, Date().timeIntervalSince($0))) } ?? 0
        }
    }

    var hasReachedMaxDuration: Bool {
        lock.lock()
        let activeMode = mode
        let sampleCount = pcmSamples.count
        let start = startedAt
        let recorder = standaloneRecorder
        lock.unlock()

        switch activeMode {
        case .idle:
            return false
        case .sharedTap:
            return sampleCount >= Self.maxSamples
        case .standaloneRecorder:
            if let recorder, !recorder.isRecording, let start, Date().timeIntervalSince(start) >= 1.0 {
                return true
            }
            if let start, Date().timeIntervalSince(start) >= Self.maxDurationSeconds {
                return true
            }
            return false
        }
    }

    /// Returns the latest normalized microphone level (`0.0 ... 1.0`) for UI waveforms.
    /// In standalone mode this refreshes `AVAudioRecorder` metering and updates peak tracking.
    func sampleMeterLevel() -> CGFloat {
        lock.lock()
        let activeMode = mode
        let recorder = standaloneRecorder
        let sharedLevel = latestRMS
        lock.unlock()

        switch activeMode {
        case .idle:
            return 0
        case .sharedTap:
            return sharedLevel
        case .standaloneRecorder:
            guard let recorder else { return 0 }
            recorder.updateMeters()
            let level = Self.normalizedLevel(fromDecibels: recorder.averagePower(forChannel: 0))
            lock.lock()
            if mode == .standaloneRecorder {
                latestRMS = level
                if level > peakRMS { peakRMS = level }
            }
            lock.unlock()
            return level
        }
    }

    // MARK: - Mode A: Shared-Tap PCM Capture

    /// Arms shared-tap PCM capture. Buffers must be forwarded via `appendBuffer(_:)` from
    /// `VoiceCommandService`'s single microphone tap.
    func beginTapCapture() {
        var oldRecorder: AVAudioRecorder?
        var oldURL: URL?

        lock.lock()
        oldRecorder = standaloneRecorder
        oldURL = standaloneFileURL
        standaloneRecorder = nil
        standaloneFileURL = nil

        pcmSamples.removeAll(keepingCapacity: true)
        pcmSamples.reserveCapacity(Self.targetSampleRate * 4)
        converter = nil
        converterInputFormat = nil
        latestRMS = 0
        peakRMS = 0
        _lastCapturedDuration = 0
        _lastCapturedPeakLevel = 0
        startedAt = Date()
        mode = .sharedTap
        lock.unlock()

        oldRecorder?.stop()
        if let oldURL {
            try? FileManager.default.removeItem(at: oldURL)
        }
    }

    /// Appends one live microphone PCM buffer from the shared tap. **Called on the Core Audio render thread.**
    /// Resamples/converts to 16 kHz 16-bit signed mono PCM, tracks live RMS, and caps length at 60 s.
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0, buffer.format.sampleRate > 0, buffer.format.channelCount > 0 else {
            return
        }

        lock.lock()
        guard mode == .sharedTap else {
            lock.unlock()
            return
        }
        let currentCount = pcmSamples.count
        lock.unlock()

        let rms = Self.normalizedRMS(from: buffer)

        guard currentCount < Self.maxSamples else {
            lock.lock()
            if mode == .sharedTap {
                latestRMS = rms
                if rms > peakRMS { peakRMS = rms }
            }
            lock.unlock()
            return
        }

        // Fast path: buffer is already 16 kHz mono signed 16-bit PCM.
        if buffer.format.commonFormat == .pcmFormatInt16,
           buffer.format.channelCount == 1,
           Int(buffer.format.sampleRate.rounded()) == Self.targetSampleRate,
           let channel = buffer.int16ChannelData?[0] {
            let count = Int(buffer.frameLength)
            lock.lock()
            if mode == .sharedTap {
                let remaining = Self.maxSamples - pcmSamples.count
                if remaining > 0 {
                    let toCopy = min(count, remaining)
                    pcmSamples.append(contentsOf: UnsafeBufferPointer(start: channel, count: toCopy))
                }
                latestRMS = rms
                if rms > peakRMS { peakRMS = rms }
            }
            lock.unlock()
            return
        }

        guard let targetFormat = targetPCMFormat else { return }

        lock.lock()
        guard mode == .sharedTap else {
            lock.unlock()
            return
        }
        if converterInputFormat != buffer.format || converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            converterInputFormat = buffer.format
        }
        guard let activeConverter = converter else {
            lock.unlock()
            return
        }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 1024
        guard capacity > 0,
              let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            lock.unlock()
            return
        }

        var supplied = false
        var conversionError: NSError?
        activeConverter.convert(to: outBuffer, error: &conversionError) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }

        if conversionError == nil,
           outBuffer.frameLength > 0,
           let channel = outBuffer.int16ChannelData?[0] {
            let remaining = Self.maxSamples - pcmSamples.count
            if remaining > 0 {
                let toCopy = min(Int(outBuffer.frameLength), remaining)
                pcmSamples.append(contentsOf: UnsafeBufferPointer(start: channel, count: toCopy))
            }
        }
        latestRMS = rms
        if rms > peakRMS { peakRMS = rms }
        lock.unlock()
    }

    /// Finalizes shared-tap PCM capture and returns a valid 16 kHz mono 16-bit RIFF/WAVE payload.
    func finishTapCapture() -> Data? {
        lock.lock()
        guard mode == .sharedTap else {
            lock.unlock()
            return nil
        }
        mode = .idle
        let samples = pcmSamples
        let peak = peakRMS
        pcmSamples.removeAll(keepingCapacity: false)
        converter = nil
        converterInputFormat = nil
        startedAt = nil
        latestRMS = 0
        peakRMS = 0
        let duration = Double(samples.count) / Double(Self.targetSampleRate)
        _lastCapturedDuration = duration
        _lastCapturedPeakLevel = peak
        lock.unlock()

        guard !samples.isEmpty else { return nil }
        return Self.encodeWAV(samples: samples, sampleRate: Self.targetSampleRate)
    }

    // MARK: - Mode B: Standalone AVAudioRecorder Fallback

    /// Starts standalone WAV recording to a temporary file (16 kHz, mono, 16-bit Linear PCM).
    /// Used for Chat Voice Notes when `VoiceCommandService`'s shared tap is not running.
    func startStandaloneRecording() throws {
        cancel()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reybain-voicenote-\(UUID().uuidString).wav")
        try? FileManager.default.removeItem(at: url)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: Double(Self.targetSampleRate),
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record(forDuration: Self.maxDurationSeconds) else {
            try? FileManager.default.removeItem(at: url)
            throw DirectAudioRecorderError.failedToStartRecorder
        }

        lock.lock()
        standaloneRecorder = recorder
        standaloneFileURL = url
        mode = .standaloneRecorder
        startedAt = Date()
        latestRMS = 0
        peakRMS = 0
        _lastCapturedDuration = 0
        _lastCapturedPeakLevel = 0
        lock.unlock()

        AppLog.info(.audio, "DirectAudioRecorder started standalone recording (\(url.lastPathComponent))")
    }

    /// Stops standalone recording, returns the WAV file bytes, and deletes the temporary file.
    func stopStandaloneRecording() -> Data? {
        lock.lock()
        guard mode == .standaloneRecorder else {
            lock.unlock()
            return nil
        }
        let recorder = standaloneRecorder
        let url = standaloneFileURL
        let start = startedAt
        let peak = peakRMS
        standaloneRecorder = nil
        standaloneFileURL = nil
        mode = .idle
        startedAt = nil
        latestRMS = 0
        peakRMS = 0
        lock.unlock()

        let recordedTime = recorder?.currentTime ?? 0
        recorder?.stop()

        defer {
            if let url {
                try? FileManager.default.removeItem(at: url)
            }
        }

        guard let url, let data = try? Data(contentsOf: url), data.count > 44 else {
            lock.lock()
            _lastCapturedDuration = 0
            _lastCapturedPeakLevel = peak
            lock.unlock()
            return nil
        }

        let estimatedFromBytes = Double(max(0, data.count - 44)) / Double(Self.targetSampleRate * 2)
        let wallElapsed = start.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        let duration = recordedTime > 0 ? recordedTime : (estimatedFromBytes > 0 ? estimatedFromBytes : wallElapsed)

        lock.lock()
        _lastCapturedDuration = min(Self.maxDurationSeconds, duration)
        _lastCapturedPeakLevel = peak
        lock.unlock()

        return data
    }

    /// Cancels whichever capture mode is active, discarding buffers and removing any temp file.
    func cancel() {
        lock.lock()
        let recorder = standaloneRecorder
        let url = standaloneFileURL
        standaloneRecorder = nil
        standaloneFileURL = nil
        mode = .idle
        pcmSamples.removeAll(keepingCapacity: false)
        converter = nil
        converterInputFormat = nil
        startedAt = nil
        latestRMS = 0
        peakRMS = 0
        lock.unlock()

        recorder?.stop()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Pure Unit-Testable Helpers

    /// Encodes 16-bit signed mono PCM samples into a valid RIFF/WAVE (`audio/wav`) payload with
    /// an exact 44-byte canonical WAV header.
    static func encodeWAV(samples: [Int16], sampleRate: Int = 16000) -> Data {
        let clampedRate = max(1, sampleRate)
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let byteRate: UInt32 = UInt32(clampedRate) * UInt32(blockAlign)
        let dataByteCount: UInt32 = UInt32(samples.count * MemoryLayout<Int16>.size)
        let riffChunkSize: UInt32 = 36 + dataByteCount

        var wav = Data(capacity: 44 + Int(dataByteCount))

        // RIFF chunk descriptor (12 bytes)
        wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendLittleEndian(riffChunkSize, to: &wav)
        wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt sub-chunk (24 bytes)
        wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        appendLittleEndian(UInt32(16), to: &wav)         // Subchunk1Size (16 for PCM)
        appendLittleEndian(UInt16(1), to: &wav)          // AudioFormat (1 = PCM)
        appendLittleEndian(numChannels, to: &wav)
        appendLittleEndian(UInt32(clampedRate), to: &wav)
        appendLittleEndian(byteRate, to: &wav)
        appendLittleEndian(blockAlign, to: &wav)
        appendLittleEndian(bitsPerSample, to: &wav)

        // data sub-chunk header (8 bytes)
        wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        appendLittleEndian(dataByteCount, to: &wav)

        // PCM sample payload
        if !samples.isEmpty {
            if Int16(1) == Int16(1).littleEndian {
                samples.withUnsafeBytes { wav.append(contentsOf: $0) }
            } else {
                for sample in samples {
                    appendLittleEndian(sample, to: &wav)
                }
            }
        }

        return wav
    }

    /// Computes a normalized RMS meter level (`0.0 ... 1.0`) from an `AVAudioPCMBuffer`.
    static func normalizedRMS(from buffer: AVAudioPCMBuffer) -> CGFloat {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sumSquares: Double = 0
        if let channels = buffer.floatChannelData {
            let data = channels[0]
            for i in 0..<frames {
                let sample = Double(data[i])
                sumSquares += sample * sample
            }
        } else if let channels = buffer.int16ChannelData {
            let data = channels[0]
            let scale = 1.0 / 32768.0
            for i in 0..<frames {
                let sample = Double(data[i]) * scale
                sumSquares += sample * sample
            }
        } else if let channels = buffer.int32ChannelData {
            let data = channels[0]
            let scale = 1.0 / 2147483648.0
            for i in 0..<frames {
                let sample = Double(data[i]) * scale
                sumSquares += sample * sample
            }
        } else {
            return 0
        }

        let rms = sqrt(sumSquares / Double(frames))
        guard rms.isFinite, rms > 0.00001 else { return 0 }
        let decibels = Float(20.0 * log10(rms))
        return normalizedLevel(fromDecibels: decibels)
    }

    /// Maps dBFS power (`-160 ... 0`) onto a smooth `0.0 ... 1.0` waveform level.
    static func normalizedLevel(fromDecibels decibels: Float) -> CGFloat {
        guard decibels.isFinite else { return 0 }
        let minDB: Double = -55.0
        let maxDB: Double = -5.0
        if Double(decibels) <= minDB { return 0 }
        let clamped = min(maxDB, Double(decibels))
        let linear = (clamped - minDB) / (maxDB - minDB)
        return CGFloat(min(1.0, max(0.0, pow(linear, 0.85))))
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}
