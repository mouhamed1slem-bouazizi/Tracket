import Foundation

struct LocalToolUsageService: Sendable {
    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func usage(for provider: ConnectionProvider) async -> ProviderAccountUsage? {
        await Task.detached(priority: .utility) {
            switch provider {
            case .openCode:
                Self.openCodeUsage()
            case .claudeCode:
                Self.claudeUsage(home: home)
            default:
                nil
            }
        }.value
    }

    static func parseOpenCodeStats(_ raw: String, checkedAt: Date = Date()) -> ProviderAccountUsage? {
        let text = raw.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        guard let sessions = value(after: "Sessions", in: text),
              let messages = value(after: "Messages", in: text) else { return nil }
        let input = value(after: "Input", in: text) ?? "0"
        let output = value(after: "Output", in: text) ?? "0"
        let totalCost = value(after: "Total Cost", in: text) ?? "$0.00"
        let topModel = firstModel(in: text)
        return ProviderAccountUsage(
            accountEmail: nil,
            planName: "30-day local stats",
            primary: nil,
            secondary: nil,
            creditBalance: nil,
            unlimitedCredits: false,
            availableResetCredits: nil,
            resetCreditExpirations: [],
            modelName: topModel,
            checkedAt: checkedAt,
            metrics: [
                ProviderUsageMetric(label: "Sessions", value: sessions),
                ProviderUsageMetric(label: "Messages", value: messages),
                ProviderUsageMetric(label: "Input tokens", value: input),
                ProviderUsageMetric(label: "Output tokens", value: output),
                ProviderUsageMetric(label: "Local cost", value: totalCost)
            ],
            note: "OpenCode routes through multiple model providers, so remaining subscription credit depends on the selected provider.",
            detailsURL: "https://opencode.ai/console/usage"
        )
    }

    static func parseClaudeHistory(
        files: [URL],
        since: Date,
        checkedAt: Date = Date()
    ) -> ProviderAccountUsage? {
        var sessions = 0
        var messages = 0
        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        var latestModel: String?

        for file in files.prefix(500) {
            guard let data = try? Data(contentsOf: file), !data.isEmpty else { continue }
            var countedSession = false
            for line in data.split(separator: 0x0A) {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      (timestamp(object["timestamp"]) ?? fileDate(file)) >= since else { continue }
                let message = object["message"] as? [String: Any]
                guard let usage = message?["usage"] as? [String: Any] else { continue }
                if !countedSession {
                    countedSession = true
                    sessions += 1
                }
                messages += 1
                inputTokens += integer(usage["input_tokens"]) ?? 0
                outputTokens += integer(usage["output_tokens"]) ?? 0
                cacheReadTokens += integer(usage["cache_read_input_tokens"]) ?? 0
                if let model = message?["model"] as? String { latestModel = model }
            }
        }
        guard sessions > 0 || messages > 0 else { return nil }
        return ProviderAccountUsage(
            accountEmail: nil,
            planName: "30-day local stats",
            primary: nil,
            secondary: nil,
            creditBalance: nil,
            unlimitedCredits: false,
            availableResetCredits: nil,
            resetCreditExpirations: [],
            modelName: latestModel,
            checkedAt: checkedAt,
            metrics: [
                ProviderUsageMetric(label: "Sessions", value: sessions.formatted()),
                ProviderUsageMetric(label: "Messages", value: messages.formatted()),
                ProviderUsageMetric(label: "Input tokens", value: inputTokens.formatted()),
                ProviderUsageMetric(label: "Output tokens", value: outputTokens.formatted()),
                ProviderUsageMetric(label: "Cache read", value: cacheReadTokens.formatted())
            ],
            note: "Claude exposes subscription limits in /usage and its usage dashboard, but not through a stable local machine-readable API.",
            detailsURL: "https://claude.ai/settings/usage"
        )
    }

    private static func openCodeUsage() -> ProviderAccountUsage? {
        guard let executable = executable(named: "opencode", candidates: ["/opt/homebrew/bin/opencode", "/usr/local/bin/opencode"]) else {
            return nil
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["stats", "--days", "30", "--models", "5"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            return parseOpenCodeStats(text)
        } catch {
            return nil
        }
    }

    private static func claudeUsage(home: URL) -> ProviderAccountUsage? {
        let directory = home.appendingPathComponent(".claude/projects")
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        let since = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        var files: [URL] = []
        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            if fileDate(file) >= since { files.append(file) }
            if files.count >= 500 { break }
        }
        return parseClaudeHistory(files: files, since: since)
    }

    private static func value(after label: String, in text: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        let pattern = "(?m)^\\s*│?\\s*\(escaped)\\s+([^│\\n]+?)\\s*│?\\s*$"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstModel(in text: String) -> String? {
        guard let range = text.range(of: "MODEL USAGE") else { return nil }
        let tail = text[range.upperBound...]
        for line in tail.components(separatedBy: .newlines) {
            let candidate = line.trimmingCharacters(in: CharacterSet(charactersIn: " │├└─"))
            if candidate.contains("/"), !candidate.contains("MODEL") { return candidate }
        }
        return nil
    }

    private static func timestamp(_ value: Any?) -> Date? {
        if let milliseconds = value as? NSNumber {
            let raw = milliseconds.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
        }
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func fileDate(_ file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func executable(named name: String, candidates: [String]) -> URL? {
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        for directory in ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":") ?? [] {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
