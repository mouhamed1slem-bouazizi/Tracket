import Foundation
import SwiftUI

enum ConnectionMode: String, Codable, Sendable {
    case localAdapter
    case oauth
    case apiKey
}

enum ConnectionProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claudeCode
    case openCode
    case cursor
    case vscode
    case github
    case cloudflare
    case vercel
    case render
    case xcode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .openCode: "OpenCode"
        case .cursor: "Cursor"
        case .vscode: "VS Code"
        case .github: "GitHub"
        case .cloudflare: "Cloudflare"
        case .vercel: "Vercel"
        case .render: "Render"
        case .xcode: "Xcode"
        }
    }

    var mode: ConnectionMode {
        switch self {
        case .github, .cloudflare, .vercel, .render: .oauth
        default: .localAdapter
        }
    }

    var symbol: String {
        switch self {
        case .codex: "shippingbox.fill"
        case .claudeCode: "terminal.fill"
        case .openCode: "terminal"
        case .cursor: "cursorarrow.rays"
        case .vscode: "curlybraces"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .cloudflare: "cloud.fill"
        case .vercel: "triangle.fill"
        case .render: "server.rack"
        case .xcode: "hammer.fill"
        }
    }

    var tint: Color {
        switch self {
        case .codex: .green
        case .claudeCode: .orange
        case .openCode: .mint
        case .cursor: .indigo
        case .vscode: .blue
        case .github: .purple
        case .cloudflare: .orange
        case .vercel: .primary
        case .render: .cyan
        case .xcode: .blue
        }
    }

    var connectionLabel: String {
        switch mode {
        case .localAdapter: "Local adapter"
        case .oauth: "OAuth account"
        case .apiKey: "OAuth account"
        }
    }

    var credentialPlaceholder: String {
        switch self {
        case .github: "GitHub OAuth client ID"
        case .cloudflare: "Cloudflare OAuth client ID"
        case .vercel: "Vercel OAuth client ID"
        case .render: "Render hosted MCP OAuth"
        default: "OAuth client ID"
        }
    }

    var tool: DeveloperTool? {
        switch self {
        case .codex: .codex
        case .claudeCode: .claudeCode
        case .openCode: .openCode
        case .cursor: .cursor
        case .vscode: .vscode
        case .github: .github
        case .xcode: .xcode
        case .cloudflare, .vercel, .render: nil
        }
    }
}

struct DeveloperConnection: Identifiable, Codable, Hashable, Sendable {
    var id: ConnectionProvider { provider }
    var provider: ConnectionProvider
    var connectedAt: Date
    var lastSyncedAt: Date?
    var accountName: String?
    var roots: [String]
    var importedProjectCount: Int
    var lastError: String?
    var usageStatus: ProviderUsageStatus? = nil
    var accountUsage: ProviderAccountUsage? = nil
}

struct ProviderUsageStatus: Codable, Hashable, Sendable {
    var label: String
    var remaining: Int
    var limit: Int
    var resetAt: Date?
    var checkedAt: Date

    var fractionRemaining: Double {
        guard limit > 0 else { return 0 }
        return min(1, max(0, Double(remaining) / Double(limit)))
    }
}

struct ProviderAccountUsage: Codable, Hashable, Sendable {
    var accountEmail: String?
    var planName: String?
    var primary: ProviderUsageWindow?
    var secondary: ProviderUsageWindow?
    var creditBalance: String?
    var unlimitedCredits: Bool
    var availableResetCredits: Int?
    var resetCreditExpirations: [Date]
    var modelName: String?
    var checkedAt: Date
    var creditCurrency: String? = nil
    var metrics: [ProviderUsageMetric]? = nil
    var note: String? = nil
    var detailsURL: String? = nil
}

struct ProviderUsageWindow: Codable, Hashable, Sendable {
    var title: String
    var usedPercent: Int
    var durationMinutes: Int?
    var resetAt: Date?

    var remainingPercent: Int {
        min(100, max(0, 100 - usedPercent))
    }

    var fractionRemaining: Double {
        Double(remainingPercent) / 100
    }
}

struct ProviderUsageMetric: Codable, Hashable, Sendable {
    var label: String
    var value: String
    var detail: String? = nil
}

struct ImportedProjectDescriptor: Hashable, Sendable {
    var name: String
    var externalID: String
    var provider: ConnectionProvider
    var remoteURL: String?
    var deploymentURL: String?
    var updatedAt: Date
    var stage: ProjectStage
}
