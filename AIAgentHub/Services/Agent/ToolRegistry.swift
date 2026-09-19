import Foundation

/// Target repository an agent is allowed to act on.
struct GitHubTargetContext: Hashable, Codable {
    var owner: String
    var repo: String
    var baseBranch: String
    var workingBranch: String?

    var fullName: String { "\(owner)/\(repo)" }
}

/// Dispatches parsed `ToolCall`s to the real implementations.
@MainActor
struct ToolRegistry {

    let agent: Agent
    let gitHub: GitHubTargetContext?
    unowned let runtime: AgentRuntime

    private var fileTool: FileTool { FileTool(permissions: agent.permissions) }
    private var webTool: WebTool { WebTool(allowNetwork: agent.permissions.allowNetwork && !agent.permissions.offlineOnly) }

    var permissionSummary: String {
        var parts: [String] = []
        parts.append(agent.permissions.allowFileWrite ? "file write ON" : "file write OFF")
        parts.append(agent.permissions.allowFileDelete ? "file delete ON" : "file delete OFF")
        parts.append(agent.permissions.offlineOnly ? "OFFLINE MODE (no network)" : (agent.permissions.allowNetwork ? "network ON" : "network OFF"))
        parts.append(agent.permissions.allowGitHubWrite ? "GitHub write ON (user confirms pushes)" : "GitHub read-only")
        parts.append(agent.permissions.allowComputerControl ? "computer control ON" : "computer control OFF")
        return parts.joined(separator: ", ")
    }

    var catalog: String {
        var lines: [String] = []
        if agent.tools.contains(.files) {
            lines.append("""
            files: list{path}, read{path}, write{path,contents}, append{path,contents}, edit{path,find,replace},
                   mkdir{path}, delete{path}, zip{path,destination}, analyze{path}, tree{}
            """)
        }
        if agent.tools.contains(.web) {
            lines.append("web: search{query}, open{url}, analyze{url}, save{url,path}")
        }
        if agent.tools.contains(.github) {
            lines.append("""
            github: listRepos{}, listFiles{path}, readFile{path}, createBranch{name}, writeFile{path,contents,message},
                    diff{base,head}, pullRequest{title,body}
            """)
        }
        if agent.tools.contains(.computer) {
            lines.append("computer: info{}, list{path}, read{path}, write{path,contents}, run{command,cwd}")
        }
        return lines.isEmpty ? "(no tools enabled)" : lines.joined(separator: "\n")
    }

    func invoke(_ call: ToolCall) async throws -> String {
        guard agent.tools.contains(call.tool) else {
            return "ERROR: the \(call.tool.title) tool is not enabled for this agent."
        }
        switch call.tool {
        case .files: return try files(call)
        case .web: return try await web(call)
        case .github: return try await github(call)
        case .computer: return try await computer(call)
        case .shellSandbox: return "ERROR: shell execution is not available inside the iOS sandbox. Use the computer tool with a paired companion."
        }
    }

    // MARK: - Files

    private func files(_ call: ToolCall) throws -> String {
        let t = fileTool
        switch call.action {
        case "list": return try t.list(call.string("path")).joined(separator: "\n")
        case "read": return try t.read(call.string("path"))
        case "write":
            let url = try t.write(call.string("path"), contents: call.string("contents"))
            return "Wrote \(Fmt.bytes(ModelStorage.size(of: url))) to \(call.string("path"))"
        case "append":
            _ = try t.append(call.string("path"), contents: call.string("contents"))
            return "Appended to \(call.string("path"))"
        case "edit":
            _ = try t.edit(call.string("path"), find: call.string("find"), replace: call.string("replace"))
            return "Edited \(call.string("path"))"
        case "mkdir":
            try t.makeFolder(call.string("path")); return "Created folder \(call.string("path"))"
        case "delete":
            try t.delete(call.string("path")); return "Deleted \(call.string("path"))"
        case "zip":
            let url = try t.zip(call.string("path"), to: call.string("destination", default: "archive.zip"))
            return "Created \(url.lastPathComponent) (\(Fmt.bytes(ModelStorage.size(of: url))))"
        case "analyze": return try t.analyze(call.string("path"))
        case "tree": return t.tree(call.string("path"))
        default: return "ERROR: unknown files action \"\(call.action)\""
        }
    }

