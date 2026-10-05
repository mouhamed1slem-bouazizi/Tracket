import Foundation

enum CodexProjectDiscoveryError: LocalizedError {
    case appStateNotFound
    case noWorkspaces

    var errorDescription: String? {
        switch self {
        case .appStateNotFound:
            "Codex local state was not found. Open Codex and create or open a project first."
        case .noWorkspaces:
            "Codex is connected, but no readable project workspaces were found yet."
        }
    }
}

struct CodexProjectDiscovery: Sendable {
    private let codexHome: URL
    private let sqliteExecutable: URL

    init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
        sqliteExecutable: URL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    ) {
        self.codexHome = codexHome
        self.sqliteExecutable = sqliteExecutable
    }

    func discover() throws -> [URL] {
        let stateDatabases = stateDatabaseCandidates()
        let catalogDatabase = codexHome.appendingPathComponent("sqlite/codex-dev.db")
        guard !stateDatabases.isEmpty || FileManager.default.fileExists(atPath: catalogDatabase.path) else {
            throw CodexProjectDiscoveryError.appStateNotFound
        }

        var paths = Set<String>()
        for database in stateDatabases {
            paths.formUnion(query(
                database: database,
                sql: "SELECT cwd FROM threads WHERE cwd != '' GROUP BY cwd ORDER BY MAX(updated_at) DESC"
            ))
        }
        if FileManager.default.fileExists(atPath: catalogDatabase.path) {
            paths.formUnion(query(
                database: catalogDatabase,
                sql: "SELECT cwd FROM local_thread_catalog WHERE cwd != '' AND missing_candidate = 0 GROUP BY cwd ORDER BY MAX(source_updated_at) DESC"
            ))
        }

        let excluded = excludedRoots()
        let urls = paths.compactMap { path -> URL? in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard url.path.hasPrefix("/"), !excluded.contains(url.path) else { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return url
        }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        guard !urls.isEmpty else { throw CodexProjectDiscoveryError.noWorkspaces }
        return urls
    }

    private func stateDatabaseCandidates() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: codexHome,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func query(database: URL, sql: String) -> Set<String> {
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
            let rows = try JSONDecoder().decode([WorkspaceRow].self, from: data)
            return Set(rows.map(\.cwd).filter { !$0.isEmpty })
        } catch {
            return []
        }
    }

    private func excludedRoots() -> Set<String> {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        return Set([
            "/", "/tmp", "/private/tmp", home.path,
            home.appendingPathComponent("Desktop").path,
            home.appendingPathComponent("Documents").path,
            home.appendingPathComponent("Downloads").path
        ])
    }
}

private struct WorkspaceRow: Decodable {
    let cwd: String
}
