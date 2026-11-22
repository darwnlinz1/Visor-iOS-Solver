// OpenVision - GlassesManager.swift
// Singleton manager for Meta Ray-Ban glasses via the Meta Wearables DAT SDK.
// Implements T2.4 (AppLog), T2.5 (WearablesBootstrap lazy SDK), T7.2 (shared captureTask),
// T7.3 (source ordering, 75s/15s stall timeout, lastPhotoSource), and T7.9 (camera-on-demand telemetry).

import Foundation
import SwiftUI
import CoreMedia
import OSLog
import MWDATCore
import MWDATCamera
import MWDATInputs

/// Outcome of `Wearables.configure()` at app start (OpenVisionApp.init). The SDK traps on any
/// `Wearables.shared` access after a failed configure, so GlassesManager reads `shared` only once
/// this says the SDK is configured; otherwise the app runs without glasses (PLAN.md N2).
@MainActor
enum WearablesBootstrap {
    /// Why configure() failed or did not run; nil once it succeeded.
    private(set) static var configureError: String? = "Wearables.configure() chưa chạy"

    static var isConfigured: Bool { configureError == nil }

    static func configureSucceeded() {
        configureError = nil
    }

    static func configureFailed(_ reason: String) {
        configureError = reason
    }

    /// Debug builds only: OPENVISION_SIMULATE_DAT_CONFIG_FAILURE=1 skips configure(), so CI can
    /// launch the app the way it starts when the SDK cannot initialise.
    static var simulatesConfigureFailure: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["OPENVISION_SIMULATE_DAT_CONFIG_FAILURE"] == "1"
        #else
        return false
        #endif
    }
}

/// A press of the glasses' capture button.
enum GlassesButtonPress: String {
    case shortPress
    case hold
    case doublePress
}

/// Manages Meta Ray-Ban glasses registration, connection, camera and capture button.
@MainActor
final class GlassesManager: ObservableObject {
    // MARK: - Singleton

    static let shared = GlassesManager()

    // MARK: - Published Properties

    @Published var isRegistered: Bool = false
    @Published var connectedDevice: DeviceIdentifier?
    @Published var connectedDeviceCount: Int = 0
    @Published var isStreaming: Bool = false
    @Published var lastFrame: UIImage?
    private(set) var lastFrameTime: Date = .distantPast
    @Published var lastPhotoData: Data?
    @Published var errorMessage: String?
    @Published private(set) var isButtonLinkActive: Bool = false
    @Published private(set) var buttonLinkStatus: String = "Tắt"
    @Published private(set) var isTakingPhoto: Bool = false
    @Published private(set) var sdkUnavailableReason: String?

    /// Source of the last photo delivered by the glasses (T7.3 / T7.4, shown in Settings & Debug).
    @Published private(set) var lastPhotoSource: String?
    /// Camera-on-demand diagnostics (T7.9): count and cumulative active seconds of glasses camera.
    @Published private(set) var cameraActivationCount: Int = 0
    @Published private(set) var totalCameraActiveSeconds: TimeInterval = 0

    static var sdkUnavailableMessage: String {
        "SDK kính chưa khởi tạo được: \(WearablesBootstrap.configureError ?? "không rõ lỗi")"
    }

    // MARK: - Private Properties

    private var wearables: (any WearablesInterface)? {
        WearablesBootstrap.isConfigured ? Wearables.shared : nil
    }

    // Session
    private var deviceSession: DeviceSession?
    private var sessionStarted = false
    private var sessionGeneration = 0
    private var sessionStartTask: Task<DeviceSession?, Never>?
    private var sessionMonitorTask: Task<Void, Never>?
    private var sessionErrorTask: Task<Void, Never>?

    // Camera & shared capture task (T7.2)
    private var camera: Camera?
    private var cameraActiveSince: Date?
    private var captureTask: Task<Data?, Never>?
    private var photoTokens: [any AnyListenerToken] = []
    private var photoStarted = false
    private var pendingPhoto: CheckedContinuation<Data?, Never>?
    private var pendingPhotoID = UUID()
    private var lastTransferProgressAt: Date = .distantPast
    /// Consecutive full-resolution failures; never reset per call (fixes B8 / T7.3).
    private var fullPhotoFailures = 0

