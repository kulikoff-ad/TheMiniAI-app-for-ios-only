import SwiftUI

/// 🤗 Hugging Face — единый хаб с 5 вкладками: Discover / Search / Phone AI / Downloaded / Favorites
struct HuggingFaceHubView: View {
    @State private var tab: Tab = .discover
    enum Tab: String, CaseIterable, Identifiable {
        case discover = "Discover"
        case search = "Search"
        case phone = "Phone AI"
        case downloaded = "Downloaded"
        case favorites = "Favorites"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .discover: return "star"
            case .search: return "magnifyingglass"
            case .phone: return "iphone.gen3"
            case .downloaded: return "arrow.down.circle"
            case .favorites: return "heart"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $tab) {
                    ForEach(Tab.allCases) { t in
                        Label(t.rawValue, systemImage: t.icon).tag(t)
                    }
                }.pickerStyle(.segmented).padding(10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch tab {
                        case .discover: DiscoverView()
                        case .search: HuggingFaceBrowserView()
                        case .phone: PhoneAIView()
                        case .downloaded: DownloadedTab()
                        case .favorites: FavoritesTab()
                        }
                    }.padding(16)
                }
            }
            .screenBackground()
            .navigationTitle("🤗 Hugging Face")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct DiscoverView: View {
    @EnvironmentObject var hf: HuggingFaceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discover trending models").font(.headline)
            Text("Sorted by trending score. Tap a model to see its card, README, files and download specific artefacts.")
                .font(.caption).foregroundStyle(Theme.textDim)
            if hf.isSearching {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                ForEach(hf.results.prefix(10)) { m in
                    NavigationLink { HFModelDetailView(repoId: m.id) } label: { HFModelRow(model: m) }.buttonStyle(.plain)
                }
                if hf.results.isEmpty {
                    Text("No results yet — switch to Search or pull to refresh.").font(.caption).foregroundStyle(Theme.textDim)
                }
            }
        }
    }
}

struct DownloadedTab: View {
    @EnvironmentObject var library: ModelLibrary
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Downloaded", subtitle: "\(library.models.count) models on device")
            if library.models.isEmpty {
                EmptyStateView(icon: "arrow.down.circle", title: "No downloads yet", message: "Download from Search or Phone AI. Progress is shown as ████████░░ 78% 3.1 GB / 4.0 GB")
            } else {
                ForEach(library.sorted) { m in
                    NavigationLink { LocalModelDetailView(model: m) } label: { LocalModelRow(model: m) }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct FavoritesTab: View {
    @EnvironmentObject var library: ModelLibrary
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Favorites", subtitle: "\(library.favorites.count) starred")
            if library.favorites.isEmpty {
                EmptyStateView(icon: "heart", title: "No favorites", message: "Star a downloaded model to find it here quickly.")
            } else {
                ForEach(library.favorites) { m in
                    NavigationLink { LocalModelDetailView(model: m) } label: { LocalModelRow(model: m) }.buttonStyle(.plain)
                }
            }
        }
    }
}
