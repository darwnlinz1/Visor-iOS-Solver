// OpenVision - VoiceAgentViewModel.swift
// MVVM orchestrator for the Live screen: voice sessions, direct chat (P0 #1/#2/#3 fixed),
// v2.1 structured streaming (`AnswerFormat` -> `ReplyAssembler` -> `ReadingEngine`),
// voice reading controls (N6-N9), Meta-album-only photo scanner (B6/T7.6), and History persistence.

import Photos
import UIKit
import ImageIO
import SwiftUI
import Speech

/// Pre-captured photo context for Visor "Capture First, Ask Later" workflow
struct CapturedPhotoContext {
    static let ttl: TimeInterval = 120.0
    static let maxUses = 5

    let id: UUID = UUID()
    let data: Data
    let timestamp: Date
    var useCount: Int
    var source: String

    init(data: Data, timestamp: Date = Date(), useCount: Int = 0, source: String = "glasses") {
        self.data = data
        self.timestamp = timestamp
        self.useCount = useCount
        self.source = source
    }

    var isFresh: Bool { isFresh(at: Date()) }

    func isFresh(at now: Date) -> Bool {
        now.timeIntervalSince(timestamp) < Self.ttl && useCount < Self.maxUses
    }

    func remainingSeconds(at now: Date) -> Int {
        max(0, Int(ceil(Self.ttl - now.timeIntervalSince(timestamp))))
    }
}

// MARK: - Solver intent (pure, unit-testable)

enum SolverIntent {
    static let recentPhotoWindow: TimeInterval = 120.0
    static let ttsEchoSettleNanoseconds: UInt64 = 350_000_000

    static func isStopCommand(_ command: String) -> Bool {
        let lowerCommand = command.lowercased()
        let commandWords = Set(lowerCommand.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let stopSingleWords: Set<String> = ["stop", "quiet", "silence", "enough"]
        let stopExact: Set<String> = ["stop", "quiet", "silence", "enough", "dừng", "thôi", "ngừng"]
        let stopPhrases = [
            "be quiet", "shut up", "ok stop", "okay stop", "stop talking", "stop it",
            "dừng lại", "dừng đi", "thôi đi", "ngừng lại", "ngừng đi"
        ]
        let isExactStop = stopExact.contains(lowerCommand.trimmingCharacters(in: .whitespacesAndNewlines))
        return (isExactStop
                || !commandWords.isDisjoint(with: stopSingleWords)
                || stopPhrases.contains { lowerCommand.contains($0) })
                && !lowerCommand.contains("video") && !lowerCommand.contains("stream")
    }

    @MainActor
    static func missingKeyMessage(for prompt: String) -> String {
        TTSService.containsVietnamese(prompt)
            ? "Chưa có API key Gemini. Bạn mở Cài đặt, chọn Gemini và dán key vào nhé."
            : "There is no Gemini API key yet. Open Settings, Gemini, and paste your key."
    }

    @MainActor
    static func networkFailureMessage(for prompt: String) -> String {
        TTSService.containsVietnamese(prompt)
            ? "Mạng đang chậm nên mình chưa nhận được câu trả lời. Bạn hỏi lại giúp mình nhé."
            : "The connection is slow and I didn't get an answer. Please ask again."
    }

    @MainActor
    static var speaksVietnamese: Bool {
        switch SettingsManager.shared.settings.recognitionLanguage {
        case "vi-VN": return true
        case "en-US": return false
        default: return Locale.preferredLanguages.first?.lowercased().hasPrefix("vi") ?? true
        }
    }

    @MainActor
    static var solvePhotoQuestion: String {
        UsageMode.resolvedSolvePrompt(
            customPrompt: SettingsManager.shared.settings.studySolvePrompt,
            speaksVietnamese: speaksVietnamese
        )
    }

    @MainActor
    static var photoReadyMessage: String {
        speaksVietnamese ? "Đã chụp. Bạn hỏi đi." : "Got the photo. Go ahead."
    }

    @MainActor
    static var photoFailedMessage: String {
        speaksVietnamese
            ? "Chưa lấy được ảnh từ kính. Bạn bấm nút chụp lại giúp mình nhé."
            : "I couldn't get the photo from the glasses. Please press the capture button again."
    }

    @MainActor
    static var nothingToRepeatMessage: String {
        speaksVietnamese ? "AI chưa có câu trả lời nào để đọc lại." : "The AI hasn't responded yet."
    }

    @MainActor
    static var stillWaitingForResponseMessage: String {
        speaksVietnamese ? "AI chưa phản hồi xong, bạn đợi chút nhé." : "The AI hasn't finished responding yet."
    }

    @MainActor
    static func missingPhotoMessage(for prompt: String) -> String {
        TTSService.containsVietnamese(prompt)
            ? "Không tìm thấy ảnh chụp bài tập từ kính Ray-Ban. Bạn hãy bấm nút chụp trên gọng kính rồi hỏi lại nhé."
            : "No photo found from Ray-Ban glasses. Please press the temple capture button and ask again."
    }
}

private final class MetaAlbumLogState: @unchecked Sendable {
    static let shared = MetaAlbumLogState()
    private let lock = NSLock()
    private var logged = false

    func consumeShouldLogMissingAlbum() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if logged { return false }
        logged = true
        return true
    }
}

// MARK: - Recent Photo Scanner (Meta / Ray-Ban albums ONLY — fixes B6 / T7.6)

