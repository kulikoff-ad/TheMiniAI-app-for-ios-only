import SwiftUI
import UIKit

@main
struct AIAgentHubApp: App {

    @StateObject private var hf = HuggingFaceStore.shared
    @StateObject private var library = ModelLibrary.shared
    @StateObject private var downloads = DownloadManager.shared
    @StateObject private var agents = AgentStore.shared
    @StateObject private var github = GitHubStore.shared
    @StateObject private var runtime = AgentRuntime.shared
    @StateObject private var companion = CompanionClient.shared
    @StateObject private var online = OnlineProviderStore.shared

    init() {
        DownloadManager.shared.warmUp()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.bg)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.surface)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(hf)
                .environmentObject(library)
                .environmentObject(downloads)
                .environmentObject(agents)
                .environmentObject(github)
                .environmentObject(runtime)
                .environmentObject(companion)
                .environmentObject(online)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task {
                    await hf.refreshUser()
                    if github.isConnected { await github.connect() }
                    library.revalidate()
                    hf.search(debounced: false)
                }
        }
    }
}

struct RootTabView: View {
    @AppStorage("selectedTab") private var selection: Int = 0

    var body: some View {
        TabView(selection: $selection) {
            HomeView().tabItem { Label("Home", systemImage: "house") }.tag(0)
            HuggingFaceHubView().tabItem { Label("Hugging Face", systemImage: "face.smiling") }.tag(1)
            ModelsView().tabItem { Label("Models", systemImage: "cube.box") }.tag(2)
            AgentsView().tabItem { Label("Agents", systemImage: "cpu") }.tag(3)
            WorkspaceView().tabItem { Label("Workspace", systemImage: "square.split.2x1") }.tag(4)
            GitHubView().tabItem { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }.tag(5)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(6)
        }
    }
}
