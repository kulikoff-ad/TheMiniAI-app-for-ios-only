import SwiftUI

struct ModelsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case discover = "Discover", downloaded = "Downloaded", running = "Running", favorites = "Favorites"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .discover
    @EnvironmentObject var library: ModelLibrary

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                switch tab {
                case .discover: DiscoverTab()
                case .downloaded: LocalModelListView(models: library.sorted, showSort: true)
                case .running: LocalModelListView(models: library.running, showSort: false,
                                                  emptyMessage: "No model is loaded right now. Start one from Downloaded.")
                case .favorites: LocalModelListView(models: library.favorites, showSort: false,
                                                    emptyMessage: "Mark models with the star to keep them here.")
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Models")
        }
    }
}

struct DiscoverTab: View {
    @EnvironmentObject var hf: HuggingFaceStore
    @State private var showFinder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink { HuggingFaceBrowserView() } label: {
                    HStack(spacing: 12) {
                        Text("🤗").font(.system(size: 34))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("HUGGING FACE")
                                .font(.system(size: 13, weight: .heavy)).tracking(1.6)
                                .foregroundStyle(Theme.accent)
                            Text("Search 1M+ models, inspect files, download exactly what you need.")
                                .font(.caption).foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.textDim)
                    }
                    .padding(16)
                    .background(
                        LinearGradient(colors: [Theme.accent.opacity(0.18), Theme.surface],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.45)))
                }
                .buttonStyle(.plain)

                Button { showFinder = true } label: {
                    Label("Find Model for Task", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent2)
                .controlSize(.large)

                SectionHeader(title: "Trending on the Hub", subtitle: "Live from the Hugging Face API")
                if hf.isSearching && hf.results.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(30)
                }
                if let e = hf.errorMessage {
                    Text(e).font(.caption).foregroundStyle(Theme.bad).card()
                }
                ForEach(hf.results.prefix(25)) { model in
                    NavigationLink { HFModelDetailView(repoId: model.id) } label: { HFModelRow(model: model) }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .sheet(isPresented: $showFinder) { ModelFinderView() }
        .task { if hf.results.isEmpty { hf.search(debounced: false) } }
    }
}
