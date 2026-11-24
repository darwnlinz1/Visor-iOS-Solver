// OpenVision - VoiceAgentView.swift
// Redesigned "Trực tiếp" Live screen (PLAN.md §4.5, T6.2):
// - Interactive Status Chip strip (Kính, Mic/Loa, Gemini, Ảnh, Trạng thái)
// - Live conversation feed with full structured SegmentCardView, active-segment highlight & auto-scroll
// - Empty state with 3-step guide + interactive Readiness Checklist
// - Floating PlaybackBar for speed, pause/resume, jump, repeat, and Đọc chép mode
// - Direct-chat composer bar + mic toggle + glasses camera capture (works with or without glasses!)

import SwiftUI
import Photos
import Speech
import AVFoundation

private struct PhotoPreviewItem: Identifiable {
    let id = UUID()
    let data: Data
}

struct VoiceAgentView: View {
    // MARK: - Environment

    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var glassesManager: GlassesManager
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - ViewModel & Observed Services

    @StateObject private var viewModel = VoiceAgentViewModel()
    @ObservedObject private var voiceCommandService = VoiceCommandService.shared
    @ObservedObject private var ttsService = TTSService.shared
    @ObservedObject private var readingEngine = ReadingEngine.shared

    // MARK: - Local UI state

    @State private var typedPrompt: String = ""
    @State private var previewPhoto: PhotoPreviewItem?
    @FocusState private var isPromptFocused: Bool

    // MARK: - Body

    var body: some View {
        ZStack {
            AnimatedBackground()

            VStack(spacing: 0) {
                headerBar
                statusChipStrip

                if settingsManager.settings.debugOverlay {
                    debugOverlayStrip
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.top, Theme.Spacing.xs)
                }

                if let status = viewModel.statusMessage {
                    transientStatusBanner(status)
                        .padding(.top, Theme.Spacing.sm)
                }

                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let error = viewModel.errorMessage {
                    inlineErrorBanner(error)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.sm)
                }

                if readingEngine.plan != nil {
                    PlaybackBar(engine: readingEngine, settingsManager: settingsManager)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.sm)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                promptComposerBar
                    .padding(.bottom, Theme.Spacing.sm)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.agentState)
        .animation(.easeInOut(duration: 0.25), value: readingEngine.plan == nil)
        .sheet(item: $previewPhoto) { item in
            FullScreenPhotoSheet(data: item.data)
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .task {
            await viewModel.requestSpeechAuthorization()
        }
        .onChange(of: ttsService.isSpeaking) { _, isSpeaking in
            viewModel.ttsSpeakingChanged(isSpeaking)
        }
        .onChange(of: viewModel.agentState) { _, newState in
            viewModel.agentStateChanged(newState)
        }
        .onChange(of: voiceCommandService.state) { _, newState in
            viewModel.voiceStateChanged(newState)
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.handleScenePhaseChanged(phase)
        }
    }

    // MARK: - Header Bar

    private var orbMode: SwirlOrb.Mode {
        switch viewModel.agentState {
        case .listening: return .listening
        case .speaking: return .speaking
        case .thinking, .connecting: return .thinking
        case .idle: return readingEngine.state == .reading ? .speaking : .idle
        }
    }

