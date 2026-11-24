// Reybain - GlassesButtonRouter.swift
// Pure button gesture classification, deduplication, and mode-aware action routing
// for Ray-Ban Meta Capture Button and Action Button (MWDATInputs).

import Foundation

/// A normalized press gesture from the glasses' physical Capture Button or Action Button.
enum GlassesButtonPress: String, Equatable, Sendable {
    case shortPress
    case hold
    case doublePress
}

/// Resolves which `GlassesButtonAction` a physical button gesture should trigger
/// based on the user's selected `UsageMode` and optional custom override mapping.
enum GlassesWorkflowPolicy {
    static func action(for press: GlassesButtonPress, settings: AppSettings) -> GlassesButtonAction {
        if settings.useCustomButtonMapping {
            switch press {
            case .shortPress: return settings.shortPressAction
            case .hold: return settings.holdAction
            case .doublePress: return settings.doublePressAction
            }
        }
        switch press {
        case .shortPress: return settings.usageMode.defaultShortPressAction
        case .hold: return settings.usageMode.defaultHoldAction
        case .doublePress: return settings.usageMode.defaultDoublePressAction
        }
    }
}

/// Deduplicates retransmitted DAT input events with identical `(channel, timestampMs)`
/// so a single physical click never fires twice across BLE hiccups.
struct GlassesInputDeduplicator: Sendable {
    private var lastTimestamps: [String: Int64] = [:]

    /// Returns `true` if this event is fresh and should be processed, `false` if duplicate.
    mutating func shouldAccept(channel: String, timestampMs: Int64) -> Bool {
        // timestampMs == 0 can appear on synthetic/mock events; always accept those.
        guard timestampMs > 0 else { return true }
        if let previous = lastTimestamps[channel], previous == timestampMs {
            return false
        }
        lastTimestamps[channel] = timestampMs
        return true
    }

    mutating func reset() {
        lastTimestamps.removeAll()
    }
}

/// Pure classifier that turns discrete single presses from `InputEvent.button` (physical Action Button)
/// into `.shortPress` or `.doublePress` using a short coalescing window.
/// Note: `InputEvent.capture` already delivers native `.shortPress` / `.doublePress` / `.hold`
/// directly from firmware and does not need to wait on this buffer.
@MainActor
final class ActionButtonPressDetector {
    /// Maximum interval between two discrete action-button presses to count as a double press.
    let doublePressWindow: TimeInterval
    var onPressClassified: ((GlassesButtonPress) -> Void)?

    private var pendingSingleTask: Task<Void, Never>?
    private var lastPressAt: Date?

    init(doublePressWindow: TimeInterval = 0.38) {
        self.doublePressWindow = doublePressWindow
    }

    /// Call on each discrete `.button` press received from `MWDATInputs`.
    func registerPress(at now: Date = Date()) {
        if let previous = lastPressAt, now.timeIntervalSince(previous) <= doublePressWindow {
            pendingSingleTask?.cancel()
            pendingSingleTask = nil
            lastPressAt = nil
            onPressClassified?(.doublePress)
            return
        }

        lastPressAt = now
        pendingSingleTask?.cancel()
        let waitNanos = UInt64(max(0.05, doublePressWindow) * 1_000_000_000)
        pendingSingleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: waitNanos)
            guard !Task.isCancelled, let self else { return }
            self.pendingSingleTask = nil
            self.lastPressAt = nil
            self.onPressClassified?(.shortPress)
        }
    }

    func reset() {
        pendingSingleTask?.cancel()
        pendingSingleTask = nil
        lastPressAt = nil
    }
}
