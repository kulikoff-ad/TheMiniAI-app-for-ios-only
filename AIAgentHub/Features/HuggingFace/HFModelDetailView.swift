import SwiftUI

struct HFModelDetailView: View {
    let repoId: String
    @StateObject private var vm: ModelDetailViewModel
    @EnvironmentObject var library: ModelLibrary
    @State private var section: Section = .overview
    @State private var showDownloadConfirm = false

    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview", files = "Files", card = "Model card"
        var id: String { rawValue }
    }

    init(repoId: String) {
        self.repoId = repoId
        _vm = StateObject(wrappedValue: ModelDetailViewModel(repoId: repoId))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .bottom], 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if vm.isLoading { ProgressView().frame(maxWidth: .infinity).padding(24) }
                    if let e = vm.errorMessage { Text(e).font(.caption).foregroundStyle(Theme.bad).card() }
                    switch section {
                    case .overview: overview
                    case .files: filesList
                    case .card: modelCard
                    }
                }
                .padding(16)
                .padding(.bottom, 120)
            }
        }
        .screenBackground()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(repoId.split(separator: "/").last.map(String.init) ?? repoId)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { downloadBar }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Link(destination: URL(string: "https://huggingface.co/\(repoId)")!) {
                    Image(systemName: "safari")
                }
            }
        }
        .task { await vm.load() }
        .alert("Download \(Fmt.bytes(vm.totalSelectedBytes))?", isPresented: $showDownloadConfirm) {
            Button("Download", role: .none) { vm.startDownload() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(vm.downloadWarning ?? "\(vm.selectedFiles.count) file(s) will be saved into the app sandbox.")
        }
    }

    // MARK: - Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(repoId).font(.headline)
                if let d = vm.detail {
                    HStack(spacing: 6) {
                        if let p = d.pipelineTag { Pill(text: p, color: Theme.accent2) }
                        if d.gated?.isGated == true { Pill(text: "Gated repo", color: Theme.warn, icon: "lock") }
                    }
                    HStack(spacing: 14) {
                        Label(Fmt.compactCount(d.downloads), systemImage: "arrow.down.circle")
                        Label(Fmt.compactCount(d.likes), systemImage: "heart")
                        Label(Fmt.ago(d.lastModified), systemImage: "clock")
                    }.font(.caption2).foregroundStyle(Theme.textDim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Specification")
                infoRow("Model size", Fmt.bytes(vm.repoTotalBytes) + (vm.repoTotalBytes.gb >= 1 ? "" : ""))
                infoRow("Formats", formatsText)
                infoRow("Architecture", vm.detail?.architecture ?? "—")
                infoRow("Parameters", parametersText)
                infoRow("License", vm.detail?.license ?? "—")
                infoRow("Library", vm.detail?.libraryName ?? "—")
                infoRow("Languages", (vm.detail?.languages.isEmpty == false) ? vm.detail!.languages.joined(separator: ", ") : "—")
                infoRow("Files", "\(vm.files.count)")
            }
            .card()

            if vm.repoTotalBytes.gb >= 1 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                    Text("Model size: \(String(format: "%.2f", vm.repoTotalBytes.gb)) GB for the whole repository. Only download the files you actually need.")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }

            runtimeAdvice
        }
    }

    private var formatsText: String {
        let set = Set(vm.files.map(\.format)).filter { $0 != .config && $0 != .other }
        return set.isEmpty ? "—" : set.map(\.title).sorted().joined(separator: ", ")
    }

    private var parametersText: String {
        guard let p = vm.detail?.parameterCount else { return "—" }
        return String(format: "%.2fB", Double(p) / 1e9)
    }

    private var runtimeAdvice: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "On this device")
            let runnable = vm.runnableFiles
            if runnable.isEmpty {
                Label("No file in this repository can run locally on iPhone. You can still download it for inspection, or use a cloud endpoint.",
                      systemImage: "xmark.octagon")
                    .font(.caption).foregroundStyle(Theme.bad)
            } else {
                Label("\(runnable.count) file(s) use an iOS-compatible runtime (\(Set(runnable.map(\.format.runtime.title)).joined(separator: ", "))).",
                      systemImage: "checkmark.seal")
                    .font(.caption).foregroundStyle(Theme.good)
            }
            Text("Free space: \(Fmt.bytes(library.freeDiskBytes)) · RAM budget: \(Fmt.bytes(DeviceCapabilities.usableMemoryBudgetBytes))")
                .font(.caption2).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.caption).foregroundStyle(Theme.textDim)
            Spacer()
            Text(v).font(.caption.weight(.medium)).multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Files

    private var filesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Repository files",
                          subtitle: "Select only what you need — nothing is downloaded automatically.")
            ForEach(vm.files) { file in
                Button { vm.toggle(file) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: vm.selectedFiles.contains(file.path) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(vm.selectedFiles.contains(file.path) ? Theme.accent : Theme.textDim)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.path).font(.system(size: 13, design: .monospaced)).lineLimit(2)
                            HStack(spacing: 6) {
                                Pill(text: file.format.title, color: Theme.accent2, icon: file.format.symbol)
                                if let q = file.quantization { Pill(text: q, color: Theme.good) }
                                Text(Fmt.bytes(file.byteSize)).font(.caption2).foregroundStyle(Theme.textDim)
                                if library.isDownloaded(repoId: repoId, file: file.path) {
                                    Pill(text: "Downloaded", color: Theme.good, icon: "checkmark")
                                }
                            }
                        }
                        Spacer()
                    }
                    .card(padding: 12)
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: - Model card

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if vm.readme.isEmpty {
                Text("No README.md published for this model.").font(.caption).foregroundStyle(Theme.textDim)
            } else {
                Text(vm.readme)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Download bar

    private var downloadBar: some View {
        VStack(spacing: 8) {
            if let warning = vm.downloadWarning {
                Text(warning).font(.caption2).foregroundStyle(Theme.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(vm.selectedFiles.count) selected").font(.caption).foregroundStyle(Theme.textDim)
                    Text(Fmt.bytes(vm.totalSelectedBytes)).font(.subheadline.weight(.bold))
                }
                Spacer()
                Button {
                    showDownloadConfirm = true
                } label: {
                    Label("Download Model", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundStyle(.black)
                .disabled(!vm.canDownload)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.stroke), alignment: .top)
    }
}
