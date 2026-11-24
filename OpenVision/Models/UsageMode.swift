// OpenVision - UsageMode.swift
// Operating modes for OpenVision: Study (auto-send short solve prompt on button press)
// vs. General (capture photo and listen for a free-form voice command).

import Foundation

/// High-level operating mode selected in Settings.
enum UsageMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Homework / exam solving: pressing the glasses button once captures and immediately
    /// sends the configurable short solve prompt; double-press repeats the previous response.
    case study
    /// Everyday use (scenery, signs, translation, objects): pressing the glasses button once
    /// captures a photo and opens the mic for any free-form command; double-press repeats.
    case general

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .study: return "Giải bài tập"
        case .general: return "Sử dụng bình thường"
        }
    }

    var shortLabel: String {
        switch self {
        case .study: return "Giải bài"
        case .general: return "Bình thường"
        }
    }

    var systemImage: String {
        switch self {
        case .study: return "graduationcap.fill"
        case .general: return "eye.fill"
        }
    }

    var summary: String {
        switch self {
        case .study:
            return "Nhấn 1 lần nút trên kính để chụp và tự gửi kèm prompt giải bài. Nhấn 2 lần để đọc lại câu trả lời cũ."
        case .general:
            return "Nhấn 1 lần nút trên kính để chụp ảnh rồi nói lệnh tự do (phong cảnh, dịch chữ, hỏi vật thể…). Nhấn 2 lần để đọc lại câu trả lời cũ."
        }
    }

    /// Optional context hint appended to `PromptV2.systemPrompt` so Gemini adapts tone/format
    /// cleanly to the active operating mode without breaking the v2.1 tag contract.
    var systemPromptHint: String? {
        switch self {
        case .study:
            return nil
        case .general:
            return """
            ACTIVE MODE: Everyday assistant (general use).
            The user is walking around, looking at scenery, signs, menus, objects, or asking free-form questions. \
            Prefer TYPE: OTHER with clear, concise spoken ANSWER lines unless the user explicitly shows an exercise or asks to solve a math/homework problem.
            """
        }
    }

    /// Default button actions implied by this mode when custom per-gesture overrides are off.
    var defaultShortPressAction: GlassesButtonAction {
        switch self {
        case .study: return .captureAndSolve
        case .general: return .captureAndListen
        }
    }

    var defaultDoublePressAction: GlassesButtonAction {
        .repeatAnswer
    }

    var defaultHoldAction: GlassesButtonAction {
        switch self {
        case .study: return .captureAndListen
        case .general: return .captureAndSolve
        }
    }

    /// Quick prompt presets offered in Settings for Study mode.
    static let studyPromptPresets: [String] = [
        "Giải bài trong ảnh này.",
        "Chỉ đọc đáp án ngắn gọn nhất cho bài trong ảnh này.",
        "Giải chi tiết từng bước bài trong ảnh này.",
        "Kiểm tra xem bài làm trong ảnh này đúng hay sai và sửa lại."
    ]

    /// Resolves the prompt sent when triggering `.captureAndSolve`.
    static func resolvedSolvePrompt(customPrompt: String, speaksVietnamese: Bool) -> String {
        let trimmed = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return speaksVietnamese ? "Giải bài trong ảnh này." : "Solve the problem in this photo."
    }
}