@MainActor
final class RecentPhotoScanner: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    static let shared = RecentPhotoScanner()

    @Published private(set) var lastScannedPhotoData: Data?
    @Published private(set) var lastScannedTimestamp: Date?
    @Published private(set) var isLimitedAccess = false
    @Published private(set) var latestPhotoDate: Date?
    @Published private(set) var latestThumbnail: UIImage?
    @Published private(set) var isWaitingForPhoto = false
    var onPhotoArrived: ((Data) -> Void)?

    private var cache: (assetID: String, created: Date, data: Data)?
    private var prefetchTask: Task<Void, Never>?
    private var inFlight: (assetID: String, task: Task<Data?, Never>)?

    private override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
        isLimitedAccess = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        isLimitedAccess = status == .limited
        if status == .limited {
            AppLog.warning(.photo, "Limited photo access — new glasses photos will NOT be visible. Ask for Full Access.")
        }
        return status == .authorized || status == .limited
    }

    func fetchMostRecentPhoto(withinSeconds seconds: TimeInterval = SolverIntent.recentPhotoWindow) async -> Data? {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            _ = await requestAuthorizationIfNeeded()
            status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            AppLog.warning(.photo, "Photo library not authorized (\(status.rawValue))")
            return nil
        }

        let cutoffDate = Date().addingTimeInterval(-seconds)
        guard let newest = await Self.newestImageAsset(since: cutoffDate) else {
            return nil
        }

        if let cached = cache, cached.assetID == newest.id {
            return cached.data
        }

        let load: Task<Data?, Never>
        if let running = inFlight, running.assetID == newest.id {
            load = running.task
        } else {
            let assetID = newest.id
            load = Task.detached(priority: .userInitiated) { await Self.loadFullResolution(assetID: assetID) }
            inFlight = (assetID: assetID, task: load)
        }
        let loaded = await load.value
        if inFlight?.assetID == newest.id { inFlight = nil }
        guard let data = loaded else {
            AppLog.warning(.photo, "Could not load image data for newest Meta album asset")
            return nil
        }

        cache = (assetID: newest.id, created: newest.created, data: data)
        lastScannedPhotoData = data
        lastScannedTimestamp = Date()
        latestPhotoDate = newest.created
        let thumbnail = await Task.detached(priority: .utility) {
            PhotoPayload.renderJPEG(from: data, maxPixelSize: 180, quality: 0.7)
        }.value
        if cache?.assetID == newest.id {
            latestThumbnail = thumbnail.flatMap { UIImage(data: $0) }
        }
        onPhotoArrived?(data)
        return data
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.prefetchTask?.cancel()
            self.prefetchTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                _ = await self.fetchMostRecentPhoto(withinSeconds: 60.0)
            }
        }
    }

    // MARK: - Background PhotoKit work (Meta/Ray-Ban albums only — fixes B6 privacy leak)

    nonisolated static func isMetaAlbumTitle(_ title: String?) -> Bool {
        guard let lower = title?.lowercased() else { return false }
        return lower.contains("meta") || lower.contains("ray-ban") || lower.contains("stories")
    }

    private nonisolated static func newestImageAsset(since cutoff: Date) async -> (id: String, created: Date)? {
        await withCheckedContinuation { (continuation: CheckedContinuation<(id: String, created: Date)?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let albumCollections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
                var metaAlbums: [PHAssetCollection] = []
                var allAlbumTitles: [String] = []
                albumCollections.enumerateObjects { col, _, _ in
                    if let title = col.localizedTitle {
                        allAlbumTitles.append(title)
                    }
                    if Self.isMetaAlbumTitle(col.localizedTitle) {
                        metaAlbums.append(col)
                    }
                }

                if metaAlbums.isEmpty {
                    if MetaAlbumLogState.shared.consumeShouldLogMissingAlbum() {
                        AppLog.info(.photo, "No Meta/Ray-Ban album found in Photos; available albums: \(allAlbumTitles.joined(separator: ", "))")
                    }
                    continuation.resume(returning: nil)
                    return
                }

                var bestMatch: (id: String, created: Date)? = nil
                for album in metaAlbums {
                    let fetchOpts = PHFetchOptions()
                    fetchOpts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                    fetchOpts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
                    fetchOpts.fetchLimit = 5
                    let albumAssets = PHAsset.fetchAssets(in: album, options: fetchOpts)
                    albumAssets.enumerateObjects { asset, _, stop in
                        if asset.mediaSubtypes.contains(.photoScreenshot) { return }
                        if asset.pixelWidth < 1000 && asset.pixelHeight < 1000 { return }
                        let date = asset.creationDate ?? asset.modificationDate ?? Date()
                        if date >= cutoff {
                            if bestMatch == nil || date > bestMatch!.created {
                                bestMatch = (id: asset.localIdentifier, created: date)
                            }
                            stop.pointee = true
                        }
                    }
                }

                continuation.resume(returning: bestMatch)
            }
        }
    }

    private nonisolated static func loadFullResolution(assetID: String) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            guard let asset = assets.firstObject else {
                continuation.resume(returning: nil)
                return
            }

            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.version = .current

            var didResume = false
            let lock = NSLock()
            let resumeOnce: (Data?) -> Void = { result in
                lock.lock()
                defer { lock.unlock() }
                if !didResume {
                    didResume = true
                    continuation.resume(returning: result)
                }
            }

            Task.detached {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                resumeOnce(nil)
            }

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let isDegraded = info?[PHImageResultIsDegradedKey] as? NSNumber, isDegraded.boolValue {
                    return
                }
                if let error = info?[PHImageErrorKey] as? Error {
                    AppLog.error(.photo, "PhotoKit requestImageData error: \(error.localizedDescription)")
                    resumeOnce(nil)
                    return
                }
                if let rawData = data, !rawData.isEmpty {
                    let prepared = PhotoPayload.uploadJPEG(from: rawData) ?? rawData
                    resumeOnce(prepared)
                } else {
                    let imgOptions = PHImageRequestOptions()
                    imgOptions.isSynchronous = false
                    imgOptions.deliveryMode = .highQualityFormat
                    imgOptions.isNetworkAccessAllowed = true
                    PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: imgOptions) { img, imgInfo in
                        if let isImgDegraded = imgInfo?[PHImageResultIsDegradedKey] as? NSNumber, isImgDegraded.boolValue {
                            return
                        }
                        if let img = img, let fullData = img.jpegData(compressionQuality: PhotoPayload.uploadQuality) {
                            resumeOnce(fullData)
                        } else {
                            resumeOnce(nil)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Photo payload (pure, unit-testable)

enum PhotoPayload {
    static let uploadMaxDimension = 3072
    static let uploadQuality: CGFloat = 0.85
    static let historyMaxDimension: CGFloat = 1536

    static func isJPEG(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(3))
        return bytes.count == 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
    }

    static func mimeType(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF { return "image/jpeg" }
        if bytes.count >= 4, bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 { return "image/png" }
        if bytes.count >= 12, bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 { return "image/webp" }
        if bytes.count >= 12, bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
            let brand = String(decoding: bytes[8..<12], as: UTF8.self)
            return brand.hasPrefix("hei") || brand.hasPrefix("hev") ? "image/heic" : "image/heif"
        }
        return "image/jpeg"
    }

    static func imageInfo(_ data: Data) -> (width: Int, height: Int, orientation: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        guard width > 0, height > 0 else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? (props[kCGImagePropertyOrientation] as? Int) ?? 1
        return (width, height, orientation)
    }

    static func uploadJPEG(from original: Data) -> Data? {
        if let info = imageInfo(original) {
            if isJPEG(original), info.orientation == 1, max(info.width, info.height) <= uploadMaxDimension {
                return original
            }
            let target = min(max(info.width, info.height), uploadMaxDimension)
            if let rendered = renderJPEG(from: original, maxPixelSize: target, quality: uploadQuality) {
                return rendered
            }
        }
        if let uiImg = UIImage(data: original), let jpeg = uiImg.jpegData(compressionQuality: uploadQuality) {
            return jpeg
        }
        return original
    }

    static func historyCopy(of data: Data) -> Data {
        guard let info = imageInfo(data), max(info.width, info.height) > Int(historyMaxDimension) else { return data }
        return renderJPEG(from: data, maxPixelSize: Int(historyMaxDimension), quality: 0.8) ?? data
    }

    static func renderJPEG(from data: Data, maxPixelSize: Int, quality: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func fingerprint(_ data: Data) -> Int {
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(data.prefix(256))
        hasher.combine(data.suffix(256))
        return hasher.finalize()
    }
}

// MARK: - Live turn grouping (pure, unit-testable — PLAN.md T6.2)

struct LiveTurn: Identifiable, Equatable {
    let id: UUID
    let userText: String
    let photoData: Data?
    let assistantText: String?
    let readingRecord: ReadingRecord?
    let timestamp: Date
    let isActiveTurn: Bool
}

enum LiveTurnGrouper {
    /// Stable fallback ID while a brand-new turn has no ReadingPlan yet (avoids random `UUID()` per render).
    private static let pendingTurnFallbackID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Groups persisted messages from `currentConversation` plus any in-flight turn into paired cards.
    static func turns(
        from messages: [Message],
        pendingUserText: String,
        pendingPhotoData: Data?,
        activePlan: ReadingPlan?,
        isThinking: Bool
    ) -> [LiveTurn] {
        var result: [LiveTurn] = []
        var i = 0
        while i < messages.count {
            let msg = messages[i]
            if msg.role == .user {
                var assistantMsg: Message? = nil
                if i + 1 < messages.count && messages[i + 1].role == .assistant {
                    assistantMsg = messages[i + 1]
                    i += 2
                } else {
                    i += 1
                }
                result.append(LiveTurn(
                    id: msg.id,
                    userText: msg.content,
                    photoData: msg.photoData,
                    assistantText: assistantMsg?.content,
                    readingRecord: assistantMsg?.reading,
                    timestamp: msg.timestamp,
                    isActiveTurn: false
                ))
            } else if msg.role == .assistant {
                result.append(LiveTurn(
                    id: msg.id,
                    userText: "",
                    photoData: nil,
                    assistantText: msg.content,
                    readingRecord: msg.reading,
                    timestamp: msg.timestamp,
                    isActiveTurn: false
                ))
                i += 1
            } else {
                i += 1
            }
        }

        // Attach the live streaming plan (or thinking indicator) to the last open turn if it matches.
        if let last = result.last, last.assistantText == nil, (activePlan != nil || isThinking) {
            result[result.count - 1] = LiveTurn(
                id: last.id,
                userText: last.userText,
                photoData: last.photoData ?? pendingPhotoData,
                assistantText: activePlan.map { $0.segments.map(\.displayText).joined(separator: "\n") },
                readingRecord: activePlan?.record,
                timestamp: last.timestamp,
                isActiveTurn: true
            )
        } else if !pendingUserText.isEmpty && (result.last?.userText != pendingUserText || isThinking) && (result.isEmpty || result.last?.assistantText != nil) {
            result.append(LiveTurn(
                id: activePlan?.turnID ?? pendingTurnFallbackID,
                userText: pendingUserText,
                photoData: pendingPhotoData,
                assistantText: activePlan.map { $0.segments.map(\.displayText).joined(separator: "\n") },
                readingRecord: activePlan?.record,
                timestamp: Date(),
                isActiveTurn: true
            ))
        }
        return result
    }
}

// MARK: - ViewModel

@MainActor
final class VoiceAgentViewModel: ObservableObject {

    // MARK: - Dependencies

    let settingsManager = SettingsManager.shared
    let glassesManager = GlassesManager.shared
    let voiceCommandService = VoiceCommandService.shared
    let gemini = GeminiLiveService.shared
    let ttsService = TTSService.shared
    let readingEngine = ReadingEngine.shared
    let soundService = SoundService.shared
    let sessionRecorder = SessionRecorder.shared

    // MARK: - Published UI state

    @Published var isSessionActive = false
    @Published var agentState: AgentState = .idle
    @Published var userTranscript = ""
    @Published var aiTranscript = ""
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var isVoiceReady = false
    @Published var isRecording = false
    @Published var recordingStatus: String?
    @Published var activePhotoContext: CapturedPhotoContext?
    @Published var currentTranscriptPhotoData: Data? = nil
    @Published private(set) var isCapturingFromButton = false
    @Published var thinkingStartedAt: Date? = nil
    /// Active v2.1 plan being streamed or read (drives Live screen `SegmentCardView` + `PlaybackBar`).
    @Published private(set) var activePlan: ReadingPlan?

    // MARK: - Internal state

    private var callbacksConfigured = false
    private var lastProcessedCommand = ""
    private var lastProcessedAt = Date.distantPast
    private var hasRequestedSpeechAuth = false

    /// Non-nil while a voice OR direct-chat turn is in flight (fixes P0 #1: typed chat replies are never dropped!).
    private var activeTurnID: UUID?
    private var activeTurnCommand: String = ""
    private var activeReplyAssembler: ReplyAssembler?
    private var streamingPlan: ReadingPlan?
    private var didStartStreamingReading = false
    private var echoSettleTask: Task<Void, Never>?

    private var historyAwaitingReply = false
    private var lastSpokenAnswer = ""
    private var endSessionAfterSpeaking = false
    private var activePlanPhotoID: UUID?
    private var lastAppliedSettings: AppSettings = SettingsManager.shared.settings

    // MARK: - Agent State

    enum AgentState: Equatable {
        case idle
        case connecting
        case listening
        case thinking
        case speaking

        var displayText: String {
            switch self {
            case .idle: return "Sẵn sàng"
            case .connecting: return "Đang kết nối…"
            case .listening: return "Đang nghe…"
            case .thinking: return "Đang suy nghĩ…"
            case .speaking: return "Đang đọc…"
            }
        }
    }

    // MARK: - View lifecycle

    func onAppear() {
        if !callbacksConfigured {
            callbacksConfigured = true
            setupVoiceCommandService()
            setupGlassesCallbacks()
            setupReadingEngineCallbacks()
        }
        applyButtonLinkSetting()
        Task { @MainActor in
            let granted = await RecentPhotoScanner.shared.requestAuthorizationIfNeeded()
            if !granted {
                errorMessage = "OpenVision cần quyền Ảnh (Toàn bộ ảnh) để đọc ảnh từ album kính Ray-Ban."
            } else if RecentPhotoScanner.shared.isLimitedAccess {
                errorMessage = "Quyền Ảnh đang ở chế độ Giới hạn. Chọn Toàn bộ ảnh trong Cài đặt iOS."
            }
        }
        if voiceCommandService.authorizationStatus == .authorized && !voiceCommandService.isListening {
            startWakeWordListening()
        }
    }

    func onDisappear() {
        // Keep audio/reading alive if user briefly opens History or Settings while reading.
        if !isSessionActive && !readingEngine.isActive {
            voiceCommandService.stopListening()
        }
    }

    // MARK: - Observed state changes

    func ttsSpeakingChanged(_ isSpeaking: Bool) {
        if isSpeaking {
            echoSettleTask?.cancel()
            agentState = .speaking
            voiceCommandService.isBargeInPaused = true
        } else {
            // N8: DO NOT re-open barge-in here immediately! `scheduleEchoSettleAndResume()` waits >= 350ms.
            MetricsCollector.shared.markSpokeDone()
            if !readingEngine.isActive {
                scheduleEchoSettleAndResume()
            }
        }
    }

    func agentStateChanged(_ newState: AgentState) {
        if newState == .thinking {
            if thinkingStartedAt == nil { thinkingStartedAt = Date() }
            soundService.startThinkingSound()
        } else {
            thinkingStartedAt = nil
            soundService.stopThinkingSound()
        }
    }

    func voiceStateChanged(_ newState: VoiceCommandService.ListeningState) {
        AppLog.debug(.voice, "VoiceCommandService state changed to: \(newState)")
        switch newState {
        case .idle:
            if isSessionActive && agentState == .listening && !readingEngine.isActive {
                AppLog.info(.voice, "Voice service idle, stopping session")
                isSessionActive = false
                agentState = .idle
                Task { await gemini.disconnect() }
            }
        case .listening, .conversationMode:
            if ttsService.isSpeaking || readingEngine.state == .reading {
                agentState = .speaking
            } else if isSessionActive {
                agentState = .listening
            }
        case .processing:
            if !ttsService.isSpeaking && !readingEngine.isActive {
                agentState = .thinking
            }
        }
    }

    private func scheduleEchoSettleAndResume() {
        echoSettleTask?.cancel()
        echoSettleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: SolverIntent.ttsEchoSettleNanoseconds)
            guard !Task.isCancelled, let self else { return }
            guard !self.ttsService.isSpeaking && self.ttsService.pendingUtterances == 0 && self.readingEngine.state != .reading else {
                return
            }
            self.voiceCommandService.isBargeInPaused = false

            // If user already interrupted TTS with "Ok Vision + new question", keep `.listening`
            // intact instead of calling `enterConversationMode()` (which would wipe `currentTranscription`).
            if self.voiceCommandService.state == .listening {
                self.agentState = .listening
                return
            }

            if self.isSessionActive && self.endSessionAfterSpeaking {
                self.endSessionAfterSpeaking = false
                AppLog.info(.app, "Goodbye spoken — ending session")
                self.stopSession()
            } else if self.gemini.isProcessing {
                // E.g. user pressed double-tap notice while Gemini was still thinking: restore thinking UI cleanly.
                self.agentState = .thinking
            } else if self.readingEngine.state == .paused || self.readingEngine.state == .waitingForNext {
                // Keep recognizer in `.processing` mode so bare commands ("tiếp", "tiếp tục") work without wake word.
                self.agentState = .idle
            } else if self.isSessionActive {
                self.agentState = .listening
                self.resumeListeningAfterSpeaking()
            } else {
                self.agentState = .idle
                if !self.voiceCommandService.isListening || self.shouldDeferWakeWordForMusic {
                    if self.voiceCommandService.isListening && self.shouldDeferWakeWordForMusic {
                        self.voiceCommandService.stopListening()
                    }
                    await AudioSessionManager.shared.deactivateSessionAsync()
                }
            }
        }
    }

    /// True when music/media is playing in another app and the user opted to avoid holding
    /// the glasses' Bluetooth HFP mic channel open while idle.
    private var shouldDeferWakeWordForMusic: Bool {
        settingsManager.settings.pauseWakeWordDuringMusic
            && AudioSessionManager.shared.isOtherAudioPlaying
            && !isSessionActive
            && !readingEngine.isActive
            && !ttsService.isSpeaking
            && !isRecording
    }

    /// Called by `VoiceAgentView` when the app moves to background/foreground so idle wake-word
    /// listening never holds Bluetooth HFP open while the user pauses/plays music with phone in pocket.
    func handleScenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            let isIdle = !isSessionActive && !readingEngine.isActive && !ttsService.isSpeaking && !isRecording
            if isIdle && (!settingsManager.settings.wakeWordEnabled || settingsManager.settings.pauseWakeWordDuringMusic) {
                if voiceCommandService.isListening {
                    voiceCommandService.stopListening()
                }
                Task { await AudioSessionManager.shared.deactivateSessionAsync() }
            }
        case .active:
            if settingsManager.settings.wakeWordEnabled
                && voiceCommandService.authorizationStatus == .authorized
                && !voiceCommandService.isListening
                && !isSessionActive
                && !shouldDeferWakeWordForMusic {
                startWakeWordListening()
            }
        default:
            break
        }
    }

    // MARK: - Session lifecycle

    func toggleSession() {
        if isSessionActive {
            stopSession()
        } else {
            startSession()
        }
    }

    func startSession() {
        Task { @MainActor in
            await startSessionAsync()
        }
    }

    private func startSessionAsync() async {
        isSessionActive = true
        agentState = .connecting

        // Off-main audio routing (avoids Hang Risk); camera is NEVER started here (T7.9).
        await configureAudioForGlassesAsync()

        do {
            try await gemini.connect()

            agentState = .listening
            userTranscript = ""

            if voiceCommandService.authorizationStatus == .authorized {
                if !voiceCommandService.isListening {
                    try? voiceCommandService.startListening()
                }
                voiceCommandService.enterConversationMode()
            } else {
                errorMessage = "Chưa được cấp quyền nhận dạng giọng nói."
            }
        } catch {
            if case AIBackendError.notConfigured = error {
                agentState = .listening
                if voiceCommandService.authorizationStatus == .authorized {
                    if !voiceCommandService.isListening { try? voiceCommandService.startListening() }
                    voiceCommandService.enterConversationMode()
                }
                errorMessage = "Chưa có API key Gemini — vào Cài đặt → Gemini để dán key."
                return
            }
            errorMessage = "Không kết nối được: \(error.localizedDescription)"
            isSessionActive = false
            agentState = .idle
        }
    }

    private func resumeListeningAfterSpeaking() {
        voiceCommandService.enterConversationMode()
    }

    /// Configures preferred audio route off-main (glasses HFP if preferred & connected, else phone speaker).
    private func configureAudioForGlassesAsync(forceRestart: Bool = false) async {
        let wantsGlasses = settingsManager.settings.preferGlassesMic
        let isHFPActive = AudioSessionManager.shared.isBluetoothHFPInputActive
        let routeAcceptable = (wantsGlasses && isHFPActive) || (!wantsGlasses && !isHFPActive)

        if !forceRestart && voiceCommandService.isListening && routeAcceptable {
            return
        }
        let wasListening = voiceCommandService.isListening
        if wasListening { voiceCommandService.stopListening() }
        _ = await AudioSessionManager.shared.configurePreferredRouteAsync(preferGlasses: wantsGlasses)
        if wasListening {
            try? voiceCommandService.startListening()
        }
    }

    private func configureAudioForGlasses(forceRestart: Bool = false) {
        Task { @MainActor in
            await configureAudioForGlassesAsync(forceRestart: forceRestart)
        }
    }

    func stopSession() {
        Task {
            await gemini.disconnect()
            if glassesManager.isStreaming && !isRecording {
                AppLog.info(.glasses, "Stopping glasses stream on session end")
                await glassesManager.stopStreaming()
            }
        }

        readingEngine.stop()
        ttsService.stop()
        activeTurnID = nil
        historyAwaitingReply = false
        streamingPlan = nil
        activeReplyAssembler = nil
        didStartStreamingReading = false
        isSessionActive = false
        agentState = .idle

        if settingsManager.settings.wakeWordEnabled && !shouldDeferWakeWordForMusic {
            voiceCommandService.exitConversationMode()
        } else {
            voiceCommandService.stopListening()
            Task { await AudioSessionManager.shared.deactivateSessionAsync() }
        }
    }

    private func performFullStop() {
        MetricsCollector.shared.markInterrupted()
        MetricsCollector.shared.markSpokeDone()
        readingEngine.stop()
        ttsService.stop()
        activeTurnID = nil
        historyAwaitingReply = false
        streamingPlan = nil
        activeReplyAssembler = nil
        didStartStreamingReading = false
        Task { await gemini.interrupt() }

        isSessionActive = false
        agentState = .idle
        if !settingsManager.settings.wakeWordEnabled || shouldDeferWakeWordForMusic {
            voiceCommandService.stopListening()
            Task { await AudioSessionManager.shared.deactivateSessionAsync() }
        }
    }

    func startNewConversation() {
        readingEngine.stop()
        ttsService.stop()
        activePlan = nil
        activePlanPhotoID = nil
        streamingPlan = nil
        userTranscript = ""
        aiTranscript = ""
        activePhotoContext = nil
        currentTranscriptPhotoData = nil
        ConversationManager.shared.startNewConversation()
        gemini.clearConversationHistory()
    }

    // MARK: - ReadingEngine callbacks

    private func setupReadingEngineCallbacks() {
        readingEngine.onWillStartSpeaking = { [weak self] in
            guard let self else { return }
            // Lesson 4: .speaking + isBargeInPaused BEFORE audio starts.
            self.agentState = .speaking
            self.voiceCommandService.isBargeInPaused = true
        }
        readingEngine.onSegmentStarted = { [weak self] _ in
            // N6: clear recognizer echo buffer on each new segment so wake-word commands work.
            self?.voiceCommandService.resetBufferForNewSegment()
        }
        readingEngine.onWaitingForNext = { [weak self] in
            guard let self else { return }
            self.agentState = .idle
            self.voiceCommandService.isBargeInPaused = false
            self.voiceCommandService.resetBufferForNewSegment()
        }
        readingEngine.onReadingFinished = { [weak self] in
            guard let self else { return }
            MetricsCollector.shared.markSpokeDone()
            self.scheduleEchoSettleAndResume()
        }
    }

    private func handleReadingCommand(_ command: ReadingCommand) {
        HapticFeedback.light()
        if command == .stop {
            readingEngine.stop()
            Task { await gemini.interrupt() }
            scheduleEchoSettleAndResume()
            return
        }
        readingEngine.apply(command)
        if readingEngine.state == .paused || readingEngine.state == .waitingForNext {
            // App is now silent: allow bare voice commands ("tiếp", "tiếp tục") without wake word.
            voiceCommandService.isBargeInPaused = false
            agentState = .idle
        }
    }

    // MARK: - Voice Command Setup

    func requestSpeechAuthorization() async {
        guard !hasRequestedSpeechAuth else { return }
        hasRequestedSpeechAuth = true

        let authorized = await voiceCommandService.requestAuthorization()
        if authorized {
            AppLog.info(.voice, "Speech recognition authorized")
            startWakeWordListening()
        } else {
            AppLog.warning(.voice, "Speech recognition not authorized")
            errorMessage = "Chưa được cấp quyền nhận dạng giọng nói. Hãy bật trong Cài đặt."
        }
    }

    private func setupVoiceCommandService() {
        AppLog.info(.voice, "Setting up voice command callbacks")

        voiceCommandService.shouldAllowInterrupt = { [weak self] in
            guard let self else { return false }
            return self.ttsService.isSpeaking || self.readingEngine.state == .reading || self.agentState == .thinking
        }

        voiceCommandService.isPausedOrWaitingForNext = { [weak self] in
            guard let self else { return false }
            return self.readingEngine.state == .paused || self.readingEngine.state == .waitingForNext
        }

        voiceCommandService.shouldSuppressConversationTimeout = { [weak self] in
            guard let self else { return false }
            return self.readingEngine.isActive
        }

        voiceCommandService.onReadingCommand = { [weak self] command in
            self?.handleReadingCommand(command)
        }

        voiceCommandService.onWakeWordDetected = { [weak self] in
            guard let self else { return }
            AppLog.info(.voice, "Wake word detected")
            self.endSessionAfterSpeaking = false
            HapticFeedback.medium()
            self.soundService.playWakeWordSound()

            // N9: stop BOTH active reading AND in-flight Gemini generation when interrupted.
            if self.ttsService.isSpeaking || self.readingEngine.isActive || self.agentState == .thinking {
                AppLog.info(.voice, "Stopping reading & Gemini due to wake word interrupt")
                MetricsCollector.shared.markInterrupted()
                MetricsCollector.shared.markSpokeDone()
                self.echoSettleTask?.cancel()
                self.readingEngine.stop()
                self.ttsService.stop()
                self.echoSettleTask?.cancel()
                self.voiceCommandService.isBargeInPaused = false
                Task { await self.gemini.interrupt() }
                self.agentState = .listening
            }

            Task { @MainActor in
                if !self.isSessionActive {
                    AppLog.info(.voice, "Starting session from wake word")
                    await self.startSessionAsync()
                }
            }
        }

        voiceCommandService.onStopCommand = { [weak self] in
            AppLog.info(.voice, "Full stop requested")
            self?.performFullStop()
        }

        voiceCommandService.onCommandCaptured = { [weak self] (command: String) in
            guard let self else { return }
            AppLog.info(.voice, "Command captured (\(command.count) chars)")
            AppLog.debug(.voice, "Command text: \(command)", sensitive: true)

            guard self.isSessionActive else {
                AppLog.debug(.voice, "Ignoring command - session not active")
                return
            }

            // If user spoke a bare reading command in conversation mode while reading is active OR
            // while still on the same photo context as the current plan (so a brand-new photo + "câu 1"
            // goes to Gemini instead of replaying the previous worksheet!).
            let canControlReading = self.readingEngine.isActive
                || (self.readingEngine.plan != nil && self.activePhotoContext?.id == self.activePlanPhotoID)
            if canControlReading, let cmd = ReadingCommand.parse(command) {
                self.handleReadingCommand(cmd)
                return
            }

            self.userTranscript = command
            self.endSessionAfterSpeaking = false
            self.activeTurnID = UUID()
            self.activeTurnCommand = command

            MetricsCollector.shared.markCommit(backend: "gemini", model: GeminiLiveService.modelName, ttsEngine: "apple")
            self.historyAwaitingReply = true

            Task {
                await self.sendCommand(command)
            }
        }

        voiceCommandService.onInterruption = { [weak self] in
            guard let self else { return }
            AppLog.info(.voice, "Barge-in detected")
            self.endSessionAfterSpeaking = false
            MetricsCollector.shared.markInterrupted()
            self.readingEngine.stop()
            self.ttsService.stop()
            Task { await self.gemini.interrupt() }
        }

        voiceCommandService.onConversationTimeout = { [weak self] in
            guard let self else { return }
            guard !self.readingEngine.isActive else { return }
            AppLog.info(.voice, "Conversation timeout - returning to idle")
            self.stopSession()
        }

        AudioSessionManager.shared.onRouteChange = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Only re-apply HFP mic routing when a voice session or wake-word mic is actually active;
                // never seize Bluetooth HFP back while idle (preserves A2DP stereo music).
                guard self.isSessionActive || self.voiceCommandService.isListening else { return }
                AppLog.info(.audio, "Audio route changed - reapplying preferred route without restart")
                await self.configureAudioForGlassesAsync(forceRestart: false)
            }
        }

        settingsManager.onSettingsChanged = { [weak self] newSettings in
            self?.handleSettingsChanged(newSettings)
        }

        setupAIServiceCallbacks()
    }

    private func handleSettingsChanged(_ newSettings: AppSettings) {
        let old = lastAppliedSettings
        lastAppliedSettings = newSettings
        readingEngine.refreshConfigFromSettings()

        if newSettings.preferGlassesMic != old.preferGlassesMic {
            if isSessionActive || voiceCommandService.isListening {
                configureAudioForGlasses(forceRestart: true)
            }
        } else if newSettings.wakeWordEnabled != old.wakeWordEnabled
                    || newSettings.wakeWord != old.wakeWord
                    || newSettings.recognitionLanguage != old.recognitionLanguage
                    || newSettings.pauseWakeWordDuringMusic != old.pauseWakeWordDuringMusic {
            if (!newSettings.wakeWordEnabled || shouldDeferWakeWordForMusic) && !isSessionActive {
                if voiceCommandService.isListening {
                    voiceCommandService.stopListening()
                }
                if !readingEngine.isActive && !ttsService.isSpeaking && !isRecording {
                    Task { await AudioSessionManager.shared.deactivateSessionAsync() }
                }
            } else if newSettings.wakeWordEnabled && !voiceCommandService.isListening && !shouldDeferWakeWordForMusic {
                startWakeWordListening()
            } else {
                voiceCommandService.refreshSettings(isSessionActive: isSessionActive)
            }
        }
    }

    private func setupAIServiceCallbacks() {
        ttsService.onSpeechEnded = { [weak self] in
            guard let self else { return }
            if !self.readingEngine.isActive {
                self.scheduleEchoSettleAndResume()
            }
        }

        // Streamed v2.1 structured sections (T4.2 + T4.3 + P0 #1 direct-chat fix).
        gemini.onPartialAnswer = { [weak self] (partial: ParsedAnswer) in
            guard let self else { return }
            guard self.isSessionActive || self.activeTurnID != nil else { return }
            guard !partial.requestsCapture else { return }

            if !self.didStartStreamingReading {
                // Wait until we have at least one complete section to begin speaking.
                guard !partial.sections.isEmpty else { return }
                // Blueprint lesson 4: set .speaking + isBargeInPaused BEFORE queueing speech!
                self.agentState = .speaking
                self.voiceCommandService.isBargeInPaused = true
                self.didStartStreamingReading = true

                let lang = self.detectReplyLanguage(sections: partial.sections, fallbackQuestion: self.activeTurnCommand)
                let assembler = ReplyAssembler(languageCode: lang, readLineNumbers: self.settingsManager.settings.readLineNumbers)
                var plan = assembler.emptyPlan(turnID: self.activeTurnID ?? UUID(), answerType: partial.type)
                let added = assembler.update(&plan, streamed: partial)
                self.activeReplyAssembler = assembler
                self.streamingPlan = plan
                self.activePlan = plan
                self.activePlanPhotoID = self.activePhotoContext?.id
                self.aiTranscript = plan.segments.map(\.displayText).joined(separator: "\n")
                MetricsCollector.shared.markFirstToken()
                self.readingEngine.start(plan: plan)
                if added.isEmpty { return }
                return
            }

            guard let assembler = self.activeReplyAssembler, var plan = self.streamingPlan else { return }
            let added = assembler.update(&plan, streamed: partial)
            self.streamingPlan = plan
            self.activePlan = plan
            self.aiTranscript = plan.segments.map(\.displayText).joined(separator: "\n")
            if !added.isEmpty {
                self.readingEngine.append(added, answerType: plan.answerType)
            }
        }

        // Final v2.1 reply + finishReason (T4.2 + T4.3 + N12 + P0 #1 direct-chat fix).
        gemini.onAnswerComplete = { [weak self] (raw: String, finishReason: String?) in
            guard let self else { return }
            guard self.isSessionActive || self.activeTurnID != nil else { return }

            let parsed = AnswerFormat.parse(raw, finishReason: finishReason)
            if parsed.requestsCapture {
                MetricsCollector.shared.abandonTurn()
                return
            }

            MetricsCollector.shared.markFirstToken()
            MetricsCollector.shared.markGenerationDone()

            let finalPlan: ReadingPlan
            if self.didStartStreamingReading, let assembler = self.activeReplyAssembler, var plan = self.streamingPlan {
                let tail = assembler.finish(&plan, with: parsed)
                self.streamingPlan = plan
                finalPlan = plan
                if !tail.isEmpty {
                    self.readingEngine.append(tail, answerType: plan.answerType)
                }
                self.readingEngine.finishAppending(answerType: plan.answerType)
            } else {
                let lang = self.detectReplyLanguage(sections: parsed.sections, fallbackQuestion: self.activeTurnCommand)
                let assembler = ReplyAssembler(languageCode: lang, readLineNumbers: self.settingsManager.settings.readLineNumbers)
                let plan = assembler.plan(turnID: self.activeTurnID ?? UUID(), parsed: parsed)
                finalPlan = plan
                if !plan.segments.isEmpty {
                    // Lesson 4: .speaking + isBargeInPaused BEFORE queueing speech!
                    self.agentState = .speaking
                    self.voiceCommandService.isBargeInPaused = true
                    self.readingEngine.start(plan: plan)
                } else {
                    MetricsCollector.shared.abandonTurn()
                }
            }

            self.activePlan = finalPlan
            self.activePlanPhotoID = self.activePhotoContext?.id
            let displayJoined = finalPlan.segments.map(\.displayText).joined(separator: "\n")
            let spokenJoined = finalPlan.segments.map(\.speechText).joined(separator: " ")
            self.aiTranscript = displayJoined
            if !spokenJoined.isEmpty && !parsed.endsConversation {
                self.lastSpokenAnswer = spokenJoined
            }
            self.endSessionAfterSpeaking = parsed.endsConversation
            self.recordAssistantReply(displayJoined, reading: finalPlan.record)
            self.activeTurnID = nil
            self.streamingPlan = nil
            self.activeReplyAssembler = nil
            self.didStartStreamingReading = false
        }

        gemini.processingChangedCallback = { [weak self] (isProcessing: Bool) in
            guard let self else { return }
            if isProcessing {
                self.agentState = .thinking
                self.didStartStreamingReading = false
                self.streamingPlan = nil
                self.activeReplyAssembler = nil
            } else {
                if self.didStartStreamingReading {
                    self.readingEngine.finishAppending()
                    self.didStartStreamingReading = false
                }
                if self.agentState == .thinking
                    && !self.ttsService.isSpeaking && self.ttsService.pendingUtterances == 0 && !self.readingEngine.isActive {
                    self.agentState = self.isSessionActive ? .listening : .idle
                }
            }
        }

        gemini.onCaptureRequested = { [weak self] (_: String) async -> Data? in
            guard let self else { return nil }
            return await self.captureForAgent()
        }
    }

    private func detectReplyLanguage(sections: [AnswerSection], fallbackQuestion: String) -> String {
        let joined = sections.map(\.text).joined(separator: " ")
        if !TTSService.isLanguageNeutral(joined) {
            return TTSService.containsVietnamese(joined) ? "vi" : "en"
        }
        if !fallbackQuestion.isEmpty && !TTSService.isLanguageNeutral(fallbackQuestion) {
            return TTSService.containsVietnamese(fallbackQuestion) ? "vi" : "en"
        }
        return SolverIntent.speaksVietnamese ? "vi" : "en"
    }

    private func startWakeWordListening() {
        guard settingsManager.settings.wakeWordEnabled else { return }
        guard voiceCommandService.authorizationStatus == .authorized else { return }
        if shouldDeferWakeWordForMusic {
            AppLog.info(.audio, "Music is playing — deferring idle wake-word mic so Ray-Ban stays in A2DP (use glasses button or tap Mic)")
            return
        }

        Task { @MainActor in
            await configureAudioForGlassesAsync(forceRestart: false)
            do {
                try voiceCommandService.startListening()
                isVoiceReady = true
                AppLog.info(.voice, "Started wake word listening - READY")
            } catch {
                AppLog.error(.voice, "Failed to start listening: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Command routing (P0 #1, #2, #3 & N10 fixed!)

    /// Submit a typed prompt from the keyboard composer bar (works with or without an active voice session,
    /// routes audio automatically to connected glasses OR phone loud speaker, and saves to History!).
    func sendTypedCommand(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        readingEngine.stop()
        ttsService.stop()
        if voiceCommandService.isListening && (voiceCommandService.state == .conversationMode || voiceCommandService.state == .listening) {
            voiceCommandService.enterProcessingState()
        }
        errorMessage = nil
        userTranscript = trimmed
        aiTranscript = ""
        endSessionAfterSpeaking = false
        activeTurnID = UUID()
        activeTurnCommand = trimmed
        historyAwaitingReply = true

        MetricsCollector.shared.markCommit(backend: "gemini", model: GeminiLiveService.modelName, ttsEngine: "apple")

        Task { @MainActor in
            // P0 #2 fix: configure audio session BEFORE speaking (glasses Bluetooth or iPhone loud speaker).
            await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                preferGlasses: settingsManager.settings.preferGlassesMic
            )
            await sendCommand(trimmed, allowRepeat: true)
        }
    }

    /// Replays a stored History answer offline using current math & speed settings (T5.5).
    func replayFromHistory(_ record: ReadingRecord) {
        let plan = ReadingPlan(record: record)
        activePlan = plan
        aiTranscript = plan.segments.map(\.displayText).joined(separator: "\n")
        if voiceCommandService.isListening && (voiceCommandService.state == .conversationMode || voiceCommandService.state == .listening) {
            voiceCommandService.enterProcessingState()
        }
        Task { @MainActor in
            await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                preferGlasses: settingsManager.settings.preferGlassesMic
            )
            self.readingEngine.replay(record: record)
        }
    }

    func detachPhoto() {
        activePhotoContext = nil
        currentTranscriptPhotoData = nil
        HapticFeedback.light()
        AppLog.info(.photo, "Photo detached by user")
    }

    private func sendCommand(_ command: String, allowRepeat: Bool = false) async {
        if SolverIntent.isStopCommand(command) {
            AppLog.info(.voice, "Stop command detected - full stop")
            performFullStop()
            return
        }

        let now = Date()
        if !allowRepeat, command == lastProcessedCommand, now.timeIntervalSince(lastProcessedAt) < 4 {
            AppLog.debug(.voice, "Ignoring duplicate command within 4s", sensitive: true)
            activeTurnID = nil
            historyAwaitingReply = false
            MetricsCollector.shared.abandonTurn()
            return
        }
        lastProcessedCommand = command
        lastProcessedAt = now
        agentState = .thinking

        // Keep Gemini context aligned with History's 5-minute conversation inactivity boundary.
        if !ConversationManager.shared.isCurrentConversationFresh {
            gemini.clearConversationHistory()
        }

        var photo: Data?
        if let context = activePhotoContext, context.isFresh {
            activePhotoContext?.useCount += 1
            photo = context.data
            AppLog.info(.photo, "Fusing photo context (\(context.data.count) bytes, use #\(context.useCount + 1))")
        }

        currentTranscriptPhotoData = photo
        ConversationManager.shared.addUserMessage(command, photoData: photo)

        do {
            try await gemini.sendRESTMessage(command, imageData: photo)
        } catch {
            handleSendFailure(error, command: command)
        }
    }

    private func handleSendFailure(_ error: Error, command: String) {
        if error is CancellationError {
            MetricsCollector.shared.abandonTurn()
            return
        }
        AppLog.error(.gemini, "Send failed: \(error.localizedDescription)")
        MetricsCollector.shared.abandonTurn()
        historyAwaitingReply = false

        let spokenError: String
        if case AIBackendError.notConfigured = error {
            spokenError = SolverIntent.missingKeyMessage(for: command)
        } else {
            spokenError = SolverIntent.networkFailureMessage(for: command)
        }
        errorMessage = spokenError
        aiTranscript = spokenError

        let shouldSpeak = (isSessionActive || activeTurnID != nil) && !ttsService.isSpeaking
        activeTurnID = nil
        if shouldSpeak {
            Task { @MainActor in
                await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                    preferGlasses: settingsManager.settings.preferGlassesMic
                )
                self.speakResponse(spokenError)
            }
        } else {
            agentState = isSessionActive ? .listening : .idle
        }
    }

    // MARK: - POV Recording

    func toggleRecording() {
        if isRecording {
            sessionRecorder.stop()
        } else {
            Task { await startRecording() }
        }
    }

    private func startRecording() async {
        guard glassesManager.isRegistered else {
            errorMessage = "Hãy kết nối kính trước khi ghi hình."
            return
        }
        if !glassesManager.isStreaming {
            await glassesManager.startStreaming(reason: "pov_recording")
        }
        guard glassesManager.isStreaming else {
            errorMessage = "Không bật được camera kính để ghi hình."
            return
        }

        glassesManager.onVideoSampleBuffer = { [weak self] sampleBuffer in
            self?.sessionRecorder.appendVideoSampleBuffer(sampleBuffer)
        }

        sessionRecorder.onFinished = { [weak self] url in
            guard let self else { return }
            self.isRecording = false
            self.glassesManager.onVideoSampleBuffer = nil
            self.showRecordingStatus(url != nil ? "Đã lưu vào Ảnh" : "Không lưu được bản ghi")
            if self.glassesManager.isStreaming {
                Task { await self.glassesManager.stopStreaming() }
            }
        }

        if !voiceCommandService.isListening {
            try? voiceCommandService.startListening()
        }
        do {
            try sessionRecorder.start()
            isRecording = true
        } catch {
            glassesManager.onVideoSampleBuffer = nil
            errorMessage = "Không bắt đầu ghi được: \(error.localizedDescription)"
        }
    }

    private func showRecordingStatus(_ text: String) {
        recordingStatus = text
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self?.recordingStatus == text { self?.recordingStatus = nil }
        }
    }

    // MARK: - Photo capture (simplified T7.5 + T7.7 audio restoration)

    private func acquireGlassesPhoto() async -> Data? {
        defer {
            // T7.7: log audio route + isOtherAudioPlaying and gently restore audio route only when mic is active.
            AppLog.info(.audio, "Post-capture route: \(AudioSessionManager.shared.currentRouteDescription), otherAudio=\(AudioSessionManager.shared.isOtherAudioPlaying)")
            if isSessionActive || voiceCommandService.isListening {
                configureAudioForGlasses(forceRestart: false)
            }
        }

        if isRecording {
            return await glassesManager.capturePhotoFromActiveStream(timeout: 10.0)
        }
        if glassesManager.isRegistered,
           let direct = await glassesManager.captureFullResolutionPhoto(
               fullResolution: settingsManager.settings.fullResolutionPhotos) {
            return direct
        }
        return await RecentPhotoScanner.shared.fetchMostRecentPhoto()
    }

    private func captureForAgent() async -> Data? {
        HapticFeedback.light()
        let data = await acquireGlassesPhoto()
        if let data {
            let source = glassesManager.lastPhotoSource ?? "camera-roll"
            activePhotoContext = CapturedPhotoContext(data: data, source: source)
            currentTranscriptPhotoData = data
            ConversationManager.shared.attachPhotoToLatestUserMessage(data)
            HapticFeedback.success()
            AppLog.info(.photo, "Agent capture: got photo (\(data.count) bytes, source=\(source))")
        } else {
            HapticFeedback.error()
            AppLog.warning(.photo, "Agent capture: no photo available")
        }
        return data
    }

    func snapPhotoFromGlasses() async {
        HapticFeedback.light()
        AppLog.info(.photo, "Manual photo snap requested from glasses")
        statusMessage = "Đang chụp ảnh từ kính…"
        let data = await acquireGlassesPhoto()
        statusMessage = nil

        if let data {
            let source = glassesManager.lastPhotoSource ?? "camera-roll"
            activePhotoContext = CapturedPhotoContext(data: data, source: source)
            currentTranscriptPhotoData = data
            HapticFeedback.success()
            AppLog.info(.photo, "Manual photo context cached (\(data.count) bytes, source=\(source))")
        } else {
            HapticFeedback.error()
            let message = SolverIntent.missingPhotoMessage(for: lastProcessedCommand.isEmpty ? "chụp ảnh" : lastProcessedCommand)
            errorMessage = message
            await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                preferGlasses: settingsManager.settings.preferGlassesMic
            )
            speakNotice(message)
        }
    }

    // MARK: - Glasses callbacks

    private func setupGlassesCallbacks() {
        glassesManager.onPhotoCaptured = { [weak self] data in
            Task { @MainActor in
                let source = self?.glassesManager.lastPhotoSource ?? "stream-still"
                self?.activePhotoContext = CapturedPhotoContext(data: data, source: source)
                self?.currentTranscriptPhotoData = data
                AppLog.info(.photo, "Active photo context cached (\(data.count) bytes)")
            }
        }
        RecentPhotoScanner.shared.onPhotoArrived = { [weak self] data in
            Task { @MainActor in
                self?.activePhotoContext = CapturedPhotoContext(data: data, source: "camera-roll")
                self?.currentTranscriptPhotoData = data
                AppLog.info(.photo, "RecentPhotoScanner synced Meta album photo (\(data.count) bytes)")
            }
        }
        glassesManager.onCaptureButton = { [weak self] press in
            self?.handleCaptureButton(press)
        }
    }

    func applyButtonLinkSetting() {
        let settings = settingsManager.settings
        Task { await glassesManager.applySettings(settings) }
    }

    // MARK: - Capture & Action button

    private func handleCaptureButton(_ press: GlassesButtonPress) {
        let settings = settingsManager.settings
        let action = GlassesWorkflowPolicy.action(for: press, settings: settings)
        AppLog.info(.glasses, "Button \(press.rawValue) [mode=\(settings.usageMode.rawValue)] -> \(action.rawValue)")
        switch action {
        case .captureAndSolve:
            Task { await performButtonCapture(action: .captureAndSolve) }
        case .captureAndListen:
            Task { await performButtonCapture(action: .captureAndListen) }
        case .capture:
            Task { await performButtonCapture(action: .capture) }
        case .repeatAnswer:
            repeatLastAnswer()
        case .none:
            break
        }
    }

    private func performButtonCapture(action: GlassesButtonAction) async {
        guard !isCapturingFromButton else { return }
        if action == .captureAndSolve && !settingsManager.settings.isGeminiConfigured {
            HapticFeedback.error()
            let msg = SolverIntent.missingKeyMessage(for: SolverIntent.solvePhotoQuestion)
            errorMessage = msg
            await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                preferGlasses: settingsManager.settings.preferGlassesMic
            )
            speakNotice(msg)
            return
        }
        isCapturingFromButton = true
        defer { isCapturingFromButton = false }
        HapticFeedback.light()

        if action == .captureAndSolve || action == .captureAndListen {
            if ttsService.isSpeaking || readingEngine.isActive {
                readingEngine.stop()
                ttsService.stop()
            }
            if action == .captureAndSolve, voiceCommandService.isListening {
                voiceCommandService.enterProcessingState()
            }
            await gemini.interrupt()
        }

        statusMessage = "Đang chụp ảnh từ kính…"
        let data = await acquireGlassesPhoto()
        statusMessage = nil

        guard let data else {
            HapticFeedback.error()
            errorMessage = SolverIntent.photoFailedMessage
            await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                preferGlasses: settingsManager.settings.preferGlassesMic
            )
            speakNotice(SolverIntent.photoFailedMessage)
            return
        }

        let source = glassesManager.lastPhotoSource ?? "glasses"
        activePhotoContext = CapturedPhotoContext(data: data, source: source)
        currentTranscriptPhotoData = data
        HapticFeedback.success()
        AppLog.info(.photo, "Button photo ready (\(data.count) bytes, source=\(source), action=\(action.rawValue))")

        switch action {
        case .captureAndSolve:
            // Study mode: immediately send the short solve prompt with the captured photo,
            // using clean A2DP playback-only if no voice session is active (never interrupts music with HFP).
            let question = SolverIntent.solvePhotoQuestion
            errorMessage = nil
            userTranscript = question
            aiTranscript = ""
            endSessionAfterSpeaking = false
            activeTurnID = UUID()
            activeTurnCommand = question
            historyAwaitingReply = true
            MetricsCollector.shared.markCommit(backend: "gemini", model: GeminiLiveService.modelName, ttsEngine: "apple")

            await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                preferGlasses: settingsManager.settings.preferGlassesMic
            )
            await sendCommand(question, allowRepeat: true)

        case .captureAndListen:
            // General mode: photo is cached; route audio and play the chime BEFORE entering `.conversationMode`
            // so the chime never leaks into Silero VAD or SFSpeechRecognizer.
            errorMessage = nil
            await configureAudioForGlassesAsync()
            if settingsManager.settings.playActivationSound {
                soundService.playWakeWordSound()
                try? await Task.sleep(nanoseconds: 280_000_000)
            }
            await startSessionAsync()

        case .capture:
            AppLog.info(.photo, "Photo cached in RAM silently for upcoming agent call")

        case .repeatAnswer, .none:
            break
        }
    }

    private func repeatLastAnswer() {
        // If AI is still working on a response, never cancel it — inform the wearer cleanly instead.
        if gemini.isProcessing || activeTurnID != nil {
            Task { @MainActor in
                await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                    preferGlasses: settingsManager.settings.preferGlassesMic
                )
                self.speakNotice(SolverIntent.stillWaitingForResponseMessage)
            }
            return
        }
        if voiceCommandService.isListening && (voiceCommandService.state == .conversationMode || voiceCommandService.state == .listening) {
            voiceCommandService.enterProcessingState()
        }
        if readingEngine.plan != nil {
            Task { @MainActor in
                await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                    preferGlasses: settingsManager.settings.preferGlassesMic
                )
                self.readingEngine.restartFromBeginning()
            }
            return
        }
        if ttsService.isSpeaking { ttsService.stop() }
        Task { @MainActor in
            await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                preferGlasses: settingsManager.settings.preferGlassesMic
            )
            self.speakNotice(self.lastSpokenAnswer.isEmpty ? SolverIntent.nothingToRepeatMessage : self.lastSpokenAnswer)
        }
    }

    private func speakNotice(_ text: String) {
        let awaiting = historyAwaitingReply
        historyAwaitingReply = false
        speakResponse(text)
        historyAwaitingReply = awaiting
    }

    // MARK: - Speech output

    /// Speaks a notice or short response (Blueprint lesson 4: `.speaking` + `isBargeInPaused` BEFORE speech).
    private func speakResponse(_ text: String, historyText: String? = nil) {
        guard !text.isEmpty else { return }
        recordAssistantReply(historyText ?? text, reading: nil)
        agentState = .speaking
        voiceCommandService.isBargeInPaused = true
        MetricsCollector.shared.markTTSRequested()
        ttsService.speak(text)
    }

    // MARK: - History

    private func recordAssistantReply(_ text: String, reading: ReadingRecord? = nil) {
        guard historyAwaitingReply else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        ConversationManager.shared.addAssistantMessage(clean, reading: reading)
        historyAwaitingReply = false
    }
}