    // Capture-button link (MWDATInputs)
    private var wantsButtonLink = false
    private var linkIncludesTouchpad = false
    private var inputs: Inputs?
    private var inputsDrainTask: Task<Void, Never>?
    private var inputsStateToken: (any AnyListenerToken)?
    private var inputsErrorToken: (any AnyListenerToken)?
    private var inputsHasActivated = false
    private var inputsPermissionDenied = false
    private var inputsRevivalTask: Task<Void, Never>?
    private var linkRetryTask: Task<Void, Never>?
    private var linkRetryDelay: UInt64 = 5

    // Listener tokens
    private var registrationTask: Task<Void, Never>?
    private var devicesTask: Task<Void, Never>?
    private var stateListenerToken: (any AnyListenerToken)?
    private var videoFrameListenerToken: (any AnyListenerToken)?
    private var photoDataListenerToken: (any AnyListenerToken)?
    private var errorListenerToken: (any AnyListenerToken)?

    // MARK: - Callbacks

    var onVideoFrame: ((UIImage) -> Void)?
    var onVideoSampleBuffer: ((CMSampleBuffer) -> Void)?
    var onPhotoCaptured: ((Data) -> Void)?
    var onCaptureButton: ((GlassesButtonPress) -> Void)?

    // MARK: - Initialization

    private init() {
        AppLog.info(.glasses, "Initializing")
        guard let wearables else {
            sdkUnavailableReason = Self.sdkUnavailableMessage
            AppLog.warning(.glasses, "\(Self.sdkUnavailableMessage) (glasses features off until the app restarts)")
            return
        }
        setupRegistrationListener(wearables)
        setupDevicesListener(wearables)
    }

    private func requireSDK(reportError: Bool = true) -> (any WearablesInterface)? {
        if let wearables { return wearables }
        AppLog.warning(.glasses, Self.sdkUnavailableMessage)
        if reportError { errorMessage = Self.sdkUnavailableMessage }
        return nil
    }

    // MARK: - Registration

    func register() async throws {
        AppLog.info(.glasses, "Starting registration")
        guard let wearables = requireSDK() else { return }

        for await state in wearables.registrationStateStream() {
            if case .registered = state {
                AppLog.info(.glasses, "Already registered")
                isRegistered = true
                return
            }
            break
        }

        try await wearables.startRegistration()
        AppLog.info(.glasses, "Registration initiated, waiting for Meta AI callback")
    }

    func unregister() async {
        AppLog.info(.glasses, "Starting unregistration")
        guard let wearables = requireSDK() else { return }
        wantsButtonLink = false
        linkRetryTask?.cancel()
        endSession()

        do {
            try await wearables.startUnregistration()
            isRegistered = false
            connectedDevice = nil
            connectedDeviceCount = 0
            errorMessage = nil
            AppLog.info(.glasses, "Unregistration successful")
        } catch {
            errorMessage = "Huỷ đăng ký thất bại: \(error.localizedDescription)"
            AppLog.error(.glasses, "Unregistration error: \(error.localizedDescription)")
        }
    }

    func openDATGlassesAppUpdate() async {
        guard let wearables = requireSDK() else { return }
        do {
            try await wearables.openDATGlassesAppUpdate()
        } catch {
            errorMessage = "Không mở được cập nhật: \(error.localizedDescription)"
            AppLog.error(.glasses, "openDATGlassesAppUpdate error: \(error.localizedDescription)")
        }
    }

    // MARK: - Session

    private func ensureSession(reportErrors: Bool = true) async -> DeviceSession? {
        if let session = deviceSession, sessionStarted { return session }
        if let task = sessionStartTask { return await task.value }
        let task = Task { @MainActor [weak self] () -> DeviceSession? in
            guard let self else { return nil }
            return await self.startSession(reportErrors: reportErrors)
        }
        sessionStartTask = task
        let session = await task.value
        sessionStartTask = nil
        return session
    }

