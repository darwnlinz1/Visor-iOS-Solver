// OpenVision - OpenVisionApp.swift
// App entry point with URL scheme handling for Meta AI registration

import SwiftUI
import MWDATCore

@main
struct OpenVisionApp: App {
    // MARK: - State Objects

    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var glassesManager = GlassesManager.shared
    @StateObject private var conversationManager = ConversationManager.shared

    // MARK: - App Storage

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Initialization

    init() {
        // Initialize Meta Wearables SDK. The outcome goes to WearablesBootstrap: GlassesManager
        // touches Wearables.shared only after a successful configure(), so a failure leaves the
        // app running without glasses instead of trapping at launch (PLAN.md N2).
        if WearablesBootstrap.simulatesConfigureFailure {
            WearablesBootstrap.configureFailed("mô phỏng lỗi (OPENVISION_SIMULATE_DAT_CONFIG_FAILURE=1)")
            AppLog.warning(.app, "Debug: Wearables.configure() skipped (OPENVISION_SIMULATE_DAT_CONFIG_FAILURE=1)")
        } else {
            do {
                try Wearables.configure()
                WearablesBootstrap.configureSucceeded()
                AppLog.info(.app, "Wearables SDK configured")
            } catch {
                WearablesBootstrap.configureFailed(error.localizedDescription)
                // Only whether each MWDAT key is set is logged, never its value (ClientToken is a secret).
                let mwdat = Bundle.main.object(forInfoDictionaryKey: "MWDAT") as? [String: Any] ?? [:]
                let keys = mwdat.keys.sorted().map { (key: String) -> String in
                    let value = String(describing: mwdat[key] ?? "")
                    return key + "=" + (value.isEmpty ? "empty" : "set")
                }.joined(separator: ", ")
                AppLog.error(.app, "Failed to configure Wearables SDK: \(String(describing: error)) | MWDAT keys: \(keys)")
            }
        }
        AppLog.info(.app, "Initialized")
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
            }
            .environmentObject(settingsManager)
            .environmentObject(glassesManager)
            .environmentObject(conversationManager)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                handleURL(url)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background || phase == .inactive {
                    settingsManager.saveNow()
                }
            }
        }
    }

    // MARK: - URL Handling

    /// Handle URL callback from Meta AI app for glasses registration
    private func handleURL(_ url: URL) {
        let scheme = url.scheme ?? "none"
        let host = url.host ?? "none"
        AppLog.info(.app, "Received callback URL (scheme=\(scheme), host=\(host))")
        guard WearablesBootstrap.isConfigured else {
            AppLog.warning(.app, "Ignoring the URL: \(GlassesManager.sdkUnavailableMessage)")
            return
        }

        Task {
            do {
                _ = try await Wearables.shared.handleUrl(url)
                AppLog.info(.app, "URL handled successfully")
            } catch {
                AppLog.error(.app, "Error handling URL: \(error.localizedDescription)")
            }
        }
    }
}