// MARK: - Text chunking (pure, unit-testable — respects `$...$` math spans, T3.3)

enum TextChunking {
    static func lastSentenceBoundary(in s: String) -> String.Index? {
        let terminators: Set<Character> = [".", "!", "?"]
        var boundary: String.Index? = nil
        var inMath = false
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            let next = s.index(after: i)
            if c == "$" && (i == s.startIndex || s[s.index(before: i)] != "\\") {
                inMath.toggle()
            } else if !inMath {
                if c == "\n" {
                    boundary = next
                } else if terminators.contains(c) {
                    let followedByBreak = next == s.endIndex || s[next] == " " || s[next] == "\n"
                    if followedByBreak { boundary = next }
                }
            }
            i = next
        }
        return boundary
    }

    static func sentences(_ s: String) -> [String] {
        let terminators: Set<Character> = [".", "!", "?"]
        var result: [String] = []
        var current = ""
        var inMath = false
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            current.append(c)
            let next = s.index(after: i)
            if c == "$" && (i == s.startIndex || s[s.index(before: i)] != "\\") {
                inMath.toggle()
            } else if !inMath {
                let isBoundary = c == "\n"
                    || (terminators.contains(c) && (next == s.endIndex || s[next] == " " || s[next] == "\n"))
                if isBoundary {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { result.append(trimmed) }
                    current = ""
                }
            }
            i = next
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }
}
