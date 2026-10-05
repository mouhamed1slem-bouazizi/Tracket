import Foundation
import Dispatch

enum ProjectScannerError: LocalizedError {
    case invalidDirectory

    var errorDescription: String? {
        "Choose a readable project folder."
    }
}

struct ProjectScanner: Sendable {
    private var fileManager: FileManager { .default }

    func scan(url: URL, fetchRemote: Bool = false) throws -> ProjectSnapshot {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectScannerError.invalidDirectory
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let allNames = Set(children.map { $0.lastPathComponent })
        var tools: Set<DeveloperTool> = []

        let gitFolder = url.appendingPathComponent(".git").path
        if fileManager.fileExists(atPath: gitFolder) { tools.insert(.git) }
        if children.contains(where: { $0.pathExtension == "xcodeproj" || $0.pathExtension == "xcworkspace" })
            || allNames.contains("Package.swift") { tools.insert(.xcode) }
        if fileManager.fileExists(atPath: url.appendingPathComponent(".vscode").path) { tools.insert(.vscode) }
        if fileManager.fileExists(atPath: url.appendingPathComponent(".cursor").path)
            || allNames.contains(".cursorrules") { tools.insert(.cursor) }
        if fileManager.fileExists(atPath: url.appendingPathComponent(".codex").path)
            || allNames.contains("AGENTS.md") { tools.insert(.codex) }
        if fileManager.fileExists(atPath: url.appendingPathComponent(".claude").path)
            || allNames.contains("CLAUDE.md") { tools.insert(.claudeCode) }
        if fileManager.fileExists(atPath: url.appendingPathComponent(".opencode").path)
            || allNames.contains("opencode.json") { tools.insert(.openCode) }

        if fetchRemote, tools.contains(.git) {
            _ = git(url, ["fetch", "--quiet", "--prune"], timeout: 12)
        }

        let branch = git(url, ["branch", "--show-current"])
        let status = git(url, ["status", "--porcelain"])
        let uncommitted = status?.split(separator: "\n").count ?? 0
        let commits = git(url, ["log", "--since=7 days ago", "--pretty=format:%H"])?
            .split(separator: "\n").count ?? 0
        let lastTimestamp = git(url, ["log", "-1", "--format=%ct"])
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:))
        let headCommit = git(url, ["rev-parse", "HEAD"])
        let headCommitMessage = git(url, ["log", "-1", "--pretty=format:%s"])
        let upstream = git(url, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"])
        let trackingCounts = upstream == nil
            ? (ahead: 0, behind: 0)
            : parseTrackingCounts(git(url, ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"]))
        let remote = git(url, ["config", "--get", "remote.origin.url"])
        if remote?.contains("github.com") == true { tools.insert(.github) }

        let inspection = inspectFiles(in: url)
        let inferredDate = [lastTimestamp, inspection.lastModified]
            .compactMap { $0 }
            .max() ?? Date()

        return ProjectSnapshot(
            name: url.lastPathComponent,
            path: url.path,
            stage: inferStage(names: allNames),
            lastActivityAt: lastTimestamp ?? inferredDate,
            branch: branch?.nilIfEmpty,
            remoteURL: normalizeRemote(remote),
            uncommittedChanges: uncommitted,
            commitCountLast7Days: commits,
            detectedTools: DeveloperTool.allCases.filter(tools.contains),
            languages: inspection.languages,
            headCommit: headCommit?.nilIfEmpty,
            headCommitMessage: headCommitMessage?.nilIfEmpty,
            upstreamBranch: upstream?.nilIfEmpty,
            aheadCount: trackingCounts.ahead,
            behindCount: trackingCounts.behind,
            toolActivity: detectToolActivity(in: url, tools: tools)
        )
    }

    private func inferStage(names: Set<String>) -> ProjectStage {
        let deployMarkers = ["vercel.json", "netlify.toml", "fly.toml", "render.yaml", "Dockerfile"]
        let projectMarkers = [
            "Package.swift", "package.json", "Cargo.toml", "go.mod", "pyproject.toml",
            "requirements.txt", "Podfile", "Gemfile"
        ]

        if names.contains(where: deployMarkers.contains) { return .launchReady }
        if names.contains(where: projectMarkers.contains) { return .building }
        if !names.isEmpty { return .prototype }
        return .idea
    }

    private func inspectFiles(in url: URL) -> FileInspection {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return FileInspection(languages: [], lastModified: nil) }

        let ignored = Set(["node_modules", ".build", "DerivedData", "Pods", "vendor", "dist"])
        var counts: [String: Int] = [:]
        var inspected = 0
        var lastModified: Date?

        for case let fileURL as URL in enumerator {
            if ignored.contains(fileURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard inspected < 4_000 else { break }
            inspected += 1

            let values = try? fileURL.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            if let modified = values?.contentModificationDate,
               modified <= Date().addingTimeInterval(60),
               lastModified == nil || modified > lastModified! {
                lastModified = modified
            }

            let language: String? = switch fileURL.pathExtension.lowercased() {
            case "swift": "Swift"
            case "ts", "tsx": "TypeScript"
            case "js", "jsx": "JavaScript"
            case "py": "Python"
            case "rs": "Rust"
            case "go": "Go"
            case "kt", "kts": "Kotlin"
            case "java": "Java"
            case "rb": "Ruby"
            case "php": "PHP"
            case "cs": "C#"
            case "cpp", "cc", "cxx", "c", "h", "hpp": "C/C++"
            default: nil
            }
            if let language { counts[language, default: 0] += 1 }
        }

        return FileInspection(
            languages: counts.sorted { $0.value > $1.value }.prefix(3).map(\.key),
            lastModified: lastModified
        )
    }

    private func detectToolActivity(in url: URL, tools: Set<DeveloperTool>) -> [DeveloperTool: Date] {
        var result: [DeveloperTool: Date] = [:]
        let candidates: [DeveloperTool: [URL]] = [
            .vscode: [url.appendingPathComponent(".vscode")],
            .cursor: [url.appendingPathComponent(".cursor"), url.appendingPathComponent(".cursorrules")],
            .codex: [url.appendingPathComponent(".codex"), url.appendingPathComponent("AGENTS.md")],
            .claudeCode: [url.appendingPathComponent(".claude"), url.appendingPathComponent("CLAUDE.md")],
            .openCode: [url.appendingPathComponent(".opencode"), url.appendingPathComponent("opencode.json")]
        ]

        for (tool, urls) in candidates where tools.contains(tool) {
            if let date = urls.compactMap(latestModificationDate).max() {
                result[tool] = date
            }
        }
        return result
    }

    private func latestModificationDate(at url: URL) -> Date? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue {
            return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }

        var latest = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return latest }

        var inspected = 0
        for case let child as URL in enumerator {
            guard inspected < 1_000 else { break }
            inspected += 1
            let values = try? child.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let modified = values?.contentModificationDate else { continue }
            if latest == nil || modified > latest! { latest = modified }
        }
        return latest
    }

    private func parseTrackingCounts(_ output: String?) -> (ahead: Int, behind: Int) {
        let values = output?.split(whereSeparator: \.isWhitespace).compactMap { Int($0) } ?? []
        guard values.count == 2 else { return (0, 0) }
        return (values[0], values[1])
    }

    private func git(_ url: URL, _ arguments: [String], timeout: TimeInterval = 5) -> String? {
        guard fileManager.fileExists(atPath: url.appendingPathComponent(".git").path) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", url.path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "GIT_TERMINAL_PROMPT": "0",
            "GCM_INTERACTIVE": "Never",
            "GIT_SSH_COMMAND": "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=5"
        ]) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
            if finished.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                _ = finished.wait(timeout: .now() + 1)
                return nil
            }
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func normalizeRemote(_ remote: String?) -> String? {
        guard let remote = remote?.nilIfEmpty else { return nil }
        if remote.hasPrefix("git@github.com:") {
            let path = remote.replacingOccurrences(of: "git@github.com:", with: "")
                .replacingOccurrences(of: ".git", with: "")
            return "https://github.com/\(path)"
        }
        return remote.replacingOccurrences(of: ".git", with: "")
    }
}

private struct FileInspection {
    let languages: [String]
    let lastModified: Date?
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
