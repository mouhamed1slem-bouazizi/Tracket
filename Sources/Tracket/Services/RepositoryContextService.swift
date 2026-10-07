import Foundation

struct RepositoryContextService: Sendable {
    private let maxDiffCharacters = 12_000
    private let maxSourceCharacters = 28_000

    func build(for project: TracketProject, sharing: AIContextSharing, query: String? = nil) -> String {
        guard project.isLocalProject else { return "Cloud project metadata only; no local workspace is linked." }
        switch sharing {
        case .metadataOnly:
            return "Metadata only. Repository file contents were not read."
        case .metadataAndDiff:
            return boundedGitDiff(at: project.path)
        case .relevantSource:
            return relevantSourceIndex(at: project.path, query: query)
        }
    }

    private func boundedGitDiff(at path: String) -> String {
        let result = run("/usr/bin/git", arguments: ["-C", path, "diff", "--stat", "--", "."])
        let names = run("/usr/bin/git", arguments: ["-C", path, "diff", "--name-status", "--", "."])
        let content = "Git diff summary:\n\(result)\nChanged files:\n\(names)"
        return String(content.prefix(maxDiffCharacters)).nilIfEmpty ?? "No current Git diff was available."
    }

    private func relevantSourceIndex(at path: String, query: String?) -> String {
        let root = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return "Repository index was unavailable." }

        let ignored = Set(["node_modules", "DerivedData", ".build", "build", "dist", "vendor", "Pods", ".git"])
        let sourceExtensions = Set(["swift", "m", "mm", "h", "js", "jsx", "ts", "tsx", "py", "rb", "go", "rs", "java", "kt", "cs", "cpp", "c", "vue", "svelte"])
        let importantNames = Set(["README.md", "Package.swift", "package.json", "Cargo.toml", "pyproject.toml", "requirements.txt", "Dockerfile", "wrangler.toml", "vercel.json"])
        let queryTerms = Set((query ?? "")
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 })
        var candidates: [(url: URL, relative: String, modified: Date, priority: Int)] = []
        var fileInventory: [String] = []

        for case let url as URL in enumerator {
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let parts = relative.split(separator: "/").map(String.init)
            if parts.contains(where: ignored.contains) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            if fileInventory.count < 300 { fileInventory.append(relative) }
            guard (values.fileSize ?? 0) <= 250_000 else { continue }
            let isImportant = importantNames.contains(url.lastPathComponent)
            let isSource = sourceExtensions.contains(url.pathExtension.lowercased())
            guard isImportant || isSource else { continue }
            let loweredPath = relative.lowercased()
            let matches = queryTerms.reduce(0) { $0 + (loweredPath.contains($1) ? 4 : 0) }
            candidates.append((url, relative, values.contentModificationDate ?? .distantPast, (isImportant ? 2 : 1) + matches))
        }

        candidates.sort {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.modified > $1.modified
        }

        let inventory = "PROJECT FILE MAP\n" + fileInventory.sorted().joined(separator: "\n")
        var remaining = max(0, maxSourceCharacters - inventory.count)
        var sections: [String] = [String(inventory.prefix(maxSourceCharacters))]
        for candidate in candidates.prefix(18) where remaining > 500 {
            guard let data = try? Data(contentsOf: candidate.url, options: [.mappedIfSafe]),
                  let text = String(data: data.prefix(min(data.count, 4_000)), encoding: .utf8) else { continue }
            let section = "--- \(candidate.relative) ---\n\(text)"
            sections.append(String(section.prefix(remaining)))
            remaining -= min(section.count, remaining)
        }
        return sections.count == 1 && fileInventory.isEmpty
            ? "No relevant project files were indexed."
            : sections.joined(separator: "\n\n")
    }

    private func run(_ executable: String, arguments: [String]) -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

struct ProjectCompletionEstimator: Sendable {
    func estimate(_ project: TracketProject) -> Int {
        if project.stage == .live { return 100 }
        let stageBase: Int = switch project.stage {
        case .idea: 5
        case .prototype: 18
        case .building: 42
        case .polishing: 68
        case .launchReady: 86
        case .live: 100
        }
        let roadmap = project.roadmap.isEmpty ? stageBase : Int(project.progress * 82) + 6
        let activity = project.commitCountLast7Days > 0 ? 4 : 0
        let repository = project.remoteURL == nil ? 0 : 4
        let deployment = project.deploymentURL == nil ? 0 : 10
        let dirtyPenalty = project.uncommittedChanges > 20 ? 3 : 0
        return min(99, max(0, (stageBase + roadmap) / 2 + activity + repository + deployment - dirtyPenalty))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
