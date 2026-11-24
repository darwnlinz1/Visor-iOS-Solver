// OpenVision - GlassesSettingsView.swift
// Ray-Ban Meta: registration, the capture button routed to the app, photo quality, status.

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
            registrationSection

            if glassesManager.isRegistered {
                captureButtonSection
                photoSection
                statusSection
                toolsSection
            }

            Section {
                Link(destination: URL(string: "https://wearables.developer.meta.com/docs/develop/")!) {
                    HStack {
                        Text("Tài liệu Meta Wearables")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                }
                NavigationLink {
                    TroubleshootingView()
                } label: {
                    Text("Khắc phục sự cố")
                }
            } header: {
                Text("Trợ giúp")
            }
        }
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
            Text("OpenVision sẽ ngắt khỏi kính. Bạn cần đăng ký lại qua app Meta AI để dùng tiếp.")
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

    // MARK: - Sections

    private var registrationSection: some View {
        Section {
            // Wearables.configure() failed at launch: nothing below can work until a restart.
            if let reason = glassesManager.sdkUnavailableReason {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundColor(Theme.danger)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reason)
                            .font(.subheadline)
                            .foregroundColor(Theme.danger)
                        Text("Các tính năng kính tắt cho tới khi mở lại app.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if glassesManager.isRegistered {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.success)
                    Text("Đã đăng ký")
                        .foregroundColor(Theme.success)
                    Spacer()
                    Button("Huỷ đăng ký") {
                        showingUnregisterConfirmation = true
                    }
                    .foregroundColor(Theme.danger)
                    .font(.caption)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Đăng ký với app Meta AI để OpenVision dùng được kính.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button {
                        register()
                    } label: {
                        HStack {
                            Spacer()
                            if isRegistering {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Đang mở Meta AI…")
                            } else {
                                Image(systemName: "person.badge.plus")
                                Text("Đăng ký app")
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRegistering || glassesManager.sdkUnavailableReason != nil)
                }
            }

            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.warning)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Theme.warning)
                }
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
            }

            if settingsManager.settings.captureButtonEnabled {
                HStack {
                    Text("Trạng thái")
                    Spacer()
                    Circle()
                        .fill(glassesManager.isButtonLinkActive ? Theme.success : Theme.inactive)
                        .frame(width: 8, height: 8)
                    Text(glassesManager.connectionPhase.displayText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if glassesManager.connectedDevice != nil {
                    Button {
                        HapticFeedback.light()
                        Task { await glassesManager.reconnectButtonLink() }
                    } label: {
                        Label("Kết nối lại nút kính", systemImage: "arrow.clockwise")
                    }
                }

                NavigationLink {
                    WorkflowModeSettingsView()
                } label: {
                    HStack {
                        Label("Chế độ sử dụng", systemImage: settingsManager.settings.usageMode.systemImage)
                        Spacer()
                        Text(settingsManager.settings.usageMode.displayName)
                            .font(.footnote)
                            .foregroundColor(Theme.accent)
                    }
                }

                Toggle(isOn: $settingsManager.settings.useCustomButtonMapping) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tùy chỉnh riêng từng thao tác nút")
                        Text("Tắt để tự động theo chế độ Giải bài / Bình thường")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if settingsManager.settings.useCustomButtonMapping {
                    Picker("Bấm 1 lần", selection: $settingsManager.settings.shortPressAction) {
                        ForEach(GlassesButtonAction.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Bấm 2 lần", selection: $settingsManager.settings.doublePressAction) {
                        ForEach(GlassesButtonAction.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Giữ nút", selection: $settingsManager.settings.holdAction) {
                        ForEach(GlassesButtonAction.allCases) { Text($0.displayName).tag($0) }
                    }
                } else {
                    HStack {
                        Text("Bấm 1 lần")
                        Spacer()
                        Text(GlassesWorkflowPolicy.action(for: .shortPress, settings: settingsManager.settings).displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Bấm 2 lần")
                        Spacer()
                        Text(GlassesWorkflowPolicy.action(for: .doublePress, settings: settingsManager.settings).displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Giữ nút")
                        Spacer()
                        Text(GlassesWorkflowPolicy.action(for: .hold, settings: settingsManager.settings).displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $settingsManager.settings.captureButtonIncludeTouchpad) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nhận cả bàn chạm (chỉ bật khi nút không phản hồi)")
                        Text("Cảnh báo: bật mục này sẽ can thiệp thao tác chạm dừng/phát nhạc trên gọng kính")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
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
                    Text(settingsManager.settings.fullResolutionPhotos ? "Mặc định: ảnh 12 MP nét nhất cho chữ nhỏ & công thức" : "Chụp nhanh từ luồng video (~1–2 giây)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                testPhoto()
            } label: {
                HStack {
                    Label("Chụp thử", systemImage: "camera")
                    Spacer()
                    if isTestingPhoto {
                        ProgressView()
                    } else if let testPhotoResult {
                        Text(testPhotoResult)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .disabled(isTestingPhoto || glassesManager.isTakingPhoto || glassesManager.connectedDevice == nil)
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
                Spacer()
                Text("\(glassesManager.connectedDeviceCount)")
                    .foregroundColor(.secondary)
            }
            if let device = glassesManager.connectedDevice {
                HStack {
                    Text("Thiết bị")
                    Spacer()
                    Text(device)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            HStack {
                Text("Camera")
                Spacer()
                if glassesManager.isTakingPhoto {
                    Text("Đang chụp…").foregroundColor(Theme.accent)
                } else if glassesManager.isStreaming {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.danger).frame(width: 8, height: 8)
                        Text("Đang bật").foregroundColor(Theme.danger)
                    }
                } else {
                    Text("Tắt").foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Trạng thái")
        }
    }

    private var toolsSection: some View {
        Section {
            // Stages/updates the on-glasses developer component via Meta AI. Sessions die with
            // "Device unavailable" when it is missing — this is the SDK's recovery path.
            Button {
                Task { await glassesManager.openDATGlassesAppUpdate() }
            } label: {
                Label("Cài/cập nhật thành phần trên kính", systemImage: "arrow.down.circle")
            }

            if glassesManager.isStreaming {
                Button {
                    Task { await glassesManager.stopStreaming() }
                } label: {
                    Label("Tắt camera kính", systemImage: "video.slash")
                }
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
                TroubleshootingItem(
                    title: "Đăng ký thất bại",
                    solution: "Bật Developer Mode trong app Meta AI rồi thử lại."
                )
            }

            Section("Nút chụp") {
                TroubleshootingItem(
                    title: "Bấm nút chụp mà app không phản hồi",
                    solution: "Xem Trạng thái trong mục Nút chụp. Nếu báo \"Meta chưa cho phép\", bật Developer Mode. Nếu \"Đang hoạt động\" mà vẫn im, bật \"Nhận cả bàn chạm\"."
                )
                TroubleshootingItem(
                    title: "Ảnh lâu mới tới",
                    solution: "Tắt \"Ảnh độ phân giải đầy đủ\" để dùng 1080p — nhanh hơn, vẫn đọc tốt chữ in."
                )
            }

            Section("Kết nối") {
                TroubleshootingItem(
                    title: "Không thấy kính",
                    solution: "Mở gọng kính, đeo vào, và kiểm tra kính đã kết nối Bluetooth với iPhone."
                )
                TroubleshootingItem(
                    title: "Camera không bật",
                    solution: "Đóng các app khác đang dùng kính (chỉ một app dùng được kính tại một thời điểm)."
                )
            }
        }
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
                .font(.subheadline)
                .fontWeight(.medium)
            Text(solution)
                .font(.caption)
                .foregroundColor(.secondary)
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
}
