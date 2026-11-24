// Reybain - AppLog.swift
// Centralised logger (PLAN.md §4.7, T2.4): OSLog + 2000-line in-memory ring buffer for the
// Debug screen + immediate stderr output (so simulator launch smoke checks see startup lines).
// Never log API keys, client tokens, team IDs, or user text unless `verboseLogging` is enabled.

import Foundation
import OSLog

enum LogCategory: String, CaseIterable, Identifiable, Sendable {
    case app
    case glasses
    case gemini
    case voice
    case tts
    case reading
    case audio
    case photo
    case settings
    case history

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .app: return "Ứng dụng"
        case .glasses: return "Kính"
        case .gemini: return "Gemini"
        case .voice: return "Giọng nói"
        case .tts: return "TTS"
        case .reading: return "Đọc bài"
        case .audio: return "Âm thanh"
        case .photo: return "Ảnh"
        case .settings: return "Cài đặt"
        case .history: return "Lịch sử"
        }
    }
}

enum LogLevel: Int, Comparable, CaseIterable, Identifiable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    var id: Int { rawValue }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var shortLabel: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

struct LogEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String

    init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel, category: LogCategory, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }

    var formattedLine: String {
        let time = AppLogFormatter.timeString(timestamp)
        return "[\(time)] [\(level.shortLabel)] [\(category.rawValue)] \(message)"
    }
}

private enum AppLogFileWriter {
    private static let queue = DispatchQueue(label: "com.reybain.applog.file", qos: .utility)
    private static let maxBytes: UInt64 = 512 * 1024

    static var logFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("reybain.log")
    }

    private static var previousLogFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("reybain.prev.log")
    }

    static func appendLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        queue.async {
            let url = logFileURL
            let fm = FileManager.default
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64,
               size >= maxBytes {
                let prev = previousLogFileURL
                try? fm.removeItem(at: prev)
                try? fm.moveItem(at: url, to: prev)
            }
            if fm.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    static func clear() {
        queue.async {
            let fm = FileManager.default
            try? fm.removeItem(at: logFileURL)
            try? fm.removeItem(at: previousLogFileURL)
        }
    }
}

private enum AppLogFormatter {
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func timeString(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: date)
    }
}

@MainActor
final class AppLogStore: ObservableObject {
    static let shared = AppLogStore()

    static let maxEntries = 2000

    @Published private(set) var entries: [LogEntry] = []

    private init() {}

    func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
        AppLogFileWriter.clear()
    }

    func filtered(category: LogCategory?, minLevel: LogLevel, query: String) -> [LogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            if let category, entry.category != category { return false }
            if entry.level < minLevel { return false }
            if !trimmed.isEmpty {
                let matchesMessage = entry.message.localizedCaseInsensitiveContains(trimmed)
                let matchesCategory = entry.category.rawValue.localizedCaseInsensitiveContains(trimmed)
                if !matchesMessage && !matchesCategory { return false }
            }
            return true
        }
    }

    func exportText(category: LogCategory? = nil, minLevel: LogLevel = .debug, query: String = "", includeSDKLogs: Bool = false) -> String {
        var lines = [
            "Reybain Log Export — \(ISO8601DateFormatter().string(from: Date()))",
            "App: \(Config.appVersion) (\(Config.buildNumber)) | Model chain: \(GeminiLiveService.modelChain.joined(separator: " -> "))",
            String(repeating: "-", count: 60),
        ]
        let items = filtered(category: category, minLevel: minLevel, query: query)
        lines.append(contentsOf: items.map(\.formattedLine))
        if includeSDKLogs {
            lines.append("")
            lines.append("===== Meta Wearables SDK Logs (last 10m) =====")
            lines.append(contentsOf: Self.fetchSDKLogs(since: 600))
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func fetchSDKLogs(since seconds: TimeInterval) -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: Date().addingTimeInterval(-seconds))
            let entries = try store.getEntries(at: position)
            var out: [String] = []
            for entry in entries {
                guard let log = entry as? OSLogEntryLog else { continue }
                let sub = log.subsystem
                guard !sub.isEmpty, !sub.hasPrefix("com.apple") else { continue }
                out.append("[SDKLOG] \(sub)/\(log.category) [\(log.level.rawValue)] \(log.composedMessage)")
            }
            return out
        } catch {
            return ["[SDKLOG] OSLogStore unavailable: \(error.localizedDescription)"]
        }
    }
}

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.reybain.app"
    private static let lock = NSLock()
    private static var _verboseLogging = false
    private static var loggers: [LogCategory: Logger] = [:]

    static var isVerboseLoggingEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _verboseLogging
    }

    static func setVerboseLogging(_ enabled: Bool) {
        lock.lock()
        _verboseLogging = enabled
        lock.unlock()
    }

    static func debug(_ category: LogCategory, _ message: @autoclosure () -> String, sensitive: Bool = false) {
        log(level: .debug, category: category, message: message, sensitive: sensitive)
    }

    static func info(_ category: LogCategory, _ message: @autoclosure () -> String, sensitive: Bool = false) {
        log(level: .info, category: category, message: message, sensitive: sensitive)
    }

    static func warning(_ category: LogCategory, _ message: @autoclosure () -> String, sensitive: Bool = false) {
        log(level: .warning, category: category, message: message, sensitive: sensitive)
    }

    static func error(_ category: LogCategory, _ message: @autoclosure () -> String, sensitive: Bool = false) {
        log(level: .error, category: category, message: message, sensitive: sensitive)
    }

    private static func logger(for category: LogCategory) -> Logger {
        lock.lock()
        defer { lock.unlock() }
        if let existing = loggers[category] { return existing }
        let created = Logger(subsystem: subsystem, category: category.rawValue)
        loggers[category] = created
        return created
    }

    private static func log(level: LogLevel, category: LogCategory, message: () -> String, sensitive: Bool) {
        if sensitive && !isVerboseLoggingEnabled { return }
        let resolvedMessage = message()
        let entry = LogEntry(level: level, category: category, message: resolvedMessage)
        let osLogger = logger(for: category)
        if sensitive {
            switch level {
            case .debug:
                osLogger.debug("\(resolvedMessage, privacy: .private)")
            case .info:
                osLogger.info("\(resolvedMessage, privacy: .private)")
            case .warning:
                osLogger.warning("\(resolvedMessage, privacy: .private)")
            case .error:
                osLogger.error("\(resolvedMessage, privacy: .private)")
            }
        } else {
            switch level {
            case .debug:
                osLogger.debug("\(resolvedMessage, privacy: .public)")
            case .info:
                osLogger.info("\(resolvedMessage, privacy: .public)")
            case .warning:
                osLogger.warning("\(resolvedMessage, privacy: .public)")
            case .error:
                osLogger.error("\(resolvedMessage, privacy: .public)")
            }
        }
        // Write to stderr (for simulator console) and persist to Documents/reybain.log for easy device debugging.
        let line = entry.formattedLine + "\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
        AppLogFileWriter.appendLine(line)
        Task { @MainActor in
            AppLogStore.shared.append(entry)
        }
    }
}