    private var headerBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                HapticFeedback.medium()
                viewModel.toggleSession()
            } label: {
                HStack(spacing: 10) {
                    SwirlOrb(mode: orbMode, size: 32)
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Trực tiếp")
                            .font(Theme.Typography.screenTitle)
                            .foregroundColor(Theme.textPrimary)
                        Text(headerSubtitle)
                            .font(Theme.Typography.caption)
                            .foregroundColor(viewModel.agentState == .idle ? Theme.textSecondary : Theme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isSessionActive ? "Dừng phiên giọng nói" : "Bắt đầu phiên giọng nói")

            Spacer()

            if let status = viewModel.recordingStatus {
                Text(status)
                    .font(Theme.Typography.badge)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
            }

            if glassesManager.isRegistered {
                Button {
                    viewModel.toggleRecording()
                } label: {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.title3)
                        .foregroundColor(viewModel.isRecording ? Theme.danger : Theme.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.bgElevated))
                }
                .accessibilityLabel(viewModel.isRecording ? "Dừng ghi hình" : "Ghi hình góc nhìn kính")
            }

            Button {
                HapticFeedback.light()
                viewModel.startNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.bgElevated))
                    .overlay(Circle().stroke(Theme.bgElevatedStroke, lineWidth: 1))
            }
            .accessibilityLabel("Cuộc hội thoại mới")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private var headerSubtitle: String {
        if readingEngine.state == .reading, let progress = readingEngine.progressLabel {
            return "Đang đọc mục \(progress)"
        }
        if readingEngine.state == .waitingForNext {
            return "Chờ lệnh \"tiếp\""
        }
        if readingEngine.state == .paused {
            return "Đang tạm dừng"
        }
        if viewModel.agentState == .thinking {
            return "Đang giải bài…"
        }
        return viewModel.agentState.displayText
    }

    // MARK: - Interactive Status Chip Strip (PLAN.md §4.5)

    private var statusChipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                // 0. Active usage mode chip (Study vs General)
                StatusChip(
                    icon: settingsManager.settings.usageMode.systemImage,
                    label: settingsManager.settings.usageMode.shortLabel,
                    tint: Theme.accent,
                    isEmphasized: true,
                    accessibilityHintText: "Đổi chế độ Giải bài tập hoặc Sử dụng bình thường"
                ) {
                    router.openSettings(.workflowMode)
                }

                // 1. Glasses chip
                StatusChip(
                    icon: "eyeglasses",
                    label: glassesChipLabel,
                    tint: glassesChipTint,
                    isEmphasized: glassesManager.connectedDevice != nil,
                    accessibilityHintText: "Mở cài đặt kính Ray-Ban Meta"
                ) {
                    router.openSettings(.glasses)
                }

                // 2. Mic / Audio route chip
                StatusChip(
                    icon: AudioSessionManager.shared.isBluetoothHFPInputActive ? "earbuds" : "mic.fill",
                    label: micChipLabel,
                    tint: voiceCommandService.isListening ? Theme.info : Theme.inactive,
                    accessibilityHintText: "Mở cài đặt nghe và micro"
                ) {
                    router.openSettings(.voice)
                }

                // 3. Gemini chip
                let keyCount = GeminiLiveService.parseKeys(settingsManager.settings.geminiAPIKey).count
                StatusChip(
                    icon: "sparkles",
                    label: keyCount > 0 ? "Gemini · \(keyCount) key" : "Chưa có key",
                    tint: keyCount > 0 ? Theme.accent : Theme.warning,
                    isEmphasized: keyCount == 0,
                    accessibilityHintText: "Mở cài đặt API key Gemini"
                ) {
                    router.openSettings(.gemini)
                }

                // 4. Photo readiness chip (only ticks 1 Hz while a photo context is attached)
                if viewModel.activePhotoContext != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        photoChip(now: timeline.date)
                    }
                } else {
                    photoChip(now: Date())
                }

                // 5. Thinking / Reading status chip
                if viewModel.agentState == .thinking, let started = viewModel.thinkingStartedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let secs = max(0, Int(timeline.date.timeIntervalSince(started)))
                        StatusChip(
                            icon: "hourglass",
                            label: "Đang nghĩ \(secs)s",
                            tint: Theme.warning,
                            isEmphasized: true
                        )
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    private var glassesChipLabel: String {
        if glassesManager.sdkUnavailableReason != nil { return "Kính: Lỗi SDK" }
        if !glassesManager.isRegistered { return "Kính: Chưa đăng ký" }
        if glassesManager.connectedDevice != nil { return "Kính: Đã kết nối" }
        return "Kính: Chờ kết nối"
    }

    private var glassesChipTint: Color {
        if glassesManager.sdkUnavailableReason != nil { return Theme.danger }
        if glassesManager.connectedDevice != nil { return Theme.success }
        return glassesManager.isRegistered ? Theme.warning : Theme.inactive
    }

    private var micChipLabel: String {
        let source = AudioSessionManager.shared.isBluetoothHFPInputActive ? "Mic kính" : "Mic iPhone"
        let mode = voiceCommandService.isOnDeviceRecognition ? "Trên máy" : "Mạng"
        return "\(source) · \(mode)"
    }

    @ViewBuilder
    private func photoChip(now: Date) -> some View {
        if let ctx = viewModel.activePhotoContext, ctx.isFresh(at: now) {
            let remaining = ctx.remainingSeconds(at: now)
            StatusChip(
                icon: "photo.fill",
                label: "Ảnh · \(remaining)s",
                tint: Theme.success,
                isEmphasized: true,
                accessibilityHintText: "Chạm để xem ảnh đang đính kèm"
            ) {
                previewPhoto = PhotoPreviewItem(data: ctx.data)
            }
        } else {
            StatusChip(
                icon: "camera",
                label: "Chụp kính",
                tint: Theme.textSecondary,
                accessibilityHintText: "Chụp một ảnh từ kính Ray-Ban"
            ) {
                Task { await viewModel.snapPhotoFromGlasses() }
            }
        }
    }

    // MARK: - Debug Overlay Strip (PLAN.md §4.7)

    private var debugOverlayStrip: some View {
        HStack(spacing: 8) {
            Text("DBG")
                .font(.caption2.monospaced().bold())
                .foregroundColor(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.warning))

            Text("agent=\(String(describing: viewModel.agentState)) | voice=\(String(describing: voiceCommandService.state)) | read=\(String(describing: readingEngine.state)) | out=\(AudioSessionManager.shared.outputLabel)")
                .font(.caption2.monospaced())
                .foregroundColor(Theme.textSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.65))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.warning.opacity(0.45), lineWidth: 1))
        )
    }

    // MARK: - Main Content Area

    private var currentTurns: [LiveTurn] {
        LiveTurnGrouper.turns(
            from: conversationManager.currentConversation?.messages ?? [],
            pendingUserText: viewModel.userTranscript,
            pendingPhotoData: viewModel.currentTranscriptPhotoData,
            activePlan: viewModel.activePlan,
            isThinking: viewModel.agentState == .thinking
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        if settingsManager.settings.hideTextSpeakOnly {
            speakOnlyModeView
        } else if currentTurns.isEmpty && viewModel.currentTranscriptPhotoData == nil && voiceCommandService.currentTranscription.isEmpty {
            emptyStateAndChecklist
        } else {
            liveFeedView
        }
    }

    /// Minimalist audio-only mode ("Ẩn chữ, chỉ nghe", PLAN.md §4.5).
    private var speakOnlyModeView: some View {
        VStack(spacing: 20) {
            Spacer()
            SwirlOrb(mode: orbMode, size: 200)
                .onTapGesture {
                    HapticFeedback.medium()
                    viewModel.toggleSession()
                }
            Text(headerSubtitle)
                .font(.title3.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
            Button("Hiện nội dung hội thoại") {
                settingsManager.settings.hideTextSpeakOnly = false
            }
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.accent)
            Spacer()
        }
        .padding()
    }

    /// Empty state with 3-step guide + interactive Readiness Checklist (PLAN.md §4.5).
    private var emptyStateAndChecklist: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                VStack(spacing: Theme.Spacing.md) {
                    SwirlOrb(mode: orbMode, size: 120)
                        .frame(height: 136)
                        .onTapGesture {
                            HapticFeedback.medium()
                            viewModel.toggleSession()
                        }
                        .accessibilityLabel("Chạm để bắt đầu nói chuyện")

                    Text("Hỏi bài bằng giọng nói hoặc gõ trực tiếp")
                        .font(.title3.weight(.bold))
                        .foregroundColor(Theme.heading)
                        .multilineTextAlignment(.center)

                    Text("Trắc nghiệm đọc gọn đáp án · Tự luận đọc từng dòng công thức tiếng Việt")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Theme.Spacing.sm)

                // 3-step quick guide
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Cách dùng nhanh (\(settingsManager.settings.usageMode.displayName))")
                        .font(Theme.Typography.cardTitle)
                        .foregroundColor(Theme.textSecondary)
                    if settingsManager.settings.usageMode == .study {
                        guideStep(number: "1", text: "Nhấn 1 lần nút kính để chụp và tự gửi kèm prompt giải bài ngay.")
                        guideStep(number: "2", text: "Nhấn 2 lần nút kính để đọc lại câu trả lời gần nhất bất cứ lúc nào.")
                    } else {
                        guideStep(number: "1", text: "Nhấn 1 lần nút kính để chụp ảnh rồi nói câu lệnh tự do bạn muốn.")
                        guideStep(number: "2", text: "Nhấn 2 lần nút kính để đọc lại câu trả lời cũ; đổi chế độ ở chip phía trên.")
                    }
                    guideStep(number: "3", text: "Hoặc nói \"\(settingsManager.settings.wakeWord)\" + câu hỏi, hay gõ trực tiếp ở ô bên dưới.")
                }
                .padding(Theme.Spacing.lg)
                .background(cardSurface)

                // Live readiness checklist
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Kiểm tra sẵn sàng")
                        .font(Theme.Typography.cardTitle)
                        .foregroundColor(Theme.textSecondary)

                    checklistRow(
                        title: "API key Gemini",
                        ready: settingsManager.settings.isGeminiConfigured,
                        status: settingsManager.settings.isGeminiConfigured ? "Đã cấu hình" : "Chưa có key"
                    ) { router.openSettings(.gemini) }

                    checklistRow(
                        title: "Kính Ray-Ban Meta",
                        ready: glassesManager.isRegistered,
                        status: glassesManager.isRegistered ? "Đã đăng ký" : "Tùy chọn · Chưa kết nối"
                    ) { router.openSettings(.glasses) }

                    let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                    checklistRow(
                        title: "Quyền Thư viện Ảnh",
                        ready: photoStatus == .authorized,
                        status: photoStatus == .authorized ? "Toàn bộ ảnh" : (photoStatus == .limited ? "Giới hạn" : "Chưa cấp")
                    ) { openSystemSettings() }

                    let micGranted = AVAudioApplication.shared.recordPermission == .granted
                    checklistRow(
                        title: "Quyền Micro",
                        ready: micGranted,
                        status: micGranted ? "Đã cấp" : "Chưa cấp"
                    ) { openSystemSettings() }

                    let speechGranted = voiceCommandService.authorizationStatus == .authorized
                    checklistRow(
                        title: "Nhận dạng giọng nói",
                        ready: speechGranted,
                        status: speechGranted ? "Đã cấp" : "Chưa cấp"
                    ) { openSystemSettings() }
                }
                .padding(Theme.Spacing.lg)
                .background(cardSurface)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
    }

    private func guideStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundColor(.black.opacity(0.9))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.buttonGradient))
            Text(text)
                .font(.footnote)
                .foregroundColor(Theme.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private func checklistRow(title: String, ready: Bool, status: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(ready ? Theme.success : Theme.warning)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text(status)
                    .font(.caption)
                    .foregroundColor(ready ? Theme.textSecondary : Theme.warning)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Theme.bgCard.opacity(0.9))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.bgElevatedStroke, lineWidth: 1))
    }

    /// Live scrollable conversation feed with active segment auto-scroll (PLAN.md §4.5).
    private var liveFeedView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.lg) {
                    // Pending attached photo before a question is sent
                    if currentTurns.isEmpty, let photoData = viewModel.currentTranscriptPhotoData, let uiImage = UIImage(data: photoData) {
                        attachedPhotoCard(uiImage: uiImage, data: photoData)
                    }

                    ForEach(currentTurns) { turn in
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            if !turn.userText.isEmpty || turn.photoData != nil {
                                TranscriptBubble(
                                    text: turn.userText,
                                    isUser: true,
                                    isStreaming: false,
                                    photoData: turn.photoData,
                                    onTapPhoto: { data in previewPhoto = PhotoPreviewItem(data: data) }
                                )
                            }

                            if let record = turn.readingRecord, !record.segments.isEmpty {
                                let isActiveCard = isCurrentPlaybackCard(turn: turn, record: record)
                                SegmentCardView(
                                    record: record,
                                    cardID: "\(turn.id.uuidString)-",
                                    activeSegmentIndex: isActiveCard ? readingEngine.currentSegmentIndex : nil,
                                    activeSpokenPiece: isActiveCard ? readingEngine.currentPieceText : nil,
                                    activeWordRange: isActiveCard ? readingEngine.currentWordRange : nil,
                                    isReadingActive: isActiveCard && readingEngine.state == .reading,
                                    onSelectSegment: { idx in
                                        HapticFeedback.light()
                                        if isActiveCard {
                                            readingEngine.jump(to: idx)
                                        } else {
                                            readingEngine.replay(record: record, startingAt: idx)
                                        }
                                    },
                                    onReplay: {
                                        HapticFeedback.light()
                                        viewModel.replayFromHistory(record)
                                    }
                                )
                            } else if let text = turn.assistantText, !text.isEmpty {
                                TranscriptBubble(text: text, isUser: false, isStreaming: false)
                            } else if turn.isActiveTurn && viewModel.agentState == .thinking {
                                HStack(spacing: 10) {
                                    TypingIndicator()
                                    Text("Gemini đang giải bài…")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.textSecondary)
                                    Spacer()
                                }
                            }
                        }
                        .id(turn.id)
                    }

                    // Live speech transcription while the user is actively talking
                    if !voiceCommandService.currentTranscription.isEmpty && (voiceCommandService.state == .listening || voiceCommandService.state == .conversationMode) {
                        TranscriptBubble(
                            text: voiceCommandService.currentTranscription,
                            isUser: true,
                            isStreaming: true
                        )
                        .opacity(0.85)
                        .id("live-speech")
                    }

                    Color.clear
                        .frame(height: 8)
                        .id("feed-bottom")
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.md)
            }
            .onChange(of: currentTurns.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("feed-bottom", anchor: .bottom)
                }
            }
            .onChange(of: readingEngine.currentSegmentIndex) { _, newIndex in
                if let plan = readingEngine.plan, plan.segments.indices.contains(newIndex) {
                    let segID = plan.segments[newIndex].id
                    let activeTurn = currentTurns.last { turn in
                        guard let record = turn.readingRecord else { return false }
                        return isCurrentPlaybackCard(turn: turn, record: record)
                    }
                    let targetID = activeTurn.map { "\($0.id.uuidString)-seg-\(segID)" } ?? "seg-\(segID)"
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
            .onChange(of: viewModel.aiTranscript) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("feed-bottom", anchor: .bottom)
                }
            }
        }
    }

    private func isCurrentPlaybackCard(turn: LiveTurn, record: ReadingRecord) -> Bool {
        guard let active = readingEngine.plan else { return false }
        if turn.isActiveTurn, let livePlan = viewModel.activePlan, active.turnID == livePlan.turnID {
            return true
        }
        return active.record == record
    }

    private func attachedPhotoCard(uiImage: UIImage, data: Data) -> some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.success).frame(width: 8, height: 8)
                    Text("Ảnh kính đã đính kèm")
                        .font(Theme.Typography.badge)
                        .foregroundColor(Theme.accent)
                    Button {
                        viewModel.detachPhoto()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.textSecondary)
                    }
                    .accessibilityLabel("Gỡ ảnh")
                }
                Button {
                    previewPhoto = PhotoPreviewItem(data: data)
                } label: {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 200, maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                Text("Nhập hoặc nói câu hỏi về ảnh này…")
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(10)
            .background(cardSurface)
        }
    }

    // MARK: - Composer Bar (Mic + Camera + Direct Chat Input)

    private var promptComposerBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Mic session toggle
            Button {
                HapticFeedback.medium()
                viewModel.toggleSession()
            } label: {
                Image(systemName: viewModel.isSessionActive ? "mic.fill" : "mic")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(viewModel.isSessionActive ? .black.opacity(0.9) : Theme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle().fill(viewModel.isSessionActive ? AnyShapeStyle(Theme.buttonGradient) : AnyShapeStyle(Theme.bgElevated))
                    )
                    .overlay(Circle().stroke(viewModel.isSessionActive ? Theme.accent : Theme.bgElevatedStroke, lineWidth: 1))
            }
            .accessibilityLabel(viewModel.isSessionActive ? "Dừng micro" : "Bắt đầu hỏi bằng giọng nói")

            // Camera snap button
            Button {
                Task { await viewModel.snapPhotoFromGlasses() }
            } label: {
                Image(systemName: viewModel.currentTranscriptPhotoData != nil ? "camera.fill" : "camera")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(viewModel.currentTranscriptPhotoData != nil ? Theme.accent : Theme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.bgElevated))
                    .overlay(
                        Circle().stroke(
                            viewModel.currentTranscriptPhotoData != nil ? Theme.accent.opacity(0.8) : Theme.bgElevatedStroke,
                            lineWidth: 1
                        )
                    )
            }
            .accessibilityLabel("Chụp ảnh bằng kính")

            // Text input (direct chat — works with or without glasses!)
            TextField("Nhập câu hỏi hoặc gọi \"\(settingsManager.settings.wakeWord)\"…", text: $typedPrompt)
                .font(.subheadline)
                .foregroundColor(Theme.textPrimary)
                .focused($isPromptFocused)
                .submitLabel(.send)
                .onSubmit { submitPrompt() }

            if !typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    submitPrompt()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(Theme.accent)
                }
                .accessibilityLabel("Gửi câu hỏi")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.composer, style: .continuous)
                .fill(Theme.bgElevated.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.composer, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        )
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private func submitPrompt() {
        let text = typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typedPrompt = ""
        isPromptFocused = false
        HapticFeedback.light()
        viewModel.sendTypedCommand(text)
    }

    // MARK: - Banners & Helpers

    private func transientStatusBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(Theme.accent)
                .scaleEffect(0.8)
            Text(text)
                .font(Theme.Typography.badge)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.75))
                .overlay(Capsule().stroke(Theme.accent.opacity(0.55), lineWidth: 1))
        )
    }

    private func inlineErrorBanner(_ message: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.warning)
            Text(message)
                .font(.footnote)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.7))
            }
            .accessibilityLabel("Đóng thông báo lỗi")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.danger.opacity(0.82))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row).stroke(Color.white.opacity(0.2), lineWidth: 1))
        )
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// Full-screen photo preview sheet when tapping an attached photo thumbnail.
private struct FullScreenPhotoSheet: View {
    let data: Data
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
            }
            .navigationTitle("Ảnh đề bài")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    VoiceAgentView()
        .environmentObject(SettingsManager.shared)
        .environmentObject(GlassesManager.shared)
        .environmentObject(ConversationManager.shared)
        .environmentObject(AppRouter())
        .preferredColorScheme(.dark)
}
