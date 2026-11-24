// Reybain - DebugSettingsView.swift
// Diagnostics suite styled in OLED obsidian & Liquid Glass:
// Log Viewer (glass filter pills, Reybain-logs.txt export), Turn Timeline (tabular metric tiles),
// Raw Reply vs Spoken Inspector, and Live debugOverlay / verboseLogging toggles.

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
                            .foregroundColor(Theme.textPrimary)
                        Text("Hiện trạng thái agent, voice, đọc bài và tuyến âm thanh")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()

                Toggle(isOn: $settingsManager.settings.verboseLogging) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log chi tiết (kể cả nội dung hỏi)")
                            .foregroundColor(Theme.textPrimary)
                        Text("Chỉ lưu trên máy; chỉ xuất khi bạn bấm Xuất log")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()
            } header: {
                Text("Tùy chọn chẩn đoán")
            }

            Section {
                NavigationLink {
                    LogViewerScreen()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconBadge(icon: "doc.text.magnifyingglass", tint: Theme.accent)
                        Text("Nhật ký ứng dụng (Log)")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text("\(logStore.entries.count)")
                            .font(Theme.Typography.monoMetric)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()

                NavigationLink {
                    TurnTimelineScreen()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconBadge(icon: "clock.arrow.circlepath", tint: Theme.iridescentIndigo)
                        Text("Dòng thời gian lượt hỏi")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text("\(metrics.recentTurns.count) lượt")
                            .font(Theme.Typography.monoMetric)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()

                NavigationLink {
                    RawReplyInspectorScreen()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconBadge(icon: "chevron.left.forwardslash.chevron.right", tint: Theme.iridescentCyan)
                        Text("Câu trả lời thô & Văn bản đọc")
                            .foregroundColor(Theme.textPrimary)
                    }
                }
                .reybainSettingsRow()
            } header: {
                Text("Công cụ gỡ lỗi")
            }

            Section {
                HStack {
                    Text("Tuyến âm thanh")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text(AudioSessionManager.shared.outputLabel)
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                .reybainSettingsRow()

                HStack {
                    Text("Nhận dạng giọng nói")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text(VoiceCommandService.shared.isOnDeviceRecognition ? "Trên máy (On-Device)" : "Máy chủ Apple")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                .reybainSettingsRow()

                HStack {
                    Text("Số lần bật camera kính")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text("\(glassesManager.cameraActivationCount) lần (\(String(format: "%.1f", glassesManager.totalCameraActiveSeconds))s)")
                        .font(Theme.Typography.monoMetric)
                        .foregroundColor(Theme.textSecondary)
                }
                .reybainSettingsRow()

                if let source = glassesManager.lastPhotoSource {
                    HStack {
                        Text("Nguồn ảnh gần nhất")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text(source)
                            .font(Theme.Typography.monoLog)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .reybainSettingsRow()
                }
            } header: {
                Text("Trạng thái tức thời")
            }
        }
        .reybainSettingsCanvas()
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
        .suggestedFileName("Reybain-logs.txt")
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
        ZStack {
            Theme.bg.ignoresSafeArea()

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
                        .tint(Theme.accent)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                Divider()
                    .overlay(Color.white.opacity(0.08))

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(entries) { entry in
                                Text(entry.formattedLine)
                                    .font(Theme.Typography.monoLog)
                                    .foregroundColor(color(for: entry.level))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(entry.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: entries.last?.id) { _, lastID in
                        if !pauseAutoScroll, let lastID {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }

                Divider()
                    .overlay(Color.white.opacity(0.08))

                HStack(spacing: 10) {
                    Toggle("Gộp log SDK Meta", isOn: $includeSDKLogs)
                        .font(.caption)
                        .foregroundColor(Theme.textPrimary)
                        .tint(Theme.accent)

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
                            .foregroundColor(Theme.textPrimary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .liquidGlassPill(interactive: true)
                    }
                    .buttonStyle(.plain)

                    ShareLink(
                        item: LazyLogExport(
                            category: selectedCategory,
                            minLevel: minLevel,
                            query: searchText,
                            includeSDKLogs: includeSDKLogs
                        ),
                        preview: SharePreview("Reybain-logs.txt")
                    ) {
                        Label("Xuất log", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.ctaForeground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Theme.buttonGradient))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Theme.bgSurface.opacity(0.95))
            }
        }
        .navigationTitle("Log (\(entries.count))")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Tìm trong log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Xoá", role: .destructive) { logStore.clear() }
                    .foregroundColor(Theme.danger)
            }
        }
    }

    private func categoryButton(title: String, category: LogCategory?) -> some View {
        let active = selectedCategory == category
        return Button {
            HapticFeedback.selection()
            selectedCategory = category
        } label: {
            Text(title)
                .font(.caption.weight(active ? .semibold : .medium))
                .foregroundColor(active ? Theme.accentBright : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .liquidGlassPill(tint: active ? Theme.accent : nil, interactive: true)
        }
        .buttonStyle(.plain)
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
                    .foregroundColor(Theme.textSecondary)
                    .reybainSettingsRow()
            } else {
                ForEach(metrics.recentTurns) { turn in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(turn.startedAt.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            if turn.abandoned {
                                badge("Bị huỷ / Lỗi", color: Theme.danger)
                            } else if turn.interrupted {
                                badge("Bị ngắt", color: Theme.warning)
                            } else {
                                badge("Hoàn tất", color: Theme.success)
                            }
                        }

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                            spacing: 6
                        ) {
                            metricTile("Model", shortModel(turn.model))
                            metricTile("TTFT", formatSec(turn.timeToFirstToken))
                            metricTile("Tiếng đầu", formatSec(turn.perceivedLatency))
                            metricTile("Tổng", formatSec(turn.totalDuration))
                        }
                    }
                    .padding(.vertical, 6)
                    .reybainSettingsRow()
                }
            }
        }
        .reybainSettingsCanvas()
        .navigationTitle("Lượt hỏi gần đây")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shortModel(_ model: String?) -> String {
        guard let model else { return "—" }
        return model.replacingOccurrences(of: "gemini-", with: "")
    }

    private func metricTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(Theme.textTertiary)
            Text(value)
                .font(Theme.Typography.monoMetric)
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.bgElevatedStroke, lineWidth: 0.7)
                )
        )
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
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.16))
                    .overlay(Capsule().strokeBorder(color.opacity(0.36), lineWidth: 0.7))
            )
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
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text(gemini.lastUsedModel ?? "—")
                        .font(Theme.Typography.monoLog)
                        .foregroundColor(Theme.accentBright)
                }
                .reybainSettingsRow()

                HStack {
                    Text("Finish reason")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text(gemini.lastFinishReason ?? "—")
                        .font(Theme.Typography.monoLog)
                        .foregroundColor(Theme.textSecondary)
                }
                .reybainSettingsRow()

                if !readingEngine.lastWarnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cảnh báo bộ đọc toán (lệnh lạ)")
                            .font(.caption.bold())
                            .foregroundColor(Theme.warning)
                        Text(readingEngine.lastWarnings.joined(separator: ", "))
                            .font(Theme.Typography.monoLog)
                            .foregroundColor(Theme.warning)
                    }
                    .reybainSettingsRow()
                }
            }

            Section("Văn bản thô từ Gemini") {
                if gemini.lastRawReply.isEmpty {
                    Text("Chưa có dữ liệu.")
                        .foregroundColor(Theme.textSecondary)
                        .reybainSettingsRow()
                } else {
                    Text(gemini.lastRawReply)
                        .font(Theme.Typography.monoLog)
                        .foregroundColor(Theme.textPrimary)
                        .textSelection(.enabled)
                        .reybainSettingsRow()
                }
            }

            Section("Các mẩu đã đưa tới giọng đọc (\(readingEngine.spokenLog.count))") {
                if readingEngine.spokenLog.isEmpty {
                    Text("Chưa đọc mẩu nào.")
                        .foregroundColor(Theme.textSecondary)
                        .reybainSettingsRow()
                } else {
                    ForEach(readingEngine.spokenLog) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Đoạn #\(item.segmentID)")
                                    .font(.caption2.monospacedDigit().bold())
                                    .foregroundColor(item.isMath ? Theme.info : Theme.accentBright)
                                Text(item.isMath ? "Toán" : "Lời văn")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textSecondary)
                                Spacer()
                                Text(String(format: "rate %.2f", item.rate))
                                    .font(Theme.Typography.monoLog)
                                    .foregroundColor(Theme.textTertiary)
                            }
                            Text(item.text)
                                .font(.footnote)
                                .foregroundColor(Theme.textPrimary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                        .reybainSettingsRow()
                    }
                }
            }
        }
        .reybainSettingsCanvas()
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
