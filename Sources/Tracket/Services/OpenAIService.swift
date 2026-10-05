import Foundation

enum OpenAIServiceError: LocalizedError {
    case invalidResponse
    case api(String)
    case missingOutput

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "OpenAI returned an invalid response."
        case .api(let message): message
        case .missingOutput: "OpenAI completed without a project plan."
        }
    }
}

struct OpenAIService: Sendable {
    static let model = "gpt-6-astra"
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    func createPlan(for project: TracketProject, apiKey: String) async throws -> AIProjectPlan {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(for: project))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw OpenAIServiceError.api(envelope?.error.message ?? "OpenAI request failed (\(http.statusCode)).")
        }

        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        let contentItems = envelope.output.flatMap { output in output.content ?? [] }
        guard let text = contentItems.first(where: { $0.type == "output_text" })?.text,
              let planData = text.data(using: String.Encoding.utf8) else {
            throw OpenAIServiceError.missingOutput
        }
        return try JSONDecoder().decode(AIProjectPlan.self, from: planData)
    }

    private func requestBody(for project: TracketProject) -> [String: Any] {
        let toolNames = project.detectedTools.map(\.title).joined(separator: ", ")
        let languages = project.languages.joined(separator: ", ")
        let currentTasks = project.roadmap.map { "- \($0.title): \($0.status.rawValue)" }.joined(separator: "\n")

        let input = """
        Project: \(project.name)
        Goal: \(project.goal)
        Current stage: \(project.stage.title)
        Days until deadline: \(project.daysUntilDeadline)
        Days since meaningful activity: \(project.daysSinceActivity)
        Commits in the last 7 days: \(project.commitCountLast7Days)
        Uncommitted changes: \(project.uncommittedChanges)
        Languages: \(languages.isEmpty ? "Unknown" : languages)
        Detected developer tools: \(toolNames.isEmpty ? "None" : toolNames)
        Current roadmap:
        \(currentTasks.isEmpty ? "No roadmap yet." : currentTasks)
        """

        return [
            "model": Self.model,
            "store": false,
            "reasoning": ["effort": "medium"],
            "instructions": """
                You are the product execution coach inside Tracket, a macOS app that helps developers finish and deploy side projects. Create a practical plan that reaches a small live release. Respect the existing stack and tools. Prefer concrete, independently finishable milestones. Keep every milestone small enough for one focused work session. Do not recommend unnecessary rewrites, platforms, or features. The first unfinished milestone must be the highest-value next action. Use a direct, encouraging tone without hype.
                """,
            "input": input,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "project_execution_plan",
                    "strict": true,
                    "schema": planSchema
                ]
            ]
        ]
    }

    private var planSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "summary": [
                    "type": "string",
                    "description": "A two-sentence assessment of the project's current execution state."
                ],
                "stage": [
                    "type": "string",
                    "enum": ProjectStage.allCases.map(\.rawValue)
                ],
                "nextSuggestion": [
                    "type": "string",
                    "description": "One concrete action the developer can start immediately."
                ],
                "completionPercent": [
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 100,
                    "description": "Evidence-based estimate of how much of the smallest useful live release is complete."
                ],
                "completionRationale": [
                    "type": "string",
                    "description": "A short explanation of the strongest evidence behind the completion estimate."
                ],
                "milestones": [
                    "type": "array",
                    "minItems": 4,
                    "maxItems": 8,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "title": ["type": "string"],
                            "detail": ["type": "string"],
                            "priority": ["type": "string", "enum": ["high", "medium", "low"]],
                            "dueInDays": ["type": "integer", "minimum": 0, "maximum": 90]
                        ],
                        "required": ["title", "detail", "priority", "dueInDays"]
                    ]
                ]
            ],
            "required": ["summary", "stage", "nextSuggestion", "completionPercent", "completionRationale", "milestones"]
        ]
    }
}

private struct ResponseEnvelope: Decodable {
    let output: [Output]

    struct Output: Decodable {
        let content: [Content]?
    }

    struct Content: Decodable {
        let type: String
        let text: String?
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}
