// OpenVision - ReadingCommand.swift
// Pure Foundation bilingual parser for voice playback control commands (PLAN.md §4.4, T5.3).
// Distinguishes short reading commands ("tạm dừng", "đọc lại câu 3", "tiếp", "slower") from
// genuine follow-up questions ("tại sao câu 3 chọn C?", "giải thích dòng 2").

import Foundation

enum ReadingCommand: Equatable, Sendable {
    case pause
    case resume
    case next
    case previous
    case jump(Int)
    case repeatCurrent
    case restart
    case slower
    case faster
    case stop

    /// Parses a command utterance (already stripped of wake word when spoken during reading).
    /// Returns nil for real questions so they flow verbatim to Gemini.
    static func parse(_ rawText: String) -> ReadingCommand? {
        let normalized = normalize(rawText)
        guard !normalized.isEmpty else { return nil }

        // Reject obvious questions or explanatory requests — those belong to Gemini, not playback controls.
        let questionIndicators = [
            "tại sao", "tai sao", "vì sao", "vi sao", "giải thích", "giai thich",
            "giải chi tiết", "giai chi tiet", "giải tiếp", "giai tiep", "giải nốt", "giai not",
            "làm sao", "lam sao", "như thế nào", "nhu the nao", "bằng bao nhiêu", "bang bao nhieu",
            "chọn gì", "chon gi", "là gì", "la gi", "còn câu", "con cau",
            "why", "how", "what", "explain", "solve", "calculate", "prove", "?"
        ]
        if questionIndicators.contains(where: { normalized.contains($0) }) {
            return nil
        }

        // Reject long sentences (> 7 words) so normal questions never misfire as playback controls.
        let words = normalized.split(separator: " ").map(String.init)
        guard words.count <= 7 else { return nil }

        // 1. Restart from beginning (check before repeatCurrent / jump)
        let restartPhrases = [
            "đọc lại từ đầu", "doc lai tu dau", "từ đầu", "tu dau", "nghe lại từ đầu", "nghe lai tu dau",
            "from the start", "from the beginning", "start over", "restart", "read from the start"
        ]
        if restartPhrases.contains(normalized) { return .restart }

        // 2. Jump to specific question / line number: "đọc lại câu 3", "câu 3", "dòng 5", "question 3", "line 5"
        if let number = parseJumpNumber(normalized) {
            return .jump(number)
        }

        // 3. Pause
        let pausePhrases = [
            "tạm dừng", "tam dung", "dừng chút", "dung chut", "chờ chút", "cho chut",
            "đợi chút", "doi chut", "pause", "hold on", "wait"
        ]
        if pausePhrases.contains(normalized) { return .pause }

        // 4. Resume / continue (also bare "tiếp" in dictation mode)
        let resumePhrases = [
            "tiếp tục", "tiep tuc", "đọc tiếp", "doc tiep", "tiếp", "tiep", "tiếp đi", "tiep di",
            "continue", "resume", "keep going", "go on", "play"
        ]
        if resumePhrases.contains(normalized) { return .resume }

        // 5. Next segment
        let nextPhrases = [
            "dòng tiếp", "dong tiep", "dòng tiếp theo", "dong tiep theo", "dòng sau", "dong sau",
            "câu tiếp", "cau tiep", "câu tiếp theo", "cau tiep theo", "câu sau", "cau sau",
            "bước tiếp", "buoc tiep", "bỏ qua", "bo qua",
            "next", "next line", "next question", "skip"
        ]
        if nextPhrases.contains(normalized) { return .next }

        // 6. Previous segment
        let previousPhrases = [
            "dòng trước", "dong truoc", "câu trước", "cau truoc", "bước trước", "buoc truoc",
            "quay lại", "quay lai", "lùi lại", "lui lai",
            "previous", "previous line", "previous question", "back", "go back"
        ]
        if previousPhrases.contains(normalized) { return .previous }

        // 7. Repeat current segment
        let repeatPhrases = [
            "đọc lại", "doc lai", "lặp lại", "lap lai", "nhắc lại", "nhac lai",
            "nghe lại", "nghe lai", "đọc lại dòng này", "doc lai dong nay",
            "đọc lại câu này", "doc lai cau nay", "nói lại", "noi lai",
            "repeat", "repeat that", "say again", "read again", "again"
        ]
        if repeatPhrases.contains(normalized) { return .repeatCurrent }

        // 8. Slower
        let slowerPhrases = [
            "chậm lại", "cham lai", "đọc chậm", "doc cham", "đọc chậm lại", "doc cham lai",
            "chậm hơn", "cham hon", "chậm thôi", "cham thoi",
            "slower", "slow down", "read slower"
        ]
        if slowerPhrases.contains(normalized) { return .slower }

        // 9. Faster
        let fasterPhrases = [
            "nhanh lên", "nhanh len", "đọc nhanh", "doc nhanh", "đọc nhanh lên", "doc nhanh len",
            "nhanh hơn", "nhanh hon",
            "faster", "speed up", "read faster"
        ]
        if fasterPhrases.contains(normalized) { return .faster }

        // 10. Stop reading (keeps ReadingPlan for later replay)
        let stopPhrases = [
            "dừng lại", "dung lai", "dừng", "dung", "thôi", "thoi", "thôi đi", "thoi di",
            "ngừng", "ngung", "ngừng lại", "ngung lai", "im đi", "im di",
            "stop", "stop reading", "quiet", "silence", "enough", "be quiet"
        ]
        if stopPhrases.contains(normalized) { return .stop }

        return nil
    }

    private static func normalize(_ raw: String) -> String {
        let lower = raw.lowercased()
        let cleaned = lower.map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == "?" { return ch }
            return " "
        }
        return String(cleaned)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func parseJumpNumber(_ normalized: String) -> Int? {
        let prefixes = [
            "đọc lại câu ", "doc lai cau ", "đọc câu ", "doc cau ", "nhảy tới câu ", "nhay toi cau ", "câu ", "cau ",
            "đọc lại dòng ", "doc lai dong ", "đọc dòng ", "doc dong ", "nhảy tới dòng ", "nhay toi dong ", "dòng ", "dong ",
            "đọc lại bài ", "doc lai bai ", "đọc bài ", "doc bai ", "bài ", "bai ",
            "repeat question ", "read question ", "go to question ", "question ",
            "repeat line ", "read line ", "go to line ", "line ",
            "repeat problem ", "problem "
        ]
        for prefix in prefixes {
            if normalized.hasPrefix(prefix) {
                let tail = String(normalized.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if let n = parseSmallNumber(tail), n > 0 {
                    return n
                }
            }
        }
        return nil
    }

    private static func parseSmallNumber(_ token: String) -> Int? {
        if let n = Int(token) { return n }
        let words: [String: Int] = [
            "một": 1, "mot": 1, "one": 1,
            "hai": 2, "two": 2,
            "ba": 3, "three": 3,
            "bốn": 4, "bon": 4, "tư": 4, "tu": 4, "four": 4,
            "năm": 5, "nam": 5, "five": 5,
            "sáu": 6, "sau": 6, "six": 6,
            "bảy": 7, "bay": 7, "seven": 7,
            "tám": 8, "tam": 8, "eight": 8,
            "chín": 9, "chin": 9, "nine": 9,
            "mười": 10, "muoi": 10, "ten": 10
        ]
        return words[token]
    }
}
