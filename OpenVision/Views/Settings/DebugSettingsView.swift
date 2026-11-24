// OpenVision - DebugSettingsView.swift
// Diagnostics suite (PLAN.md §4.7, T6.5):
// - Log Viewer (filter by category/level, search, pause scroll, copy, ShareLink .txt export, Meta SDK logs)
// - Turn Timeline (MetricsCollector.recentTurns + camera activations)
// - Raw Reply vs Parsed Segments vs Spoken Pieces + Math Warnings inspector
// - Toggles for Live debugOverlay and verboseLogging.

import SwiftUI
import UniformTypeIdentifiers

struct DebugSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @ObservedObject private var logStore = AppLogStore.shared
    @ObservedObject private var metrics = MetricsCollector.shared
    @ObservedObject private var glassesManager = GlassesManager.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settingsManager.settings.debugOverlay) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lớp phủ gỡ lỗi trên Trực tiếp")
                        Text("Hiện trạng thái agent, voice, đọc bài và tuyến âm thanh")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $settingsManager.settings.verboseLogging) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log chi tiết (kể cả nội dung hỏi)")
                        Text("Chỉ lưu trên máy; chỉ xuất khi bạn bấm Xuất log")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Tùy chọn chẩn đoán")
            }

            Section {
                NavigationLink {
                    LogViewerScreen()
                } label: {
                    HStack {
                        Label("Nhật ký ứng dụng (Log)", systemImage: "doc.text.magnifyingglass")
                        Spacer()
                        Text("\(logStore.entries.count)")
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink {
                    TurnTimelineScreen()
                } label: {
                    HStack {
                        Label("Dòng thời gian lượt hỏi", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Text("\(metrics.recentTurns.count) lượt")
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink {
                    RawReplyInspectorScreen()
                } label: {
                    Label("Câu trả lời thô & Văn bản đọc", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } header: {
                Text("Công cụ gỡ lỗi")
            }

            Section {
                HStack {
                    Text("Tuyến âm thanh")
                    Spacer()
                    Text(AudioSessionManager.shared.outputLabel)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Nhận dạng giọng nói")
                    Spacer()
                    Text(VoiceCommandService.shared.isOnDeviceRecognition ? "Trên máy (On-Device)" : "Máy chủ Apple")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Số lần bật camera kính")
                    Spacer()
                    Text("\(glassesManager.cameraActivationCount) lần (\(String(format: "%.1f", glassesManager.totalCameraActiveSeconds))s)")
                        .foregroundColor(.secondary)
                }
                if let source = glassesManager.lastPhotoSource {
                    HStack {
                        Text("Nguồn ảnh gần nhất")
                        Spacer()
                        Text(source)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Trạng thái tức thời")
            }
        }
        .navigationTitle("Gỡ lỗi")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Log Viewer Screen

/// Lazy Transferable so ShareLink only generates export text (and fetches OSLogStore off-main)
/// when the user actually taps "Xuất log", never during SwiftUI body evaluation.
private struct LazyLogExport: Transferable, Sendable {
    let category: LogCategory?
    let minLevel: LogLevel
    let query: String
    let includeSDKLogs: Bool

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { item in
            let baseText = await MainActor.run {
                AppLogStore.shared.exportText(
                    category: item.category,
                    minLevel: item.minLevel,
                    query: item.query,
                    includeSDKLogs: false
                )
            }
            if item.includeSDKLogs {
                let sdkLines = await Task.detached(priority: .userInitiated) {
                    AppLogStore.fetchSDKLogs(since: 600)
                }.value
                let combined = baseText + "\n\n===== Meta Wearables SDK Logs (last 10m) =====\n" + sdkLines.joined(separator: "\n")
                return Data(combined.utf8)
            }
            return Data(baseText.utf8)
        }
        .suggestedFileName("OpenVision-logs.txt")
    }
}

struct LogViewerScreen: View {
    @ObservedObject private var logStore = AppLogStore.shared
    @State private var selectedCategory: LogCategory? = nil
    @State private var minLevel: LogLevel = .debug
    @State private var searchText: String = ""
    @State private var pauseAutoScroll: Bool = false
    @State private var includeSDKLogs: Bool = false
    @State private var copiedToast: Bool = false

    private var visibleEntries: [LogEntry] {
        logStore.filtered(category: selectedCategory, minLevel: minLevel, query: searchText)
    }

    var body: some View {
        let entries = visibleEntries
        VStack(spacing: 0) {
            // Filters bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryButton(title: "Tất cả", category: nil)
                    ForEach(LogCategory.allCases) { cat in
                        categoryButton(title: cat.displayName, category: cat)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            HStack(spacing: 10) {
                Picker("Mức", selection: $minLevel) {
                    ForEach(LogLevel.allCases) { lvl in
                        Text(lvl.shortLabel).tag(lvl)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Dừng cuộn", isOn: $pauseAutoScroll)
                    .toggleStyle(.button)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(entries) { entry in
                            Text(entry.formattedLine)
                                .font(.caption2.monospaced())
                                .foregroundColor(color(for: entry.level))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: entries.last?.id) { _, lastID in
                    if !pauseAutoScroll, let lastID {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack {
                Toggle("Gộp log SDK Meta", isOn: $includeSDKLogs)
                    .font(.caption)
                Spacer()
                Button {
                    let cat = selectedCategory
                    let lvl = minLevel
                    let q = searchText
                    let sdk = includeSDKLogs
                    Task {
                        let baseText = logStore.exportText(category: cat, minLevel: lvl, query: q, includeSDKLogs: false)
                        let fullText: String
                        if sdk {
                            let sdkLines = await Task.detached(priority: .userInitiated) {
                                AppLogStore.fetchSDKLogs(since: 600)
                            }.value
                            fullText = baseText + "\n\n===== Meta Wearables SDK Logs (last 10m) =====\n" + sdkLines.joined(separator: "\n")
                        } else {
                            fullText = baseText
                        }
                        UIPasteboard.general.string = fullText
                        copiedToast = true
                        HapticFeedback.success()
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        copiedToast = false
                    }
                } label: {
                    Label(copiedToast ? "Đã chép" : "Sao chép", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)

                ShareLink(
                    item: LazyLogExport(
                        category: selectedCategory,
                        minLevel: minLevel,
                        query: searchText,
                        includeSDKLogs: includeSDKLogs
                    ),
                    preview: SharePreview("OpenVision-logs.txt")
                ) {
                    Label("Xuất log", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("Log (\(entries.count))")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Tìm trong log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Xoá", role: .destructive) { logStore.clear() }
            }
        }
    }

    private func categoryButton(title: String, category: LogCategory?) -> some View {
        let active = selectedCategory == category
        return Button(title) {
            selectedCategory = category
        }
        .font(.caption.weight(active ? .bold : .regular))
        .foregroundColor(active ? .black : Theme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(active ? Theme.accent : Theme.bgElevated))
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: return Theme.textSecondary
        case .info: return Theme.textPrimary
        case .warning: return Theme.warning
        case .error: return Theme.danger
        }
    }
}

// MARK: - Turn Timeline Screen (MetricsCollector)

struct TurnTimelineScreen: View {
    @ObservedObject private var metrics = MetricsCollector.shared

    var body: some View {
        List {
            if metrics.recentTurns.isEmpty {
                Text("Chưa có lượt hỏi nào được ghi nhận trong phiên này.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(metrics.recentTurns) { turn in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(turn.startedAt.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                            Spacer()
                            if turn.abandoned {
                                badge("Bị huỷ / Lỗi", color: Theme.danger)
                            } else if turn.interrupted {
                                badge("Bị ngắt", color: Theme.warning)
                            } else {
                                badge("Hoàn tất", color: Theme.success)
                            }
                        }

                        HStack(spacing: 12) {
                            metricItem("Model", turn.model ?? "—")
                            metricItem("TTFT", formatSec(turn.timeToFirstToken))
                            metricItem("Tiếng đầu", formatSec(turn.perceivedLatency))
                            metricItem("Tổng", formatSec(turn.totalDuration))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Lượt hỏi gần đây")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metricItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
        }
    }

    private func formatSec(_ value: TimeInterval?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2fs", value)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}

// MARK: - Raw Reply vs Spoken Inspector

struct RawReplyInspectorScreen: View {
    @ObservedObject private var gemini = GeminiLiveService.shared
    @ObservedObject private var readingEngine = ReadingEngine.shared

    var body: some View {
        List {
            Section("Thông tin phản hồi") {
                HStack {
                    Text("Model")
                    Spacer()
                    Text(gemini.lastUsedModel ?? "—").font(.caption.monospaced())
                }
                HStack {
                    Text("Finish reason")
                    Spacer()
                    Text(gemini.lastFinishReason ?? "—").font(.caption.monospaced())
                }
                if !readingEngine.lastWarnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cảnh báo bộ đọc toán (lệnh lạ)")
                            .font(.caption.bold())
                            .foregroundColor(Theme.warning)
                        Text(readingEngine.lastWarnings.joined(separator: ", "))
                            .font(.caption.monospaced())
                            .foregroundColor(Theme.warning)
                    }
                }
            }

            Section("Văn bản thô từ Gemini") {
                if gemini.lastRawReply.isEmpty {
                    Text("Chưa có dữ liệu.")
                        .foregroundColor(.secondary)
                } else {
                    Text(gemini.lastRawReply)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section("Các mẩu đã đưa tới giọng đọc (\(readingEngine.spokenLog.count))") {
                if readingEngine.spokenLog.isEmpty {
                    Text("Chưa đọc mẩu nào.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(readingEngine.spokenLog) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Đoạn #\(item.segmentID)")
                                    .font(.caption2.bold())
                                    .foregroundColor(item.isMath ? Theme.info : Theme.accent)
                                Text(item.isMath ? "Toán" : "Lời văn")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "rate %.2f", item.rate))
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }
                            Text(item.text)
                                .font(.footnote)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle("Câu trả lời thô")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        DebugSettingsView()
            .environmentObject(SettingsManager.shared)
    }
    .preferredColorScheme(.dark)
}