    // MARK: - Web

    private func web(_ call: ToolCall) async throws -> String {
        let t = webTool
        switch call.action {
        case "search":
            let results = try await t.search(call.string("query"))
            guard !results.isEmpty else { return "No results." }
            return results.enumerated().map { "\($0.offset + 1). \($0.element.title)\n   \($0.element.url)\n   \($0.element.snippet)" }
                .joined(separator: "\n")
        case "open": return try await t.openPage(call.string("url"))
        case "analyze": return try await t.analyzeSite(call.string("url"))
        case "save":
            let text = try await t.openPage(call.string("url"))
            _ = try fileTool.write(call.string("path", default: "web-capture.md"), contents: text)
            return "Saved \(text.count) characters to \(call.string("path", default: "web-capture.md"))"
        default: return "ERROR: unknown web action \"\(call.action)\""
        }
    }

    // MARK: - GitHub

    private func github(_ call: ToolCall) async throws -> String {
        if agent.permissions.offlineOnly { return "ERROR: Offline Mode is on; GitHub is unavailable." }
        let api = GitHubAPI.shared

        if call.action == "listRepos" {
            let repos = try await api.repositories()
            return repos.prefix(40).map { "\($0.fullName)\(($0.isPrivate) ? " (private)" : "") — \($0.descriptionText ?? "")" }
                .joined(separator: "\n")
        }

        guard let ctx = gitHub else {
            return "ERROR: no repository selected. Ask the user to pick one in the GitHub tab."
        }
        let branch = ctx.workingBranch ?? ctx.baseBranch

        switch call.action {
        case "listFiles":
            let items = try await api.contents(owner: ctx.owner, repo: ctx.repo, path: call.string("path"), ref: branch)
            return items.map { "\($0.isDirectory ? "📁" : "📄") \($0.path)" }.joined(separator: "\n")
        case "readFile":
            return try await api.fileText(owner: ctx.owner, repo: ctx.repo, path: call.string("path"), ref: branch)
        case "diff":
            return try await api.compare(owner: ctx.owner, repo: ctx.repo,
                                         base: call.string("base", default: ctx.baseBranch),
                                         head: call.string("head", default: branch))
        case "createBranch":
            guard agent.permissions.allowGitHubWrite else { return "ERROR: GitHub write permission is off." }
            let name = call.string("name", default: "ai-agent-hub/\(Int(Date().timeIntervalSince1970))")
            _ = try await api.createBranch(owner: ctx.owner, repo: ctx.repo, newBranch: name, fromBranch: ctx.baseBranch)
            GitHubStore.shared.setWorkingBranch(name)
            return "Created branch \(name) from \(ctx.baseBranch)."
        case "writeFile":
            guard agent.permissions.allowGitHubWrite else { return "ERROR: GitHub write permission is off." }
            let path = call.string("path")
            let contents = call.string("contents")
            let message = call.string("message", default: "AI Agent Hub: update \(path)")
            let existing = (try? await api.fileText(owner: ctx.owner, repo: ctx.repo, path: path, ref: branch)) ?? ""
            let diff = DiffBuilder.unified(old: existing, new: contents, path: path)

            let commit: () async -> String = {
                do {
                    let resp = try await api.putFile(owner: ctx.owner, repo: ctx.repo, path: path,
                                                     content: contents, message: message, branch: branch)
                    return "Committed \(path) to \(branch) (\(resp.commit?.sha?.prefix(7) ?? "ok"))."
                } catch { return "ERROR: \(error.localizedDescription)" }
            }

            if agent.permissions.requireConfirmationBeforePush {
                return await runtime.requestConfirmation(
                    title: "Commit \(path) to \(ctx.fullName)@\(branch)",
                    detail: message, diff: diff, perform: commit)
            }
            return await commit()
        case "pullRequest":
            guard agent.permissions.allowGitHubWrite else { return "ERROR: GitHub write permission is off." }
            guard let head = ctx.workingBranch else { return "ERROR: create a branch first." }
            let title = call.string("title", default: "AI Agent Hub changes")
            let body = call.string("body", default: "Opened from AI Agent Hub.")
            let diff = (try? await api.compare(owner: ctx.owner, repo: ctx.repo, base: ctx.baseBranch, head: head)) ?? ""
            let open: () async -> String = {
                do {
                    let pr = try await api.createPullRequest(owner: ctx.owner, repo: ctx.repo, title: title,
                                                             head: head, base: ctx.baseBranch, body: body)
                    return "Opened PR #\(pr.number): \(pr.htmlUrl)"
                } catch { return "ERROR: \(error.localizedDescription)" }
            }
            return await runtime.requestConfirmation(title: "Open pull request in \(ctx.fullName)",
                                                     detail: title, diff: diff, perform: open)
        default:
            return "ERROR: unknown github action \"\(call.action)\""
        }
    }

