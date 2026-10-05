import Foundation

enum CodexHookInstallerError: LocalizedError {
    case helperMissing
    case invalidExistingConfiguration

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            "The Tracket hook helper is missing. Rebuild the packaged app and try again."
        case .invalidExistingConfiguration:
            "The existing .codex/hooks.json is not valid JSON, so Tracket left it unchanged."
        }
    }
}

struct CodexHookInstaller {
    private let marker = "Tracket/bin/tracket-hook"
    private let helperSourceOverride: URL?
    private let installDirectoryOverride: URL?

    init(helperSourceURL: URL? = nil, installDirectory: URL? = nil) {
        self.helperSourceOverride = helperSourceURL
        self.installDirectoryOverride = installDirectory
    }

    func isConnected(to project: TracketProject) -> Bool {
        let url = hooksURL(for: project)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        return containsTracketCommand(in: object)
    }

    func connect(to project: TracketProject) throws {
        let installedHelper = try installHelper()
        let fileManager = FileManager.default
        let hooksURL = hooksURL(for: project)
        try fileManager.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var root: [String: Any]
        if fileManager.fileExists(atPath: hooksURL.path) {
            let data = try Data(contentsOf: hooksURL)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CodexHookInstallerError.invalidExistingConfiguration
            }
            root = object
        } else {
            root = ["description": "Project hooks, including Tracket's local progress bridge."]
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = shellQuoted(installedHelper.path)
        addHandler(event: "SessionStart", matcher: "startup|resume|clear", command: command, async: true, hooks: &hooks)
        addHandler(event: "PostToolUse", matcher: "apply_patch|Edit|Write", command: command, async: true, hooks: &hooks)
        addHandler(event: "Stop", matcher: nil, command: command, async: true, hooks: &hooks)
        addHandler(event: "SessionEnd", matcher: nil, command: command, async: false, hooks: &hooks)
        root["hooks"] = hooks

        let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: hooksURL, options: .atomic)
    }

    private func addHandler(
        event: String,
        matcher: String?,
        command: String,
        async: Bool,
        hooks: inout [String: Any]
    ) {
        var groups = hooks[event] as? [[String: Any]] ?? []
        let alreadyInstalled = groups.contains { group in
            let handlers = group["hooks"] as? [[String: Any]] ?? []
            return handlers.contains { ($0["command"] as? String)?.contains(marker) == true }
        }
        guard !alreadyInstalled else { return }

        var handler: [String: Any] = [
            "type": "command",
            "command": command,
            "timeout": 3
        ]
        if async { handler["async"] = true }

        var group: [String: Any] = ["hooks": [handler]]
        if let matcher { group["matcher"] = matcher }
        groups.append(group)
        hooks[event] = groups
    }

    private func installHelper() throws -> URL {
        let fileManager = FileManager.default
        guard let source = helperSourceURLs.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
            throw CodexHookInstallerError.helperMissing
        }

        let binDirectory: URL
        if let installDirectoryOverride {
            binDirectory = installDirectoryOverride
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            binDirectory = appSupport
                .appendingPathComponent("Tracket", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
        }
        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let destination = binDirectory.appendingPathComponent("tracket-hook")

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    private var helperSourceURLs: [URL] {
        var urls: [URL] = []
        if let helperSourceOverride { urls.append(helperSourceOverride) }
        urls.append(
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/tracket-hook")
        )
        if let executable = Bundle.main.executableURL {
            urls.append(executable.deletingLastPathComponent().appendingPathComponent("tracket-hook"))
        }
        return urls
    }

    private func hooksURL(for project: TracketProject) -> URL {
        URL(fileURLWithPath: project.path)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func containsTracketCommand(in value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            if let command = dictionary["command"] as? String,
               command.contains(marker) {
                return true
            }
            return dictionary.values.contains(where: containsTracketCommand)
        }
        if let array = value as? [Any] {
            return array.contains(where: containsTracketCommand)
        }
        return false
    }
}
