// Reybain - VoiceAgentView.swift
// iOS 26 Liquid Glass & Apple Intelligence "Trực tiếp" Live screen:
// - Floating glass header + interactive Liquid Glass StatusChip strip
// - Editorial OLED conversation feed with structured SegmentCardView, active-segment highlight & auto-scroll
// - Iridescent LiveActivityCard with custom gradient progress bar & tabular metrics
// - Floating Liquid Glass PlaybackBar
// - 4-state morphing Floating Glass Pill Composer (Idle / Typing / Recording Voice Note / Sending)
//   with live AudioWaveformMeter and attached-photo synergy pill
// - Reybain-branded empty state & interactive Readiness Checklist

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

    // MARK: - Local UI State

    @State private var typedPrompt: String = ""
    @State private var previewPhoto: PhotoPreviewItem?
    @FocusState private var isPromptFocused: Bool

    private var hasTypedPrompt: Bool {
        !typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
                        .padding(.horizontal, 14)
                        .padding(.bottom, Theme.Spacing.sm)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                floatingComposerSection
                    .padding(.bottom, Theme.Spacing.sm)
            }
        }
        .animation(Theme.Motion.gentle, value: viewModel.agentState)
        .animation(Theme.Motion.gentle, value: viewModel.liveActivity)
        .animation(Theme.Motion.snappy, value: readingEngine.plan == nil)
        .sheet(item: $previewPhoto) { item in
            FullScreenPhotoSheet(data: item.data)
        }
        .onAppear {
            viewModel.onAppear()
            syncTabBarVisibility()
        }
        .onDisappear {
            viewModel.onDisappear()
            router.isTabBarHidden = false
        }
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
        .onChange(of: isPromptFocused) { _, _ in
            syncTabBarVisibility()
        }
        .onChange(of: viewModel.isRecordingVoiceNote) { _, _ in
            syncTabBarVisibility()
        }
        .onChange(of: viewModel.isSendingVoiceNote) { _, _ in
            syncTabBarVisibility()
        }
    }

    private func syncTabBarVisibility() {
        let shouldHide = isPromptFocused || viewModel.isRecordingVoiceNote || viewModel.isSendingVoiceNote
        withAnimation(Theme.Motion.snappy) {
            router.isTabBarHidden = shouldHide
        }
    }

    // MARK: - Header Bar

    private var orbMode: SwirlOrb.Mode {
        if viewModel.isRecordingVoiceNote {
            return .listening
        }
        if viewModel.isSendingVoiceNote {
            return .thinking
        }
        if let kind = viewModel.liveActivity?.kind {
            switch kind {
            case .capturing, .uploading, .thinking, .retrying: return .thinking
            case .listening: return .listening
            case .reading, .repeating: return .speaking
            case .notice, .error: break
            }
        }
        switch viewModel.agentState {
        case .listening: return .listening
        case .speaking: return .speaking
        case .thinking, .connecting: return .thinking
        case .idle: return readingEngine.state == .reading ? .speaking : .idle
        }
    }

    private var isHeaderActive: Bool {
        viewModel.agentState != .idle
            || viewModel.isRecordingVoiceNote
            || viewModel.isSendingVoiceNote
            || viewModel.liveActivity != nil
            || readingEngine.state == .reading
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
                            .tracking(-0.2)
                            .foregroundColor(Theme.textPrimary)

                        Text(headerSubtitle)
                            .font(Theme.Typography.caption.monospacedDigit())
                            .foregroundColor(isHeaderActive ? Theme.accentBright : Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isSessionActive ? "Dừng phiên giọng nói" : "Bắt đầu phiên giọng nói")

            Spacer(minLength: 8)

            if let status = viewModel.recordingStatus {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.danger)
                        .frame(width: 6.5, height: 6.5)
                        .shadow(color: Theme.danger.opacity(0.8), radius: 3)
                    Text(status)
                        .font(Theme.Typography.badge.monospacedDigit())
                        .foregroundColor(Theme.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .liquidGlassPill(tint: Theme.danger)
            }

            if glassesManager.isRegistered {
                Button {
                    HapticFeedback.light()
                    viewModel.toggleRecording()
                } label: {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(viewModel.isRecording ? Theme.danger : Theme.textPrimary)
                        .frame(width: 36, height: 36)
                        .liquidGlassPill(tint: viewModel.isRecording ? Theme.danger : nil, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.isRecording ? "Dừng ghi hình" : "Ghi hình góc nhìn kính")
            }

            Button {
                HapticFeedback.light()
                viewModel.startNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .liquidGlassPill(interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cuộc hội thoại mới")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, 6)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private var headerSubtitle: String {
        if viewModel.isRecordingVoiceNote {
            return "Đang ghi âm · \(formatRecordingDuration(viewModel.voiceNoteDuration))"
        }
        if viewModel.isSendingVoiceNote {
            return "Đang gửi ghi âm tới Reybain…"
        }
        if let activity = viewModel.liveActivity {
            return activity.title
        }
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
        if viewModel.agentState == .idle {
            return "Sẵn sàng · Reybain"
        }
        return viewModel.agentState.displayText
    }

    // MARK: - Interactive Status Chip Strip

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
                    isEmphasized: voiceCommandService.isListening,
                    accessibilityHintText: "Mở cài đặt nghe và micro"
                ) {
                    router.openSettings(.voice)
                }

                // 3. Gemini chip
                let keyCount = GeminiLiveService.parseKeys(settingsManager.settings.geminiAPIKey).count
                StatusChip(
                    icon: "sparkles",
                    label: keyCount > 0 ? "Gemini · \(keyCount) key" : "Chưa có key",
                    tint: keyCount > 0 ? Theme.iridescentCyan : Theme.warning,
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

                // 5. Thinking status chip
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

    // MARK: - Debug Overlay Strip

    private var debugOverlayStrip: some View {
        HStack(spacing: 8) {
            Text("DBG")
                .font(.caption2.monospaced().bold())
                .foregroundColor(Theme.bg)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.warning))

            Text("agent=\(String(describing: viewModel.agentState)) | voice=\(String(describing: voiceCommandService.state)) | read=\(String(describing: readingEngine.state)) | out=\(AudioSessionManager.shared.outputLabel)")
                .font(Theme.Typography.monoLog)
                .foregroundColor(Theme.textSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .liquidGlassCard(cornerRadius: 12, style: .tinted(Theme.warning))
    }

    // MARK: - Main Content Area

    private var currentTurns: [LiveTurn] {
        LiveTurnGrouper.turns(
            from: conversationManager.currentConversation?.messages ?? [],
            pendingUserText: viewModel.isCapturingFromButton ? "" : viewModel.userTranscript,
            pendingPhotoData: viewModel.isCapturingFromButton ? nil : viewModel.currentTranscriptPhotoData,
            activePlan: viewModel.activePlan,
            isThinking: viewModel.agentState == .thinking
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        if settingsManager.settings.hideTextSpeakOnly {
            speakOnlyModeView
        } else if currentTurns.isEmpty
                    && viewModel.liveActivity == nil
                    && viewModel.currentTranscriptPhotoData == nil
                    && voiceCommandService.currentTranscription.isEmpty {
            emptyStateAndChecklist
        } else {
            liveFeedView
        }
    }

    /// Minimalist audio-only mode ("Ẩn chữ, chỉ nghe").
    private var speakOnlyModeView: some View {
        VStack(spacing: 22) {
            Spacer()

            SwirlOrb(mode: orbMode, size: 210)
                .onTapGesture {
                    HapticFeedback.medium()
                    viewModel.toggleSession()
                }
                .accessibilityLabel(viewModel.isSessionActive ? "Dừng phiên giọng nói" : "Bắt đầu phiên giọng nói")

            Text(headerSubtitle)
                .font(.title3.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Button {
                HapticFeedback.selection()
                settingsManager.settings.hideTextSpeakOnly = false
            } label: {
                Label("Hiện nội dung hội thoại", systemImage: "text.bubble")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.accentBright)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .liquidGlassPill(tint: Theme.accent, interactive: true)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding()
    }

    /// Reybain-branded empty state with 3-step guide + interactive Readiness Checklist.
    private var emptyStateAndChecklist: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Theme.Spacing.xl) {
                VStack(spacing: Theme.Spacing.sm) {
                    SwirlOrb(mode: orbMode, size: 112)
                        .frame(height: 132)
                        .onTapGesture {
                            HapticFeedback.medium()
                            viewModel.toggleSession()
                        }
                        .accessibilityLabel("Chạm để bắt đầu nói chuyện cùng Reybain")

                    Text("Reybain")
                        .font(Theme.Typography.heroTitle)
                        .tracking(-0.4)
                        .foregroundStyle(Theme.intelligenceLinear)

                    Text("Trợ lý AI kính thông minh · Chụp đề, ghi âm hoặc hỏi tự do")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .padding(.top, Theme.Spacing.xs)

                // 3-step quick guide
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(spacing: 8) {
                        SettingsIconBadge(icon: settingsManager.settings.usageMode.systemImage, tint: Theme.accent)
                        Text("Cách dùng nhanh (\(settingsManager.settings.usageMode.displayName))")
                            .font(Theme.Typography.cardTitle)
                            .foregroundColor(Theme.textPrimary)
                    }

                    if settingsManager.settings.usageMode == .study {
                        guideStep(number: "1", text: "Nhấn 1 lần nút kính để chụp và tự gửi kèm prompt giải bài ngay.")
                        guideStep(number: "2", text: "Nhấn 2 lần nút kính để đọc lại câu trả lời gần nhất bất cứ lúc nào.")
                    } else {
                        guideStep(number: "1", text: "Nhấn 1 lần nút kính để chụp ảnh rồi nói câu lệnh tự do bạn muốn.")
                        guideStep(number: "2", text: "Nhấn 2 lần nút kính để đọc lại câu trả lời cũ; đổi chế độ ở chip phía trên.")
                    }
                    guideStep(
                        number: "3",
                        text: "Hoặc chạm micro để gửi ghi âm trực tiếp, gọi \"\(settingsManager.settings.wakeWord)\", hay gõ câu hỏi bên dưới."
                    )
                }
                .padding(Theme.Spacing.lg)
                .liquidGlassCard(cornerRadius: Theme.Radius.card, style: .surface)

                // Live readiness checklist
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: 8) {
                        SettingsIconBadge(icon: "checkmark.shield.fill", tint: Theme.success)
                        Text("Kiểm tra sẵn sàng")
                            .font(Theme.Typography.cardTitle)
                            .foregroundColor(Theme.textPrimary)
                    }
                    .padding(.bottom, 2)

                    checklistRow(
                        title: "API key Gemini",
                        ready: settingsManager.settings.isGeminiConfigured,
                        status: settingsManager.settings.isGeminiConfigured ? "Đã cấu hình" : "Chưa có key"
                    ) { router.openSettings(.gemini) }

                    checklistRow(
                        title: "Kính Ray-Ban Meta",
                        ready: glassesManager.isRegistered,
                        status: glassesManager.isRegistered ? "Đã đăng ký" : "Tuỳ chọn · Chưa kết nối"
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
                .liquidGlassCard(cornerRadius: Theme.Radius.card, style: .surface)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
    }

    private func guideStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundColor(Theme.ctaForeground)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.buttonGradient))
                .shadow(color: Theme.glow.opacity(0.32), radius: 5, y: 1)

            Text(text)
                .font(.footnote)
                .foregroundColor(Theme.textPrimary)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func checklistRow(title: String, ready: Bool, status: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(ready ? Theme.success : Theme.warning)

                Text(title)
                    .font(.subheadline)
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                Text(status)
                    .font(.caption.weight(.medium))
                    .foregroundColor(ready ? Theme.textSecondary : Theme.warning)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Live scrollable conversation feed with active segment auto-scroll.
    private var liveFeedView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.lg) {
                    // Pending attached photo card when no conversation turns exist yet
                    if currentTurns.isEmpty,
                       !viewModel.isRecordingVoiceNote,
                       !viewModel.isSendingVoiceNote,
                       let photoData = viewModel.currentTranscriptPhotoData,
                       let uiImage = UIImage(data: photoData) {
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
                            } else if turn.isActiveTurn && viewModel.agentState == .thinking && viewModel.liveActivity == nil {
                                HStack(spacing: 10) {
                                    TypingIndicator()
                                    Text("Reybain đang suy nghĩ…")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.textSecondary)
                                    Spacer()
                                }
                            }
                        }
                        .id(turn.id)
                    }

                    // Live speech transcription while the user is actively talking
                    if !voiceCommandService.currentTranscription.isEmpty
                        && (voiceCommandService.state == .listening || voiceCommandService.state == .conversationMode) {
                        TranscriptBubble(
                            text: voiceCommandService.currentTranscription,
                            isUser: true,
                            isStreaming: true
                        )
                        .opacity(0.86)
                        .id("live-speech")
                    }

                    // Real-time glasses & AI activity card
                    if let activity = viewModel.liveActivity {
                        liveActivityCard(activity)
                            .id("live-activity")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
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
            .onChange(of: viewModel.liveActivity?.kind) { _, _ in
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

    // MARK: - Live Activity Card

    private func isActiveAIWork(_ kind: LiveActivity.Kind) -> Bool {
        switch kind {
        case .capturing, .uploading, .thinking, .listening:
            return true
        case .retrying, .reading, .repeating, .notice, .error:
            return false
        }
    }

    private func liveActivityCard(_ activity: LiveActivity) -> some View {
        let tint = activityTint(for: activity.kind)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: activityIcon(for: activity.kind))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(tint.opacity(0.18))
                            .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 0.75))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.textPrimary)
                    if let detail = activity.detail, !detail.isEmpty {
                        Text(detail)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 4)

                switch activity.kind {
                case .capturing, .uploading, .retrying:
                    ProgressView()
                        .tint(tint)
                        .scaleEffect(0.85)
                case .thinking:
                    TypingIndicator()
                case .repeating:
                    Text("2× KÍNH")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundColor(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(tint.opacity(0.16))
                                .overlay(Capsule().strokeBorder(tint.opacity(0.36), lineWidth: 0.75))
                        )
                case .reading, .listening, .notice, .error:
                    EmptyView()
                }
            }

            if let progress = activity.progress {
                let clamped = min(1.0, max(0.0, progress))
                HStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.10))
                            Capsule()
                                .fill(Theme.intelligenceLinear)
                                .frame(width: max(6, geo.size.width * clamped))
                        }
                    }
                    .frame(height: 5)

                    Text("\(Int(clamped * 100))%")
                        .font(Theme.Typography.monoMetric)
                        .foregroundColor(Theme.accentBright)
                        .frame(minWidth: 36, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 20, style: .tinted(tint))
        .appleIntelligenceGlow(
            isActive: isActiveAIWork(activity.kind),
            cornerRadius: 20,
            lineWidth: 1.3,
            glowRadius: 7
        )
    }

    private func activityIcon(for kind: LiveActivity.Kind) -> String {
        switch kind {
        case .capturing: return "eyeglasses"
        case .uploading: return "icloud.and.arrow.up.fill"
        case .thinking: return "sparkles"
        case .retrying: return "arrow.triangle.2.circlepath"
        case .listening: return "waveform"
        case .reading: return "speaker.wave.2.fill"
        case .repeating: return "repeat.circle.fill"
        case .notice: return "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private func activityTint(for kind: LiveActivity.Kind) -> Color {
        switch kind {
        case .capturing, .listening: return Theme.info
        case .uploading, .thinking, .repeating: return Theme.accent
        case .retrying: return Theme.warning
        case .reading: return Theme.success
        case .notice: return Theme.textSecondary
        case .error: return Theme.danger
        }
    }

    private func attachedPhotoCard(uiImage: UIImage, data: Data) -> some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.success).frame(width: 7, height: 7)
                    Text("Ảnh kính đã đính kèm")
                        .font(Theme.Typography.badge)
                        .foregroundColor(Theme.accentBright)
                    Button {
                        HapticFeedback.light()
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
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.specularRimGradient, lineWidth: 0.85)
                        )
                }
                .buttonStyle(.plain)

                Text("Ghi âm, nhập hoặc nói câu hỏi về ảnh này…")
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(10)
            .liquidGlassCard(cornerRadius: 20, style: .surface)
        }
    }

    // MARK: - 4-State Floating Glass Pill Composer (with Direct-Audio Voice Note)

    private var shouldShowAttachedPhotoPill: Bool {
        viewModel.currentTranscriptPhotoData != nil
            && (!currentTurns.isEmpty || viewModel.isRecordingVoiceNote || viewModel.isSendingVoiceNote)
    }

    @ViewBuilder
    private var floatingComposerSection: some View {
        VStack(spacing: 6) {
            if shouldShowAttachedPhotoPill,
               let photoData = viewModel.currentTranscriptPhotoData,
               let uiImage = UIImage(data: photoData) {
                attachedPhotoMiniBar(uiImage: uiImage, data: photoData)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Group {
                if viewModel.isRecordingVoiceNote || viewModel.isSendingVoiceNote {
                    voiceNoteRecordingBar
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    standardComposerBar
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .liquidGlassCard(cornerRadius: Theme.Radius.composer, style: .chrome, interactive: true)
            .appleIntelligenceGlow(
                isActive: viewModel.isRecordingVoiceNote || viewModel.isSessionActive,
                cornerRadius: Theme.Radius.composer,
                lineWidth: viewModel.isRecordingVoiceNote ? 1.8 : 1.3,
                glowRadius: viewModel.isRecordingVoiceNote ? 9 : 6
            )
        }
        .padding(.horizontal, 14)
        .animation(Theme.Motion.snappy, value: viewModel.isRecordingVoiceNote)
        .animation(Theme.Motion.snappy, value: viewModel.isSendingVoiceNote)
        .animation(Theme.Motion.snappy, value: hasTypedPrompt)
        .animation(Theme.Motion.snappy, value: shouldShowAttachedPhotoPill)
    }

    private func attachedPhotoMiniBar(uiImage: UIImage, data: Data) -> some View {
        HStack(spacing: 8) {
            Button {
                previewPhoto = PhotoPreviewItem(data: data)
            } label: {
                HStack(spacing: 8) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6)
                        )

                    if viewModel.activePhotoContext != nil {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            attachedPhotoPillText(now: timeline.date)
                        }
                    } else {
                        attachedPhotoPillText(now: Date())
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Xem ảnh kính đang đính kèm")

            Spacer(minLength: 4)

            if !viewModel.isSendingVoiceNote {
                Button {
                    HapticFeedback.light()
                    viewModel.detachPhoto()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Gỡ ảnh đính kèm")
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .liquidGlassPill(tint: Theme.accent)
    }

    @ViewBuilder
    private func attachedPhotoPillText(now: Date) -> some View {
        let baseTitle: String = {
            if let ctx = viewModel.activePhotoContext, ctx.isFresh(at: now) {
                return "Ảnh kính · \(ctx.remainingSeconds(at: now))s"
            }
            return "Ảnh đã đính kèm"
        }()

        HStack(spacing: 6) {
            Text(baseTitle)
                .font(Theme.Typography.monoMetric)
                .foregroundColor(Theme.textPrimary)

            if viewModel.isRecordingVoiceNote || viewModel.isSendingVoiceNote {
                Text("· Sẽ gửi kèm ghi âm")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(Theme.accentBright)
            }
        }
    }

    private var standardComposerBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Left: Glasses Camera button
            Button {
                HapticFeedback.light()
                Task { await viewModel.snapPhotoFromGlasses() }
            } label: {
                let hasPhoto = viewModel.currentTranscriptPhotoData != nil
                Image(systemName: hasPhoto ? "camera.fill" : "camera")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(hasPhoto ? Theme.accentBright : Theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(hasPhoto ? Theme.accent.opacity(0.20) : Color.white.opacity(0.08))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                hasPhoto ? Theme.accent.opacity(0.55) : Color.white.opacity(0.14),
                                lineWidth: 0.8
                            )
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chụp ảnh bằng kính")

            // Center: Multiline direct chat input
            TextField("Hỏi Reybain hoặc ghi âm…", text: $typedPrompt, axis: .vertical)
                .font(.subheadline)
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1...4)
                .focused($isPromptFocused)
                .submitLabel(.send)
                .onSubmit { submitPrompt() }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)

            // Right #1: Direct-Audio Voice Note button
            Button {
                HapticFeedback.medium()
                isPromptFocused = false
                viewModel.startVoiceNoteRecording()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(hasTypedPrompt ? Theme.textSecondary : Theme.accentBright)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(hasTypedPrompt ? Color.white.opacity(0.05) : Theme.accent.opacity(0.14))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                hasTypedPrompt ? Color.white.opacity(0.10) : Theme.accent.opacity(0.36),
                                lineWidth: 0.8
                            )
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ghi âm tin nhắn thoại gửi Gemini")

            // Right #2: Send Text (when typing) OR Live Hands-Free Session toggle (when idle)
            if hasTypedPrompt {
                Button {
                    submitPrompt()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Theme.ctaForeground)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.buttonGradient))
                        .shadow(color: Theme.glow.opacity(0.45), radius: 8, y: 2)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Gửi câu hỏi")
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else {
                Button {
                    HapticFeedback.medium()
                    viewModel.toggleSession()
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(viewModel.isSessionActive ? Theme.ctaForeground : Theme.textPrimary)
                        .frame(width: 38, height: 38)
                        .background {
                            if viewModel.isSessionActive {
                                Circle().fill(Theme.buttonGradient)
                            } else {
                                Circle().fill(Color.white.opacity(0.08))
                            }
                        }
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    viewModel.isSessionActive
                                        ? AnyShapeStyle(Theme.specularTop)
                                        : AnyShapeStyle(Theme.intelligenceLinear.opacity(0.65)),
                                    lineWidth: viewModel.isSessionActive ? 0.9 : 1.15
                                )
                        )
                        .shadow(
                            color: viewModel.isSessionActive ? Theme.glow.opacity(0.48) : .clear,
                            radius: 8,
                            y: 2
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.isSessionActive ? "Dừng phiên giọng nói rảnh tay" : "Bắt đầu phiên giọng nói rảnh tay")
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
    }

    private var voiceNoteRecordingBar: some View {
        HStack(spacing: 10) {
            // Cancel recording
            Button {
                HapticFeedback.light()
                viewModel.cancelVoiceNoteRecording()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundColor(Theme.danger)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.danger.opacity(0.16)))
                    .overlay(Circle().strokeBorder(Theme.danger.opacity(0.40), lineWidth: 0.8))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSendingVoiceNote)
            .opacity(viewModel.isSendingVoiceNote ? 0.35 : 1.0)
            .accessibilityLabel("Huỷ ghi âm")

            // Live pulsing dot + tabular duration
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.danger)
                    .frame(width: 7, height: 7)
                    .shadow(color: Theme.danger.opacity(0.8), radius: 3)
                    .opacity(viewModel.isSendingVoiceNote ? 0.4 : 1.0)

                Text(formatRecordingDuration(viewModel.voiceNoteDuration))
                    .font(Theme.Typography.monoMetric)
                    .foregroundColor(Theme.textPrimary)
                    .frame(minWidth: 38, alignment: .leading)
            }

            // Real-time animated waveform or encoding/sending label
            if viewModel.isSendingVoiceNote {
                Text("Đang gửi ghi âm…")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                AudioWaveformMeter(
                    levels: viewModel.voiceNoteMeterLevels,
                    barCount: 24,
                    isRecording: viewModel.isRecordingVoiceNote
                )
            }

            // Send direct-audio voice note
            Button {
                HapticFeedback.medium()
                viewModel.sendVoiceNoteRecording()
            } label: {
                Group {
                    if viewModel.isSendingVoiceNote {
                        ProgressView()
                            .tint(Theme.ctaForeground)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Theme.ctaForeground)
                    }
                }
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.buttonGradient))
                .shadow(color: Theme.glow.opacity(0.45), radius: 8, y: 2)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSendingVoiceNote)
            .accessibilityLabel("Gửi tin nhắn thoại tới Reybain")
        }
    }

    private func formatRecordingDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
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
                .tint(Theme.accentBright)
                .scaleEffect(0.8)
            Text(text)
                .font(Theme.Typography.badge)
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .liquidGlassPill(tint: Theme.accent)
    }

    private func inlineErrorBanner(_ message: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.danger)
            Text(message)
                .font(.footnote)
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đóng thông báo lỗi")
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 16, style: .tinted(Theme.danger))
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
                Theme.bg.ignoresSafeArea()
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
                        .foregroundColor(Theme.accentBright)
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
