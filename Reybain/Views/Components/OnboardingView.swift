// Reybain - OnboardingView.swift
// iOS 26 Liquid Glass & Apple Intelligence first-run walkthrough branded Reybain:
// Iridescent SwirlOrb welcome, Direct-Audio Voice Note & Ray-Ban Meta features,
// numbered quick setup, and interactive Permissions & Gemini API key checklist.

import SwiftUI
import Photos
import Speech
import AVFoundation

struct OnboardingView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var glassesManager: GlassesManager

    @State private var currentPage = 0
    @Binding var hasCompletedOnboarding: Bool

    var body: some View {
        ZStack {
            AnimatedBackground()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    WelcomePage()
                        .tag(0)

                    FeaturesPage()
                        .tag(1)

                    SetupPage()
                        .tag(2)

                    PermissionsChecklistPage(hasCompletedOnboarding: $hasCompletedOnboarding)
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(Theme.Motion.fluid, value: currentPage)

                // Modern expanding capsule page indicator
                HStack(spacing: 7) {
                    ForEach(0..<4, id: \.self) { index in
                        let isSelected = currentPage == index
                        Capsule()
                            .fill(
                                isSelected
                                    ? AnyShapeStyle(Theme.intelligenceLinear)
                                    : AnyShapeStyle(Color.white.opacity(0.24))
                            )
                            .frame(width: isSelected ? 22 : 7, height: 7)
                            .animation(Theme.Motion.snappy, value: currentPage)
                    }
                }
                .padding(.bottom, 20)

                HStack {
                    if currentPage > 0 {
                        Button {
                            HapticFeedback.light()
                            withAnimation(Theme.Motion.snappy) { currentPage -= 1 }
                        } label: {
                            Text("Quay lại")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Theme.textSecondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .liquidGlassPill(interactive: true)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if currentPage < 3 {
                        Button {
                            HapticFeedback.light()
                            withAnimation(Theme.Motion.snappy) { currentPage += 1 }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Tiếp")
                                    .font(.subheadline.weight(.semibold))
                                Image(systemName: "arrow.right")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundColor(Theme.ctaForeground)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Theme.buttonGradient))
                            .shadow(color: Theme.glow.opacity(0.45), radius: 10, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    @State private var logoScale: CGFloat = 0.72
    @State private var logoOpacity: CGFloat = 0

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                SwirlOrb(mode: .speaking, size: 150)
                    .frame(width: 196, height: 196)

                Image(systemName: "eyeglasses")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .shadow(color: Theme.iridescentCyan.opacity(0.55), radius: 12)
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)

            VStack(spacing: 10) {
                Text("Reybain")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Theme.accentBright],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Trợ lý AI cho kính Ray-Ban Meta — chụp đề bài, ghi âm trực tiếp và nghe đọc lời giải tự nhiên bằng tiếng Việt.")
                    .font(.body)
                    .foregroundColor(Theme.textSecondary)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .opacity(logoOpacity)

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.72)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
        }
    }
}

// MARK: - Page 2: Features

private struct FeaturesPage: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            VStack(spacing: 6) {
                Text("Thông minh ở mọi nhịp học")
                    .font(.title2.weight(.bold))
                    .foregroundColor(Theme.textPrimary)
                Text("Thiết kế tối ưu cho kính Ray-Ban Meta và iPhone")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }

            VStack(spacing: 12) {
                FeatureRow(
                    icon: "checklist",
                    tint: Theme.accent,
                    title: "Trắc nghiệm đọc gọn đáp án",
                    description: "Đọc \"Câu 1: A. Câu 2: C. Câu 3: a đúng, b sai…\" không lan man."
                )

                FeatureRow(
                    icon: "function",
                    tint: Theme.info,
                    title: "Đọc công thức toán tiếng Việt",
                    description: "Tự luận đọc từng dòng có nghỉ, công thức tự nhiên (\"ích bình phương trừ 5 ích…\")."
                )

                FeatureRow(
                    icon: "waveform.badge.mic",
                    tint: Theme.iridescentViolet,
                    title: "Ghi âm trực tiếp & Đọc chép",
                    description: "Gửi thẳng âm thanh song ngữ Việt–Anh lên Gemini, hoặc dừng sau mỗi dòng chờ lệnh \"tiếp\"."
                )

                FeatureRow(
                    icon: "eyeglasses",
                    tint: Theme.iridescentCyan,
                    title: "Kính Ray-Ban Meta & Chat trực tiếp",
                    description: "Nhấn nút kính chụp ảnh 12 MP, phát ra loa kính khi đeo hoặc loa iPhone khi dùng trực tiếp."
                )
            }
            .padding(.horizontal, 22)

            Spacer()
            Spacer()
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let tint: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(tint.opacity(0.36), lineWidth: 0.8))

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)

                Text(description)
                    .font(.footnote)
                    .foregroundColor(Theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 18, style: .surface)
    }
}

// MARK: - Page 3: Quick Setup

private struct SetupPage: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            VStack(spacing: 6) {
                Text("Cách dùng nhanh")
                    .font(.title2.weight(.bold))
                    .foregroundColor(Theme.textPrimary)
                Text("Bốn bước để bắt đầu với Reybain")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }

            VStack(spacing: 12) {
                SetupStep(
                    number: 1,
                    title: "Dán API key Gemini",
                    description: "Vào Cài đặt → Gemini. Key được lưu an toàn tuyệt đối trong Keychain của máy."
                )

                SetupStep(
                    number: 2,
                    title: "Kết nối kính (tuỳ chọn)",
                    description: "Đăng ký Ray-Ban Meta qua app Meta AI, hoặc sử dụng ngay trên iPhone."
                )

                SetupStep(
                    number: 3,
                    title: "Chụp, ghi âm hoặc hỏi tự do",
                    description: "Bấm nút chụp trên kính, chạm nút micro để gửi ghi âm trực tiếp, hoặc gọi \"Ok Vision\"."
                )

                SetupStep(
                    number: 4,
                    title: "Nghe đọc & điều khiển nhịp",
                    description: "Màn hình hiện từng dòng và tô sáng đoạn đang đọc; chạm mục bất kỳ để nhảy tới."
                )
            }
            .padding(.horizontal, 22)

            Spacer()
            Spacer()
        }
    }
}

