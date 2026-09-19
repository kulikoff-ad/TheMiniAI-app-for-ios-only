import SwiftUI

/// "Find Model for Task" — turns a natural-language need into real Hub queries.
struct ModelFinderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var prompt: String = ""
    @State private var isSearching = false
    @State private var results: [HFModelDetail] = []
    @State private var summaries: [HFModelSummary] = []
    @State private var error: String?
    @State private var interpreted: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Describe your task").font(.subheadline.weight(.semibold))
                        TextEditor(text: $prompt)
                            .frame(height: 90)
                            .font(.callout)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
                        Text("For example: “Мне нужна модель для программирования на Mac.”")
                            .font(.caption2).foregroundStyle(Theme.textDim)
                        Button {
                            Task { await run() }
                        } label: {
                            Label(isSearching ? "Searching Hugging Face…" : "Find Model for Task",
                                  systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
                        .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                    }
                    .card()

                    if !interpreted.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader(title: "Interpretation")
                            Text(interpreted).font(.caption).foregroundStyle(Theme.textDim)
                        }.frame(maxWidth: .infinity, alignment: .leading).card()
                    }

                    if let error { Text(error).font(.caption).foregroundStyle(Theme.bad).card() }

                    ForEach(results) { detail in
                        NavigationLink { HFModelDetailView(repoId: detail.id) } label: {
                            FinderResultCard(detail: detail,
                                             summary: summaries.first { $0.id == detail.id })
                        }.buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Find Model for Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func run() async {
        isSearching = true
        error = nil
        results = []
        let intent = TaskIntent.parse(prompt)
        interpreted = intent.explanation
        do {
            var query = HFSearchQuery()
            query.text = intent.keywords.joined(separator: " ")
            query.tags = intent.tags
            query.pipelineTag = intent.pipeline
            query.sort = .downloads
            query.limit = 12
            summaries = try await HuggingFaceAPI.shared.searchModels(query)
            if summaries.isEmpty {
                query.tags = []
                summaries = try await HuggingFaceAPI.shared.searchModels(query)
            }
            var details: [HFModelDetail] = []
            for s in summaries.prefix(8) {
                if let d = try? await HuggingFaceAPI.shared.modelDetail(id: s.id) { details.append(d) }
            }
            results = details
            if results.isEmpty { error = "No models matched. Try describing the task differently." }
        } catch {
            self.error = error.localizedDescription
        }
        isSearching = false
    }
}

struct FinderResultCard: View {
    let detail: HFModelDetail
    let summary: HFModelSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.id).font(.subheadline.weight(.semibold)).lineLimit(1)
            HStack(spacing: 6) {
                if let p = detail.pipelineTag { Pill(text: p, color: Theme.accent2) }
                ForEach(summary?.advertisedFormats ?? []) { f in Pill(text: f.title, color: Theme.good, icon: f.symbol) }
            }
            grid
            Link("View on Hugging Face ↗", destination: detail.hfURL).font(.caption2).tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 3) {
            line("Parameters", detail.parameterCount.map { String(format: "%.2fB", Double($0) / 1e9) } ?? "—")
            line("Purpose", detail.pipelineTag ?? "—")
            line("Languages", detail.languages.isEmpty ? "—" : detail.languages.prefix(6).joined(separator: ", "))
            line("License", detail.license ?? "—")
            line("Library", detail.libraryName ?? "—")
        }
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.caption2).foregroundStyle(Theme.textDim).frame(width: 84, alignment: .leading)
            Text(v).font(.caption2)
        }
    }
}

/// Tiny rule-based intent parser (works offline, no LLM needed) that maps a
/// natural-language need onto real Hub filters.
struct TaskIntent {
    var keywords: [String] = []
    var tags: [String] = []
    var pipeline: String?
    var explanation: String = ""

    static func parse(_ text: String) -> TaskIntent {
        let lower = text.lowercased()
        var intent = TaskIntent()
        var notes: [String] = []

        func has(_ words: [String]) -> Bool { words.contains { lower.contains($0) } }

        if has(["код", "программ", "code", "coding", "developer", "swift", "python", "programming"]) {
            intent.keywords.append("coder")
            intent.pipeline = "text-generation"
            notes.append("coding assistant → text-generation models tuned for code")
        }
        if has(["перевод", "translate", "translation"]) {
            intent.pipeline = "translation"; notes.append("translation")
        }
        if has(["изображен", "картин", "image", "picture", "photo", "draw"]) {
            intent.pipeline = "text-to-image"; notes.append("image generation")
        }
        if has(["речь", "голос", "speech", "voice", "audio", "whisper", "transcri"]) {
            intent.pipeline = "automatic-speech-recognition"; notes.append("speech recognition")
        }
        if has(["суммар", "summar", "конспект"]) {
            intent.pipeline = "summarization"; notes.append("summarization")
        }
        if has(["embed", "поиск по смыслу", "rag", "retriev", "вектор"]) {
            intent.pipeline = "feature-extraction"; notes.append("embeddings / RAG")
        }
        if has(["mac", "macos", "apple", "iphone", "ios", "offline", "локальн", "on-device", "локально"]) {
            intent.tags.append("gguf")
            notes.append("runs on Apple hardware → prefer GGUF (llama.cpp) builds")
        }
        if has(["маленьк", "small", "tiny", "быстр", "fast", "lightweight"]) {
            intent.keywords.append("1.5b"); notes.append("small/fast → ~1-3B parameters")
        }
        if has(["русск", "russian"]) { intent.keywords.append("russian"); notes.append("Russian language support") }
        if has(["chat", "assistant", "чат", "ассистент", "instruct"]) {
            intent.keywords.append("instruct")
            if intent.pipeline == nil { intent.pipeline = "text-generation" }
            notes.append("instruction-tuned chat model")
        }

        if intent.keywords.isEmpty {
            let stop: Set<String> = ["мне","нужна","нужен","модель","для","на","a","the","i","need","model","for","to","with","что","бы"]
            intent.keywords = lower
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stop.contains($0) }
                .prefix(4).map { $0 }
        }
        if intent.pipeline == nil { intent.pipeline = "text-generation" }

        intent.explanation = notes.isEmpty
            ? "Searching text-generation models matching: \(intent.keywords.joined(separator: ", "))."
            : notes.joined(separator: " · ") + ". Query: \(intent.keywords.joined(separator: " "))" +
              (intent.tags.isEmpty ? "" : " [\(intent.tags.joined(separator: ", "))]")
        return intent
    }
}
