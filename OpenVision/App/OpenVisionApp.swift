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

    // MARK: - Initialization

    init() {
        // Initialize Meta Wearables SDK. The outcome goes to WearablesBootstrap: GlassesManager
        // touches Wearables.shared only after a successful configure(), so a failure leaves the
        // app running without glasses instead of trapping at launch (PLAN.md N2).
        if WearablesBootstrap.simulatesConfigureFailure {
            WearablesBootstrap.configureFailed("mô phỏng lỗi (OPENVISION_SIMULATE_DAT_CONFIG_FAILURE=1)")
            NSLog("[OpenVisionApp] Debug: Wearables.configure() skipped (OPENVISION_SIMULATE_DAT_CONFIG_FAILURE=1)")
        } else {
            do {
                try Wearables.configure()
                WearablesBootstrap.configureSucceeded()
                print("[OpenVisionApp] Wearables SDK configured")
            } catch {
                WearablesBootstrap.configureFailed(error.localizedDescription)
                // NSLog, not print: print is buffered, NSLog reaches the console at once. Only
                // whether each MWDAT key is set is logged, never its value (ClientToken is a secret).
                let mwdat = Bundle.main.object(forInfoDictionaryKey: "MWDAT") as? [String: Any] ?? [:]
                let keys = mwdat.keys.sorted().map { (key: String) -> String in
                    let value = String(describing: mwdat[key] ?? "")
                    return key + "=" + (value.isEmpty ? "empty" : "set")
                }.joined(separator: ", ")
                NSLog("[OpenVisionApp] Failed to configure Wearables SDK: %@ | MWDAT keys: %@",
                      String(describing: error), keys)
            }
        }
        print("[OpenVisionApp] Initialized")
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                        .environmentObject(settingsManager)
                        .environmentObject(glassesManager)
                        .environmentObject(conversationManager)
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
            }
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                handleURL(url)
            }
        }
    }

    // MARK: - URL Handling

    /// Handle URL callback from Meta AI app for glasses registration
    private func handleURL(_ url: URL) {
        print("[OpenVisionApp] Received URL: \(url)")
        guard WearablesBootstrap.isConfigured else {
            print("[OpenVisionApp] Ignoring the URL: \(GlassesManager.sdkUnavailableMessage)")
            return
        }

        Task {
            do {
                _ = try await Wearables.shared.handleUrl(url)
                print("[OpenVisionApp] URL handled successfully")
            } catch {
                print("[OpenVisionApp] Error handling URL: \(error)")
            }
        }
    }
}
