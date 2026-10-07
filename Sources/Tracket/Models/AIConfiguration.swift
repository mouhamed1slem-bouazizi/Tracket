import Foundation

enum AIExecutionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case local
    case cloud
    case smartHybrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: "Local only"
        case .cloud: "Cloud provider"
        case .smartHybrid: "Smart hybrid"
        }
    }

    var detail: String {
        switch self {
        case .local: "Runs privately on this Mac after the model is downloaded."
        case .cloud: "Uses the selected provider for every AI request."
        case .smartHybrid: "Uses local AI first and asks before any cloud fallback."
        }
    }
}

enum CloudAIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI
    case openRouter
    case anthropic
    case deepSeek
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .anthropic: "Anthropic"
        case .deepSeek: "DeepSeek"
        case .custom: "Custom compatible API"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-6.1-sol"
        case .openRouter: "openai/gpt-6.1-sol"
        case .anthropic: "claude-sonnet-4-5"
        case .deepSeek: "deepseek-chat"
        case .custom: ""
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .deepSeek: "https://api.deepseek.com/v1"
        case .custom: ""
        }
    }
}

enum AIContextSharing: String, Codable, CaseIterable, Identifiable, Sendable {
    case metadataOnly
    case metadataAndDiff
    case relevantSource

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metadataOnly: "Metadata only"
        case .metadataAndDiff: "Metadata and Git diff"
        case .relevantSource: "Relevant source excerpts"
        }
    }

    var detail: String {
        switch self {
        case .metadataOnly: "Project status, roadmap, languages, and Git counters."
        case .metadataAndDiff: "Also includes a bounded summary of current changes."
        case .relevantSource: "Also includes locally ranked excerpts; never the whole repository."
        }
    }
}

enum LocalAIModel: String, Codable, CaseIterable, Identifiable, Sendable {
    case qwenCoder7B
    case devstral24B

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qwenCoder7B: "Qwen2.5-Coder 7B"
        case .devstral24B: "Devstral Small 2 24B"
        }
    }

    var repositoryID: String {
        switch self {
        case .qwenCoder7B: "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit"
        case .devstral24B: "mlx-community/Devstral-Small-2-24B-Instruct-2512-4bit"
        }
    }

    var estimatedDownload: String {
        switch self {
        case .qwenCoder7B: "about 4.5 GB"
        case .devstral24B: "about 14 GB"
        }
    }

    var minimumMemoryGB: Int {
        switch self {
        case .qwenCoder7B: 16
        case .devstral24B: 32
        }
    }

    var summary: String {
        switch self {
        case .qwenCoder7B: "Recommended for everyday planning on Apple silicon Macs."
        case .devstral24B: "Stronger repository reasoning for Macs with at least 32 GB memory."
        }
    }
}

struct AISettings: Codable, Equatable, Sendable {
    var mode: AIExecutionMode = .local
    var localModel: LocalAIModel = .qwenCoder7B
    var cloudProvider: CloudAIProvider = .openAI
    var cloudModel: String = CloudAIProvider.openAI.defaultModel
    var customBaseURL: String = ""
    var contextSharing: AIContextSharing = .metadataOnly
    var allowCloudFallback: Bool = false

    var effectiveBaseURL: String {
        customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? cloudProvider.defaultBaseURL
            : customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveModel: String {
        let trimmed = cloudModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? cloudProvider.defaultModel : trimmed
    }
}

enum LocalModelState: Equatable, Sendable {
    case notDownloaded
    case partial(bytes: Int64)
    case downloading(Double)
    case ready(bytes: Int64)
    case loading
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}
