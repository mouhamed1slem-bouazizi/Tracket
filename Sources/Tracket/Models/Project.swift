import Foundation
import SwiftUI

enum ProjectStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case idea
    case prototype
    case building
    case polishing
    case launchReady
    case live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idea: "Idea"
        case .prototype: "Prototype"
        case .building: "Building"
        case .polishing: "Polishing"
        case .launchReady: "Launch ready"
        case .live: "Live"
        }
    }

    var symbol: String {
        switch self {
        case .idea: "lightbulb.fill"
        case .prototype: "hammer.fill"
        case .building: "wrench.and.screwdriver.fill"
        case .polishing: "sparkles"
        case .launchReady: "paperplane.fill"
        case .live: "globe.americas.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idea: .yellow
        case .prototype: .orange
        case .building: .blue
        case .polishing: .purple
        case .launchReady: .mint
        case .live: .green
        }
    }
}

enum RoadmapStatus: String, Codable, Sendable {
    case todo
    case active
    case done
}

enum RoadmapPriority: String, Codable, Sendable {
    case high
    case medium
    case low

    var title: String { rawValue.capitalized }
}

struct RoadmapItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var detail: String
    var status: RoadmapStatus
    var priority: RoadmapPriority
    var dueDate: Date
}

enum DeveloperTool: String, Codable, CaseIterable, Identifiable, Sendable {
    case git
    case github
    case xcode
    case vscode
    case cursor
    case codex
    case claudeCode
    case openCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .git: "Git"
        case .github: "GitHub"
        case .xcode: "Xcode"
        case .vscode: "VS Code"
        case .cursor: "Cursor"
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .openCode: "OpenCode"
        }
    }

    var symbol: String {
        switch self {
        case .git: "point.3.connected.trianglepath.dotted"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .xcode: "hammer.fill"
        case .vscode: "curlybraces"
        case .cursor: "cursorarrow.rays"
        case .codex: "shippingbox.fill"
        case .claudeCode: "terminal.fill"
        case .openCode: "terminal"
        }
    }

    var isDevelopmentEnvironment: Bool {
        switch self {
        case .xcode, .vscode, .cursor, .codex, .claudeCode, .openCode: true
        case .git, .github: false
        }
    }
}

enum ActivitySource: String, Codable, Sendable {
    case workspace
    case git
    case github
    case xcode
    case vscode
    case cursor
    case codex
    case claudeCode
    case openCode
    case system

    var title: String {
        switch self {
        case .workspace: "Workspace"
        case .git: "Git"
        case .github: "GitHub"
        case .xcode: "Xcode"
        case .vscode: "VS Code"
        case .cursor: "Cursor"
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .openCode: "OpenCode"
        case .system: "Tracket"
        }
    }

    var symbol: String {
        switch self {
        case .workspace: "doc.badge.clock"
        case .git: "arrow.triangle.branch"
        case .github: "arrow.up.arrow.down.circle.fill"
        case .xcode: "hammer.fill"
        case .vscode: "curlybraces"
        case .cursor: "cursorarrow.rays"
        case .codex: "shippingbox.fill"
        case .claudeCode: "terminal.fill"
        case .openCode: "terminal"
        case .system: "menubar.rectangle"
        }
    }

    var tint: Color {
        switch self {
        case .workspace: .blue
        case .git: .orange
        case .github: .purple
        case .xcode: .cyan
        case .vscode: .blue
        case .cursor: .indigo
        case .codex: .green
        case .claudeCode: .orange
        case .openCode: .mint
        case .system: .secondary
        }
    }
}

enum ActivityKind: String, Codable, Sendable {
    case workspaceChanged
    case commit
    case branchChanged
    case workingTreeChanged
    case push
    case pullAvailable
    case pullIntegrated
    case agentStarted
    case agentProgress
    case agentFinished
    case toolConfiguration
    case monitoring
}

struct ProjectActivityEvent: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var projectID: UUID
    var occurredAt: Date = Date()
    var source: ActivitySource
    var kind: ActivityKind
    var title: String
    var detail: String
    var fingerprint: String
}

struct HookInboxEvent: Codable, Sendable {
    let id: UUID
    let occurredAt: Date
    let source: String
    let event: String
    let cwd: String
    let sessionID: String?
    let turnID: String?
    let toolName: String?
}

