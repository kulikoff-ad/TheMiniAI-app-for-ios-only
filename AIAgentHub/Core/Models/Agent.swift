import Foundation

enum AgentToolKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case files, web, github, computer, shellSandbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: return "Files"
        case .web: return "Web"
        case .github: return "GitHub"
        case .computer: return "Computer"
        case .shellSandbox: return "Sandbox Shell"
        }
    }

    var symbol: String {
        switch self {
        case .files: return "folder"
        case .web: return "globe"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .computer: return "desktopcomputer"
        case .shellSandbox: return "terminal"
        }
    }

    var emoji: String {
        switch self {
        case .files: return "📁"
        case .web: return "🌐"
        case .github: return "🐙"
        case .computer: return "💻"
        case .shellSandbox: return "⌨️"
        }
    }
}

struct AgentPermissions: Codable, Hashable {
    var allowFileWrite: Bool = true
    var allowFileDelete: Bool = false
    var allowNetwork: Bool = true
    var allowGitHubWrite: Bool = false
    var allowComputerControl: Bool = false
    var requireConfirmationBeforePush: Bool = true
    var offlineOnly: Bool = false
}

enum AgentModelBinding: Codable, Hashable {
    case cloud(provider: CloudProvider, model: String)
    case local(modelId: UUID)

    var displayName: String {
        switch self {
        case .cloud(let p, let m): return "\(p.title) · \(m)"
        case .local: return "Local model"
        }
    }

    var isLocal: Bool { if case .local = self { return true }; return false }
}

enum CloudProvider: String, Codable, CaseIterable, Identifiable, Hashable {
    case huggingFace, openAICompatible

    var id: String { rawValue }
    var title: String {
        switch self {
        case .huggingFace: return "Hugging Face Inference"
        case .openAICompatible: return "OpenAI-compatible endpoint"
        }
    }
}

struct Agent: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var descriptionText: String = ""
    var systemPrompt: String = "You are a helpful autonomous engineering agent. Plan, then act with tools."
    var temperature: Double = 0.7
    var maxTokens: Int = 2048
    var tools: Set<AgentToolKind> = [.files, .web]
    var permissions: AgentPermissions = .init()
    var binding: AgentModelBinding = .cloud(provider: .huggingFace, model: "Qwen/Qwen2.5-7B-Instruct")
    var createdAt: Date = Date()
}

// MARK: - Runs

enum PlanStepState: String, Codable, Hashable {
    case pending, active, done, failed, skipped

    var glyph: String {
        switch self {
        case .pending: return "○"
        case .active: return "→"
        case .done: return "✓"
        case .failed: return "✗"
        case .skipped: return "-"
        }
    }
}

struct PlanStep: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var state: PlanStepState = .pending
    var detail: String?
}

enum AgentEventKind: String, Codable, Hashable {
    case info, thought, toolCall, toolResult, output, error, confirmation
}

struct AgentEvent: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: AgentEventKind
    var title: String
    var body: String = ""
    var tool: AgentToolKind?
    var timestamp: Date = Date()
}

enum AgentRunStatus: String, Codable, Hashable {
    case idle, planning, running, waitingConfirmation, finished, failed, cancelled

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .planning: return "Planning"
        case .running: return "Running"
        case .waitingConfirmation: return "Waiting for confirmation"
        case .finished: return "Finished"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

struct AgentRun: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var agentId: UUID
    var task: String
    var status: AgentRunStatus = .idle
    var plan: [PlanStep] = []
    var events: [AgentEvent] = []
    var output: String = ""
    var startedAt: Date = Date()
    var finishedAt: Date?
    var pendingDiff: String?
}
