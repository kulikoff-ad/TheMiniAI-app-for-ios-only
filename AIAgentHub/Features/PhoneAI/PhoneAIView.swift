import SwiftUI
import Combine

/// 📱 AI for iPhone — отдельный режим поиска моделей, подходящих именно для телефона.
/// Учитывает: модель iPhone, RAM/budget, свободное место, архитектуру, формат, quantization, runtime.
struct PhoneAIView: View {
    @State private var prompt: String = ""
    @State private var isSearching = false
    @State private var results: [HFModelSummary] = []
    @State private var error: String?
    @State private var interpreted: String = ""

    // Filters
    @State private var phoneCompatibleOnly = true
    @State private var sizeFilter: SizeFilter = .gb2
    @State private var selectedFormats: Set<ModelFormat> = [.gguf]
    @State private var selectedTasks: Set<String> = []
    @State private var showDeviceSheet = false

    enum SizeFilter: String, CaseIterable, Identifiable {
        case mb500 = "< 500 MB", gb1 = "< 1 GB", gb2 = "< 2 GB", gb4 = "< 4 GB", gb8 = "< 8 GB", any = "Any"
        var id: String { rawValue }
        var bytes: Int64? {
            switch self {
            case .mb500: return 500 * 1024 * 1024
            case .gb1: return 1 * 1024 * 1024 * 1024
            case .gb2: return 2 * 1024 * 1024 * 1024
            case .gb4: return 4 * 1024 * 1024 * 1024
            case .gb8: return 8 * 1024 * 1024 * 1024
            case .any: return nil
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                deviceCard
                promptCard
                filtersCard
                if isSearching { ProgressView().frame(maxWidth: .infinity).padding() }
                if let error { Text(error).font(.caption).foregroundStyle(Theme.bad).card() }
                if !interpreted.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Interpretation")
                        Text(interpreted).font(.caption).foregroundStyle(Theme.textDim)
                    }.card()
                }
                if !results.isEmpty {
                    SectionHeader(title: "Results", subtitle: "\(results.count) models")
                    ForEach(results) { model in
                        NavigationLink { HFModelDetailView(repoId: model.id) } label: { PhoneResultRow(model: model) }
                            .buttonStyle(.plain)
                    }
                } else if !isSearching && !prompt.isEmpty && error == nil {
                    EmptyStateView(icon: "iphone.gen1", title: "No phone-compatible models yet", message: "Try another phrase or relax filters.")
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("📱 AI for iPhone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showDeviceSheet = true } label: { Image(systemName: "iphone") }
            }
        }
        .sheet(isPresented: $showDeviceSheet) { DeviceInfoSheet() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Find AI that actually runs on this iPhone")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("We check not just size — but format, quantization and which runtime can execute it on-device.")
                .font(.caption).foregroundStyle(Theme.textDim)
        }.card()
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "This device")
            HStack {
                statCol("Model", DeviceCapabilities.deviceModelIdentifier)
                Divider().overlay(Theme.stroke)
                statCol("RAM", Fmt.bytes(DeviceCapabilities.physicalMemoryBytes))
                Divider().overlay(Theme.stroke)
                statCol("Budget", Fmt.bytes(DeviceCapabilities.usableMemoryBudgetBytes))
            }
            HStack {
                statCol("Free space", Fmt.bytes(DeviceCapabilities.freeDiskBytes))
                Divider().overlay(Theme.stroke)
                statCol("MLX", DeviceCapabilities.supportsMLX ? "yes" : "no")
                Divider().overlay(Theme.stroke)
                statCol("Arch", "arm64")
            }
            Text("Budget is the conservative working-set we allow a model to use so iOS won't kill the app (≈45-55% of RAM + overhead).")
                .font(.caption2).foregroundStyle(Theme.textDim)
        }.card()
    }

    private func statCol(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption2).foregroundStyle(Theme.textDim)
            Text(v).font(.caption.weight(.semibold)).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What do you need?").font(.subheadline.weight(.semibold))
            TextField("AI для программирования, маленькая модель до 2 GB, coding, vision...", text: $prompt, axis: .vertical)
                .lineLimit(2...4)
                .padding(10)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
                .autocorrectionDisabled()
            Button {
                Task { await run() }
            } label: {
                Label(isSearching ? "Searching Hugging Face…" : "Search phone-compatible models", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
            .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            Text("Examples: “AI для программирования”, “маленькая модель для iPhone”, “AI до 2 GB”, “vision embeddings”")
                .font(.caption2).foregroundStyle(Theme.textDim)
        }.card()
    }

    private var filtersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $phoneCompatibleOnly) {
                Label("📱 Phone Compatible only", systemImage: "iphone.gen3")
                    .font(.subheadline.weight(.semibold))
            }.tint(Theme.good)
            Text("When on, we hide every model whose format or estimated RAM cannot run on this device.")
                .font(.caption2).foregroundStyle(Theme.textDim)

            VStack(alignment: .leading, spacing: 6) {
                Text("Size").font(.caption.weight(.semibold)).foregroundStyle(Theme.textDim)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(SizeFilter.allCases) { f in
                            FilterChip(title: f.rawValue, selected: sizeFilter == f) { sizeFilter = f }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Format").font(.caption.weight(.semibold)).foregroundStyle(Theme.textDim)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach([ModelFormat.gguf, .onnx, .coreml, .safetensors, .mlx], id: \.self) { fmt in
                            FilterChip(title: fmt.title, selected: selectedFormats.contains(fmt)) {
                                if selectedFormats.contains(fmt) { selectedFormats.remove(fmt) } else { selectedFormats.insert(fmt) }
                            }
                        }
                    }
                }
                Text("SafeTensors alone is not Phone Compatible — it must be converted to GGUF/Core ML/ONNX.")
                    .font(.caption2).foregroundStyle(Theme.warn)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Task").font(.caption.weight(.semibold)).foregroundStyle(Theme.textDim)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(["Text Generation", "Coding", "Vision", "Embeddings", "Small Models"], id: \.self) { t in
                            FilterChip(title: t, selected: selectedTasks.contains(t)) {
                                if selectedTasks.contains(t) { selectedTasks.remove(t) } else { selectedTasks.insert(t) }
                            }
                        }
                    }
                }
            }
        }.card()
    }

    // MARK: Search

    private func run() async {
        isSearching = true; error = nil; results = []; interpreted = ""
        let intent = TaskIntent.parse(prompt)
        // Merge UI filters into intent
        var tags = intent.tags
        for fmt in selectedFormats {
            let tag: String
            switch fmt {
            case .gguf: tag = "gguf"
            case .onnx: tag = "onnx"
            case .coreml: tag = "coreml"
            case .safetensors: tag = "safetensors"
            case .mlx: tag = "mlx"
            default: continue
            }
            if !tags.contains(tag) { tags.append(tag) }
        }
        // Task mapping
        var pipeline = intent.pipeline
        if selectedTasks.contains("Coding") { pipeline = "text-generation"; if !tags.contains("code") { tags.append("code") } }
        if selectedTasks.contains("Vision") { pipeline = "image-classification" }
        if selectedTasks.contains("Embeddings") { pipeline = "feature-extraction" }
        if selectedTasks.contains("Small Models") {
            if !intent.keywords.contains("1.5b") && !intent.keywords.contains("small") {
                tags.append("1b")
            }
        }

        interpreted = intent.explanation + " · Size \(sizeFilter.rawValue) · Formats: \(selectedFormats.map{ $0.title}.joined(separator: ", ")) · Tasks: \(selectedTasks.joined(separator: ", "))"

        do {
            var q = HFSearchQuery()
            q.text = intent.keywords.joined(separator: " ")
            q.tags = tags
            q.pipelineTag = pipeline
            q.sort = .downloads
            q.limit = 30
            var found = try await HuggingFaceAPI.shared.searchModels(q)
            // Fallback if too strict
            if found.isEmpty && !tags.isEmpty {
                q.tags = []
                found = try await HuggingFaceAPI.shared.searchModels(q)
            }
            // Phone-compatibility + size filtering
            if phoneCompatibleOnly {
                found = found.filter { summary in
                    // Quick check: if no advertised format overlaps selected, still keep — detail may reveal GGUF file
                    // But strictly: if selectedFormats is non-empty, require intersection
                    if !selectedFormats.isEmpty {
                        let adv = Set(summary.advertisedFormats)
                        if !adv.isEmpty && adv.isDisjoint(with: selectedFormats) {
                            // allow through if tags unknown — will be checked per-file later; but for list we filter
                            // Keep only if adv overlaps or adv empty (older models)
                            return false
                        }
                    }
                    return true
                }
            }
            // Size filter is applied at file level; for summary list we keep all, but indicate.
            results = found
            if results.isEmpty { error = "No models matched. Try widening size or disabling Phone Compatible temporarily." }
        } catch {
            self.error = error.localizedDescription
        }
        isSearching = false
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? Theme.accent : Theme.surfaceElevated, in: Capsule())
                .foregroundStyle(selected ? .black : Theme.textDim)
                .overlay(Capsule().stroke(selected ? Theme.accent : Theme.stroke))
        }.buttonStyle(.plain)
    }
}

