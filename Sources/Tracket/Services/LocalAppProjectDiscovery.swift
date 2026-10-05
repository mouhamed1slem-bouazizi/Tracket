import Foundation

enum LocalAppProjectDiscoveryError: LocalizedError {
    case unsupported
    case appStateNotFound(String)
    case noWorkspaces(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            "This tool does not have an automatic local adapter."
        case .appStateNotFound(let app):
            "\(app) local state was not found. Open the app and use a project first."
        case .noWorkspaces(let app):
            "\(app) is installed, but no readable project workspaces were found yet."
        }
    }
}

struct LocalAppProjectDiscovery: Sendable {
    private let home: URL
    private let applicationSupport: URL
    private let preferences: URL
    private let sqliteExecutable: URL

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationSupport: URL? = nil,
        preferences: URL? = nil,
        sqliteExecutable: URL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    ) {
        self.home = home.standardizedFileURL
        self.applicationSupport = applicationSupport
            ?? home.appendingPathComponent("Library/Application Support")
        self.preferences = preferences
            ?? home.appendingPathComponent("Library/Preferences")
        self.sqliteExecutable = sqliteExecutable
    }

    func discover(provider: ConnectionProvider) throws -> [URL] {
        let candidates: [WorkspaceCandidate]
        switch provider {
        case .claudeCode: candidates = try claudeCandidates()
        case .openCode: candidates = try openCodeCandidates()
        case .cursor: candidates = try editorCandidates(appFolder: "Cursor", appName: provider.title)
        case .vscode: candidates = try editorCandidates(appFolder: "Code", appName: provider.title)
        case .xcode: candidates = try xcodeCandidates()
        default: throw LocalAppProjectDiscoveryError.unsupported
        }

        var seen = Set<String>()
        let urls = candidates.compactMap { candidate -> URL? in
            guard let normalized = normalize(candidate) else { return nil }
            return seen.insert(normalized.path).inserted ? normalized : nil
        }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        guard !urls.isEmpty else { throw LocalAppProjectDiscoveryError.noWorkspaces(provider.title) }
        return urls
    }

    private func editorCandidates(appFolder: String, appName: String) throws -> [WorkspaceCandidate] {
        let storage = applicationSupport
            .appendingPathComponent(appFolder)
            .appendingPathComponent("User/globalStorage/storage.json")
        guard let data = try? Data(contentsOf: storage),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            throw LocalAppProjectDiscoveryError.appStateNotFound(appName)
        }

        var values: [WorkspaceCandidate] = []
        collectEditorURLs(json, key: nil, into: &values)
        return values
    }

    private func collectEditorURLs(_ value: Any, key: String?, into output: inout [WorkspaceCandidate]) {
        if let dictionary = value as? [String: Any] {
            for (childKey, child) in dictionary {
                if childKey.hasPrefix("file://"), let url = URL(string: childKey) {
                    output.append(WorkspaceCandidate(url: url, isExplicitFolder: true))
                }
                collectEditorURLs(child, key: childKey, into: &output)
            }
            return
        }
        if let array = value as? [Any] {
            for child in array { collectEditorURLs(child, key: key, into: &output) }
            return
        }
        guard let string = value as? String else { return }
        let lowerKey = key?.lowercased() ?? ""
        guard lowerKey.contains("folder") || lowerKey.contains("workspace") else { return }
        if string.hasPrefix("file://"), let url = URL(string: string) {
            output.append(WorkspaceCandidate(url: url, isExplicitFolder: true))
        } else if string.hasPrefix("/") {
            output.append(WorkspaceCandidate(url: URL(fileURLWithPath: string), isExplicitFolder: true))
        }
    }

    private func openCodeCandidates() throws -> [WorkspaceCandidate] {
        let database = home.appendingPathComponent(".local/share/opencode/opencode.db")
        guard FileManager.default.fileExists(atPath: database.path) else {
            throw LocalAppProjectDiscoveryError.appStateNotFound(ConnectionProvider.openCode.title)
        }
        let sql = """
            SELECT worktree AS path FROM project WHERE worktree != ''
            UNION SELECT directory FROM session WHERE directory != ''
            UNION SELECT directory FROM workspace WHERE directory IS NOT NULL AND directory != ''
            UNION SELECT directory FROM project_directory WHERE directory != ''
            """
        return sqlitePaths(database: database, sql: sql).map {
            WorkspaceCandidate(url: URL(fileURLWithPath: $0), isExplicitFolder: true)
        }
    }

    private func claudeCandidates() throws -> [WorkspaceCandidate] {
        let config = home.appendingPathComponent(".claude.json")
        let projectsDirectory = home.appendingPathComponent(".claude/projects")
        let hasConfig = FileManager.default.fileExists(atPath: config.path)
        let hasProjects = FileManager.default.fileExists(atPath: projectsDirectory.path)
        guard hasConfig || hasProjects else {
            throw LocalAppProjectDiscoveryError.appStateNotFound(ConnectionProvider.claudeCode.title)
        }

        var paths = Set<String>()
        if let data = try? Data(contentsOf: config),
           let json = try? JSONSerialization.jsonObject(with: data) {
            collectClaudeProjectKeys(json, parentKey: nil, into: &paths)
        }

        if let enumerator = FileManager.default.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            var inspected = 0
            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                guard inspected < 1_000 else { break }
                inspected += 1
                paths.formUnion(cwdsFromJSONLines(file))
            }
        }
        return paths.map { WorkspaceCandidate(url: URL(fileURLWithPath: $0), isExplicitFolder: true) }
    }

    private func collectClaudeProjectKeys(_ value: Any, parentKey: String?, into paths: inout Set<String>) {
        guard let dictionary = value as? [String: Any] else { return }
        for (key, child) in dictionary {
            if parentKey == "projects", key.hasPrefix("/") { paths.insert(key) }
            collectClaudeProjectKeys(child, parentKey: key, into: &paths)
        }
    }

    private func cwdsFromJSONLines(_ file: URL) -> Set<String> {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 2_000_000)) ?? Data()
        var result = Set<String>()
        for line in data.split(separator: 0x0A).prefix(200) {
            if let row = try? JSONDecoder().decode(CWDRow.self, from: Data(line)),
               let cwd = row.cwd, cwd.hasPrefix("/") {
                result.insert(cwd)
            }
        }
        return result
    }

    private func xcodeCandidates() throws -> [WorkspaceCandidate] {
        let plist = preferences.appendingPathComponent("com.apple.dt.Xcode.plist")
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: Any] else {
            throw LocalAppProjectDiscoveryError.appStateNotFound(ConnectionProvider.xcode.title)
        }

        var output: [WorkspaceCandidate] = []
        for key in ["IDERecentWorkspaceDocuments", "IDERecentEditorDocuments"] {
            guard let bookmarks = dictionary[key] as? [Data] else { continue }
            for bookmark in bookmarks {
                var stale = false
                if let url = try? URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withoutUI, .withoutMounting],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ) {
                    output.append(WorkspaceCandidate(url: url, isExplicitFolder: false))
                }
            }
        }
        return output
    }

    private func sqlitePaths(database: URL, sql: String) -> Set<String> {
        let process = Process()
        process.executableURL = sqliteExecutable
        process.arguments = ["-readonly", "-json", database.path, sql]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let rows = try JSONDecoder().decode([PathRow].self, from: data)
            return Set(rows.map(\.path))
        } catch {
            return []
        }
    }

    private func normalize(_ candidate: WorkspaceCandidate) -> URL? {
        var url = candidate.url.standardizedFileURL
        if ["code-workspace", "xcodeproj", "xcworkspace"].contains(url.pathExtension.lowercased()) {
            url.deleteLastPathComponent()
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue { url.deleteLastPathComponent() }

        if candidate.isExplicitFolder, isUsableRoot(url) { return url }
        for _ in 0..<10 {
            guard isUsableRoot(url) else { return nil }
            if hasProjectMarker(url) { return url }
            let parent = url.deletingLastPathComponent()
            guard parent.path != url.path else { break }
            url = parent
        }
        return nil
    }

    private func hasProjectMarker(_ url: URL) -> Bool {
        if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) { return true }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let markers = Set(["Package.swift", "package.json", "project.pbxproj", "Cargo.toml", "go.mod", "pyproject.toml", "Podfile"])
        return !markers.isDisjoint(with: names)
            || names.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }

    private func isUsableRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let excluded = Set([
            "/", "/tmp", "/private/tmp", home.path,
            home.appendingPathComponent("Desktop").path,
            home.appendingPathComponent("Documents").path,
            home.appendingPathComponent("Downloads").path,
            applicationSupport.path
        ])
        return path.hasPrefix("/") && !excluded.contains(path)
    }
}

private struct WorkspaceCandidate {
    let url: URL
    let isExplicitFolder: Bool
}

private struct CWDRow: Decodable {
    let cwd: String?
}

private struct PathRow: Decodable {
    let path: String
}
