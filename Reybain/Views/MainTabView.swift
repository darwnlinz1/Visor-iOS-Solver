// Reybain - MainTabView.swift
// Main tab navigation shell with floating iOS 26 Liquid Glass dock (Trực tiếp | Lịch sử | Cài đặt).
// Preserves `TabView` so `VoiceAgentViewModel` stays alive across tab switches.

import SwiftUI

enum SettingsDestination: Hashable {
    case workflowMode
    case glasses
    case gemini
    case voice
    case reading
    case mathSpeech
    case debug
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: MainTabView.Tab = .live
    @Published var settingsPath = NavigationPath()
    @Published var isTabBarHidden: Bool = false

    func openSettings(_ destination: SettingsDestination? = nil) {
        isTabBarHidden = false
        selectedTab = .settings
        settingsPath = NavigationPath()
        if let destination {
            settingsPath.append(destination)
        }
    }

    func openLive() {
        selectedTab = .live
    }
}

struct MainTabView: View {
    // MARK: - Environment

    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var glassesManager: GlassesManager
    @EnvironmentObject var conversationManager: ConversationManager

    // MARK: - Observed Live Indicators

    @ObservedObject private var voiceCommandService = VoiceCommandService.shared
    @ObservedObject private var readingEngine = ReadingEngine.shared

    // MARK: - Router

    @StateObject private var router = AppRouter()

    // MARK: - Tab Enum

    enum Tab: String, CaseIterable {
        case live = "Trực tiếp"
        case history = "Lịch sử"
        case settings = "Cài đặt"

        var icon: String {
            switch self {
            case .live: return "waveform.circle.fill"
            case .history: return "clock.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    private var shouldShowTabBar: Bool {
        !(router.selectedTab == .live && router.isTabBarHidden)
    }

    private var isLiveSessionRunning: Bool {
        voiceCommandService.isListening || readingEngine.isActive
    }

    // MARK: - Body

    var body: some View {
        TabView(selection: $router.selectedTab) {
            VoiceAgentView()
                .toolbar(.hidden, for: .tabBar)
                .tag(Tab.live)

            ConversationListView()
                .toolbar(.hidden, for: .tabBar)
                .tag(Tab.history)

            SettingsView()
                .toolbar(.hidden, for: .tabBar)
                .tag(Tab.settings)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowTabBar {
                LiquidGlassFloatingTabBar(
                    selectedTab: $router.selectedTab,
                    isLiveActive: isLiveSessionRunning
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.snappy, value: shouldShowTabBar)
        .environmentObject(router)
        .tint(Theme.accent)
        .background(Theme.bg.ignoresSafeArea())
    }
}

#Preview {
    MainTabView()
        .environmentObject(SettingsManager.shared)
        .environmentObject(GlassesManager.shared)
        .environmentObject(ConversationManager.shared)
        .preferredColorScheme(.dark)
}
