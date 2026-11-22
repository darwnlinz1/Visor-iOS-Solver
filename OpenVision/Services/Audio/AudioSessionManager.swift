// OpenVision - AudioSessionManager.swift
// Manages AVAudioSession configuration for Ray-Ban Meta glasses (Bluetooth HFP) and iPhone speaker.
// Offloads synchronous setCategory/setActive XPC calls onto a dedicated serial queue to avoid
// iOS main-thread Hang Risk warnings while preserving all Lesson 2 audio invariants.

import AVFoundation
import Foundation

/// Dedicated serial queue for blocking AVAudioSession XPC calls (prevents main-thread hang warnings).
private let audioSessionQueue = DispatchQueue(label: "com.openvision.audio-session", qos: .userInitiated)

/// Manages audio session configuration
@MainActor
final class AudioSessionManager {
    // MARK: - Singleton

    static let shared = AudioSessionManager()

    // MARK: - Properties

    private nonisolated var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }

    /// Current audio mode
    private(set) var currentMode: AudioMode = .inactive

    // MARK: - Audio Modes

    enum AudioMode {
        /// No audio session active
        case inactive

        /// Voice chat mode (aggressive echo cancellation for iPhone mic)
        case voiceChat

        /// Video chat mode (mild echo cancellation for glasses mic)
        case videoChat

        /// Measurement mode (for wake word detection)
        case measurement
    }

    /// Callback invoked when audio route changes (device connected/disconnected)
    var onRouteChange: (() -> Void)?

    private var routeChangeWorkItem: DispatchWorkItem?
    private var lastInputPortUID: String?

    // MARK: - Initialization

    private init() {
        lastInputPortUID = audioSession.currentRoute.inputs.first?.uid
        setupRouteChangeObserver()
    }

    private func setupRouteChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleAudioRouteChange(notification)
            }
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        AppLog.debug(.audio, "Route changed: reason=\(reason.rawValue), route: \(currentRouteDescription)")

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            // IGNORE .categoryChange and .routeConfigurationChange to prevent infinite ping-pong loops!
            // DO NOT call audioSession.setPreferredInput(hfp) inside handleAudioRouteChange!
            routeChangeWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.lastInputPortUID = self.audioSession.currentRoute.inputs.first?.uid
                AppLog.info(.audio, "Debounced route change fired (reason=\(reason.rawValue)), route: \(self.currentRouteDescription)")
                self.onRouteChange?()
            }
            routeChangeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        default:
            break
        }
    }

    // MARK: - Configuration

    /// Configure audio session for specified mode
    func configure(for mode: AudioMode) throws {
        guard mode != currentMode else { return }

        switch mode {
        case .inactive:
            try deactivate()

        case .voiceChat:
            try configureVoiceChat()

        case .videoChat:
            try configureVideoChat()

        case .measurement:
            try configureMeasurement()
        }

        currentMode = mode
        AppLog.info(.audio, "Configured for \(mode)")
    }

    /// Deactivate audio session
    func deactivate() throws {
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        currentMode = .inactive
    }

    // MARK: - Mode Configurations

    private func configureVoiceChat() throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [
                .defaultToSpeaker,
                .allowBluetoothHFP,
                .allowBluetoothA2DP,
                .mixWithOthers,
                .duckOthers
            ]
        )
        try audioSession.setActive(true)
    }

    private func configureVideoChat() throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .videoChat,
            options: [
                .defaultToSpeaker,
                .allowBluetoothHFP,
                .allowBluetoothA2DP,
                .mixWithOthers
            ]
        )
        try audioSession.setActive(true)
    }

    private func configureMeasurement() throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [
                .defaultToSpeaker,
                .allowBluetoothHFP,
                .duckOthers
            ]
        )
        try audioSession.setActive(true)
    }

    // MARK: - Async Off-Main Routing (avoids iOS AVAudioSession Hang Risk on main thread)

    /// Applies the preferred audio route off the main thread: glasses Bluetooth HFP when wanted
    /// and connected, otherwise iPhone built-in mic + loud speaker. Returns true if glasses HFP won.
    @discardableResult
    func configurePreferredRouteAsync(preferGlasses: Bool) async -> Bool {
        let usedGlasses: Bool = await withCheckedContinuation { continuation in
            audioSessionQueue.async { [self] in
                if preferGlasses, (try? self.configureForGlasses()) == true {
                    continuation.resume(returning: true)
                    return
                }
                try? self.configureForPhone()
                continuation.resume(returning: false)
            }
        }
        currentMode = .voiceChat
        lastInputPortUID = audioSession.currentRoute.inputs.first?.uid
        return usedGlasses
    }

    /// Ensures playback audio works loudly right now (used by direct chat, History replay, and voice previews).
    /// Does not tear down a running glasses HFP session; configures glasses or phone speaker if inactive.
    func ensurePlaybackRouteAsync(preferGlasses: Bool) async {
        let alreadyActiveOnGlasses = preferGlasses && isBluetoothHFPInputActive
        if currentMode != .inactive && (alreadyActiveOnGlasses || !preferGlasses) {
            // Still make sure built-in earpiece is overridden to loud speaker when no glasses/headphones are active.
            if !isBluetoothHFPActive && audioSession.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    audioSessionQueue.async { [self] in
                        try? self.audioSession.overrideOutputAudioPort(.speaker)
                        continuation.resume()
                    }
                }
            }
            return
        }
        _ = await configurePreferredRouteAsync(preferGlasses: preferGlasses)
    }

    // MARK: - Bluetooth HFP Routing

    /// Configure the audio session for the glasses' Bluetooth HFP mic + speaker.
    /// Nonisolated so `configurePreferredRouteAsync` executes the XPC calls off the main thread.
    /// Keeps Lesson 2 invariants: `.playAndRecord` + `mode: .default` +
    /// `[.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]`.
    @discardableResult
    nonisolated func configureForGlasses() throws -> Bool {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        guard let hfpInput = findBluetoothHFPInput() else {
            AppLog.info(.audio, "No Bluetooth HFP input — glasses not connected as an audio device. Inputs: \(availableInputsDescription)")
            return false
        }
        try audioSession.setPreferredInput(hfpInput)
        let uid = hfpInput.uid
        Task { @MainActor [weak self] in
            self?.lastInputPortUID = uid
            self?.currentMode = .voiceChat
        }
        AppLog.info(.audio, "Configured for glasses (Bluetooth HFP): \(hfpInput.portName) — route: \(currentRouteDescription)")
        return true
    }

    /// Names + types of every input iOS currently reports — for diagnosing mic routing.
    nonisolated var availableInputsDescription: String {
        (audioSession.availableInputs ?? []).map { "\($0.portName)[\($0.portType.rawValue)]" }.joined(separator: ", ")
    }

    /// Configure audio for phone-only use (no glasses): record from built-in mic and play spoken
    /// responses out of the LOUD speaker (audible even when the hardware mute switch is on).
    nonisolated func configureForPhone() throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP, .allowBluetoothHFP]
        )
        try audioSession.setActive(true)
        try? audioSession.setPreferredInput(nil)
        let uid = audioSession.currentRoute.inputs.first?.uid
        // Force loud speaker if routed to quiet earpiece (keep AirPods / A2DP headphones alone).
        if audioSession.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
            try? audioSession.overrideOutputAudioPort(.speaker)
        }
        Task { @MainActor [weak self] in
            self?.lastInputPortUID = uid
            self?.currentMode = .voiceChat
        }
        AppLog.info(.audio, "Configured for phone (built-in mic + loud speaker) — route: \(currentRouteDescription)")
    }

    /// Find Bluetooth HFP input port (prioritizing Ray-Ban Meta devices)
    private nonisolated func findBluetoothHFPInput() -> AVAudioSessionPortDescription? {
        let available = audioSession.availableInputs ?? []
        if let metaInput = available.first(where: { input in
            let name = input.portName.lowercased()
            return name.contains("ray-ban") || name.contains("meta") || name.contains("rb meta")
        }) {
            return metaInput
        }
        return available.first(where: { input in
            input.portType == .bluetoothHFP || input.portType == .bluetoothLE
        })
    }

    /// Check if Bluetooth HFP / glasses microphone is currently the active input route
    nonisolated var isBluetoothHFPInputActive: Bool {
        let inputs = audioSession.currentRoute.inputs
        return inputs.contains { input in
            if input.portType == .bluetoothHFP || input.portType == .bluetoothLE { return true }
            let name = input.portName.lowercased()
            return name.contains("ray-ban") || name.contains("meta") || name.contains("rb meta")
        }
    }

    /// Check if Bluetooth HFP is currently active (input or output)
    nonisolated var isBluetoothHFPActive: Bool {
        let inputs = audioSession.currentRoute.inputs
        let outputs = audioSession.currentRoute.outputs

        let hasHFPInput = inputs.contains { input in
            if input.portType == .bluetoothHFP || input.portType == .bluetoothLE { return true }
            let name = input.portName.lowercased()
            return name.contains("ray-ban") || name.contains("meta") || name.contains("rb meta")
        }
        let hasHFPOutput = outputs.contains { output in
            if output.portType == .bluetoothHFP { return true }
            let name = output.portName.lowercased()
            return output.portType == .bluetoothA2DP && (name.contains("ray-ban") || name.contains("meta") || name.contains("rb meta"))
        }

        return hasHFPInput || hasHFPOutput
    }

    /// True if another app (e.g. Music) is currently playing audio (for T7.7 post-capture diagnostics).
    nonisolated var isOtherAudioPlaying: Bool {
        audioSession.isOtherAudioPlaying
    }

    /// Get current audio route description
    nonisolated var currentRouteDescription: String {
        let inputs = audioSession.currentRoute.inputs.map { $0.portName }.joined(separator: ", ")
        let outputs = audioSession.currentRoute.outputs.map { $0.portName }.joined(separator: ", ")
        return "Input: \(inputs.isEmpty ? "none" : inputs), Output: \(outputs.isEmpty ? "none" : outputs)"
    }

    /// Short output label for UI status chips.
    nonisolated var outputLabel: String {
        if let first = audioSession.currentRoute.outputs.first {
            switch first.portType {
            case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
                return first.portName
            case .builtInSpeaker:
                return "Loa ngoài"
            case .builtInReceiver:
                return "Loa trong"
            case .headphones:
                return "Tai nghe"
            default:
                return first.portName
            }
        }
        return "Mặc định"
    }

    // MARK: - Utilities

    nonisolated var inputSampleRate: Double { audioSession.sampleRate }
    nonisolated var outputSampleRate: Double { audioSession.sampleRate }

    nonisolated var isBluetoothAvailable: Bool {
        audioSession.availableInputs?.contains { port in
            port.portType == .bluetoothHFP || port.portType == .bluetoothA2DP
        } ?? false
    }

    nonisolated var isUsingBuiltInMic: Bool {
        audioSession.currentRoute.inputs.contains { port in
            port.portType == .builtInMic
        }
    }
}
