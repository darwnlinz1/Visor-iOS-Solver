// Reybain - GlassesSettingsView.swift
// Ray-Ban Meta hardware status hero card, Meta AI registration, capture button routing,
// photo quality, and troubleshooting — styled in OLED obsidian & Liquid Glass.

import SwiftUI
import MWDATCore

struct GlassesSettingsView: View {
    // MARK: - Environment

    @EnvironmentObject var glassesManager: GlassesManager
    @EnvironmentObject var settingsManager: SettingsManager

    // MARK: - State

    @State private var isRegistering: Bool = false
    @State private var errorMessage: String?
    @State private var showingUnregisterConfirmation: Bool = false
    @State private var testPhotoResult: String?
    @State private var isTestingPhoto = false

    // MARK: - Body

    var body: some View {
        Form {
            hardwareHeroSection
            registrationSection

            if glassesManager.isRegistered {
                captureButtonSection
                photoSection
                statusSection
                toolsSection
            }

            Section {
                Link(destination: URL(string: "https://wearables.developer.meta.com/docs/develop/")!) {
                    HStack(spacing: 12) {
                        SettingsIconBadge(icon: "book.closed.fill", tint: Theme.accent)
                        Text("Tài liệu Meta Wearables")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                .reybainSettingsRow()

                NavigationLink {
                    TroubleshootingView()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconBadge(icon: "wrench.and.screwdriver.fill", tint: Theme.warning)
                        Text("Khắc phục sự cố")
                            .foregroundColor(Theme.textPrimary)
                    }
                }
                .reybainSettingsRow()
            } header: {
                Text("Trợ giúp")
            }
        }
        .reybainSettingsCanvas()
        .navigationTitle("Kính Ray-Ban Meta")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settingsManager.settings.captureButtonEnabled) { _, _ in applyButtonLink() }
        .onChange(of: settingsManager.settings.captureButtonIncludeTouchpad) { _, _ in applyButtonLink() }
        .onChange(of: settingsManager.settings.fullResolutionPhotos) { _, _ in glassesManager.resetPhotoFailures() }
        .confirmationDialog(
            "Huỷ đăng ký kính",
            isPresented: $showingUnregisterConfirmation,
            titleVisibility: .visible
        ) {
            Button("Huỷ đăng ký", role: .destructive) {
                Task { await glassesManager.unregister() }
            }
            Button("Không", role: .cancel) {}
        } message: {
            Text("Reybain sẽ ngắt khỏi kính. Bạn cần đăng ký lại qua app Meta AI để dùng tiếp.")
        }
        .alert(
            "Lỗi",
            isPresented: Binding(
                get: { glassesManager.errorMessage != nil },
                set: { if !$0 { glassesManager.errorMessage = nil } }
            )
        ) {
            Button("OK") { glassesManager.errorMessage = nil }
        } message: {
            if let error = glassesManager.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Hardware Status Hero Card

    private var heroStatusTint: Color {
        if glassesManager.sdkUnavailableReason != nil { return Theme.danger }
        if glassesManager.connectedDevice != nil { return Theme.success }
        return glassesManager.isRegistered ? Theme.warning : Theme.inactive
    }

    private var heroStatusTitle: String {
        if glassesManager.sdkUnavailableReason != nil { return "SDK không khả dụng" }
        if glassesManager.connectedDevice != nil { return "Đã kết nối kính" }
        return glassesManager.isRegistered ? "Đã đăng ký · Chờ kết nối" : "Chưa đăng ký kính"
    }

    private var hardwareHeroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(heroStatusTint.opacity(0.18))
                            .frame(width: 48, height: 48)
                            .overlay(Circle().strokeBorder(heroStatusTint.opacity(0.45), lineWidth: 1))

                        Image(systemName: "eyeglasses")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(heroStatusTint)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(heroStatusTint)
                                .frame(width: 7.5, height: 7.5)
                                .shadow(color: heroStatusTint.opacity(0.75), radius: 4)
                            Text(heroStatusTitle)
                                .font(.headline)
                                .foregroundColor(Theme.textPrimary)
                        }

                        Text(glassesManager.connectedDevice ?? "Ray-Ban Meta Smart Glasses")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }

