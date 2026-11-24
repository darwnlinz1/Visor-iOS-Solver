// OpenVision - ReadingCommand.swift
// Pure Foundation bilingual parser for voice playback control commands (PLAN.md §4.4, T5.3).
// Distinguishes short reading commands ("tạm dừng", "đọc lại câu 3", "tiếp", "slower") from
// genuine follow-up questions ("tại sao câu 3 chọn C?", "giải thích dòng 2").

import Foundation

enum ReadingCommand: Equatable, Sendable {
    enum JumpScope: Equatable, Sendable {
        case any
        case question
        case line
        case problem
    }

    case pause
    case resume
    case next
    case previous
    case jump(Int, scope: JumpScope = .any)
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

        // 2. Jump to specific question / line / problem number: "đọc lại câu 3", "dòng 5", "bài 2", "question 3", "line 5"
        if let target = parseJumpTarget(normalized) {
            return .jump(target.number, scope: target.scope)
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

    private static func parseJumpTarget(_ normalized: String) -> (number: Int, scope: JumpScope)? {
        let prefixes: [(String, JumpScope)] = [
            ("đọc lại câu ", .question), ("doc lai cau ", .question),
            ("đọc câu ", .question), ("doc cau ", .question),
            ("nhảy tới câu ", .question), ("nhay toi cau ", .question),
            ("câu ", .question), ("cau ", .question),
            ("đọc lại dòng ", .line), ("doc lai dong ", .line),
            ("đọc dòng ", .line), ("doc dong ", .line),
            ("nhảy tới dòng ", .line), ("nhay toi dong ", .line),
            ("dòng ", .line), ("dong ", .line),
            ("đọc lại bài ", .problem), ("doc lai bai ", .problem),
            ("đọc bài ", .problem), ("doc bai ", .problem),
            ("bài ", .problem), ("bai ", .problem),
            ("repeat question ", .question), ("read question ", .question),
            ("go to question ", .question), ("question ", .question),
            ("repeat line ", .line), ("read line ", .line),
            ("go to line ", .line), ("line ", .line),
            ("repeat problem ", .problem), ("problem ", .problem)
        ]
        for (prefix, scope) in prefixes {
            if normalized.hasPrefix(prefix) {
                let tail = String(normalized.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if let n = parseSmallNumber(tail), n > 0 {
                    return (n, scope)
                }
            }
        }
        return nil
    }

    private static func parseSmallNumber(_ token: String) -> Int? {
        if let n = Int(token) { return n }
        let singleWords: [String: Int] = [
            "một": 1, "mot": 1, "mốt": 1, "one": 1,
            "hai": 2, "two": 2,
            "ba": 3, "three": 3,
            "bốn": 4, "bon": 4, "tư": 4, "tu": 4, "four": 4,
            "năm": 5, "nam": 5, "lăm": 5, "lam": 5, "nhăm": 5, "nham": 5, "five": 5,
            "sáu": 6, "sau": 6, "six": 6,
            "bảy": 7, "bay": 7, "seven": 7,
            "tám": 8, "tam": 8, "eight": 8,
            "chín": 9, "chin": 9, "nine": 9,
            "mười": 10, "muoi": 10, "ten": 10,
            "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
            "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20
        ]
        if let direct = singleWords[token] { return direct }

        // Vietnamese compound numbers 11..99 ("mười hai", "hai mươi mốt", "ba mươi lăm", "hai lăm")
        let parts = token.split(separator: " ").map(String.init)
        if parts.count == 2 {
            if (parts[0] == "mười" || parts[0] == "muoi"), let u = singleWords[parts[1]], (1...9).contains(u) {
                return 10 + u
            }
            if (parts[1] == "mươi" || parts[1] == "muoi"), let t = singleWords[parts[0]], (2...9).contains(t) {
                return t * 10
            }
            if let t = singleWords[parts[0]], (2...9).contains(t), let u = singleWords[parts[1]], (1...9).contains(u) {
                return t * 10 + u
            }
        } else if parts.count == 3, (parts[1] == "mươi" || parts[1] == "muoi"),
                  let t = singleWords[parts[0]], (2...9).contains(t),
                  let u = singleWords[parts[2]], (1...9).contains(u) {
            return t * 10 + u
        }
        return nil
    }
}
