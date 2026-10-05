import AppKit
import Foundation

struct GitHubCLIAuthService: Sendable {
    @MainActor
    func authenticate() async throws -> OAuthCredential {
        guard let executable = Self.executableURL() else {
            throw OAuthServiceError.provider(
                "GitHub CLI is not installed. Install GitHub CLI, or use a Tracket build with a GitHub OAuth registration."
            )
        }

        let login = try await Self.runStreaming(
            executable,
            arguments: [
                "auth", "login",
                "--hostname", "github.com",
                "--git-protocol", "https",
                "--web",
                "--clipboard",
                "--skip-ssh-key",
                "--scopes", "repo,read:user"
            ],
            environment: ["GH_BROWSER": "/usr/bin/true"]
        ) { code in
            Task { @MainActor in
                Self.presentDeviceCode(code)
            }
        }
        guard login.status == 0 else {
            if login.output.localizedCaseInsensitiveContains("deadline exceeded")
                || login.output.localizedCaseInsensitiveContains("expired") {
                throw OAuthServiceError.provider(
                    "The GitHub code expired before approval. Press Connect again to receive a new code."
                )
            }
            throw OAuthServiceError.provider(
                login.output.nilIfBlank ?? "GitHub browser authorization did not complete."
            )
        }

        return try await Task.detached(priority: .userInitiated) {
            let token = try Self.run(
                executable,
                arguments: ["auth", "token", "--hostname", "github.com"]
            )
            let value = token.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.status == 0, !value.isEmpty else {
                throw OAuthServiceError.provider("GitHub connected, but its credential could not be read securely.")
            }
            return OAuthCredential(accessToken: value, refreshToken: nil, expiresAt: nil)
        }.value
    }

    @MainActor
    private static func presentDeviceCode(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Connect GitHub"
        alert.informativeText = "Your one-time code is \(code). It has been copied. Open GitHub, paste the code, and approve Tracket."
        alert.addButton(withTitle: "Open GitHub")
        alert.runModal()

        if let verificationURL = URL(string: "https://github.com/login/device") {
            NSWorkspace.shared.open(verificationURL)
        }
    }

    private static func executableURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }

    static func deviceCode(in output: String) -> String? {
        let pattern = #"\b[A-Z0-9]{4}-[A-Z0-9]{4}\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: output,
                range: NSRange(output.startIndex..., in: output)
              ),
              let range = Range(match.range, in: output) else { return nil }
        return String(output[range])
    }

    private static func run(
        _ executable: URL,
        arguments: [String],
        environment overrides: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        for (name, value) in overrides { environment[name] = value }
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private static func runStreaming(
        _ executable: URL,
        arguments: [String],
        environment overrides: [String: String],
        onCode: @escaping @Sendable (String) -> Void
    ) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let buffer = GitHubProcessOutputBuffer(onCode: onCode)
            process.executableURL = executable
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            for (name, value) in overrides { environment[name] = value }
            process.environment = environment
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { buffer.append(data) }
            }
            process.terminationHandler = { finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty { buffer.append(remaining) }
                continuation.resume(returning: (finished.terminationStatus, buffer.output))
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class GitHubProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var emittedCode = false
    private let onCode: @Sendable (String) -> Void

    init(onCode: @escaping @Sendable (String) -> Void) {
        self.onCode = onCode
    }

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        let text = String(data: data, encoding: .utf8) ?? ""
        let code: String? = emittedCode ? nil : GitHubCLIAuthService.deviceCode(in: text)
        if code != nil { emittedCode = true }
        lock.unlock()
        if let code { onCode(code) }
    }

    var output: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