                if glassesManager.isRegistered {
                    HStack(spacing: 8) {
                        Label(glassesManager.connectionPhase.displayText, systemImage: "camera.shutter.button")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(Theme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7))
                            )

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
            .liquidGlassCard(cornerRadius: Theme.Radius.card, style: .tinted(heroStatusTint))
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Sections

    private var registrationSection: some View {
        Section {
            // Wearables.configure() failed at launch: nothing below can work until a restart.
            if let reason = glassesManager.sdkUnavailableReason {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundColor(Theme.danger)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reason)
                            .font(.subheadline)
                            .foregroundColor(Theme.danger)
                        Text("Các tính năng kính tắt cho tới khi mở lại app.")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()
            }

            if glassesManager.isRegistered {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.success)
                    Text("Đã đăng ký với Meta AI")
                        .foregroundColor(Theme.success)
                    Spacer()
                    Button("Huỷ đăng ký") {
                        showingUnregisterConfirmation = true
                    }
                    .foregroundColor(Theme.danger)
                    .font(.caption.weight(.semibold))
                }
                .reybainSettingsRow()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Đăng ký với app Meta AI để Reybain dùng được kính.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)

                    Button {
                        register()
                    } label: {
                        HStack(spacing: 8) {
                            Spacer()
                            if isRegistering {
                                ProgressView()
                                    .tint(Theme.ctaForeground)
                                Text("Đang mở Meta AI…")
                            } else {
                                Image(systemName: "person.badge.plus")
                                Text("Đăng ký app")
                            }
                            Spacer()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.ctaForeground)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Theme.buttonGradient))
                        .shadow(color: Theme.glow.opacity(0.40), radius: 8, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRegistering || glassesManager.sdkUnavailableReason != nil)
                    .opacity((isRegistering || glassesManager.sdkUnavailableReason != nil) ? 0.55 : 1.0)
                }
                .padding(.vertical, 4)
                .reybainSettingsRow()
            }

            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.warning)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Theme.warning)
                }
                .reybainSettingsRow()
            }
        } header: {
            Text("Đăng ký")
        } footer: {
            Text("Bật Developer Mode trong app Meta AI (Cài đặt → Thiết bị → Kính → Developer Mode) trước khi đăng ký.")
        }
    }

    private var captureButtonSection: some View {
        Section {
            Toggle(isOn: $settingsManager.settings.captureButtonEnabled) {
                Label("Nút chụp & Action gửi thẳng vào app", systemImage: "camera.shutter.button")
                    .foregroundColor(Theme.textPrimary)
            }
            .reybainSettingsRow()

            if settingsManager.settings.captureButtonEnabled {
                HStack {
                    Text("Trạng thái")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Circle()
                        .fill(glassesManager.isButtonLinkActive ? Theme.success : Theme.inactive)
                        .frame(width: 8, height: 8)
                    Text(glassesManager.connectionPhase.displayText)
                        .font(.footnote)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
                .reybainSettingsRow()

                if glassesManager.connectedDevice != nil {
                    Button {
                        HapticFeedback.light()
                        Task { await glassesManager.reconnectButtonLink() }
                    } label: {
                        Label("Kết nối lại nút kính", systemImage: "arrow.clockwise")
                            .foregroundColor(Theme.accentBright)
                    }
                    .reybainSettingsRow()
                }

                NavigationLink {
                    WorkflowModeSettingsView()
                } label: {
                    HStack {
                        Label("Chế độ sử dụng", systemImage: settingsManager.settings.usageMode.systemImage)
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text(settingsManager.settings.usageMode.displayName)
                            .font(.footnote)
                            .foregroundColor(Theme.accentBright)
                    }
                }
                .reybainSettingsRow()

                Toggle(isOn: $settingsManager.settings.useCustomButtonMapping) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tùy chỉnh riêng từng thao tác nút")
                            .foregroundColor(Theme.textPrimary)
                        Text("Tắt để tự động theo chế độ Giải bài / Bình thường")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()

                if settingsManager.settings.useCustomButtonMapping {
                    Picker("Bấm 1 lần", selection: $settingsManager.settings.shortPressAction) {
                        ForEach(GlassesButtonAction.allCases) { Text($0.displayName).tag($0) }
                    }
                    .reybainSettingsRow()

                    Picker("Bấm 2 lần", selection: $settingsManager.settings.doublePressAction) {
                        ForEach(GlassesButtonAction.allCases) { Text($0.displayName).tag($0) }
                    }
                    .reybainSettingsRow()

                    Picker("Giữ nút", selection: $settingsManager.settings.holdAction) {
                        ForEach(GlassesButtonAction.allCases) { Text($0.displayName).tag($0) }
                    }
                    .reybainSettingsRow()
                } else {
                    HStack {
                        Text("Bấm 1 lần")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text(GlassesWorkflowPolicy.action(for: .shortPress, settings: settingsManager.settings).displayName)
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .reybainSettingsRow()

                    HStack {
                        Text("Bấm 2 lần")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text(GlassesWorkflowPolicy.action(for: .doublePress, settings: settingsManager.settings).displayName)
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .reybainSettingsRow()

                    HStack {
                        Text("Giữ nút")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text(GlassesWorkflowPolicy.action(for: .hold, settings: settingsManager.settings).displayName)
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .reybainSettingsRow()
                }

                Toggle(isOn: $settingsManager.settings.captureButtonIncludeTouchpad) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nhận cả bàn chạm (chỉ bật khi nút không phản hồi)")
                            .foregroundColor(Theme.textPrimary)
                        Text("Cảnh báo: bật mục này sẽ can thiệp thao tác chạm dừng/phát nhạc trên gọng kính")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .reybainSettingsRow()
            }
        } header: {
            Text("Nút chụp & Action trên kính")
        } footer: {
            Text("Hỗ trợ cả nút chụp (Capture) và nút Action mà không chiếm bàn chạm nghe nhạc. Nếu kính đang tắt Developer Mode hoặc mất kết nối nút, app tự dự phòng bằng ảnh mới nhất trong album Meta của Thư viện.")
        }
    }

    private var photoSection: some View {
        Section {
            Toggle(isOn: $settingsManager.settings.fullResolutionPhotos) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ảnh độ phân giải tối đa (~12 MP)")
                        .foregroundColor(Theme.textPrimary)
                    Text(settingsManager.settings.fullResolutionPhotos ? "Mặc định: ảnh 12 MP nét nhất cho chữ nhỏ & công thức" : "Chụp nhanh từ luồng video (~1–2 giây)")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .reybainSettingsRow()

            Button {
                testPhoto()
            } label: {
                HStack {
                    Label("Chụp thử", systemImage: "camera")
                        .foregroundColor(Theme.accentBright)
                    Spacer()
                    if isTestingPhoto {
                        ProgressView()
                            .tint(Theme.accent)
                    } else if let testPhotoResult {
                        Text(testPhotoResult)
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            .disabled(isTestingPhoto || glassesManager.isTakingPhoto || glassesManager.connectedDevice == nil)
            .reybainSettingsRow()
        } header: {
            Text("Chất lượng ảnh")
        } footer: {
            Text("App tự giảm ảnh xuống 3072 px trước khi gửi Gemini (mức chi tiết tối đa Gemini dùng), nên ảnh gốc lớn chỉ làm truyền từ kính lâu hơn chứ không tốn thêm token.")
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                Text("Kính đang kết nối")
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text("\(glassesManager.connectedDeviceCount)")
                    .font(Theme.Typography.monoMetric)
                    .foregroundColor(Theme.textSecondary)
            }
            .reybainSettingsRow()

            if let device = glassesManager.connectedDevice {
                HStack {
                    Text("Thiết bị")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text(device)
                        .font(.footnote)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .reybainSettingsRow()
            }

            HStack {
                Text("Camera")
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if glassesManager.isTakingPhoto {
                    Text("Đang chụp…").foregroundColor(Theme.accentBright)
                } else if glassesManager.isStreaming {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.danger).frame(width: 8, height: 8)
                        Text("Đang bật").foregroundColor(Theme.danger)
                    }
                } else {
                    Text("Tắt").foregroundColor(Theme.textSecondary)
                }
            }
            .reybainSettingsRow()
        } header: {
            Text("Trạng thái")
        }
    }

    private var toolsSection: some View {
        Section {
            // Stages/updates the on-glasses developer component via Meta AI.
            Button {
                Task { await glassesManager.openDATGlassesAppUpdate() }
            } label: {
                Label("Cài/cập nhật thành phần trên kính", systemImage: "arrow.down.circle")
                    .foregroundColor(Theme.accentBright)
            }
            .reybainSettingsRow()

            if glassesManager.isStreaming {
                Button {
                    Task { await glassesManager.stopStreaming() }
                } label: {
                    Label("Tắt camera kính", systemImage: "video.slash")
                        .foregroundColor(Theme.danger)
                }
                .reybainSettingsRow()
            }
        } header: {
            Text("Công cụ")
        } footer: {
            Text("Dùng khi kính báo \"Device unavailable\" hoặc phiên kết nối bị ngắt ngay.")
        }
    }

    // MARK: - Methods

    private func applyButtonLink() {
        let settings = settingsManager.settings
        Task { await glassesManager.applySettings(settings) }
    }

    private func testPhoto() {
        isTestingPhoto = true
        testPhotoResult = nil
        let full = settingsManager.settings.fullResolutionPhotos
        Task {
            let started = Date()
            if let data = await glassesManager.captureFullResolutionPhoto(fullResolution: full) {
                let size = UIImage(data: data).map { "\(Int($0.size.width * $0.scale))×\(Int($0.size.height * $0.scale))" } ?? "?"
                let source = glassesManager.lastPhotoSource ?? "glasses"
                testPhotoResult = String(format: "%@ · %@ · %.1f s", source, size, Date().timeIntervalSince(started))
            } else {
                testPhotoResult = "Không chụp được"
            }
            isTestingPhoto = false
        }
    }

    private func register() {
        isRegistering = true
        errorMessage = nil

        Task {
            do {
                try await glassesManager.register()
                isRegistering = false
            } catch {
                isRegistering = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Troubleshooting View

struct TroubleshootingView: View {
    var body: some View {
        List {
            Section("Đăng ký") {
                TroubleshootingItem(
                    title: "App Meta AI không mở",
                    solution: "Cài app Meta AI và đăng nhập."
                )
                .reybainSettingsRow()

                TroubleshootingItem(
                    title: "Đăng ký thất bại",
                    solution: "Bật Developer Mode trong app Meta AI (Cài đặt → Thông tin ứng dụng → chạm số phiên bản 5 lần). Nếu trước đó bạn từng đăng ký app cũ (như OpenVision), hãy hủy kết nối app cũ trong Meta AI → Kết nối ứng dụng → Developer Mode rồi thử đăng ký lại Reybain."
                )
                .reybainSettingsRow()
            }

            Section("Nút chụp") {
                TroubleshootingItem(
                    title: "Bấm nút chụp mà app không phản hồi",
                    solution: "Xem Trạng thái trong mục Nút chụp. Nếu báo \"Meta chưa cho phép\", bật Developer Mode. Nếu \"Đang hoạt động\" mà vẫn im, bật \"Nhận cả bàn chạm\"."
                )
                .reybainSettingsRow()

                TroubleshootingItem(
                    title: "Ảnh lâu mới tới",
                    solution: "Tắt \"Ảnh độ phân giải đầy đủ\" để dùng 1080p — nhanh hơn, vẫn đọc tốt chữ in."
                )
                .reybainSettingsRow()
            }

            Section("Kết nối") {
                TroubleshootingItem(
                    title: "Không thấy kính",
                    solution: "Mở gọng kính, đeo vào, và kiểm tra kính đã kết nối Bluetooth với iPhone."
                )
                .reybainSettingsRow()

                TroubleshootingItem(
                    title: "Camera không bật",
                    solution: "Đóng các app khác đang dùng kính (chỉ một app dùng được kính tại một thời điểm)."
                )
                .reybainSettingsRow()
            }
        }
        .reybainSettingsCanvas()
        .navigationTitle("Khắc phục sự cố")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TroubleshootingItem: View {
    let title: String
    let solution: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(Theme.textPrimary)
            Text(solution)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(2)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        GlassesSettingsView()
            .environmentObject(GlassesManager.shared)
            .environmentObject(SettingsManager.shared)
    }
    .preferredColorScheme(.dark)
}