private struct SetupStep: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.buttonGradient)
                    .frame(width: 32, height: 32)
                    .shadow(color: Theme.glow.opacity(0.38), radius: 6, y: 2)

                Text("\(number)")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundColor(Theme.ctaForeground)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)

                Text(description)
                    .font(.footnote)
                    .foregroundColor(Theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 18, style: .surface)
    }
}

// MARK: - Page 4: Interactive Permissions & Setup Checklist

private struct PermissionsChecklistPage: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var glassesManager: GlassesManager
    @Binding var hasCompletedOnboarding: Bool

    @State private var micGranted = AVAudioApplication.shared.recordPermission == .granted
    @State private var speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
    @State private var photoGranted = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
    @State private var apiKeyDraft: String = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Spacer(minLength: 48)

                VStack(spacing: 6) {
                    Text("Quyền & Thiết lập")
                        .font(.title2.weight(.bold))
                        .foregroundColor(Theme.textPrimary)

                    Text("Cấp quyền cần thiết để Reybain nghe lệnh, ghi âm trực tiếp và đọc đề bài ngay lập tức.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 12) {
                    permissionCard(
                        icon: "mic.fill",
                        tint: Theme.info,
                        title: "Micro",
                        detail: "Ghi âm trực tiếp tới Gemini & nghe \"Ok Vision\"",
                        granted: micGranted,
                        buttonTitle: "Cấp quyền"
                    ) {
                        Task {
                            let ok = await AVAudioApplication.requestRecordPermission()
                            micGranted = ok
                        }
                    }

                    permissionCard(
                        icon: "waveform",
                        tint: Theme.iridescentViolet,
                        title: "Nhận dạng giọng nói",
                        detail: "Nghe từ đánh thức và điều khiển nhịp đọc trên máy",
                        granted: speechGranted,
                        buttonTitle: "Cấp quyền"
                    ) {
                        Task {
                            let ok = await VoiceCommandService.shared.requestAuthorization()
                            speechGranted = ok
                        }
                    }

                    permissionCard(
                        icon: "photo.on.rectangle",
                        tint: Theme.accent,
                        title: "Thư viện Ảnh (Toàn bộ)",
                        detail: "Đọc ảnh dự phòng từ album kính Ray-Ban Meta",
                        granted: photoGranted,
                        buttonTitle: "Cấp quyền"
                    ) {
                        Task {
                            _ = await RecentPhotoScanner.shared.requestAuthorizationIfNeeded()
                            photoGranted = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
                        }
                    }

                    // Inline Gemini API key quick setup
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            SettingsIconBadge(
                                icon: "sparkles",
                                tint: settingsManager.settings.isGeminiConfigured ? Theme.success : Theme.warning
                            )
                            Text("API key Gemini")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text(settingsManager.settings.isGeminiConfigured ? "Đã lưu" : "Cần dán key")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(settingsManager.settings.isGeminiConfigured ? Theme.success : Theme.warning)
                        }

                        HStack(spacing: 8) {
                            SecureField("Dán key Google AI Studio (có thể để sau)…", text: $apiKeyDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.footnote)
                                .foregroundColor(Theme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Theme.bgElevated)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(Theme.bgElevatedStroke, lineWidth: 0.8)
                                        )
                                )

                            if !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button("Lưu") {
                                    settingsManager.settings.geminiAPIKey = GeminiLiveService.parseKeys(apiKeyDraft).joined(separator: ", ")
                                    settingsManager.saveNow()
                                    HapticFeedback.success()
                                }
                                .font(.caption.weight(.bold))
                                .foregroundColor(Theme.ctaForeground)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Capsule().fill(Theme.buttonGradient))
                            }
                        }
                    }
                    .padding(14)
                    .liquidGlassCard(cornerRadius: 18, style: .surface)
                }
                .padding(.horizontal, 22)

                Button {
                    HapticFeedback.medium()
                    if !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        settingsManager.settings.geminiAPIKey = GeminiLiveService.parseKeys(apiKeyDraft).joined(separator: ", ")
                        settingsManager.saveNow()
                    }
                    withAnimation(Theme.Motion.fluid) {
                        hasCompletedOnboarding = true
                    }
                } label: {
                    Text("Bắt đầu sử dụng")
                        .font(.headline)
                        .foregroundColor(Theme.ctaForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Theme.buttonGradient))
                        .shadow(color: Theme.glow.opacity(0.45), radius: 14, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 10)

                Spacer(minLength: 24)
            }
        }
        .onAppear {
            apiKeyDraft = settingsManager.settings.geminiAPIKey
            micGranted = AVAudioApplication.shared.recordPermission == .granted
            speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
            photoGranted = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
        }
    }

    private func permissionCard(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        granted: Bool,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            SettingsIconBadge(icon: icon, tint: granted ? Theme.success : tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(Theme.success)
            } else {
                Button(buttonTitle, action: action)
                    .font(.caption.weight(.bold))
                    .foregroundColor(Theme.ctaForeground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.buttonGradient))
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 18, style: .surface)
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(SettingsManager.shared)
        .environmentObject(GlassesManager.shared)
        .preferredColorScheme(.dark)
}