struct TracketProject: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var path: String
    var goal: String
    var stage: ProjectStage
    var createdAt: Date = Date()
    var lastScannedAt: Date = Date()
    var lastActivityAt: Date
    var deadline: Date
    var branch: String?
    var remoteURL: String?
    var deploymentURL: String?
    var uncommittedChanges: Int
    var commitCountLast7Days: Int
    var detectedTools: [DeveloperTool]
    var languages: [String]
    var roadmap: [RoadmapItem]
    var aiSummary: String?
    var nextSuggestion: String?
    var headCommit: String? = nil
    var headCommitMessage: String? = nil
    var upstreamBranch: String? = nil
    var aheadCount: Int? = nil
    var behindCount: Int? = nil
    var toolActivity: [DeveloperTool: Date]? = nil
    var lastMonitorAt: Date? = nil
    var sourceProvider: ConnectionProvider? = nil
    var externalID: String? = nil
    var aiCompletionPercent: Int? = nil
    var aiCompletionRationale: String? = nil
    var aiAssessedAt: Date? = nil

    var completedTaskCount: Int {
        roadmap.filter { $0.status == .done }.count
    }

    var progress: Double {
        guard !roadmap.isEmpty else { return stage == .live ? 1 : 0 }
        return Double(completedTaskCount) / Double(roadmap.count)
    }

    var completionPercent: Int {
        if let aiCompletionPercent { return min(100, max(0, aiCompletionPercent)) }
        if stage == .live { return 100 }
        if !roadmap.isEmpty { return Int((progress * 100).rounded()) }
        return switch stage {
        case .idea: 5
        case .prototype: 20
        case .building: 45
        case .polishing: 70
        case .launchReady: 88
        case .live: 100
        }
    }

    var remainingPercent: Int { 100 - completionPercent }

    var latestDevelopmentTool: DeveloperTool? {
        let developmentActivity = (toolActivity ?? [:])
            .filter { $0.key.isDevelopmentEnvironment }
        if let sourceTool = sourceProvider?.tool,
           sourceTool.isDevelopmentEnvironment,
           let sourceDate = developmentActivity[sourceTool],
           sourceDate == developmentActivity.map(\.value).max() {
            return sourceTool
        }
        let recent = developmentActivity.max { $0.value < $1.value }?.key
        if let recent { return recent }
        if let tool = sourceProvider?.tool, tool.isDevelopmentEnvironment { return tool }
        let preference: [DeveloperTool] = [.codex, .claudeCode, .openCode, .cursor, .vscode, .xcode]
        return preference.first { detectedTools.contains($0) }
    }

    var latestDevelopmentActivityAt: Date {
        let toolDate = (toolActivity ?? [:])
            .filter { $0.key.isDevelopmentEnvironment }
            .map(\.value)
            .max()
        return max(lastActivityAt, toolDate ?? .distantPast)
    }

    var isLocalProject: Bool {
        path.hasPrefix("/") && URL(fileURLWithPath: path).isFileURL
    }

    var activeTask: RoadmapItem? {
        roadmap.first(where: { $0.status == .active })
            ?? roadmap.first(where: { $0.status == .todo })
    }

    var daysSinceActivity: Int {
        max(0, Calendar.current.dateComponents([.day], from: lastActivityAt, to: Date()).day ?? 0)
    }

    var daysUntilDeadline: Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: deadline)
        ).day ?? 0
    }

    var momentumScore: Int {
        let recency: Int
        switch daysSinceActivity {
        case 0...1: recency = 45
        case 2...3: recency = 35
        case 4...7: recency = 24
        case 8...14: recency = 12
        default: recency = 2
        }

        let commits = min(commitCountLast7Days * 4, 24)
        let completion = Int(progress * 21)
        let shipped = stage == .live ? 10 : 0
        return min(100, recency + commits + completion + shipped)
    }

    var momentumLabel: String {
        switch momentumScore {
        case 75...: "Strong"
        case 45...: "Moving"
        case 20...: "Cooling"
        default: "Stalled"
        }
    }

    var isAtRisk: Bool {
        stage != .live && (daysSinceActivity >= 7 || daysUntilDeadline < 0)
    }
}

struct ProjectSnapshot: Sendable {
    let name: String
    let path: String
    let stage: ProjectStage
    let lastActivityAt: Date
    let branch: String?
    let remoteURL: String?
    let uncommittedChanges: Int
    let commitCountLast7Days: Int
    let detectedTools: [DeveloperTool]
    let languages: [String]
    let headCommit: String?
    let headCommitMessage: String?
    let upstreamBranch: String?
    let aheadCount: Int
    let behindCount: Int
    let toolActivity: [DeveloperTool: Date]
}

struct AIProjectPlan: Codable, Sendable {
    let summary: String
    let stage: String
    let nextSuggestion: String
    let completionPercent: Int
    let completionRationale: String
    let milestones: [AIMilestone]
}

struct AIMilestone: Codable, Sendable {
    let title: String
    let detail: String
    let priority: String
    let dueInDays: Int
}
