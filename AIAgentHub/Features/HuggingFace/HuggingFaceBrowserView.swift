import SwiftUI

struct HuggingFaceBrowserView: View {
    @EnvironmentObject var hf: HuggingFaceStore
    @State private var showFilters = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !hf.query.tags.isEmpty || hf.query.pipelineTag != nil {
                    activeFilters
                }
                if hf.isSearching { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12) }
                if let e = hf.errorMessage {
                    Text(e).font(.caption).foregroundStyle(Theme.bad).card()
                }
                if !hf.isSearching && hf.results.isEmpty && hf.errorMessage == nil {
                    EmptyStateView(icon: "magnifyingglass", title: "No models found",
                                   message: "Try another keyword or clear the filters.")
                }
                ForEach(hf.results) { model in
                    NavigationLink { HFModelDetailView(repoId: model.id) } label: { HFModelRow(model: model) }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("🤗 Hugging Face")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $hf.query.text, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search Hugging Face models...")
        .onChange(of: hf.query.text) { _, _ in hf.search() }
        .onSubmit(of: .search) { hf.search(debounced: false) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: Binding(get: { hf.query.sort }, set: { hf.query.sort = $0; hf.search(debounced: false) })) {
                        ForEach(HFSortOption.allCases) { Text($0.title).tag($0) }
                    }
                    Button { showFilters = true } label: { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }
                } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .sheet(isPresented: $showFilters) { FiltersSheet() }
        .task { if hf.results.isEmpty { hf.search(debounced: false) } }
    }

    private var activeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(hf.query.tags, id: \.self) { tag in
                    Button { hf.toggleTag(tag) } label: { Pill(text: "\(tag) ✕", color: Theme.accent) }
                }
                if let p = hf.query.pipelineTag {
                    Button { hf.setPipeline(p) } label: { Pill(text: "\(p) ✕", color: Theme.accent2) }
                }
                Button("Clear") { hf.clearFilters() }.font(.caption)
            }
        }
    }
}

struct FiltersSheet: View {
    @EnvironmentObject var hf: HuggingFaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var author: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    ForEach(HuggingFaceStore.formatFilters, id: \.1) { name, tag in
                        Toggle(name, isOn: Binding(
                            get: { hf.query.tags.contains(tag) },
                            set: { _ in hf.toggleTag(tag) }))
                    }
                }
                Section("Task") {
                    ForEach(HuggingFaceStore.taskFilters, id: \.self) { task in
                        Button {
                            hf.setPipeline(task)
                        } label: {
                            HStack {
                                Text(task)
                                Spacer()
                                if hf.query.pipelineTag == task { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }.foregroundStyle(.white)
                    }
                }
                Section("Author / organisation") {
                    TextField("e.g. Qwen, meta-llama, TheBloke", text: $author)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            hf.query.author = author.isEmpty ? nil : author
                            hf.search(debounced: false)
                        }
                }
                Section {
                    Button("Clear all filters", role: .destructive) { author = ""; hf.clearFilters() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct HFModelRow: View {
    let model: HFModelSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(model.owner).font(.caption2).foregroundStyle(Theme.textDim)
                }
                Spacer()
                if model.gated?.isGated == true { Pill(text: "Gated", color: Theme.warn, icon: "lock") }
            }
            HStack(spacing: 6) {
                if let p = model.pipelineTag { Pill(text: p, color: Theme.accent2) }
                ForEach(model.advertisedFormats) { f in Pill(text: f.title, color: Theme.good, icon: f.symbol) }
            }
            HStack(spacing: 14) {
                Label(Fmt.compactCount(model.downloads), systemImage: "arrow.down.circle")
                Label(Fmt.compactCount(model.likes), systemImage: "heart")
                Label(Fmt.ago(model.lastModified), systemImage: "clock")
            }
            .font(.caption2)
            .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