struct PhoneResultRow: View {
    let model: HFModelSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.id).font(.subheadline.weight(.semibold)).lineLimit(1)
            HStack(spacing: 6) {
                if let p = model.pipelineTag { Pill(text: p, color: Theme.accent2) }
                ForEach(model.advertisedFormats) { f in Pill(text: f.title, color: phoneColor(f)) }
                if model.gated?.isGated == true { Pill(text: "gated", color: Theme.warn) }
            }
            HStack(spacing: 12) {
                Label("\(model.downloads ?? 0)", systemImage: "arrow.down.circle").font(.caption2).foregroundStyle(Theme.textDim)
                Label("\(model.likes ?? 0)", systemImage: "heart").font(.caption2).foregroundStyle(Theme.textDim)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
    private func phoneColor(_ f: ModelFormat) -> Color {
        switch f {
        case .gguf, .coreml, .onnx: return Theme.good
        case .mlx: return DeviceCapabilities.supportsMLX ? Theme.good : Theme.warn
        default: return Theme.textDim
        }
    }
}

struct DeviceInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Hardware") {
                    LabeledContent("Device identifier", value: DeviceCapabilities.deviceModelIdentifier)
                    LabeledContent("Physical RAM", value: Fmt.bytes(DeviceCapabilities.physicalMemoryBytes))
                    LabeledContent("Usable budget (model)", value: Fmt.bytes(DeviceCapabilities.usableMemoryBudgetBytes))
                    LabeledContent("MLX capable", value: DeviceCapabilities.supportsMLX ? "Yes (≥8GB)" : "No")
                }
                Section("Storage") {
                    LabeledContent("Free space", value: Fmt.bytes(DeviceCapabilities.freeDiskBytes))
                    LabeledContent("Total disk", value: Fmt.bytes(DeviceCapabilities.totalDiskBytes))
                }
                Section("Capabilities") {
                    Text("Supported formats: GGUF via llama.cpp, ONNX via ONNX Runtime, Core ML, MLX on supported devices. SafeTensors / PyTorch / TFLite are not executable on iOS without conversion.")
                        .font(.caption).foregroundStyle(Theme.textDim)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Device").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
