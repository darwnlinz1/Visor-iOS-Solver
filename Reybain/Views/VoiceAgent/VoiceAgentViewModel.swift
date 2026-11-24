// Reybain - VoiceAgentViewModel.swift
// MVVM orchestrator for the Live screen: voice sessions, direct chat (P0 #1/#2/#3 fixed),
// v2.1 structured streaming (`AnswerFormat` -> `ReplyAssembler` -> `ReadingEngine`),
// voice reading controls (N6-N9), Meta-album-only photo scanner (B6/T7.6), and History persistence.

import Photos
import UIKit
import ImageIO
import SwiftUI
import Speech
import AVFoundation

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
    static func failureMessage(for prompt: String, error: Error, kind: GeminiFailureKind?) -> String {
        if case AIBackendError.notConfigured = error {
            return missingKeyMessage(for: prompt)
        }
        let vi = TTSService.containsVietnamese(prompt) || (TTSService.isLanguageNeutral(prompt) && speaksVietnamese)
        switch kind {
        case .badAPIKey:
            return vi
                ? "API key Google Gemini không hợp lệ hoặc đã bị khóa. Bạn kiểm tra lại key trong phần Cài đặt nhé."
                : "Your Google Gemini API key is invalid or revoked. Please check your key in Settings."
        case .rateLimited:
            return vi
                ? "Tất cả API key Gemini đều đã hết hạn mức lỗi 429. Bạn đợi một lát hoặc thêm key mới nhé."
                : "All Gemini API keys hit the 429 quota limit. Please wait a moment or add another key."
        case .serverOverloaded:
            return vi
                ? "Máy chủ Google Gemini đang quá tải lỗi 503 ở tất cả các key và model. Bạn thử lại sau vài giây nhé."
                : "Google Gemini servers are overloaded with 503 errors across all keys and models. Please try again shortly."
        case .modelUnavailable:
            return vi
                ? "Model Gemini tạm không khả dụng trên API key này. Bạn kiểm tra lại quyền model trong Google AI Studio nhé."
                : "The Gemini model is unavailable on this API key. Please check model access in Google AI Studio."
        case .blockedOrInvalid:
            return vi
                ? "Google Gemini không xử lý được yêu cầu này. Bạn thử chụp lại rõ hơn hoặc hỏi lại nhé."
                : "Google Gemini could not process this request. Please try taking a clearer photo or asking again."
        case .network, .none:
            return networkFailureMessage(for: prompt)
        }
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
    private var consumedAssetIDs: Set<String> = []
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

    func fetchMostRecentPhoto(
        withinSeconds seconds: TimeInterval = SolverIntent.recentPhotoWindow,
        minCreationDate: Date? = nil,
        ignoreConsumed: Bool = false,
        markConsumed: Bool = false
    ) async -> Data? {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            _ = await requestAuthorizationIfNeeded()
            status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            AppLog.warning(.photo, "Photo library not authorized (\(status.rawValue))")
            return nil
        }

        let windowCutoff = Date().addingTimeInterval(-seconds)
        let cutoffDate = minCreationDate.map { max(windowCutoff, $0) } ?? windowCutoff
        guard let newest = await Self.newestImageAsset(since: cutoffDate) else {
            return nil
        }
        if ignoreConsumed && consumedAssetIDs.contains(newest.id) {
            AppLog.info(.photo, "Skipping already-consumed Meta album photo (\(newest.id))")
            return nil
        }

        if let cached = cache, cached.assetID == newest.id {
            if markConsumed { consumedAssetIDs.insert(newest.id) }
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
        if markConsumed {
            consumedAssetIDs.insert(newest.id)
        }
        lastScannedPhotoData = data
        lastScannedTimestamp = Date()
        latestPhotoDate = newest.created
        let thumbnail = await Task.detached(priority: .utility) {
            PhotoPayload.renderJPEG(from: data, maxPixelSize: 180, quality: 0.7)
        }.value
        if cache?.assetID == newest.id {
            latestThumbnail = thumbnail.flatMap { UIImage(data: $0) }
        }
        if !markConsumed && !consumedAssetIDs.contains(newest.id) && newest.created >= Date().addingTimeInterval(-20) {
            onPhotoArrived?(data)
        }
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
    static let uploadQuality: CGFloat = 0.90
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

/// Real-time status card model shown in the Live chat feed so the phone screen mirrors
/// every glasses & AI action (capturing, 12 MP transfer %, upload %, 429/503 retries, reading, double-press repeat).
struct LiveActivity: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case capturing
        case uploading
        case thinking
        case retrying
        case listening
        case reading
        case repeating
        case notice
        case error
    }

    let kind: Kind
    let title: String
    let detail: String?
    let progress: Double?
    let updatedAt: Date

    init(kind: Kind, title: String, detail: String? = nil, progress: Double? = nil, updatedAt: Date = Date()) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.progress = progress
        self.updatedAt = updatedAt
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
    let directAudioRecorder = DirectAudioRecorder()

    // MARK: - Published UI state

    @Published var isSessionActive = false
    @Published var agentState: AgentState = .idle
    @Published var userTranscript = ""
    @Published var aiTranscript = ""
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published private(set) var liveActivity: LiveActivity? = nil
    @Published var isVoiceReady = false
    @Published var isRecording = false
    @Published var recordingStatus: String?
    @Published var activePhotoContext: CapturedPhotoContext?
    @Published var currentTranscriptPhotoData: Data? = nil
    @Published private(set) var isCapturingFromButton = false
    @Published var thinkingStartedAt: Date? = nil
    /// Active v2.1 plan being streamed or read (drives Live screen `SegmentCardView` + `PlaybackBar`).
    @Published private(set) var activePlan: ReadingPlan?

    // MARK: - Direct-Audio Voice Note state (Composer binding contract)

    @Published var isRecordingVoiceNote: Bool = false
    @Published var isSendingVoiceNote: Bool = false
    @Published var voiceNoteDuration: TimeInterval = 0
    @Published var voiceNoteMeterLevels: [CGFloat] = []

    // MARK: - Internal state

    private var callbacksConfigured = false
    private var lastProcessedCommand = ""
    private var lastProcessedAt = Date.distantPast
    private var hasRequestedSpeechAuth = false

    /// Non-nil while a voice OR direct-chat turn is in flight (fixes P0 #1: typed chat replies are never dropped!).
    private var activeTurnID: UUID?
    private var activeTurnCommand: String = ""
    private var activeTurnHasAudio = false
    private var activeReplyAssembler: ReplyAssembler?
    private var streamingPlan: ReadingPlan?
    private var didStartStreamingReading = false
    private var echoSettleTask: Task<Void, Never>?
    private var activityClearTask: Task<Void, Never>?
    private var statusClearTask: Task<Void, Never>?
    private var wakeWordStartTask: Task<Void, Never>?
    private var voiceNoteStartTask: Task<Void, Never>?
    private var voiceNoteMeterTask: Task<Void, Never>?
    private var isDirectAudioSessionCaptureActive = false
    private var forceDirectAudioNextSession = false
    private var isRepeatingViaGlasses = false
    private var isSpeakingStatusCue = false
    private var didAnnouncePhotoTransferHalfway = false
    private var didAnnounceUploadHalfway = false
    private var didAnnounceUploadDoneWaitingAI = false
    private var lastStatusCueSpokenAt: Date = .distantPast
    private var activeBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid

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

    // MARK: - Live activity & background execution helpers

    private func setLiveActivity(_ activity: LiveActivity?, autoClearAfter seconds: TimeInterval? = nil) {
        activityClearTask?.cancel()
        activityClearTask = nil
        liveActivity = activity
        guard let activity, let seconds else { return }
        activityClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.liveActivity == activity else { return }
            self.liveActivity = nil
        }
    }

    private func flashStatusMessage(_ text: String, duration: TimeInterval = 2.5) {
        statusClearTask?.cancel()
        statusMessage = text
        statusClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let self, self.statusMessage == text else { return }
            self.statusMessage = nil
        }
    }

    private func updateReadingLiveActivity() {
        let progressText = readingEngine.progressLabel.map { "Mục \($0)" }
        if isRepeatingViaGlasses {
            let detail = progressText.map { "Bấm 2 lần trên kính · \($0)" } ?? "Bấm 2 lần trên kính"
            setLiveActivity(LiveActivity(kind: .repeating, title: "Đang đọc lại câu trả lời trước", detail: detail))
        } else {
            setLiveActivity(LiveActivity(kind: .reading, title: "AI đang đọc bài giải", detail: progressText))
        }
    }

    private func beginBackgroundWork(name: String) {
        endBackgroundWork()
        let taskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in
                AppLog.warning(.app, "iOS background task '\(name)' reached expiration limit")
                self?.endBackgroundWork()
            }
        }
        activeBackgroundTaskID = taskID
        if taskID != .invalid {
            let remaining = UIApplication.shared.backgroundTimeRemaining
            let remainingText = remaining.isFinite && remaining < 3600 ? "\(Int(remaining))s" : "unlimited"
            AppLog.info(.app, "Started background task '\(name)' (remaining=\(remainingText))")
        }
    }

    private func endBackgroundWork() {
        guard activeBackgroundTaskID != .invalid else { return }
        let id = activeBackgroundTaskID
        activeBackgroundTaskID = .invalid
        UIApplication.shared.endBackgroundTask(id)
    }

    private func resetTurnSpokenMilestones() {
        didAnnouncePhotoTransferHalfway = false
        didAnnounceUploadHalfway = false
        didAnnounceUploadDoneWaitingAI = false
    }

    /// Announces real-time glasses / upload / 503-429 key-rotation status aloud over the glasses speaker.
    /// Never talks over an active ReadingEngine answer and never writes into ConversationManager history.
    private func speakStatusCue(_ text: String, important: Bool = false) {
        guard settingsManager.settings.spokenStatusUpdates else { return }
        guard !readingEngine.isActive, !didStartStreamingReading else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let now = Date()
        if !important && now.timeIntervalSince(lastStatusCueSpokenAt) < 1.4 {
            return
        }
        lastStatusCueSpokenAt = now
        AppLog.info(.tts, "Spoken status cue: \(clean)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard !self.readingEngine.isActive, !self.didStartStreamingReading else { return }
            await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                preferGlasses: self.settingsManager.settings.preferGlassesMic
            )
            guard !self.readingEngine.isActive, !self.didStartStreamingReading else { return }
            self.voiceCommandService.isBargeInPaused = true
            self.isSpeakingStatusCue = true
            self.ttsService.speakStatusCue(clean, interruptCurrent: true)
        }
    }

    /// Speaks a short status cue and waits for it to finish before opening the microphone (General mode).
    private func speakStatusCueAndWait(_ text: String) async {
        guard settingsManager.settings.spokenStatusUpdates else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        AppLog.info(.tts, "Spoken status cue (sync): \(clean)")
        await AudioSessionManager.shared.ensurePlaybackRouteAsync(
            preferGlasses: settingsManager.settings.preferGlassesMic
        )
        voiceCommandService.isBargeInPaused = true
        isSpeakingStatusCue = true
        lastStatusCueSpokenAt = Date()
        ttsService.speakStatusCue(clean, interruptCurrent: true)
        let deadline = Date().addingTimeInterval(3.5)
        while ttsService.isSpeaking && Date() < deadline {
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        isSpeakingStatusCue = false
        try? await Task.sleep(nanoseconds: 250_000_000)
    }

    private func ensureWakeWordListeningIfEnabled() {
        guard !isRecordingVoiceNote && !isSendingVoiceNote else { return }
        voiceCommandService.syncAuthorizationStatus()
        guard settingsManager.settings.wakeWordEnabled else { return }
        guard voiceCommandService.authorizationStatus == .authorized else { return }
        guard !shouldDeferWakeWordForMusic else {
            AppLog.info(.voice, "Wake-word auto-listen deferred while music is playing")
            return
        }
        if !voiceCommandService.isListening {
            startWakeWordListening()
        } else if !voiceCommandService.isRecognitionHealthy {
            AppLog.warning(.voice, "Wake-word recognizer unhealthy — restarting cleanly")
            voiceCommandService.stopListening()
            startWakeWordListening()
        } else if !isSessionActive && !readingEngine.isActive && !gemini.isProcessing && !ttsService.isSpeaking
                    && voiceCommandService.state != .idle {
            AppLog.info(.voice, "Returning wake-word recognizer from \(voiceCommandService.state) back to .idle")
            voiceCommandService.exitConversationMode()
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
                errorMessage = "Reybain cần quyền Ảnh (Toàn bộ ảnh) để đọc ảnh từ album kính Ray-Ban."
            } else if RecentPhotoScanner.shared.isLimitedAccess {
                errorMessage = "Quyền Ảnh đang ở chế độ Giới hạn. Chọn Toàn bộ ảnh trong Cài đặt iOS."
            }
        }
        ensureWakeWordListeningIfEnabled()
    }

    func onDisappear() {
        // Preserve wake-word auto-listening across tab switches (History / Settings) unless disabled or music is playing.
        if !isSessionActive && !readingEngine.isActive && !isRecordingVoiceNote && !isSendingVoiceNote
            && (!settingsManager.settings.wakeWordEnabled || shouldDeferWakeWordForMusic) {
            voiceCommandService.stopListening()
        }
    }

    // MARK: - Observed state changes

    func ttsSpeakingChanged(_ isSpeaking: Bool) {
        if isSpeaking {
            echoSettleTask?.cancel()
            voiceCommandService.isBargeInPaused = true
            if !isSpeakingStatusCue && !isCapturingFromButton && !gemini.isProcessing {
                agentState = .speaking
            }
        } else {
            if isSpeakingStatusCue {
                isSpeakingStatusCue = false
                if isCapturingFromButton || gemini.isProcessing || readingEngine.isActive {
                    return
                }
                scheduleEchoSettleAndResume()
                return
            }
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
                self.isRepeatingViaGlasses = false
                self.agentState = .listening
                self.setLiveActivity(LiveActivity(kind: .listening, title: "Đang nghe lệnh tiếp theo…", detail: "Hãy nói câu hỏi của bạn"))
                self.resumeListeningAfterSpeaking()
            } else {
                self.isRepeatingViaGlasses = false
                self.agentState = .idle
                if let kind = self.liveActivity?.kind,
                   kind == .reading || kind == .repeating || kind == .thinking || kind == .uploading || kind == .listening {
                    self.setLiveActivity(nil)
                }
                self.endBackgroundWork()
                if self.settingsManager.settings.wakeWordEnabled && !self.shouldDeferWakeWordForMusic {
                    // Crucial fix: exit `.processing` state after Study button solve / double-press repeat /
                    // typed prompt so wake-word listening ALWAYS resumes automatically!
                    if self.voiceCommandService.isListening {
                        if self.voiceCommandService.state != .idle {
                            self.voiceCommandService.exitConversationMode()
                        } else if !self.voiceCommandService.isRecognitionHealthy {
                            self.voiceCommandService.stopListening()
                            self.startWakeWordListening()
                        }
                    } else if self.voiceCommandService.authorizationStatus == .authorized {
                        self.startWakeWordListening()
                    }
                } else {
                    if self.voiceCommandService.isListening {
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
            && !isRecordingVoiceNote
            && !isSendingVoiceNote
    }

    /// True when hands-free General voice sessions (or `.captureAndListen` button captures) should
    /// stream raw 16 kHz WAV audio directly to Gemini alongside Apple Speech draft captioning.
    private var shouldUseHandsFreeDirectAudio: Bool {
        settingsManager.settings.directAudioToGemini
            && (settingsManager.settings.usageMode == .general || forceDirectAudioNextSession)
    }

    /// Called by `VoiceAgentView` when the app moves to background/foreground so idle wake-word
    /// listening releases Bluetooth HFP ONLY when music is actually playing (or wake word is off),
    /// and automatically recovers whenever the app returns to foreground.
    func handleScenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            let isIdle = !isSessionActive && !readingEngine.isActive && !ttsService.isSpeaking
                && !isRecording && !isCapturingFromButton && !isRecordingVoiceNote && !isSendingVoiceNote
            if isIdle && (!settingsManager.settings.wakeWordEnabled || shouldDeferWakeWordForMusic) {
                if voiceCommandService.isListening {
                    voiceCommandService.stopListening()
                }
                Task { await AudioSessionManager.shared.deactivateSessionAsync() }
            }
        case .active:
            ensureWakeWordListeningIfEnabled()
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
                beginHandsFreeDirectAudioCaptureIfNeeded()
            } else {
                errorMessage = "Chưa được cấp quyền nhận dạng giọng nói."
            }
        } catch {
            if case AIBackendError.notConfigured = error {
                agentState = .listening
                if voiceCommandService.authorizationStatus == .authorized {
                    if !voiceCommandService.isListening { try? voiceCommandService.startListening() }
                    voiceCommandService.enterConversationMode()
                    beginHandsFreeDirectAudioCaptureIfNeeded()
                }
                errorMessage = "Chưa có API key Gemini — vào Cài đặt → Gemini để dán key."
                return
            }
            errorMessage = "Không kết nối được: \(error.localizedDescription)"
            isSessionActive = false
            forceDirectAudioNextSession = false
            agentState = .idle
        }
    }

    private func resumeListeningAfterSpeaking() {
        voiceCommandService.enterConversationMode()
        beginHandsFreeDirectAudioCaptureIfNeeded()
    }

    private func beginHandsFreeDirectAudioCaptureIfNeeded() {
        guard shouldUseHandsFreeDirectAudio else {
            stopHandsFreeDirectAudioCapture()
            return
        }
        guard isSessionActive, !isRecordingVoiceNote, !isSendingVoiceNote else { return }
        guard voiceCommandService.isListening else { return }
        directAudioRecorder.beginTapCapture()
        isDirectAudioSessionCaptureActive = true
        voiceCommandService.isDirectAudioCapturing = true
        AppLog.info(.audio, "Hands-free direct-audio capture armed (shared tap)")
    }

    private func stopHandsFreeDirectAudioCapture() {
        if isDirectAudioSessionCaptureActive {
            directAudioRecorder.cancel()
            isDirectAudioSessionCaptureActive = false
        }
        voiceCommandService.isDirectAudioCapturing = false
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
            do {
                try voiceCommandService.startListening()
            } catch {
                AppLog.warning(.voice, "startListening after route switch failed (\(error.localizedDescription)) — scheduling auto-listen retry")
                startWakeWordListening()
            }
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
        stopHandsFreeDirectAudioCapture()
        forceDirectAudioNextSession = false
        activeTurnID = nil
        activeTurnHasAudio = false
        historyAwaitingReply = false
        streamingPlan = nil
        activeReplyAssembler = nil
        didStartStreamingReading = false
        isRepeatingViaGlasses = false
        isSpeakingStatusCue = false
        isSessionActive = false
        agentState = .idle
        setLiveActivity(nil)
        endBackgroundWork()

        if settingsManager.settings.wakeWordEnabled && !shouldDeferWakeWordForMusic {
            if voiceCommandService.isListening {
                voiceCommandService.exitConversationMode()
            } else {
                startWakeWordListening()
            }
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
        stopHandsFreeDirectAudioCapture()
        if isRecordingVoiceNote {
            voiceNoteStartTask?.cancel()
            voiceNoteMeterTask?.cancel()
            directAudioRecorder.cancel()
            voiceCommandService.isVoiceNoteRecording = false
            isRecordingVoiceNote = false
            voiceNoteDuration = 0
            voiceNoteMeterLevels = []
        }
        isSendingVoiceNote = false
        forceDirectAudioNextSession = false
        activeTurnID = nil
        activeTurnHasAudio = false
        historyAwaitingReply = false
        streamingPlan = nil
        activeReplyAssembler = nil
        didStartStreamingReading = false
        isRepeatingViaGlasses = false
        isSpeakingStatusCue = false
        Task { await gemini.interrupt() }

        isSessionActive = false
        agentState = .idle
        setLiveActivity(nil)
        endBackgroundWork()
        if settingsManager.settings.wakeWordEnabled && !shouldDeferWakeWordForMusic {
            if voiceCommandService.isListening && voiceCommandService.state != .idle {
                voiceCommandService.exitConversationMode()
            } else if !voiceCommandService.isListening {
                startWakeWordListening()
            }
        } else {
            voiceCommandService.stopListening()
            Task { await AudioSessionManager.shared.deactivateSessionAsync() }
        }
    }

    func startNewConversation() {
        readingEngine.stop()
        ttsService.stop()
        stopHandsFreeDirectAudioCapture()
        if isRecordingVoiceNote {
            cancelVoiceNoteRecording()
        }
        isSendingVoiceNote = false
        forceDirectAudioNextSession = false
        activeTurnHasAudio = false
        activePlan = nil
        activePlanPhotoID = nil
        streamingPlan = nil
        userTranscript = ""
        aiTranscript = ""
        activePhotoContext = nil
        currentTranscriptPhotoData = nil
        isRepeatingViaGlasses = false
        isSpeakingStatusCue = false
        errorMessage = nil
        statusMessage = nil
        setLiveActivity(nil)
        endBackgroundWork()
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
            self.updateReadingLiveActivity()
        }
        readingEngine.onSegmentStarted = { [weak self] _ in
            guard let self else { return }
            // N6: clear recognizer echo buffer on each new segment so wake-word commands work.
            self.voiceCommandService.resetBufferForNewSegment()
            self.updateReadingLiveActivity()
        }
        readingEngine.onWaitingForNext = { [weak self] in
            guard let self else { return }
            self.agentState = .idle
            self.voiceCommandService.isBargeInPaused = false
            self.voiceCommandService.resetBufferForNewSegment()
            self.setLiveActivity(LiveActivity(
                kind: .reading,
                title: "Đang chờ lệnh \"tiếp\"",
                detail: self.readingEngine.progressLabel.map { "Mục \($0)" }
            ))
        }
        readingEngine.onReadingFinished = { [weak self] in
            guard let self else { return }
            self.isRepeatingViaGlasses = false
            if self.liveActivity?.kind == .reading || self.liveActivity?.kind == .repeating {
                self.setLiveActivity(nil)
            }
            MetricsCollector.shared.markSpokeDone()
            self.scheduleEchoSettleAndResume()
        }
    }

    private func handleReadingCommand(_ command: ReadingCommand) {
        HapticFeedback.light()
        if command == .stop {
            readingEngine.stop()
            isRepeatingViaGlasses = false
            setLiveActivity(nil)
            Task { await gemini.interrupt() }
            scheduleEchoSettleAndResume()
            return
        }
        readingEngine.apply(command)
        if readingEngine.state == .paused {
            // App is now silent: allow bare voice commands ("tiếp", "tiếp tục") without wake word.
            voiceCommandService.isBargeInPaused = false
            agentState = .idle
            setLiveActivity(LiveActivity(
                kind: .reading,
                title: "Đã tạm dừng đọc",
                detail: readingEngine.progressLabel.map { "Mục \($0)" }
            ))
        } else if readingEngine.state == .waitingForNext {
            voiceCommandService.isBargeInPaused = false
            agentState = .idle
        } else if readingEngine.state == .reading {
            updateReadingLiveActivity()
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

        // Single shared microphone tap relay (Lesson 1) — cheap no-op whenever DirectAudioRecorder is idle.
        voiceCommandService.onAudioBuffer = { [weak recorder = directAudioRecorder] buffer in
            recorder?.appendBuffer(buffer)
        }

        voiceCommandService.onDirectAudioSpeechEnded = { [weak self] in
            self?.handleDirectAudioSpeechEnded()
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
                if self.isSessionActive {
                    self.beginHandsFreeDirectAudioCaptureIfNeeded()
                }
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
                self.stopHandsFreeDirectAudioCapture()
                self.handleReadingCommand(cmd)
                return
            }

            if SolverIntent.isStopCommand(command) {
                self.stopHandsFreeDirectAudioCapture()
                self.performFullStop()
                return
            }

            var directAudioPayload: Data? = nil
            if self.isDirectAudioSessionCaptureActive {
                self.isDirectAudioSessionCaptureActive = false
                self.voiceCommandService.isDirectAudioCapturing = false
                if let wav = self.directAudioRecorder.finishTapCapture(),
                   self.directAudioRecorder.lastCapturedDuration >= 0.35,
                   self.directAudioRecorder.lastCapturedPeakLevel >= DirectAudioRecorder.minAudibleRMS {
                    directAudioPayload = wav
                    AppLog.info(
                        .audio,
                        "Hands-free direct audio finalized (\(wav.count) bytes, \(String(format: "%.1f", self.directAudioRecorder.lastCapturedDuration))s) alongside draft transcript"
                    )
                } else {
                    AppLog.debug(.audio, "Hands-free direct audio too short/silent — falling back to speech draft transcript")
                }
            }

            self.isRepeatingViaGlasses = false
            self.userTranscript = command
            self.endSessionAfterSpeaking = false
            self.activeTurnID = UUID()
            self.activeTurnCommand = command

            MetricsCollector.shared.markCommit(backend: "gemini", model: GeminiLiveService.modelName, ttsEngine: "apple")
            self.historyAwaitingReply = true

            Task {
                await self.sendCommand(command, audioData: directAudioPayload)
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
                if self.isSessionActive || self.voiceCommandService.isListening {
                    AppLog.info(.audio, "Audio route changed - reapplying preferred route")
                    await self.configureAudioForGlassesAsync(forceRestart: false)
                    if self.voiceCommandService.isListening && !self.voiceCommandService.isRecognitionHealthy {
                        self.voiceCommandService.stopListening()
                        self.startWakeWordListening()
                    }
                } else if self.settingsManager.settings.wakeWordEnabled && !self.shouldDeferWakeWordForMusic {
                    // Glasses connected after app launch — automatically start wake-word listening!
                    self.ensureWakeWordListeningIfEnabled()
                }
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
        } else if newSettings.directAudioToGemini != old.directAudioToGemini
                    || newSettings.usageMode != old.usageMode {
            if isSessionActive && !isRecordingVoiceNote && !isSendingVoiceNote
                && (voiceCommandService.state == .conversationMode || voiceCommandService.state == .listening) {
                if shouldUseHandsFreeDirectAudio {
                    if !isDirectAudioSessionCaptureActive {
                        beginHandsFreeDirectAudioCaptureIfNeeded()
                    }
                } else {
                    stopHandsFreeDirectAudioCapture()
                }
            }
        }
    }

    private func handleDirectAudioSpeechEnded() {
        guard isSessionActive, isDirectAudioSessionCaptureActive else { return }
        isDirectAudioSessionCaptureActive = false
        voiceCommandService.isDirectAudioCapturing = false

        let wav = directAudioRecorder.finishTapCapture()
        let duration = directAudioRecorder.lastCapturedDuration
        let peak = directAudioRecorder.lastCapturedPeakLevel

        guard let audioData = wav,
              !audioData.isEmpty,
              duration >= 0.35,
              peak >= DirectAudioRecorder.minAudibleRMS else {
            AppLog.debug(
                .audio,
                "Discarding short/silent hands-free direct-audio commit (duration=\(String(format: "%.2f", duration))s, peak=\(String(format: "%.3f", peak)))"
            )
            agentState = .listening
            voiceCommandService.enterConversationMode()
            beginHandsFreeDirectAudioCaptureIfNeeded()
            return
        }

        let fallbackPrompt = "Nghe đoạn ghi âm của người dùng và trả lời trực tiếp bằng ngôn ngữ họ nói."
        let displayLabel = "🎙 Câu hỏi giọng nói (gửi trực tiếp Gemini)"
        AppLog.info(.audio, "Committing hands-free direct audio turn (\(audioData.count) bytes, \(String(format: "%.1f", duration))s, empty draft)")

        isRepeatingViaGlasses = false
        userTranscript = displayLabel
        endSessionAfterSpeaking = false
        activeTurnID = UUID()
        activeTurnCommand = fallbackPrompt
        historyAwaitingReply = true
        setLiveActivity(LiveActivity(
            kind: .uploading,
            title: "Đang gửi giọng nói trực tiếp tới Gemini…",
            detail: "\(max(1, audioData.count / 1024)) KB"
        ))
        MetricsCollector.shared.markCommit(backend: "gemini", model: GeminiLiveService.modelName, ttsEngine: "apple")

        Task {
            await self.sendCommand(fallbackPrompt, allowRepeat: true, audioData: audioData, displayOverride: displayLabel)
        }
    }

    private func setupAIServiceCallbacks() {
        ttsService.onSpeechEnded = { [weak self] in
            guard let self else { return }
            if self.isSpeakingStatusCue && (self.isCapturingFromButton || self.gemini.isProcessing) {
                self.isSpeakingStatusCue = false
                return
            }
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
                self.isSpeakingStatusCue = false
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
                let leadIn = self.settingsManager.settings.spokenStatusUpdates
                    ? (lang == "vi" ? "AI đã phản hồi." : "AI responded.")
                    : nil
                self.readingEngine.start(plan: plan, leadIn: leadIn)
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
                    self.isSpeakingStatusCue = false
                    self.agentState = .speaking
                    self.voiceCommandService.isBargeInPaused = true
                    let leadIn = self.settingsManager.settings.spokenStatusUpdates
                        ? (lang == "vi" ? "AI đã phản hồi." : "AI responded.")
                        : nil
                    self.readingEngine.start(plan: plan, leadIn: leadIn)
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
            self.activeTurnHasAudio = false
            self.isSendingVoiceNote = false
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

        gemini.onStatusUpdate = { [weak self] status in
            guard let self else { return }
            guard self.isSessionActive || self.activeTurnID != nil else { return }
            switch status {
            case .preparingImage:
                self.setLiveActivity(LiveActivity(
                    kind: .uploading,
                    title: "Đang tối ưu ảnh…",
                    detail: "Chuẩn bị dữ liệu gửi lên Gemini"
                ))
            case .uploading(let progress, let kilobytes):
                let pct = Int((progress * 100).rounded())
                let hasPhoto = self.currentTranscriptPhotoData != nil
                let uploadTitle: String
                if hasPhoto && self.activeTurnHasAudio {
                    uploadTitle = "Đang tải ảnh & ghi âm lên Gemini (\(pct)%)"
                } else if self.activeTurnHasAudio {
                    uploadTitle = "Đang tải ghi âm lên Gemini (\(pct)%)"
                } else {
                    uploadTitle = "Đang tải ảnh lên Gemini (\(pct)%)"
                }
                self.setLiveActivity(LiveActivity(
                    kind: .uploading,
                    title: uploadTitle,
                    detail: "\(kilobytes) KB",
                    progress: progress
                ))
                if progress >= 0.45 && progress < 0.95 && !self.didAnnounceUploadHalfway {
                    self.didAnnounceUploadHalfway = true
                    self.speakStatusCue(SolverIntent.speaksVietnamese ? "Đã tải lên 50 phần trăm." : "Upload 50 percent.")
                }
            case .waitingForModel(let model, let keyLabel):
                self.isSendingVoiceNote = false
                self.setLiveActivity(LiveActivity(
                    kind: .thinking,
                    title: "Gemini đang giải bài…",
                    detail: "\(model) · \(keyLabel)"
                ))
                if !self.didAnnounceUploadDoneWaitingAI {
                    self.didAnnounceUploadDoneWaitingAI = true
                    let hasPhoto = self.currentTranscriptPhotoData != nil
                    let cue: String
                    if SolverIntent.speaksVietnamese {
                        if hasPhoto && self.activeTurnHasAudio {
                            cue = "Đã tải ảnh và ghi âm xong, đang đợi AI suy nghĩ."
                        } else if self.activeTurnHasAudio {
                            cue = "Đã gửi ghi âm xong, đang đợi AI suy nghĩ."
                        } else if hasPhoto {
                            cue = "Đã tải ảnh xong, đang đợi AI suy nghĩ."
                        } else {
                            cue = "Đang đợi AI suy nghĩ."
                        }
                    } else {
                        if hasPhoto || self.activeTurnHasAudio {
                            cue = "Upload complete, waiting for AI."
                        } else {
                            cue = "Waiting for AI."
                        }
                    }
                    self.speakStatusCue(cue)
                }
            case .retrying(let reason, let spokenCue):
                self.setLiveActivity(LiveActivity(
                    kind: .retrying,
                    title: "Đang tự động thử lại…",
                    detail: reason
                ))
                self.speakStatusCue(spokenCue, important: true)
            case .streaming(let model):
                self.isSendingVoiceNote = false
                if !self.didStartStreamingReading {
                    self.setLiveActivity(LiveActivity(
                        kind: .thinking,
                        title: "AI đã phản hồi — đang chuẩn bị đọc…",
                        detail: model
                    ))
                }
            }
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
        voiceCommandService.syncAuthorizationStatus()
        guard settingsManager.settings.wakeWordEnabled else { return }
        guard voiceCommandService.authorizationStatus == .authorized else {
            AppLog.info(.voice, "Wake-word start skipped — speech auth=\(voiceCommandService.authorizationStatus.rawValue)")
            return
        }
        if shouldDeferWakeWordForMusic {
            AppLog.info(.audio, "Music is playing — deferring idle wake-word mic so Ray-Ban stays in A2DP (use glasses button or tap Mic)")
            return
        }
        guard wakeWordStartTask == nil else { return }

        wakeWordStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.wakeWordStartTask = nil }

            // Ensure microphone permission is granted before touching AVAudioEngine on cold launch.
            if AVAudioApplication.shared.recordPermission == .undetermined {
                let granted = await AVAudioApplication.requestRecordPermission()
                guard granted else {
                    AppLog.warning(.voice, "Microphone permission denied — cannot start wake-word auto-listening")
                    self.errorMessage = "Chưa cấp quyền Micro để tự động lắng nghe từ đánh thức."
                    return
                }
            } else if AVAudioApplication.shared.recordPermission != .granted {
                AppLog.warning(.voice, "Microphone permission not granted — wake-word auto-listening inactive")
                return
            }

            // Cold-start retry loop: Bluetooth HFP on Ray-Ban Meta often takes 0.5–1.5s to settle after launch.
            let retryDelaysNs: [UInt64] = [0, 700_000_000, 1_500_000_000]
            var lastError: Error?
            for (attempt, delayNs) in retryDelaysNs.enumerated() {
                if delayNs > 0 {
                    try? await Task.sleep(nanoseconds: delayNs)
                }
                guard !Task.isCancelled, self.settingsManager.settings.wakeWordEnabled, !self.shouldDeferWakeWordForMusic else {
                    return
                }
                if self.voiceCommandService.isListening && self.voiceCommandService.isRecognitionHealthy {
                    self.isVoiceReady = true
                    return
                }
                await self.configureAudioForGlassesAsync(forceRestart: attempt > 0)
                do {
                    try self.voiceCommandService.startListening()
                    self.isVoiceReady = true
                    if self.errorMessage == VoiceCommandError.audioEngineUnavailable.errorDescription {
                        self.errorMessage = nil
                    }
                    AppLog.info(.voice, "Started wake word auto-listening - READY (attempt \(attempt + 1), route=\(AudioSessionManager.shared.currentRouteDescription))")
                    return
                } catch {
                    lastError = error
                    AppLog.warning(.voice, "Wake-word start attempt \(attempt + 1) failed: \(error.localizedDescription)")
                }
            }
            if let lastError {
                AppLog.error(.voice, "Failed to start wake-word listening after retries: \(lastError.localizedDescription)")
                self.errorMessage = lastError.localizedDescription
            }
        }
    }

    // MARK: - Direct-Audio Voice Note Composer (Regular Chat)

    /// Begins recording a direct-audio voice note (16 kHz mono WAV) to send straight to Gemini.
    /// Uses `VoiceCommandService`'s shared tap when already active (Lesson 1) and falls back to
    /// standalone `AVAudioRecorder` when wake word is disabled or paused during music.
    func startVoiceNoteRecording() {
        guard !isRecordingVoiceNote && !isSendingVoiceNote else { return }

        if AVAudioApplication.shared.recordPermission == .denied {
            errorMessage = "Chưa cấp quyền Micro. Hãy bật quyền Micro trong Cài đặt iOS."
            return
        }

        voiceNoteStartTask?.cancel()
        voiceNoteMeterTask?.cancel()
        echoSettleTask?.cancel()
        readingEngine.stop()
        ttsService.stop()
        stopHandsFreeDirectAudioCapture()
        isSpeakingStatusCue = false
        isRepeatingViaGlasses = false
        errorMessage = nil

        isRecordingVoiceNote = true
        isSendingVoiceNote = false
        voiceNoteDuration = 0
        voiceNoteMeterLevels = []
        setLiveActivity(LiveActivity(
            kind: .listening,
            title: "Đang ghi âm gửi Gemini…",
            detail: "Nhấn nút gửi khi nói xong"
        ))
        HapticFeedback.medium()

        voiceNoteStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.voiceNoteStartTask = nil }

            if AVAudioApplication.shared.recordPermission == .undetermined {
                let granted = await AVAudioApplication.requestRecordPermission()
                guard granted, !Task.isCancelled, self.isRecordingVoiceNote else {
                    if !granted {
                        self.errorMessage = "Chưa cấp quyền Micro để ghi âm gửi Gemini."
                    }
                    self.cancelVoiceNoteRecording()
                    return
                }
            }

            await self.configureAudioForGlassesAsync(forceRestart: false)
            guard !Task.isCancelled, self.isRecordingVoiceNote else { return }

            if self.voiceCommandService.isListening && self.voiceCommandService.isRecognitionHealthy {
                self.voiceCommandService.isVoiceNoteRecording = true
                self.directAudioRecorder.beginTapCapture()
                AppLog.info(.audio, "Voice note recording started (shared tap, route=\(AudioSessionManager.shared.currentRouteDescription))")
            } else {
                do {
                    try self.directAudioRecorder.startStandaloneRecording()
                    AppLog.info(.audio, "Voice note recording started (standalone AVAudioRecorder, route=\(AudioSessionManager.shared.currentRouteDescription))")
                } catch {
                    AppLog.error(.audio, "Failed to start standalone voice note recording: \(error.localizedDescription)")
                    self.isRecordingVoiceNote = false
                    self.voiceNoteDuration = 0
                    self.voiceNoteMeterLevels = []
                    self.setLiveActivity(nil)
                    self.errorMessage = "Không thể bắt đầu ghi âm: \(error.localizedDescription)"
                    return
                }
            }

            self.startVoiceNoteMeterLoop()
        }
    }

    /// Cancels an active voice note recording, discards buffered audio, and restores idle/wake-word state.
    func cancelVoiceNoteRecording() {
        voiceNoteStartTask?.cancel()
        voiceNoteStartTask = nil
        voiceNoteMeterTask?.cancel()
        voiceNoteMeterTask = nil

        directAudioRecorder.cancel()
        voiceCommandService.isVoiceNoteRecording = false
        if voiceCommandService.isListening {
            voiceCommandService.clearBufferAfterVoiceNote()
        }

        isRecordingVoiceNote = false
        isSendingVoiceNote = false
        voiceNoteDuration = 0
        voiceNoteMeterLevels = []
        if liveActivity?.kind == .listening {
            setLiveActivity(nil)
        }

        restoreAudioAfterVoiceNoteDismissed()
        AppLog.info(.audio, "Voice note recording cancelled")
    }

    /// Stops voice note recording, encodes 16 kHz mono WAV, attaches fresh photo context if present,
    /// and sends directly to Gemini through the unified streaming + ReadingEngine pipeline.
    func sendVoiceNoteRecording() {
        guard isRecordingVoiceNote && !isSendingVoiceNote else { return }

        voiceNoteStartTask?.cancel()
        voiceNoteStartTask = nil
        voiceNoteMeterTask?.cancel()
        voiceNoteMeterTask = nil

        let activeMode = directAudioRecorder.currentMode
        let wavData: Data?
        switch activeMode {
        case .sharedTap:
            wavData = directAudioRecorder.finishTapCapture()
        case .standaloneRecorder:
            wavData = directAudioRecorder.stopStandaloneRecording()
        case .idle:
            wavData = nil
        }

        let duration = max(directAudioRecorder.lastCapturedDuration, voiceNoteDuration)
        voiceCommandService.isVoiceNoteRecording = false
        if voiceCommandService.isListening {
            if voiceCommandService.state == .conversationMode || voiceCommandService.state == .listening {
                voiceCommandService.enterProcessingState()
            } else {
                voiceCommandService.clearBufferAfterVoiceNote()
            }
        }

        isRecordingVoiceNote = false
        voiceNoteDuration = 0
        voiceNoteMeterLevels = []

        guard let wavData, !wavData.isEmpty, duration >= 0.3 else {
            isSendingVoiceNote = false
            let shortMsg = SolverIntent.speaksVietnamese
                ? "Bản ghi âm quá ngắn — hãy nói lâu hơn một chút rồi nhấn gửi."
                : "Voice note is too short — please speak a little longer before sending."
            flashStatusMessage(shortMsg, duration: 2.5)
            setLiveActivity(LiveActivity(
                kind: .notice,
                title: "Bản ghi âm quá ngắn",
                detail: "Hãy nói ít nhất 0.3 giây rồi gửi"
            ), autoClearAfter: 2.5)
            restoreAudioAfterVoiceNoteDismissed()
            AppLog.info(.audio, "Discarded voice note shorter than 0.3s (duration=\(String(format: "%.2f", duration))s)")
            return
        }

        let roundedSeconds = max(1, Int(duration.rounded()))
        let durationLabel = String(format: "%d:%02d", roundedSeconds / 60, roundedSeconds % 60)
        let displayLabel = "🎙 Tin nhắn thoại · \(durationLabel)"
        let prompt = SolverIntent.speaksVietnamese
            ? "Nghe đoạn ghi âm của người dùng và trả lời trực tiếp bằng ngôn ngữ họ nói."
            : "Listen directly to the user's audio recording and answer directly in the language they spoke."

        isSendingVoiceNote = true
        errorMessage = nil
        isRepeatingViaGlasses = false
        userTranscript = displayLabel
        aiTranscript = ""
        endSessionAfterSpeaking = false
        activeTurnID = UUID()
        activeTurnCommand = prompt
        historyAwaitingReply = true
        resetTurnSpokenMilestones()
        setLiveActivity(LiveActivity(
            kind: .uploading,
            title: "Đang gửi tin nhắn thoại tới Gemini…",
            detail: "\(max(1, wavData.count / 1024)) KB · \(durationLabel)"
        ))

        MetricsCollector.shared.markCommit(backend: "gemini", model: GeminiLiveService.modelName, ttsEngine: "apple")
        AppLog.info(.audio, "Sending Chat voice note to Gemini (\(wavData.count) bytes, \(durationLabel))")

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSendingVoiceNote = false }
            await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                preferGlasses: self.settingsManager.settings.preferGlassesMic
            )
            self.speakStatusCue(
                SolverIntent.speaksVietnamese ? "Đang gửi ghi âm lên Gemini." : "Sending voice note to Gemini.",
                important: true
            )
            await self.sendCommand(prompt, allowRepeat: true, audioData: wavData, displayOverride: displayLabel)
        }
    }

    private func startVoiceNoteMeterLoop() {
        voiceNoteMeterTask?.cancel()
        voiceNoteMeterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000) // ~20 Hz
                guard !Task.isCancelled, let self, self.isRecordingVoiceNote else { break }
                self.voiceNoteDuration = self.directAudioRecorder.currentDuration
                let level = self.directAudioRecorder.sampleMeterLevel()
                self.voiceNoteMeterLevels.append(level)
                if self.voiceNoteMeterLevels.count > 40 {
                    self.voiceNoteMeterLevels.removeFirst(self.voiceNoteMeterLevels.count - 40)
                }
                if self.directAudioRecorder.hasReachedMaxDuration {
                    AppLog.info(.audio, "Voice note reached 60s max duration — sending automatically")
                    self.sendVoiceNoteRecording()
                    break
                }
            }
        }
    }

    private func restoreAudioAfterVoiceNoteDismissed() {
        if isSessionActive {
            beginHandsFreeDirectAudioCaptureIfNeeded()
        } else if settingsManager.settings.wakeWordEnabled && !shouldDeferWakeWordForMusic {
            ensureWakeWordListeningIfEnabled()
        } else if !voiceCommandService.isListening && !readingEngine.isActive && !ttsService.isSpeaking && !isRecording {
            Task { await AudioSessionManager.shared.deactivateSessionAsync() }
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
        stopHandsFreeDirectAudioCapture()
        if voiceCommandService.isListening && (voiceCommandService.state == .conversationMode || voiceCommandService.state == .listening) {
            voiceCommandService.enterProcessingState()
        }
        errorMessage = nil
        isRepeatingViaGlasses = false
        userTranscript = trimmed
        aiTranscript = ""
        endSessionAfterSpeaking = false
        activeTurnID = UUID()
        activeTurnCommand = trimmed
        historyAwaitingReply = true
        setLiveActivity(LiveActivity(kind: .thinking, title: "Đang gửi câu hỏi lên Gemini…", detail: nil))

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
        isRepeatingViaGlasses = false
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

    private func sendCommand(
        _ command: String,
        allowRepeat: Bool = false,
        audioData: Data? = nil,
        displayOverride: String? = nil
    ) async {
        if SolverIntent.isStopCommand(command) {
            AppLog.info(.voice, "Stop command detected - full stop")
            performFullStop()
            return
        }

        let now = Date()
        if !allowRepeat, audioData == nil, command == lastProcessedCommand, now.timeIntervalSince(lastProcessedAt) < 4 {
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
        activeTurnHasAudio = (audioData?.isEmpty == false)
        ConversationManager.shared.addUserMessage(displayOverride ?? command, photoData: photo)
        didAnnounceUploadHalfway = false
        didAnnounceUploadDoneWaitingAI = false

        do {
            try await gemini.sendRESTMessage(command, imageData: photo, audioData: audioData)
        } catch {
            handleSendFailure(error, command: command)
        }
    }

    private func handleSendFailure(_ error: Error, command: String) {
        activeTurnHasAudio = false
        isSendingVoiceNote = false
        if error is CancellationError {
            MetricsCollector.shared.abandonTurn()
            endBackgroundWork()
            return
        }
        let failureKind = gemini.lastFailureKind
        AppLog.error(.gemini, "Send failed [kind=\(String(describing: failureKind))]: \(error.localizedDescription)")
        MetricsCollector.shared.abandonTurn()

        let spokenError = SolverIntent.failureMessage(for: command, error: error, kind: failureKind)
        // Close the open user turn in ConversationManager so a failed turn never stays open
        // and mis-attaches a future turn's thinking spinner onto an old photo!
        if historyAwaitingReply {
            ConversationManager.shared.addAssistantMessage("⚠️ \(spokenError)", reading: nil)
            historyAwaitingReply = false
        }
        errorMessage = spokenError
        aiTranscript = spokenError
        let cardTitle: String
        switch failureKind {
        case .badAPIKey: cardTitle = "Lỗi API key Google Gemini"
        case .rateLimited: cardTitle = "Hết hạn mức API (HTTP 429)"
        case .serverOverloaded: cardTitle = "Máy chủ Google quá tải (HTTP 503)"
        case .modelUnavailable: cardTitle = "Model không khả dụng (HTTP 404)"
        case .blockedOrInvalid: cardTitle = "Gemini từ chối yêu cầu"
        case .network, .none: cardTitle = "Lỗi kết nối mạng tới Gemini"
        }
        setLiveActivity(LiveActivity(
            kind: .error,
            title: cardTitle,
            detail: error.localizedDescription
        ), autoClearAfter: 10.0)

        let shouldSpeak = (isSessionActive || activeTurnID != nil) && (!ttsService.isSpeaking || isSpeakingStatusCue)
        activeTurnID = nil
        if shouldSpeak {
            isSpeakingStatusCue = false
            Task { @MainActor in
                await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                    preferGlasses: settingsManager.settings.preferGlassesMic
                )
                self.speakResponse(spokenError)
            }
        } else {
            agentState = isSessionActive ? .listening : .idle
            endBackgroundWork()
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

    private func acquireGlassesPhoto(freshSince: Date? = nil) async -> Data? {
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
        if let freshSince {
            // Strict freshness gate for explicit button/manual captures: NEVER reuse an old photo from a prior turn.
            let minDate = freshSince.addingTimeInterval(-3.0)
            let synced = await RecentPhotoScanner.shared.fetchMostRecentPhoto(
                withinSeconds: 20.0,
                minCreationDate: minDate,
                ignoreConsumed: true,
                markConsumed: true
            )
            if synced == nil {
                AppLog.warning(.photo, "Direct glasses capture failed and no new Meta album photo arrived since \(minDate)")
            }
            return synced
        }
        return await RecentPhotoScanner.shared.fetchMostRecentPhoto(
            withinSeconds: SolverIntent.recentPhotoWindow,
            ignoreConsumed: false,
            markConsumed: true
        )
    }

    private func captureForAgent() async -> Data? {
        HapticFeedback.light()
        resetTurnSpokenMilestones()
        setLiveActivity(LiveActivity(
            kind: .capturing,
            title: "AI yêu cầu chụp ảnh từ kính…",
            detail: settingsManager.settings.fullResolutionPhotos ? "Chế độ 12 MP nét nhất" : "Chế độ nhanh"
        ))
        speakStatusCue(
            SolverIntent.speaksVietnamese ? "Đang chụp ảnh từ kính." : "Capturing photo from glasses.",
            important: true
        )
        let data = await acquireGlassesPhoto(freshSince: nil)
        if let data {
            let source = glassesManager.lastPhotoSource ?? "camera-roll"
            activePhotoContext = CapturedPhotoContext(data: data, source: source)
            currentTranscriptPhotoData = data
            ConversationManager.shared.attachPhotoToLatestUserMessage(data)
            HapticFeedback.success()
            speakStatusCue(
                SolverIntent.speaksVietnamese ? "Đã chụp ảnh xong, đang gửi lên Gemini." : "Photo captured, sending to Gemini.",
                important: true
            )
            AppLog.info(.photo, "Agent capture: got photo (\(data.count) bytes, source=\(source))")
        } else {
            HapticFeedback.error()
            setLiveActivity(LiveActivity(
                kind: .error,
                title: "Không lấy được ảnh từ kính",
                detail: "Hãy bấm nút chụp trên kính rồi thử lại"
            ), autoClearAfter: 5.0)
            AppLog.warning(.photo, "Agent capture: no photo available")
        }
        return data
    }

    func snapPhotoFromGlasses() async {
        HapticFeedback.light()
        AppLog.info(.photo, "Manual photo snap requested from glasses")
        let captureRequestedAt = Date()
        resetTurnSpokenMilestones()
        errorMessage = nil
        activePhotoContext = nil
        currentTranscriptPhotoData = nil
        setLiveActivity(LiveActivity(
            kind: .capturing,
            title: "Kính đang chụp ảnh…",
            detail: settingsManager.settings.fullResolutionPhotos ? "Chế độ 12 MP nét nhất" : "Chế độ nhanh"
        ))
        speakStatusCue(
            SolverIntent.speaksVietnamese
                ? (settingsManager.settings.fullResolutionPhotos ? "Đang chụp ảnh độ nét cao." : "Đang chụp ảnh.")
                : "Capturing photo.",
            important: true
        )
        let data = await acquireGlassesPhoto(freshSince: captureRequestedAt)

        if let data {
            let source = glassesManager.lastPhotoSource ?? "camera-roll"
            activePhotoContext = CapturedPhotoContext(data: data, source: source)
            currentTranscriptPhotoData = data
            HapticFeedback.success()
            setLiveActivity(LiveActivity(
                kind: .notice,
                title: "Đã nhận ảnh từ kính",
                detail: "Nguồn: \(source) · \(max(1, data.count / 1024)) KB"
            ), autoClearAfter: 3.0)
            speakStatusCue(SolverIntent.speaksVietnamese ? "Đã chụp ảnh xong." : "Photo captured.", important: true)
            AppLog.info(.photo, "Manual photo context cached (\(data.count) bytes, source=\(source))")
        } else {
            HapticFeedback.error()
            let message = SolverIntent.photoFailedMessage
            errorMessage = message
            setLiveActivity(LiveActivity(
                kind: .error,
                title: "Chưa nhận được ảnh từ kính",
                detail: "Kiểm tra kết nối kính và thử chụp lại"
            ), autoClearAfter: 6.0)
            isSpeakingStatusCue = false
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
                guard let self else { return }
                let source = self.glassesManager.lastPhotoSource ?? "stream-still"
                self.activePhotoContext = CapturedPhotoContext(data: data, source: source)
                self.currentTranscriptPhotoData = data
                AppLog.info(.photo, "Active photo context cached (\(data.count) bytes)")
            }
        }
        glassesManager.onPhotoProgress = { [weak self] received, total in
            guard let self, self.isCapturingFromButton || self.liveActivity?.kind == .capturing else { return }
            let receivedKB = max(1, received / 1024)
            if total > 0 {
                let fraction = min(1.0, max(0.0, Double(received) / Double(total)))
                let pct = Int((fraction * 100).rounded())
                let totalKB = max(1, total / 1024)
                self.setLiveActivity(LiveActivity(
                    kind: .capturing,
                    title: "Đang tải ảnh từ kính (\(pct)%)",
                    detail: "\(receivedKB) / \(totalKB) KB",
                    progress: fraction
                ))
                if fraction >= 0.45 && fraction < 0.95 && !self.didAnnouncePhotoTransferHalfway {
                    self.didAnnouncePhotoTransferHalfway = true
                    self.speakStatusCue(SolverIntent.speaksVietnamese ? "Đang tải ảnh từ kính, 50 phần trăm." : "Transferring photo, 50 percent.")
                }
            } else {
                self.setLiveActivity(LiveActivity(
                    kind: .capturing,
                    title: "Đang tải ảnh từ kính…",
                    detail: "\(receivedKB) KB"
                ))
            }
        }
        RecentPhotoScanner.shared.onPhotoArrived = { [weak self] data in
            Task { @MainActor in
                guard let self, !self.isCapturingFromButton else { return }
                self.activePhotoContext = CapturedPhotoContext(data: data, source: "camera-roll")
                self.currentTranscriptPhotoData = data
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
        guard !isCapturingFromButton else {
            AppLog.info(.glasses, "Ignoring overlapping button capture while another capture is running")
            return
        }
        if action == .captureAndSolve && !settingsManager.settings.isGeminiConfigured {
            HapticFeedback.error()
            let msg = SolverIntent.missingKeyMessage(for: SolverIntent.solvePhotoQuestion)
            errorMessage = msg
            setLiveActivity(LiveActivity(kind: .error, title: "Chưa cấu hình Gemini API key", detail: "Mở Cài đặt → Gemini để dán key"), autoClearAfter: 6.0)
            await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                preferGlasses: settingsManager.settings.preferGlassesMic
            )
            speakNotice(msg)
            return
        }

        let captureRequestedAt = Date()
        beginBackgroundWork(name: "Reybain.Button.\(action.rawValue)")
        isCapturingFromButton = true
        isRepeatingViaGlasses = false
        defer { isCapturingFromButton = false }
        HapticFeedback.light()

        // Clear any stale photo context immediately so a failed capture can NEVER display or send an old photo!
        errorMessage = nil
        activePhotoContext = nil
        currentTranscriptPhotoData = nil

        if action == .captureAndSolve || action == .captureAndListen {
            stopHandsFreeDirectAudioCapture()
            if ttsService.isSpeaking || readingEngine.isActive {
                readingEngine.stop()
                ttsService.stop()
            }
            if action == .captureAndSolve, voiceCommandService.isListening {
                voiceCommandService.enterProcessingState()
            }
            await gemini.interrupt()
        }

        setLiveActivity(LiveActivity(
            kind: .capturing,
            title: "Kính đang chụp ảnh…",
            detail: settingsManager.settings.fullResolutionPhotos ? "Chế độ 12 MP nét nhất" : "Chế độ nhanh"
        ))
        resetTurnSpokenMilestones()
        speakStatusCue(
            SolverIntent.speaksVietnamese
                ? (settingsManager.settings.fullResolutionPhotos ? "Đang chụp ảnh độ nét cao." : "Đang chụp ảnh.")
                : (settingsManager.settings.fullResolutionPhotos ? "Capturing high resolution photo." : "Capturing photo."),
            important: true
        )
        let data = await acquireGlassesPhoto(freshSince: captureRequestedAt)

        guard let data else {
            HapticFeedback.error()
            errorMessage = SolverIntent.photoFailedMessage
            setLiveActivity(LiveActivity(
                kind: .error,
                title: "Chưa nhận được ảnh từ kính",
                detail: "Kiểm tra kết nối kính và bấm nút chụp lại"
            ), autoClearAfter: 6.0)
            isSpeakingStatusCue = false
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
            setLiveActivity(LiveActivity(
                kind: .uploading,
                title: "Đã nhận ảnh từ kính",
                detail: "Nguồn: \(source) · \(max(1, data.count / 1024)) KB — đang gửi Gemini…"
            ))
            MetricsCollector.shared.markCommit(backend: "gemini", model: GeminiLiveService.modelName, ttsEngine: "apple")

            await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                preferGlasses: settingsManager.settings.preferGlassesMic
            )
            speakStatusCue(
                SolverIntent.speaksVietnamese ? "Đã chụp ảnh xong, đang tải lên Gemini." : "Photo received, uploading to Gemini.",
                important: true
            )
            await sendCommand(question, allowRepeat: true)

        case .captureAndListen:
            // General mode: photo is cached; announce completion and wait for it to finish BEFORE entering
            // `.conversationMode` so speech never leaks into Silero VAD or SFSpeechRecognizer.
            errorMessage = nil
            forceDirectAudioNextSession = true
            setLiveActivity(LiveActivity(
                kind: .listening,
                title: "Đã nhận ảnh — Đang nghe lệnh…",
                detail: "Hãy nói yêu cầu của bạn với ảnh vừa chụp"
            ))
            await speakStatusCueAndWait(
                SolverIntent.speaksVietnamese ? "Đã chụp ảnh xong, mời bạn nói lệnh." : "Photo captured, go ahead."
            )
            await configureAudioForGlassesAsync()
            if settingsManager.settings.playActivationSound {
                soundService.playWakeWordSound()
                try? await Task.sleep(nanoseconds: 280_000_000)
            }
            await startSessionAsync()

        case .capture:
            setLiveActivity(LiveActivity(
                kind: .notice,
                title: "Đã lưu ảnh vào bộ nhớ tạm",
                detail: "Nguồn: \(source) · \(max(1, data.count / 1024)) KB"
            ), autoClearAfter: 3.0)
            speakStatusCue(SolverIntent.speaksVietnamese ? "Đã chụp ảnh xong." : "Photo captured.", important: true)
            endBackgroundWork()
            AppLog.info(.photo, "Photo cached in RAM silently for upcoming agent call")

        case .repeatAnswer, .none:
            endBackgroundWork()
            break
        }
    }

    private func repeatLastAnswer() {
        AppLog.info(.reading, "Double-press repeat requested (isProcessing=\(gemini.isProcessing), hasPlan=\(readingEngine.plan != nil), lastSpokenLen=\(lastSpokenAnswer.count))")
        // If AI is still working on a response, never cancel it — inform the wearer cleanly instead.
        if gemini.isProcessing || activeTurnID != nil {
            flashStatusMessage("Bấm 2 lần trên kính: AI chưa phản hồi xong…", duration: 2.5)
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
            beginBackgroundWork(name: "Reybain.RepeatAnswer")
            isRepeatingViaGlasses = true
            isSpeakingStatusCue = false
            setLiveActivity(LiveActivity(
                kind: .repeating,
                title: "Đang đọc lại câu trả lời trước",
                detail: "Kích hoạt từ bấm 2 lần trên kính"
            ))
            let leadIn = settingsManager.settings.spokenStatusUpdates
                ? (SolverIntent.speaksVietnamese ? "Đọc lại câu trả lời trước." : "Repeating the previous answer.")
                : nil
            Task { @MainActor in
                await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                    preferGlasses: settingsManager.settings.preferGlassesMic
                )
                self.readingEngine.restartFromBeginning(leadIn: leadIn)
            }
            return
        }
        if ttsService.isSpeaking { ttsService.stop() }
        if !lastSpokenAnswer.isEmpty {
            beginBackgroundWork(name: "Reybain.RepeatAnswer")
            isRepeatingViaGlasses = true
            setLiveActivity(LiveActivity(
                kind: .repeating,
                title: "Đang đọc lại câu trả lời trước",
                detail: "Kích hoạt từ bấm 2 lần trên kính"
            ))
            Task { @MainActor in
                await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                    preferGlasses: settingsManager.settings.preferGlassesMic
                )
                self.speakNotice(self.lastSpokenAnswer)
            }
        } else {
            setLiveActivity(LiveActivity(
                kind: .notice,
                title: "AI chưa có câu trả lời để đọc lại",
                detail: "Hãy chụp ảnh hoặc đặt câu hỏi trước"
            ), autoClearAfter: 3.5)
            Task { @MainActor in
                await AudioSessionManager.shared.ensurePlaybackRouteAsync(
                    preferGlasses: settingsManager.settings.preferGlassesMic
                )
                self.speakNotice(SolverIntent.nothingToRepeatMessage)
            }
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
