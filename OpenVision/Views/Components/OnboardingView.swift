// OpenVision - OnboardingView.swift
// Redesigned v2 first-run walkthrough (PLAN.md §4.5, T6.6):
// Voice-first math & exam assistant copy (no KaTeX/phone-screen DISPLAY messaging)
// + Page 4 interactive permissions & setup checklist with live status and action buttons.

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
                .animation(.easeInOut, value: currentPage)

                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? Theme.accent : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .scaleEffect(currentPage == index ? 1.2 : 1.0)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 20)

                HStack {
                    if currentPage > 0 {
                        Button("Quay lại") {
                            withAnimation { currentPage -= 1 }
                        }
                        .foregroundColor(Theme.textSecondary)
                    }

                    Spacer()

                    if currentPage < 3 {
                        Button {
                            withAnimation { currentPage += 1 }
                        } label: {
                            HStack {
                                Text("Tiếp")
                                Image(systemName: "arrow.right")
                            }
                            .foregroundColor(.black.opacity(0.9))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Theme.buttonGradient))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Welcome Page

private struct WelcomePage: View {
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: CGFloat = 0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Theme.accentBright.opacity(0.3), Theme.accentDeep.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: CGFloat(120 + i * 40), height: CGFloat(120 + i * 40))
                        .opacity(logoOpacity * (1 - Double(i) * 0.3))
                }

                Circle()
                    .fill(Theme.buttonGradient)
                    .frame(width: 100, height: 100)
                    .shadow(color: Theme.glow.opacity(0.5), radius: 20)

                Image(systemName: "eyeglasses")
                    .font(.system(size: 44))
                    .foregroundColor(.white)
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)

            VStack(spacing: 8) {
                Text("OpenVision")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)

                Text("Chụp đề bài, hỏi tự do, nghe đọc lời giải trọn vẹn bằng tiếng Việt.")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .opacity(logoOpacity)

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
        }
    }
}

// MARK: - Features Page

private struct FeaturesPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Đọc trọn vẹn mọi bài tập")
                .font(.title.bold())
                .foregroundColor(.white)

            VStack(spacing: 16) {
                FeatureRow(
                    icon: "checklist",
                    title: "Trắc nghiệm đọc gọn đáp án",
                    description: "Đọc \"Câu 1: A. Câu 2: C. Câu 3: a đúng, b sai…\" không lan man."
                )

                FeatureRow(
                    icon: "function",
                    title: "Đọc công thức toán tiếng Việt",
                    description: "Tự luận đọc từng dòng có nghỉ, công thức tự nhiên (\"ích bình phương trừ 5 ích…\")."
                )

                FeatureRow(
                    icon: "pencil.and.outline",
                    title: "Điều khiển nhịp đọc & Đọc chép",
                    description: "Ra lệnh tạm dừng, chậm lại, đọc lại câu 3, hoặc dừng sau mỗi dòng chờ \"tiếp\"."
                )

                FeatureRow(
                    icon: "speaker.wave.2.fill",
                    title: "Kính Ray-Ban Meta & Chat trực tiếp",
                    description: "Tự phát ra loa kính khi đeo, hoặc loa ngoài iPhone khi gõ trực tiếp."
                )
            }
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.2))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
    }
}

// MARK: - Setup Page

private struct SetupPage: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("Cách dùng nhanh")
                .font(.title.bold())
                .foregroundColor(.white)

            VStack(spacing: 18) {
                SetupStep(
                    number: 1,
                    title: "Dán API key Gemini",
                    description: "Vào Cài đặt → Gemini. Key lưu an toàn trong Keychain của máy."
                )

                SetupStep(
                    number: 2,
                    title: "Kết nối kính (tuỳ chọn)",
                    description: "Đăng ký Ray-Ban Meta qua Meta AI, hoặc dùng ngay trên iPhone."
                )

                SetupStep(
                    number: 3,
                    title: "Chụp & hỏi tự do",
                    description: "Bấm nút chụp rồi nói \"Ok Vision\" + câu hỏi, hoặc gõ câu hỏi trực tiếp."
                )

                SetupStep(
                    number: 4,
                    title: "Nghe đọc & điều khiển",
                    description: "Màn hình hiện đủ từng dòng và tô sáng đoạn đang đọc; chạm mục bất kỳ để nhảy tới."
                )
            }
            .padding(.horizontal, 24)

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
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.buttonGradient)
                    .frame(width: 34, height: 34)

                Text("\(number)")
                    .font(.headline)
                    .foregroundColor(.black.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }

            Spacer()
        }
    }
}

// MARK: - Page 4: Interactive Permissions & Setup Checklist (PLAN.md §4.5, T6.6)

private struct PermissionsChecklistPage: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var glassesManager: GlassesManager
    @Binding var hasCompletedOnboarding: Bool

    @State private var micGranted = AVAudioApplication.shared.recordPermission == .granted
    @State private var speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
    @State private var photoGranted = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
    @State private var apiKeyDraft: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 48)

                Text("Quyền & Thiết lập")
                    .font(.title.bold())
                    .foregroundColor(.white)

                Text("Cấp quyền cần thiết để OpenVision nghe lệnh và đọc đề bài ngay lập tức.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    permissionCard(
                        icon: "mic.fill",
                        title: "Micro",
                        detail: "Nghe \"Ok Vision\" và câu hỏi của bạn",
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
                        title: "Nhận dạng giọng nói",
                        detail: "Chuyển giọng nói thành văn bản ngay trên máy",
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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(settingsManager.settings.isGeminiConfigured ? Theme.success : Theme.warning)
                            Text("API key Gemini")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Text(settingsManager.settings.isGeminiConfigured ? "Đã lưu" : "Cần dán key")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(settingsManager.settings.isGeminiConfigured ? Theme.success : Theme.warning)
                        }
                        HStack {
                            SecureField("Dán key Google AI Studio (có thể để sau)…", text: $apiKeyDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.footnote)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                            if !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button("Lưu") {
                                    settingsManager.settings.geminiAPIKey = GeminiLiveService.parseKeys(apiKeyDraft).joined(separator: ", ")
                                    settingsManager.saveNow()
                                    HapticFeedback.success()
                                }
                                .font(.caption.weight(.bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Theme.buttonGradient))
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    )
                }
                .padding(.horizontal, 24)

                Button {
                    if !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        settingsManager.settings.geminiAPIKey = GeminiLiveService.parseKeys(apiKeyDraft).joined(separator: ", ")
                        settingsManager.saveNow()
                    }
                    withAnimation {
                        hasCompletedOnboarding = true
                    }
                } label: {
                    Text("Bắt đầu sử dụng")
                        .font(.headline)
                        .foregroundColor(.black.opacity(0.92))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Theme.buttonGradient))
                        .shadow(color: Theme.glow.opacity(0.3), radius: 10)
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)

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
        title: String,
        detail: String,
        granted: Bool,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(granted ? Theme.success : Theme.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(Theme.success)
            } else {
                Button(buttonTitle, action: action)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.black.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.buttonGradient))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(SettingsManager.shared)
        .environmentObject(GlassesManager.shared)
        .preferredColorScheme(.dark)
}
