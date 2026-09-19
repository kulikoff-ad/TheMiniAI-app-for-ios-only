import SwiftUI

struct GitHubView: View {
    @EnvironmentObject var store: GitHubStore
    @State private var token: String = ""
    @State private var fileText: String?
    @State private var fileName: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.user == nil { connectCard } else { accountCard }
                    if let e = store.errorMessage { Text(e).font(.caption).foregroundStyle(Theme.bad).card() }
                    if store.isLoading { ProgressView().frame(maxWidth: .infinity).padding(12) }

                    if let repo = store.selected {
                        repoHeader(repo)
                        browser
                    } else if !store.repos.isEmpty {
                        SectionHeader(title: "Repositories", subtitle: "\(store.repos.count) found")
                        ForEach(store.repos) { repo in
                            Button { Task { await store.open(repo) } } label: { RepoRow(repo: repo) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("GitHub")
            .sheet(isPresented: Binding(get: { fileText != nil }, set: { if !$0 { fileText = nil } })) {
                NavigationStack {
                    ScrollView {
                        Text(fileText ?? "").font(Theme.mono).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    }
                    .screenBackground()
                    .navigationTitle(fileName).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { fileText = nil } } }
                }
            }
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect GitHub").font(.headline)
            Text("Paste a fine-grained personal access token with Contents + Pull requests permissions. It is stored in the iOS Keychain and never leaves the device except to api.github.com.")
                .font(.caption).foregroundStyle(Theme.textDim)
            SecureField("ghp_… / github_pat_…", text: $token)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            HStack {
                Button("Connect") {
                    KeychainStore.set(token, for: .githubToken)
                    token = ""
                    Task { await store.connect() }
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent2)
                .disabled(token.isEmpty)
                Link("Create token ↗", destination: URL(string: "https://github.com/settings/tokens?type=beta")!)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var accountCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("@\(store.user?.login ?? "")").font(.subheadline.weight(.semibold))
                Text("\(store.repos.count) repositories").font(.caption2).foregroundStyle(Theme.textDim)
            }
            Spacer()
            Button("Disconnect", role: .destructive) { store.disconnect() }.font(.caption)
        }
        .card()
    }

    private func repoHeader(_ repo: GHRepo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { store.selected = nil; store.contents = [] } label: {
                    Image(systemName: "chevron.left")
                }
                Text(repo.fullName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Pill(text: store.workingBranch ?? repo.defaultBranch, color: Theme.accent2, icon: "arrow.triangle.branch")
            }
            if let d = repo.descriptionText { Text(d).font(.caption).foregroundStyle(Theme.textDim) }
            Text("Path: /\(store.path)").font(.caption2).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.path.isEmpty {
                Button { Task { await store.goUp() } } label: {
                    Label("..", systemImage: "arrow.turn.left.up").font(.caption)
                }
            }
            ForEach(store.contents) { item in
                Button {
                    Task {
                        if item.isDirectory { await store.loadContents(item.path) }
                        else if let ctx = store.context {
                            fileName = item.name
                            fileText = (try? await GitHubAPI.shared.fileText(owner: ctx.owner, repo: ctx.repo,
                                                                             path: item.path,
                                                                             ref: store.workingBranch ?? ctx.baseBranch))
                                ?? "(binary or unreadable file)"
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc.text")
                            .foregroundStyle(item.isDirectory ? Theme.accent : Theme.textDim)
                        Text(item.name).font(.system(size: 13, design: .monospaced))
                        Spacer()
                        if let s = item.size, !item.isDirectory {
                            Text(Fmt.bytes(s)).font(.caption2).foregroundStyle(Theme.textDim)
                        }
                    }
                    .padding(10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }
}

struct RepoRow: View {
    let repo: GHRepo
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(repo.fullName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                if repo.isPrivate { Pill(text: "private", color: Theme.warn, icon: "lock") }
            }
            if let d = repo.descriptionText {
                Text(d).font(.caption2).foregroundStyle(Theme.textDim).lineLimit(2)
            }
            HStack(spacing: 12) {
                if let l = repo.language { Label(l, systemImage: "circle.fill") }
                Label("\(repo.stargazersCount ?? 0)", systemImage: "star")
                Label(repo.defaultBranch, systemImage: "arrow.triangle.branch")
            }.font(.caption2).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
