// OpenVision - GlassesConnectionCoordinator.swift
// Pure state machine and exponential backoff policy for Ray-Ban Meta DAT session & button-link health.

import Foundation

/// High-level connection phase for the Ray-Ban Meta DAT session + input link.
enum GlassesConnectionPhase: Equatable, Sendable {
    case sdkUnavailable(String)
    case disabled
    case unregistered
    case waitingForGlasses
    case connectingSession
    case attachingInputs
    case ready
    case permissionDenied
    case reconnecting(attempt: Int, delaySeconds: UInt64)

    var isReady: Bool {
        self == .ready
    }

    var displayText: String {
        switch self {
        case .sdkUnavailable(let reason):
            return reason
        case .disabled:
            return "Tắt"
        case .unregistered:
            return "Chưa đăng ký kính"
        case .waitingForGlasses:
            return "Chờ kính kết nối…"
        case .connectingSession:
            return "Đang mở phiên kính…"
        case .attachingInputs:
            return "Đang kích hoạt nút kính…"
        case .ready:
            return "Đang hoạt động"
        case .permissionDenied:
            return "Meta chưa cho phép app nhận nút kính — bật Developer Mode trong Meta AI"
        case .reconnecting(let attempt, let delaySeconds):
            return "Đang thử kết nối lại (#\(attempt), \(delaySeconds)s)…"
        }
    }
}

/// Deterministic exponential backoff policy for rebuilding a dropped DAT session/inputs link.
struct GlassesReconnectPolicy: Equatable, Sendable {
    static let schedule: [UInt64] = [2, 4, 8, 15, 30, 60]

    private(set) var attemptCount: Int = 0

    mutating func reset() {
        attemptCount = 0
    }

    mutating func nextDelaySeconds() -> UInt64 {
        let idx = min(attemptCount, Self.schedule.count - 1)
        let delay = Self.schedule[idx]
        attemptCount += 1
        return delay
    }

    func canAttemptReconnect(
        wantsLink: Bool,
        isSDKAvailable: Bool,
        isRegistered: Bool,
        hasConnectedDevice: Bool,
        permissionDenied: Bool
    ) -> Bool {
        wantsLink && isSDKAvailable && isRegistered && hasConnectedDevice && !permissionDenied
    }
}
