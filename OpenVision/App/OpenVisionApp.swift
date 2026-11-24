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
        let mwdatReport = MWDATConfigurationValidator.inspect(infoDictionary: Bundle.main.infoDictionary)
        // Initialize Meta Wearables SDK. The outcome goes to WearablesBootstrap: GlassesManager
        // touches Wearables.shared only after a successful configure(), so a failure leaves the
        // app running without glasses instead of trapping at launch (PLAN.md N2).
        if WearablesBootstrap.simulatesConfigureFailure {
            WearablesBootstrap.configureFailed("mô phỏng lỗi (OPENVISION_SIMULATE_DAT_CONFIG_FAILURE=1)")
            NSLog("[OpenVisionApp] Debug: Wearables.configure() skipped (OPENVISION_SIMULATE_DAT_CONFIG_FAILURE=1) | MWDAT: %@",
                  mwdatReport.logSummary)
        } else {
            do {
                try Wearables.configure()
                WearablesBootstrap.configureSucceeded()
                // Only redacted MWDAT state is logged, never raw ClientToken or TeamID values.
                NSLog("[OpenVisionApp] Wearables SDK configured | MWDAT: %@", mwdatReport.logSummary)
            } catch {
                WearablesBootstrap.configureFailed(error.localizedDescription)
                // NSLog, not print: print is buffered, NSLog reaches the console at once. Only
                // redacted MWDAT state is logged, never raw ClientToken or TeamID values.
                NSLog("[OpenVisionApp] Failed to configure Wearables SDK: %@ | MWDAT: %@",
                      String(describing: error), mwdatReport.logSummary)
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
    @MainActor
    private func handleURL(_ url: URL) {
        let summary = MWDATConfigurationValidator.redactedURLSummary(url)
        let registeredSchemes = glassesManager.mwdatConfigReport.registeredURLSchemes
        guard MWDATConfigurationValidator.shouldForwardToWearablesSDK(
            url,
            registeredSchemes: registeredSchemes
        ) else {
            NSLog("[OpenVisionApp] Ignoring non-MWDAT URL (%@)", summary)
            return
        }

        NSLog("[OpenVisionApp] Received Meta Wearables callback URL (%@)", summary)
        guard WearablesBootstrap.isConfigured else {
            NSLog("[OpenVisionApp] Ignoring Meta Wearables URL (%@): %@", summary, GlassesManager.sdkUnavailableMessage)
            return
        }

        let glassesManager = self.glassesManager
        Task { @MainActor in
            do {
                let handled = try await Wearables.shared.handleUrl(url)
                NSLog("[OpenVisionApp] Meta Wearables URL handled=%@ (%@)", handled ? "true" : "false", summary)
            } catch {
                NSLog("[OpenVisionApp] Error handling Meta Wearables URL (%@): %@", summary, String(describing: error))
                glassesManager.handleURLCallbackError(error)
            }
        }
    }
}
