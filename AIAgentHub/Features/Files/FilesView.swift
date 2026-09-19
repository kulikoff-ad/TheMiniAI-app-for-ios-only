import SwiftUI
import UniformTypeIdentifiers

/// 📁 Files — стандартный Files браузера iOS песочницы + workspace агента.
struct FilesView: View {
    @State private var path: String = ""
    @State private var entries: [FileEntry] = []
    @State private var showCreateFile = false
    @State private var showCreateFolder = false
    @State private var newName: String = ""
    @State private var editContent: String = ""
    @State private var editingPath: String?
    @State private var message: String?
    @State private var treeOutput: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let m = message {
                        Text(m).font(.caption).foregroundStyle(Theme.accent).card()
                    }
                    pathBar
                    actions
                    if entries.isEmpty {
                        EmptyStateView(icon: "folder", title: "Empty", message: "No files in \(path.isEmpty ? "Workspace" : path)")
                    } else {
                        ForEach(entries, id: \.name) { e in
                            HStack {
                                Image(systemName: e.isDirectory ? "folder.fill" : "doc.text")
                                    .foregroundStyle(e.isDirectory ? Theme.accent : Theme.textDim)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.name).font(.system(size: 13, design: .monospaced)).lineLimit(1)
                                    if !e.isDirectory { Text(Fmt.bytes(e.size)).font(.caption2).foregroundStyle(Theme.textDim) }
                                }
                                Spacer()
                                if e.isDirectory {
                                    Button { navigate(to: e.path) } label: { Image(systemName: "chevron.right").font(.caption) }
                                } else {
                                    Menu {
                                        Button { openForEdit(e) } label: { Label("Edit", systemImage: "pencil") }
                                        Button { share(e) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                                        Button(role: .destructive) { delete(e) } label: { Label("Delete", systemImage: "trash") }
                                    } label: { Image(systemName: "ellipsis.circle") }
                                }
                            }
                            .padding(10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    zipCard
                }.padding(16)
            }
            .screenBackground()
            .navigationTitle("📁 Files")
            .navigationBarTitleDisplayMode(.inline)
            .task { reload() }
            .sheet(isPresented: $showCreateFile) { createFileSheet }
            .sheet(isPresented: $showCreateFolder) { createFolderSheet }
            .sheet(isPresented: Binding(get: { editingPath != nil }, set: { if !$0 { editingPath = nil } })) {
                editSheet
            }
        }
    }

    private var pathBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Workspace").font(.caption.weight(.semibold)).foregroundStyle(Theme.textDim)
                Spacer()
                if !path.isEmpty {
                    Button { navigateUp() } label: { Label("Up", systemImage: "arrow.turn.left.up").font(.caption) }
                }
            }
            Text("/" + path).font(Theme.mono).foregroundStyle(.white).lineLimit(1)
            Text("Sandbox: Documents/Workspace — iOS File Sharing enabled so you can browse it in the Files app.").font(.caption2).foregroundStyle(Theme.textDim)
        }.card()
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { showCreateFile = true } label: { Label("File", systemImage: "doc.badge.plus").font(.caption) }
            Button { showCreateFolder = true } label: { Label("Folder", systemImage: "folder.badge.plus").font(.caption) }
            Button { reload() } label: { Label("Refresh", systemImage: "arrow.clockwise").font(.caption) }
        }.buttonStyle(.bordered).tint(Theme.accent2).controlSize(.small)
    }

    private var zipCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Archive")
            HStack(spacing: 8) {
                Button { doZip() } label: { Label("Create ZIP", systemImage: "archivebox") }
                Button { analyze() } label: { Label("Analyze documents", systemImage: "magnifyingglass") }
            }.font(.caption).buttonStyle(.bordered).tint(Theme.accent)
            if !treeOutput.isEmpty {
                Text(treeOutput).font(Theme.mono).textSelection(.enabled).padding(8).background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
            }
        }.card()
    }

    // MARK: Tool bridging (correct FileTool API)

    private func reload() {
        entries = list(at: path)
        message = nil
    }

    private func list(at rel: String) -> [FileEntry] {
        let base = ModelStorage.workspaceRoot
        let url = rel.isEmpty ? base : base.appendingPathComponent(rel)
        guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return [] }
        return items.map { u in
            let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
            let relPath = u.path.replacingOccurrences(of: base.path + "/", with: "")
            return FileEntry(name: u.lastPathComponent, path: relPath, isDirectory: isDir, size: size)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func navigate(to p: String) { path = p; reload() }
    private func navigateUp() {
        path = (path as NSString).deletingLastPathComponent
        if path == "." { path = "" }
        reload()
    }

    private func delete(_ e: FileEntry) {
        let base = ModelStorage.workspaceRoot.appendingPathComponent(e.path)
        try? FileManager.default.removeItem(at: base)
        reload()
        message = "Deleted \(e.name)"
    }

    private func share(_ e: FileEntry) {
        message = "Share: \(e.path) — open Files app → On My iPhone → AI Agent Hub → Workspace"
    }

    private func openForEdit(_ e: FileEntry) {
        let url = ModelStorage.workspaceRoot.appendingPathComponent(e.path)
        editContent = (try? String(contentsOf: url, encoding: .utf8)) ?? "(binary)"
        editingPath = e.path
    }

    private func doZip() {
        let tool = FileTool(permissions: AgentPermissions(allowFileWrite: true))
        // Zip workspace root to Workspace.zip
        do {
            let dest = try tool.zip(path.isEmpty ? "." : path, to: (path.isEmpty ? "Workspace" : (path as NSString).lastPathComponent) + ".zip")
            message = "Created \(dest.lastPathComponent)"
        } catch {
            message = "ZIP failed: \(error.localizedDescription)"
        }
        reload()
    }
    private func analyze() {
        let tool = FileTool(permissions: AgentPermissions())
        treeOutput = tool.tree(path, depth: 4)
    }

    private var createFileSheet: some View {
        NavigationStack {
            Form {
                Section("New file") { TextField("path/to/file.swift", text: $newName).autocorrectionDisabled().textInputAutocapitalization(.never) }
                Section { Text("Will be created under Workspace/").font(.caption).foregroundStyle(Theme.textDim) }
            }.scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Create file").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showCreateFile = false; newName = "" } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let tool = FileTool(permissions: AgentPermissions(allowFileWrite: true))
                        do {
                            let target = newName.isEmpty ? "untitled.txt" : newName
                            _ = try tool.write(target, contents: "// created by Files\n")
                            message = "Created \(target)"
                        } catch {
                            message = error.localizedDescription
                        }
                        showCreateFile = false; newName = ""; reload()
                    }.disabled(newName.isEmpty)
                }
            }
        }
    }

    private var createFolderSheet: some View {
        NavigationStack {
            Form {
                Section("New folder") { TextField("my-folder", text: $newName).autocorrectionDisabled().textInputAutocapitalization(.never) }
            }.scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Create folder").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showCreateFolder = false; newName = "" } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let tool = FileTool(permissions: AgentPermissions(allowFileWrite: true))
                        do {
                            try tool.makeFolder(newName)
                            message = "Created folder \(newName)"
                        } catch {
                            message = error.localizedDescription
                        }
                        showCreateFolder = false; newName = ""; reload()
                    }.disabled(newName.isEmpty)
                }
            }
        }
    }

    private var editSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(editingPath ?? "").font(Theme.mono).foregroundStyle(Theme.textDim)
                TextEditor(text: $editContent).font(Theme.mono).scrollContentBackground(.hidden).padding(8).background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
                Spacer()
            }.padding(16).screenBackground()
            .navigationTitle("Edit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingPath = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let p = editingPath else { return }
                        let tool = FileTool(permissions: AgentPermissions(allowFileWrite: true))
                        do {
                            _ = try tool.write(p, contents: editContent)
                            message = "Saved \(p)"
                        } catch {
                            message = error.localizedDescription
                        }
                        editingPath = nil
                        reload()
                    }
                }
            }
        }
    }
}

struct FileEntry {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
}
