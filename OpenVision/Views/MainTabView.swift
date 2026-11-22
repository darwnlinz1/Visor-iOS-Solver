// OpenVision - MainTabView.swift
// Main tab navigation in Vietnamese (PLAN.md §4.5, T6.1): Trực tiếp | Lịch sử | Cài đặt.

import SwiftUI

enum SettingsDestination: Hashable {
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

    func openSettings(_ destination: SettingsDestination? = nil) {
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

    // MARK: - Body

    var body: some View {
        TabView(selection: $router.selectedTab) {
            VoiceAgentView()
                .tabItem {
                    Label(Tab.live.rawValue, systemImage: Tab.live.icon)
                }
                .tag(Tab.live)

            ConversationListView()
                .tabItem {
                    Label(Tab.history.rawValue, systemImage: Tab.history.icon)
                }
                .tag(Tab.history)

            SettingsView()
                .tabItem {
                    Label(Tab.settings.rawValue, systemImage: Tab.settings.icon)
                }
                .tag(Tab.settings)
        }
        .environmentObject(router)
        .tint(Theme.accent)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(white: 0.05, alpha: 0.96)

            appearance.stackedLayoutAppearance.normal.iconColor = .gray
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray]

            let accent = UIColor(Theme.accent)
            appearance.stackedLayoutAppearance.selected.iconColor = accent
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accent]

            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(SettingsManager.shared)
        .environmentObject(GlassesManager.shared)
        .environmentObject(ConversationManager.shared)
        .preferredColorScheme(.dark)
}
