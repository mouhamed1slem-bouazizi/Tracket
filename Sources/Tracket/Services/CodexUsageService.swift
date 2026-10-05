import Foundation

enum CodexUsageServiceError: LocalizedError {
    case executableNotFound
    case appServerUnavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "The Codex app-server executable could not be found."
        case .appServerUnavailable:
            "Codex usage is temporarily unavailable."
        case .invalidResponse:
            "Codex returned an unreadable usage response."
        }
    }
}

struct CodexUsageResult: Sendable {
    var usage: ProviderAccountUsage
    var accountName: String?
}

struct CodexUsageService: Sendable {
    func readUsage() async throws -> CodexUsageResult {
        try await Task.detached(priority: .utility) {
            try Self.readUsageSynchronously()
        }.value
    }

    static func parse(
        accountResult: [String: Any],
        rateLimitResult: [String: Any],
        checkedAt: Date = Date()
    ) throws -> CodexUsageResult {
        let account = accountResult["account"] as? [String: Any]
        let email = account?["email"] as? String
        let accountPlan = account?["planType"] as? String

        let byID = rateLimitResult["rateLimitsByLimitId"] as? [String: Any]
        let preferred = (byID?["codex"] as? [String: Any])
            ?? (byID?.values.compactMap { $0 as? [String: Any] }.first)
        guard let limits = preferred ?? rateLimitResult["rateLimits"] as? [String: Any] else {
            throw CodexUsageServiceError.invalidResponse
        }

        let plan = (limits["planType"] as? String) ?? accountPlan
        let credits = limits["credits"] as? [String: Any]
        let resetSummary = rateLimitResult["rateLimitResetCredits"] as? [String: Any]
        let resetRows = resetSummary?["credits"] as? [[String: Any]] ?? []
        let resetExpirations = resetRows.compactMap { row in
            integer(row["expiresAt"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }

        let usage = ProviderAccountUsage(
            accountEmail: email,
            planName: plan.map(displayPlan),
            primary: window(from: limits["primary"], defaultTitle: "Session"),
            secondary: window(from: limits["secondary"], defaultTitle: "Weekly"),
            creditBalance: credits?["balance"] as? String,
            unlimitedCredits: credits?["unlimited"] as? Bool ?? false,
            availableResetCredits: integer(resetSummary?["availableCount"]),
            resetCreditExpirations: resetExpirations,
            modelName: limits["normalModelSlug"] as? String,
            checkedAt: checkedAt
        )
        return CodexUsageResult(usage: usage, accountName: email)
    }

    private static func readUsageSynchronously() throws -> CodexUsageResult {
        guard let executable = executableURL() else {
            throw CodexUsageServiceError.executableNotFound
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        let messages: [[String: Any]] = [
            [
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": ["name": "tracket", "title": "Tracket", "version": appVersion],
                    "capabilities": ["experimentalApi": true]
                ]
            ],
            ["method": "initialized"],
            ["id": 2, "method": "account/read", "params": ["refreshToken": false]],
            [
                "id": 3,
                "method": "account/rateLimits/read",
                "params": ["excludeResetCreditDetails": false, "supportsLunaReserve": false]
            ]
        ]

        for message in messages {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        }

        var buffer = Data()
        var accountResult: [String: Any]?
        var rateLimitResult: [String: Any]?
        let deadline = Date().addingTimeInterval(15)

        while Date() < deadline, accountResult == nil || rateLimitResult == nil {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard !line.isEmpty,
                      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = integer(object["id"]),
                      let result = object["result"] as? [String: Any] else { continue }
                if id == 2 { accountResult = result }
                if id == 3 { rateLimitResult = result }
            }
        }

        guard let accountResult, let rateLimitResult else {
            throw CodexUsageServiceError.appServerUnavailable
        }
        return try parse(accountResult: accountResult, rateLimitResult: rateLimitResult)
    }

    private static func window(from value: Any?, defaultTitle: String) -> ProviderUsageWindow? {
        guard let object = value as? [String: Any],
              let used = integer(object["usedPercent"]) else { return nil }
        let duration = integer(object["windowDurationMins"])
        let resetAt = integer(object["resetsAt"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return ProviderUsageWindow(
            title: windowTitle(minutes: duration, fallback: defaultTitle),
            usedPercent: used,
            durationMinutes: duration,
            resetAt: resetAt
        )
    }

    private static func windowTitle(minutes: Int?, fallback: String) -> String {
        guard let minutes else { return fallback }
        if minutes == 300 { return "Session" }
        if minutes == 10_080 { return "Weekly" }
        if minutes.isMultiple(of: 1_440) { return "\(minutes / 1_440)-day" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)-hour" }
        return fallback
    }

    private static func displayPlan(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func executableURL() -> URL? {
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        let pathDirectories = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":") ?? []
        for directory in pathDirectories {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("codex")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