    private func startSession(reportErrors: Bool) async -> DeviceSession? {
        func report(_ message: String) {
            AppLog.warning(.glasses, message)
            if reportErrors { errorMessage = message }
        }
        guard let wearables = requireSDK(reportError: reportErrors) else { return nil }
        guard isRegistered else {
            report("Chưa đăng ký với Meta AI")
            return nil
        }
        guard let deviceId = connectedDevice else {
            report("Chưa kết nối kính")
            return nil
        }

        if let device = wearables.deviceForIdentifier(deviceId) {
            AppLog.info(.glasses, "Device \(device.nameOrId()): type=\(device.deviceType()) link=\(device.linkState) compatibility=\(device.compatibility())")
            if device.compatibility() == .deviceUpdateRequired {
                report("Kính cần cập nhật firmware — cập nhật trong app Meta AI")
            } else if device.compatibility() == .sdkUpdateRequired {
                report("Kính mới hơn phiên bản SDK của app")
            }
        }

        endSession()

        do {
            let session = try wearables.createSession(deviceSelector: SpecificDeviceSelector(device: deviceId))
            sessionGeneration += 1
            let generation = sessionGeneration
            deviceSession = session
            sessionStarted = false

            let stateStream = session.stateStream()
            sessionMonitorTask = Task { @MainActor [weak self] in
                for await state in stateStream {
                    AppLog.info(.glasses, "Device session state: \(state)")
                    guard let self, generation == self.sessionGeneration else { return }
                    if state == .started {
                        self.sessionStarted = true
                    } else if state == .stopped {
                        self.sessionDidStop(generation: generation)
                        return
                    }
                }
            }
            let errorStream = session.errorStream()
            sessionErrorTask = Task { @MainActor [weak self] in
                for await error in errorStream {
                    AppLog.error(.glasses, "Device session error: \(error) — \(error.description)")
                    if reportErrors, UIApplication.shared.applicationState == .active {
                        self?.errorMessage = "Lỗi phiên kính: \(error.description)"
                    }
                }
            }

            AppLog.info(.glasses, "Starting device session...")
            try session.start()

            let deadline = Date().addingTimeInterval(15)
            while !sessionStarted, Date() < deadline, deviceSession != nil, generation == sessionGeneration {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard sessionStarted, generation == sessionGeneration else {
                report("Không mở được phiên kết nối kính (hết thời gian)")
                dumpSDKLogs(since: 30)
                if generation == sessionGeneration { endSession() }
                return nil
            }
            AppLog.info(.glasses, "Device session started")
            return session
        } catch {
            report("Không mở được phiên kết nối kính: \(error.localizedDescription)")
            endSession()
            return nil
        }
    }

    private func sessionDidStop(generation: Int) {
        guard generation == sessionGeneration else { return }
        AppLog.warning(.glasses, "Device session stopped by the device")
        endSession()
        scheduleLinkRetry()
    }

    private func endSession() {
        recordCameraStopped(reason: "endSession")
        sessionGeneration += 1
        resolvePendingPhoto(nil)
        teardownInputs(removeFromSession: false)
        camera?.stop()
        deviceSession?.stop()
        sessionMonitorTask?.cancel()
        sessionErrorTask?.cancel()
        sessionMonitorTask = nil
        sessionErrorTask = nil
        cleanupStreamListeners()
        photoTokens = []
        photoStarted = false
        camera = nil
        deviceSession = nil
        sessionStarted = false
        isStreaming = false
        lastFrame = nil
        lastFrameTime = .distantPast
    }

    private func ensureCameraPermission() async -> Bool {
        guard let wearables = requireSDK() else { return false }
        do {
            var status = try await wearables.checkPermissionStatus(.camera)
            if status != .granted {
                AppLog.info(.glasses, "Requesting camera permission...")
                status = try await wearables.requestPermission(.camera)
            }
            guard status == .granted else {
                errorMessage = "Chưa cấp quyền camera kính"
                return false
            }
            return true
        } catch {
            errorMessage = "Lỗi quyền camera kính: \(error.localizedDescription)"
            AppLog.error(.glasses, "Permission error: \(error.localizedDescription)")
            return false
        }
    }

    private func cameraForSession(_ session: DeviceSession) -> Camera? {
        if let camera { return camera }
        do {
            let config = StreamConfiguration(videoCodec: .raw, resolution: .high, frameRate: 30)
            guard let cam = try session.addCamera(config: config) else {
                errorMessage = "Không gắn được camera vào phiên kính"
                AppLog.error(.glasses, "addCamera returned nil")
                return nil
            }
            camera = cam
            observePhoto(cam)
            return cam
        } catch {
            errorMessage = "Không gắn được camera: \(error.localizedDescription)"
            AppLog.error(.glasses, "addCamera error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Camera Telemetry (T7.9)

    private func recordCameraStarted(reason: String) {
        guard cameraActiveSince == nil else { return }
        cameraActiveSince = Date()
        cameraActivationCount += 1
        AppLog.info(.glasses, "Camera start (reason: \(reason), count: \(cameraActivationCount))")
    }

    private func recordCameraStopped(reason: String) {
        guard let started = cameraActiveSince else { return }
        let elapsed = Date().timeIntervalSince(started)
        totalCameraActiveSeconds += elapsed
        cameraActiveSince = nil
        AppLog.info(.glasses, "Camera stop (reason: \(reason), active: \(String(format: "%.1f", elapsed))s)")
    }

    // MARK: - Streaming

    func startStreaming(reason: String = "pov_recording") async {
        guard !isStreaming else { return }
        guard !isTakingPhoto else {
            AppLog.info(.glasses, "Not starting stream — a photo capture is in progress")
            return
        }
        guard requireSDK() != nil else { return }
        guard isRegistered else {
            errorMessage = "Chưa đăng ký với Meta AI"
            return
        }
        guard await ensureCameraPermission() else { return }
        AppLog.info(.glasses, "Starting camera stream (reason: \(reason))")
        isStreaming = await wakeCamera(reason: reason) != nil
        reviveInputsIfNeeded()
    }

    private func wakeCamera(reason: String) async -> Camera? {
        for attempt in 1...2 {
            guard let session = await ensureSession(), let cam = cameraForSession(session) else { return nil }
            setupStreamListeners(stream: cam.stream)
            recordCameraStarted(reason: reason)
            cam.stream.start()
            if await waitUntil(seconds: 8, { cam.stream.state == .streaming }) { return cam }
            AppLog.warning(.glasses, "Camera stream did not start (attempt \(attempt)) — rebuilding session")
            endSession()
        }
        errorMessage = "Camera kính không khởi động được"
        return nil
    }

    func stopStreaming() async {
        guard isStreaming || camera != nil || deviceSession != nil else { return }
        AppLog.info(.glasses, "Stopping camera stream")
        guard !isTakingPhoto else { return }

        if wantsButtonLink, deviceSession != nil {
            stopCameraKeepingSession()
        } else {
            endSession()
        }
        AppLog.info(.glasses, "Streaming stopped")
    }

    private func stopCameraKeepingSession() {
        recordCameraStopped(reason: "stopCameraKeepingSession")
        if photoStarted {
            camera?.photo.stop()
            photoStarted = false
        }
        camera?.stream.stop()
        camera?.stop()
        cleanupStreamListeners()
        isStreaming = false
        lastFrame = nil
        lastFrameTime = .distantPast
    }

    /// Capture a still from the currently running video stream (used during POV recording).
    func capturePhotoFromActiveStream(timeout: TimeInterval = 10.0) async -> Data? {
        guard requireSDK() != nil, isStreaming, let stream = camera?.stream else { return nil }
        let startedAt = Date()
        lastPhotoData = nil
        if stream.capturePhoto(format: .jpeg) {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if let photo = lastPhotoData, !photo.isEmpty {
                    lastPhotoData = nil
                    recordCapturedPhoto(photo, source: "stream-still", startedAt: startedAt)
                    return photo
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
        if let frameData = lastFrame?.jpegData(compressionQuality: 0.95) {
            recordCapturedPhoto(frameData, source: "video-frame", startedAt: startedAt)
            return frameData
        }
        return nil
    }

    func capturePhoto() async {
        guard requireSDK() != nil else { return }
        guard isStreaming, let stream = camera?.stream else {
            errorMessage = "Camera kính phải đang bật để chụp"
            return
        }
        AppLog.info(.glasses, "Capturing photo from stream")
        if !stream.capturePhoto(format: .jpeg) {
            errorMessage = "Không chụp được ảnh"
            AppLog.warning(.glasses, "capturePhoto returned false")
        }
    }

    // MARK: - Unified Photo Capture (T7.2 shared captureTask + T7.3 source order & timeouts)

    func resetPhotoFailures() {
        fullPhotoFailures = 0
    }

    /// Single shared capture entrypoint (T7.2): concurrent callers join the in-flight `captureTask`
    /// instead of polling `isTakingPhoto`. Respects `fullResolution` ordering (T7.3):
    /// - `fullResolution == true`: tries `Camera.photo .full` first (75 s overall, 15 s stall cap),
    ///   then falls back to stream still (10 s) -> live frame.
    /// - `fullResolution == false` (default): tries stream still (10 s) -> live frame first,
    ///   then `Camera.photo .large`.
    func captureFullResolutionPhoto(fullResolution: Bool, timeout: TimeInterval = 75) async -> Data? {
        if let existing = captureTask {
            AppLog.info(.glasses, "Joining in-flight glasses photo capture")
            return await existing.value
        }
        let task = Task { @MainActor [weak self] () -> Data? in
            guard let self else { return nil }
            return await self.performPhotoCapture(fullResolution: fullResolution, timeout: timeout)
        }
        captureTask = task
        let data = await task.value
        captureTask = nil
        return data
    }

    private func performPhotoCapture(fullResolution: Bool, timeout: TimeInterval) async -> Data? {
        guard requireSDK() != nil else { return nil }
        guard isRegistered, connectedDevice != nil else { return nil }
        if isStreaming {
            return await capturePhotoFromActiveStream(timeout: 10.0)
        }

        isTakingPhoto = true
        let startedAt = Date()
        defer {
            isTakingPhoto = false
            reviveInputsIfNeeded()
        }

        guard await ensureCameraPermission() else { return nil }
        guard let cam = await wakeCamera(reason: "photo_capture") else {
            AppLog.warning(.glasses, "Direct photo: camera never woke")
            stopCameraAfterPhoto()
            return nil
        }

        if fullResolution && fullPhotoFailures < 2 {
            // T7.3: 12 MP mode tries standalone Camera.photo first (75s cap, 15s transfer stall cap).
            if let full = await captureStandalonePhoto(cam: cam, fullResolution: true, maxDuration: timeout, stallTimeout: 15.0) {
                stopCameraAfterPhoto()
                recordCapturedPhoto(full, source: "camera-photo-12mp", startedAt: startedAt)
                return full
            }
            noteFullPhotoFailure()
            // Re-wake stream for fallback if standalone stopped it.
            if cam.stream.state != .streaming {
                cam.stream.start()
                _ = await waitUntil(seconds: 5, { cam.stream.state == .streaming })
            }
        }

        // Fast stream still (~1-2 s, 10 s timeout).
        lastPhotoData = nil
        if cam.stream.capturePhoto(format: .jpeg) {
            let streamDeadline = Date().addingTimeInterval(10.0)
            while Date() < streamDeadline {
                if let photo = lastPhotoData, !photo.isEmpty {
                    lastPhotoData = nil
                    stopCameraAfterPhoto()
                    recordCapturedPhoto(photo, source: "stream-still", startedAt: startedAt)
                    return photo
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }

        // Fallback: freshest live video frame from the active sensor.
        if let liveFrame = lastFrame?.jpegData(compressionQuality: 0.95) {
            stopCameraAfterPhoto()
            recordCapturedPhoto(liveFrame, source: "video-frame", startedAt: startedAt)
            return liveFrame
        }

        // Secondary fallback for non-fullResolution mode: Camera.photo .large
        if !fullResolution && fullPhotoFailures < 2 {
            if let large = await captureStandalonePhoto(cam: cam, fullResolution: false, maxDuration: 30.0, stallTimeout: 15.0) {
                stopCameraAfterPhoto()
                recordCapturedPhoto(large, source: "camera-photo-large", startedAt: startedAt)
                return large
            }
            noteFullPhotoFailure()
        }

        stopCameraAfterPhoto()
        return nil
    }

    private func captureStandalonePhoto(
        cam: Camera,
        fullResolution: Bool,
        maxDuration: TimeInterval,
        stallTimeout: TimeInterval
    ) async -> Data? {
        if !photoStarted { cam.photo.start() }
        guard await waitUntil(seconds: 2.0, { [weak self] in self?.photoStarted == true }) else {
            return nil
        }
        cam.stream.stop()
        _ = await waitUntil(seconds: 1.5, { cam.stream.state == .stopped })

        let captureID = UUID()
        pendingPhotoID = captureID
        lastTransferProgressAt = Date()
        let started = Date()

        return await withCheckedContinuation { continuation in
            pendingPhoto = continuation
            cam.photo.capturePhoto(resolution: fullResolution ? .full : .large, quality: .high)
            Task { @MainActor [weak self] in
                while let self, self.pendingPhotoID == captureID {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard self.pendingPhotoID == captureID else { return }
                    let totalElapsed = Date().timeIntervalSince(started)
                    let stallElapsed = Date().timeIntervalSince(self.lastTransferProgressAt)
                    if totalElapsed >= maxDuration || stallElapsed >= stallTimeout {
                        AppLog.warning(.glasses, "Camera.photo timed out (total=\(Int(totalElapsed))s, stall=\(Int(stallElapsed))s)")
                        self.resolvePendingPhoto(nil)
                        return
                    }
                }
            }
        }
    }

    private func recordCapturedPhoto(_ data: Data, source: String, startedAt: Date) {
        lastPhotoSource = source
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(startedAt))
        let dims: String
        if let info = PhotoPayload.imageInfo(data) {
            dims = "\(info.width)x\(info.height)"
        } else {
            dims = "?x?"
        }
        AppLog.info(.photo, "Photo: \(source) \(dims) \(data.count) bytes in \(elapsed) s")
    }

    private func noteFullPhotoFailure() {
        fullPhotoFailures += 1
        if fullPhotoFailures >= 2 {
            AppLog.warning(.glasses, "Full photo disabled for this session after repeated failures")
        }
    }

    private func stopCameraAfterPhoto() {
        recordCameraStopped(reason: "stopCameraAfterPhoto")
        if photoStarted {
            camera?.photo.stop()
            photoStarted = false
        }
        camera?.stream.stop()
        camera?.stop()
        isStreaming = false
        if !wantsButtonLink { endSession() }
    }

    private func resolvePendingPhoto(_ data: Data?) {
        guard let continuation = pendingPhoto else { return }
        pendingPhoto = nil
        pendingPhotoID = UUID()
        continuation.resume(returning: data)
    }

    private func observePhoto(_ cam: Camera) {
        let photo = cam.photo
        photoTokens = []
        photoStarted = false

        photoTokens.append(photo.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                AppLog.debug(.glasses, "Photo state: \(state)")
                if case .started = state {
                    self.photoStarted = true
                } else if case .stopped = state {
                    self.photoStarted = false
                    self.resolvePendingPhoto(nil)
                }
            }
        })
        photoTokens.append(photo.photoDataPublisher.listen { [weak self] capture in
            let data = capture.imageData
            Task { @MainActor in
                self?.resolvePendingPhoto(data)
            }
        })
        photoTokens.append(photo.errorPublisher.listen { [weak self] error in
            let detail = String(describing: error)
            Task { @MainActor in
                AppLog.error(.glasses, "Photo error: \(detail)")
                self?.resolvePendingPhoto(nil)
            }
        })
        photoTokens.append(photo.transferProgressPublisher.listen { [weak self] progress in
            Task { @MainActor in
                self?.lastTransferProgressAt = Date()
            }
            AppLog.debug(.glasses, "Photo transfer: \(progress.bytesReceived)/\(progress.totalBytes) bytes")
        })
    }

    private func waitUntil(seconds: TimeInterval, _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    // MARK: - Capture-button link (MWDATInputs, experimental)

    func applySettings(_ settings: AppSettings) async {
        await configureButtonLink(enabled: settings.captureButtonEnabled,
                                  includeTouchpad: settings.captureButtonIncludeTouchpad)
    }

    func configureButtonLink(enabled: Bool, includeTouchpad: Bool) async {
        let changed = includeTouchpad != linkIncludesTouchpad
        wantsButtonLink = enabled
        linkIncludesTouchpad = includeTouchpad
        linkRetryTask?.cancel()
        linkRetryDelay = 5

        guard enabled else {
            teardownInputs(removeFromSession: true)
            buttonLinkStatus = "Tắt"
            if !isStreaming && !isTakingPhoto { endSession() }
            return
        }
        if changed { teardownInputs(removeFromSession: true) }
        await startButtonLink()
    }

    private func startButtonLink() async {
        guard wantsButtonLink, inputs == nil, !inputsPermissionDenied else { return }
        guard requireSDK(reportError: false) != nil else { buttonLinkStatus = Self.sdkUnavailableMessage; return }
        guard isRegistered else { buttonLinkStatus = "Chưa đăng ký kính"; return }
        guard connectedDevice != nil else { buttonLinkStatus = "Chờ kính kết nối…"; return }

        buttonLinkStatus = "Đang kết nối…"
        guard let session = await ensureSession(reportErrors: false) else {
            buttonLinkStatus = "Không mở được phiên kính"
            scheduleLinkRetry()
            return
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard wantsButtonLink, inputs == nil, deviceSession != nil else { return }
        attachInputs(to: session)
    }

    private func attachInputs(to session: DeviceSession) {
        let configuration = linkIncludesTouchpad
            ? InputsConfiguration(sources: [.captouch, .captureButton, .actionButton], consumeBack: true)
            : InputsConfiguration(sources: [.captureButton], consumeBack: false)

        let attached: Inputs?
        do {
            attached = try session.addInputs(configuration: configuration)
        } catch {
            AppLog.warning(.glasses, "addInputs failed: \(error.localizedDescription)")
            buttonLinkStatus = "Không gắn được nút chụp — thử lại…"
            scheduleLinkRetry()
            return
        }
        guard let attached else {
            AppLog.warning(.glasses, "addInputs returned nil")
            buttonLinkStatus = "Kính này không gửi nút chụp cho app"
            return
        }

        inputs = attached
        inputsHasActivated = false
        buttonLinkStatus = "Đang kích hoạt…"

        let events = attached.events
        inputsDrainTask = Task { @MainActor [weak self] in
            for await event in events {
                self?.receive(event)
            }
            AppLog.info(.glasses, "Inputs event stream ended")
        }

        inputsStateToken = attached.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                AppLog.info(.glasses, "Inputs state: \(state)")
                if case .active = state {
                    self.inputsHasActivated = true
                    self.isButtonLinkActive = true
                    self.buttonLinkStatus = "Đang hoạt động"
                    self.linkRetryDelay = 5
                } else if case .inactive = state {
                    guard self.inputsHasActivated else { return }
                    self.isButtonLinkActive = false
                    self.buttonLinkStatus = "Đang kết nối lại…"
                    self.reviveInputsIfNeeded()
                }
            }
        }
        inputsErrorToken = attached.errorPublisher.listen { [weak self] error in
            let detail = String(describing: error)
            Task { @MainActor in
                guard let self else { return }
                AppLog.error(.glasses, "Inputs error: \(detail)")
                if detail.localizedCaseInsensitiveContains("permissionDenied") {
                    self.inputsPermissionDenied = true
                    self.isButtonLinkActive = false
                    self.buttonLinkStatus = "Meta chưa cho phép app nhận nút chụp — bật Developer Mode trong Meta AI"
                }
            }
        }
    }

    private func receive(_ event: InputEvent) {
        switch event {
        case let .capture(pressType, source, _):
            let press: GlassesButtonPress
            switch pressType {
            case .shortPress: press = .shortPress
            case .hold: press = .hold
            case .doublePress: press = .doublePress
            @unknown default:
                AppLog.debug(.glasses, "Ignored capture press \(pressType)")
                return
            }
            AppLog.info(.glasses, "Capture button: \(press.rawValue) from \(source)")
            onCaptureButton?(press)
        default:
            AppLog.debug(.glasses, "Ignored input \(event)")
        }
    }

    private func reviveInputsIfNeeded() {
        guard wantsButtonLink, !inputsPermissionDenied, inputsRevivalTask == nil else { return }
        guard inputs == nil || !isButtonLinkActive else { return }
        inputsRevivalTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.inputsRevivalTask = nil }
            while self.isTakingPhoto {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard self.wantsButtonLink, !self.isButtonLinkActive else { return }
            self.teardownInputs(removeFromSession: true)
            if let session = self.deviceSession, self.sessionStarted {
                self.attachInputs(to: session)
            } else {
                await self.startButtonLink()
            }
        }
    }

    private func teardownInputs(removeFromSession: Bool) {
        inputsDrainTask?.cancel()
        inputsDrainTask = nil
        inputsStateToken = nil
        inputsErrorToken = nil
        if removeFromSession, inputs != nil {
            try? deviceSession?.removeInputs()
        }
        inputs = nil
        inputsHasActivated = false
        isButtonLinkActive = false
    }

    private func scheduleLinkRetry() {
        guard wantsButtonLink, !inputsPermissionDenied else { return }
        linkRetryTask?.cancel()
        let delay = linkRetryDelay
        linkRetryDelay = min(linkRetryDelay * 2, 60)
        linkRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard let self, !Task.isCancelled, self.wantsButtonLink, self.inputs == nil else { return }
            await self.startButtonLink()
        }
    }

    // MARK: - Private Listeners

    private func setupRegistrationListener(_ wearables: any WearablesInterface) {
        registrationTask = Task {
            for await state in wearables.registrationStateStream() {
                await MainActor.run {
                    if case .registered = state {
                        self.isRegistered = true
                        AppLog.info(.glasses, "Registration state: registered")
                    } else {
                        self.isRegistered = false
                        AppLog.info(.glasses, "Registration state: \(state)")
                    }
                }
            }
        }
    }

    private func setupDevicesListener(_ wearables: any WearablesInterface) {
        devicesTask = Task {
            for await devices in wearables.devicesStream() {
                await MainActor.run {
                    let hadDevice = self.connectedDevice != nil
                    self.connectedDeviceCount = devices.count
                    self.connectedDevice = devices.first
                    AppLog.info(.glasses, "Devices updated: \(devices.count) connected")
                    if !hadDevice, self.connectedDevice != nil, self.wantsButtonLink, self.inputs == nil {
                        self.linkRetryDelay = 5
                        Task { await self.startButtonLink() }
                    }
                }
            }
        }
    }

    private func setupStreamListeners(stream: MWDATCamera.Stream) {
        stateListenerToken = stream.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                guard let self, !self.isTakingPhoto else { return }
                switch state {
                case .streaming:
                    self.isStreaming = true
                case .stopped:
                    self.isStreaming = false
                default:
                    break
                }
            }
        }

        videoFrameListenerToken = stream.videoFramePublisher.listen { [weak self] frame in
            Task { @MainActor in
                self?.onVideoSampleBuffer?(frame.sampleBuffer)
                if let image = frame.makeUIImage() {
                    self?.lastFrame = image
                    self?.lastFrameTime = Date()
                    self?.onVideoFrame?(image)
                }
            }
        }

        photoDataListenerToken = stream.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor in
                let data = photoData.data
                self?.lastPhotoData = data
                self?.onPhotoCaptured?(data)
                AppLog.info(.glasses, "Stream photo captured: \(data.count) bytes")
            }
        }

        errorListenerToken = stream.errorPublisher.listen { [weak self] error in
            Task { @MainActor in
                if UIApplication.shared.applicationState == .active {
                    self?.errorMessage = error.localizedDescription
                }
                AppLog.error(.glasses, "Stream error: \(error)")
            }
        }
    }

    private func dumpSDKLogs(since seconds: TimeInterval) {
        let lines = AppLogStore.fetchSDKLogs(since: seconds)
        AppLog.info(.glasses, "SDK log dump (\(lines.count) entries in last \(Int(seconds))s)")
        for line in lines.prefix(40) {
            AppLog.debug(.glasses, line)
        }
    }

    private func cleanupStreamListeners() {
        stateListenerToken = nil
        videoFrameListenerToken = nil
        photoDataListenerToken = nil
        errorListenerToken = nil
    }
}
