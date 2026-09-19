import Foundation

/// Отдельные разрешения — показываются на карточке агента и в Workspace Tools.
enum Permission: String, CaseIterable, Identifiable {
    case webAccess = "Web Access"
    case fileAccess = "File Access"
    case githubAccess = "GitHub Access"
    case computerAccess = "Computer Access"
    case terminalAccess = "Terminal Access"
    case networkAccess = "Network Access"
    case modelDownload = "Model Download"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .webAccess: return "globe"
        case .fileAccess: return "folder"
        case .githubAccess: return "chevron.left.forwardslash.chevron.right"
        case .computerAccess: return "desktopcomputer"
        case .terminalAccess: return "terminal"
        case .networkAccess: return "network"
        case .modelDownload: return "arrow.down.circle"
        }
    }
    var description: String {
        switch self {
        case .webAccess: return "Search and fetch web pages"
        case .fileAccess: return "Read, create and edit files in Workspace"
        case .githubAccess: return "Read repos, create branches/commits/PRs"
        case .computerAccess: return "Control paired computer via Companion"
        case .terminalAccess: return "Run shell commands on the computer"
        case .networkAccess: return "General internet access (web + cloud inference)"
        case .modelDownload: return "Download model files from Hugging Face"
        }
    }
}

struct PermissionEvaluator {
    static func granted(_ perm: Permission, for agent: Agent) -> Bool {
        switch perm {
        case .webAccess: return agent.tools.contains(.web) && agent.permissions.allowNetwork
        case .fileAccess: return agent.tools.contains(.files)
        case .githubAccess: return agent.tools.contains(.github)
        case .computerAccess: return agent.tools.contains(.computer) && agent.permissions.allowComputerControl
        case .terminalAccess: return agent.tools.contains(.computer) && agent.permissions.allowComputerControl // Companion --allow-shell
        case .networkAccess: return agent.permissions.allowNetwork
        case .modelDownload: return true // always allowed; space check applies
        }
    }

    static func summary(for agent: Agent) -> [(Permission, Bool)] {
        Permission.allCases.map { ($0, granted($0, for: agent)) }
    }
}