    // MARK: - Computer

    private func computer(_ call: ToolCall) async throws -> String {
        guard agent.permissions.allowComputerControl else {
            return "ERROR: computer control is disabled for this agent. The user must grant it explicitly."
        }
        let client = CompanionClient.shared
        switch call.action {
        case "info":
            if client.info == nil { await client.connect() }
            guard let i = client.info else { return "ERROR: companion not reachable. \(client.lastError ?? "")" }
            return "Host \(i.hostname) — \(i.os) \(i.osVersion) (\(i.arch)), companion \(i.companionVersion). Allowed roots: \(i.allowedRoots.joined(separator: ", "))"
        case "list":
            return try await client.listDirectory(call.string("path"), permissions: agent.permissions).joined(separator: "\n")
        case "read":
            return try await client.readFile(call.string("path"), permissions: agent.permissions)
        case "write":
            try await client.writeFile(call.string("path"), content: call.string("contents"), permissions: agent.permissions)
            return "Wrote \(call.string("path")) on \(client.info?.hostname ?? "host")."
        case "run":
            let cmd = call.string("command")
            let result = try await runtime.requestConfirmation(
                title: "Run on \(client.info?.hostname ?? "computer")",
                detail: cmd, diff: nil) {
                    do {
                        let r = try await client.run(command: cmd, cwd: call.args["cwd"] as? String, permissions: agent.permissions)
                        return "exit=\(r.exitCode)\n\(r.stdout)\n\(r.stderr)"
                    } catch { return "ERROR: \(error.localizedDescription)" }
                }
            return result
        default:
            return "ERROR: unknown computer action \"\(call.action)\""
        }
    }
}

/// Minimal unified diff generator so users always see changes before publishing.
enum DiffBuilder {
    static func unified(old: String, new: String, path: String) -> String {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        var out = ["--- a/\(path)", "+++ b/\(path)"]
        let lcs = longestCommonSubsequence(a, b)
        var i = 0, j = 0
        for token in lcs {
            while i < a.count && a[i] != token { out.append("-\(a[i])"); i += 1 }
            while j < b.count && b[j] != token { out.append("+\(b[j])"); j += 1 }
            out.append(" \(token)")
            i += 1; j += 1
        }
        while i < a.count { out.append("-\(a[i])"); i += 1 }
        while j < b.count { out.append("+\(b[j])"); j += 1 }
        return out.joined(separator: "\n")
    }

    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        guard a.count < 4000, b.count < 4000 else { return [] }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result: [String] = []
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { result.append(a[i]); i += 1; j += 1 }
            else if table[i + 1][j] >= table[i][j + 1] { i += 1 }
            else { j += 1 }
        }
        return result
    }
}
