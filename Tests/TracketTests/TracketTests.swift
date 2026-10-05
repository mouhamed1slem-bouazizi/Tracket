import AppKit
import Foundation
import XCTest
@testable import Tracket

final class TracketTests: XCTestCase {
    func testPersistenceResetRemovesOnlyTracketValues() {
        let suiteName = "TracketTests.Reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var persistence = PersistenceStore(defaults: defaults)
        persistence.monitoringEnabled = false
        persistence.remoteSyncEnabled = false
        persistence.monitorIntervalMinutes = 15
        defaults.set("keep", forKey: "unrelated.preference")

        persistence.resetAll()

        XCTAssertTrue(persistence.monitoringEnabled)
        XCTAssertTrue(persistence.remoteSyncEnabled)
        XCTAssertEqual(persistence.monitorIntervalMinutes, 2)
        XCTAssertEqual(defaults.string(forKey: "unrelated.preference"), "keep")
    }

    func testMomentumRewardsRecentProgress() {
        let project = makeProject(
            lastActivityAt: Date(),
            commits: 6,
            statuses: [.done, .active, .todo]
        )

        XCTAssertGreaterThanOrEqual(project.momentumScore, 70)
        XCTAssertEqual(project.momentumLabel, "Strong")
    }

    func testScannerDetectsSwiftPackageAndCodex() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TracketScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try "// package".write(to: folder.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "# Instructions".write(to: folder.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try "import Foundation".write(to: folder.appendingPathComponent("Main.swift"), atomically: true, encoding: .utf8)

        let snapshot = try ProjectScanner().scan(url: folder)

        XCTAssertEqual(snapshot.stage, .building)
        XCTAssertTrue(snapshot.detectedTools.contains(.xcode))
        XCTAssertTrue(snapshot.detectedTools.contains(.codex))
        XCTAssertEqual(snapshot.languages.first, "Swift")
    }

    func testLocalDiscoveryFindsProjectsAndSkipsNestedDependencies() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TracketDiscovery-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Apps/RealApp")
        let dependency = app.appendingPathComponent("node_modules/Dependency")
        try FileManager.default.createDirectory(at: dependency, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "{}".write(to: app.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: dependency.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let results = LocalProjectDiscovery().discover(in: [root])

        XCTAssertEqual(results.map(\.standardizedFileURL.path), [app.standardizedFileURL.path])
    }

    func testAICompletionOverridesRoadmapHeuristic() {
        var project = makeProject(lastActivityAt: Date(), commits: 1, statuses: [.done, .todo])
        XCTAssertEqual(project.completionPercent, 50)
        XCTAssertEqual(project.remainingPercent, 50)

        project.aiCompletionPercent = 72
        XCTAssertEqual(project.completionPercent, 72)
        XCTAssertEqual(project.remainingPercent, 28)
    }

    func testHookInboxReadsOnlyNewCompleteEvents() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("TracketHookInbox-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }

        let first = HookInboxEvent(
            id: UUID(),
            occurredAt: Date(),
            source: "codex",
            event: "Stop",
            cwd: "/tmp/project",
            sessionID: "session-1",
            turnID: "turn-1",
            toolName: nil
        )
        let second = HookInboxEvent(
            id: UUID(),
            occurredAt: Date(),
            source: "codex",
            event: "PostToolUse",
            cwd: "/tmp/project",
            sessionID: "session-1",
            turnID: "turn-2",
            toolName: "apply_patch"
        )
        let encoder = JSONEncoder()
        var data = try encoder.encode(first)
        data.append(0x0A)
        data.append(try encoder.encode(second))
        data.append(0x0A)
        try data.write(to: file)

        let service = HookInboxService(inboxURL: file)
        let initial = service.readNewEvents(from: 0)
        let repeated = service.readNewEvents(from: initial.nextOffset)

        XCTAssertEqual(initial.events.map(\.id), [first.id, second.id])
        XCTAssertTrue(repeated.events.isEmpty)
        XCTAssertEqual(repeated.nextOffset, initial.nextOffset)
    }

    func testCodexHookInstallerPreservesExistingHooks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TracketCodexHooks-\(UUID().uuidString)")
        let projectURL = root.appendingPathComponent("Project")
        let codexURL = projectURL.appendingPathComponent(".codex")
        let helperURL = root.appendingPathComponent("source-helper")
        let installURL = root
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Tracket")
            .appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: codexURL, withIntermediateDirectories: true)
        try "#!/bin/sh\nprint '{}'\n".write(to: helperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let existing: [String: Any] = [
            "hooks": [
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [["type": "command", "command": "echo existing"]]
                ]]
            ]
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existing)
        try existingData.write(to: codexURL.appendingPathComponent("hooks.json"))

        let project = makeProject(lastActivityAt: Date(), commits: 0, statuses: [.active])
        var localProject = project
        localProject.path = projectURL.path
        let installer = CodexHookInstaller(helperSourceURL: helperURL, installDirectory: installURL)
        try installer.connect(to: localProject)

        let outputData = try Data(contentsOf: codexURL.appendingPathComponent("hooks.json"))
        let output = try XCTUnwrap(JSONSerialization.jsonObject(with: outputData) as? [String: Any])
        let hooks = try XCTUnwrap(output["hooks"] as? [String: Any])

        XCTAssertNotNil(hooks["PreToolUse"])
        XCTAssertNotNil(hooks["SessionStart"])
        XCTAssertNotNil(hooks["PostToolUse"])
        XCTAssertNotNil(hooks["Stop"])
        XCTAssertNotNil(hooks["SessionEnd"])
        XCTAssertTrue(installer.isConnected(to: localProject))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installURL.appendingPathComponent("tracket-hook").path))
    }

    func testCodexDiscoveryImportsWorkspacePathsFromLocalState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TracketCodexDiscovery-\(UUID().uuidString)")
        let workspace = root.appendingPathComponent("Projects/CodexMadeApp")
        let database = root.appendingPathComponent("state_5.sqlite")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let escapedWorkspace = workspace.path.replacingOccurrences(of: "'", with: "''")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, """
            CREATE TABLE threads (cwd TEXT NOT NULL, updated_at INTEGER NOT NULL);
            INSERT INTO threads VALUES ('\(escapedWorkspace)', 2);
            INSERT INTO threads VALUES ('/path/that/does/not/exist', 1);
            """]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let discovered = try CodexProjectDiscovery(codexHome: root).discover()

        XCTAssertEqual(discovered.map(\.path), [workspace.standardizedFileURL.path])
    }

    func testVSCodeDiscoveryImportsRecentWorkspaceWithoutFolderPicker() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TracketVSCodeDiscovery-\(UUID().uuidString)")
        let workspace = root.appendingPathComponent("Projects/EditorApp")
        let support = root.appendingPathComponent("Library/Application Support")
        let storage = support.appendingPathComponent("Code/User/globalStorage/storage.json")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let json: [String: Any] = [
            "backupWorkspaces": ["folders": [["folderUri": workspace.absoluteString]]]
        ]
        try JSONSerialization.data(withJSONObject: json).write(to: storage)

        let discovered = try LocalAppProjectDiscovery(
            home: root,
            applicationSupport: support,
            preferences: root.appendingPathComponent("Library/Preferences")
        ).discover(provider: .vscode)

        XCTAssertEqual(discovered.map(\.path), [workspace.standardizedFileURL.path])
    }

    func testClaudeDiscoveryImportsConfiguredProjects() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TracketClaudeDiscovery-\(UUID().uuidString)")
        let workspace = root.appendingPathComponent("Projects/ClaudeApp")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let config: [String: Any] = ["projects": [workspace.path: ["allowedTools": []]]]
        try JSONSerialization.data(withJSONObject: config).write(to: root.appendingPathComponent(".claude.json"))

        let discovered = try LocalAppProjectDiscovery(home: root).discover(provider: .claudeCode)

        XCTAssertEqual(discovered.map(\.path), [workspace.standardizedFileURL.path])
    }

    func testOpenCodeDiscoveryImportsDatabaseWorktree() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TracketOpenCodeDiscovery-\(UUID().uuidString)")
        let workspace = root.appendingPathComponent("Projects/OpenCodeApp")
        let database = root.appendingPathComponent(".local/share/opencode/opencode.db")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let escaped = workspace.path.replacingOccurrences(of: "'", with: "''")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, """
            CREATE TABLE project (worktree TEXT);
            CREATE TABLE session (directory TEXT);
            CREATE TABLE workspace (directory TEXT);
            CREATE TABLE project_directory (directory TEXT);
            INSERT INTO project VALUES ('\(escaped)');
            """]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let discovered = try LocalAppProjectDiscovery(home: root).discover(provider: .openCode)

        XCTAssertEqual(discovered.map(\.path), [workspace.standardizedFileURL.path])
    }

    func testRenderMCPResponseBecomesImportedProject() throws {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 3,
            "result": [
                "structuredContent": [
                    "services": [[
                        "id": "srv-example",
                        "name": "Example API",
                        "repo": "https://github.com/example/api",
                        "updatedAt": "2026-10-03T18:00:00Z",
                        "serviceDetails": ["url": "https://example.onrender.com"]
                    ]]
                ]
            ]
        ]

        let project = try XCTUnwrap(RenderMCPService.serviceDescriptors(from: response).first)

        XCTAssertEqual(project.externalID, "srv-example")
        XCTAssertEqual(project.name, "Example API")
        XCTAssertEqual(project.remoteURL, "https://github.com/example/api")
        XCTAssertEqual(project.deploymentURL, "https://example.onrender.com")
        XCTAssertEqual(project.stage, .live)
    }

    func testCloudflareMCPResponseBecomesImportedProject() throws {
        let payload: [String: Any] = [
            "accounts": [["id": "account-1", "name": "Example Workspace"]],
            "projects": [[
                "name": "example-site",
                "account_id": "account-1",
                "subdomain": "example-site.pages.dev",
                "created_on": "2026-10-03T18:00:00Z"
            ]]
        ]
        let text = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 2,
            "result": ["content": [["type": "text", "text": text]]]
        ]

        let result = try CloudflareMCPService.importResult(from: response)
        let project = try XCTUnwrap(result.projects.first)

        XCTAssertEqual(result.accountName, "Example Workspace")
        XCTAssertEqual(project.externalID, "account-1:example-site")
        XCTAssertEqual(project.deploymentURL, "https://example-site.pages.dev")
        XCTAssertEqual(project.provider, .cloudflare)
        XCTAssertEqual(project.stage, .live)
    }

    func testOlderOAuthCredentialStillDecodes() throws {
        let data = Data(#"{"accessToken":"old-token","refreshToken":null,"expiresAt":null}"#.utf8)
        let credential = try JSONDecoder().decode(OAuthCredential.self, from: data)

        XCTAssertEqual(credential.accessToken, "old-token")
        XCTAssertNil(credential.clientID)
        XCTAssertNil(credential.tokenEndpoint)
        XCTAssertNil(credential.resource)
    }

    func testGitHubDeviceCodeIsReadFromLiveCLIOutput() {
        let output = "! One-time code (26B0-6785) copied to clipboard\nOpen this URL to continue"

        XCTAssertEqual(GitHubCLIAuthService.deviceCode(in: output), "26B0-6785")
    }

    func testRecentDevelopmentToolUsesNewestIDEActivity() {
        var project = makeProject(lastActivityAt: Date(), commits: 1, statuses: [.active])
        let older = Date().addingTimeInterval(-300)
        let newer = Date().addingTimeInterval(-30)
        project.detectedTools = [.git, .cursor, .codex]
        project.toolActivity = [.cursor: older, .codex: newer]

        XCTAssertEqual(project.latestDevelopmentTool, .codex)
        XCTAssertEqual(project.latestDevelopmentActivityAt, project.lastActivityAt)
    }

    func testProviderUsageFractionIsClamped() {
        let normal = ProviderUsageStatus(
            label: "API requests",
            remaining: 250,
            limit: 1_000,
            resetAt: nil,
            checkedAt: Date()
        )
        let overreported = ProviderUsageStatus(
            label: "API requests",
            remaining: 1_200,
            limit: 1_000,
            resetAt: nil,
            checkedAt: Date()
        )

        XCTAssertEqual(normal.fractionRemaining, 0.25)
        XCTAssertEqual(overreported.fractionRemaining, 1)
    }

    func testCodexUsageParsesAccountWindowsAndResetCredits() throws {
        let account: [String: Any] = [
            "account": ["type": "chatgpt", "email": "coder@example.com", "planType": "plus"]
        ]
        let limits: [String: Any] = [
            "rateLimits": [
                "primary": ["usedPercent": 20, "windowDurationMins": 300, "resetsAt": 2_000_000_000],
                "secondary": ["usedPercent": 26, "windowDurationMins": 10_080, "resetsAt": 2_000_100_000],
                "credits": ["hasCredits": false, "unlimited": false, "balance": "0"],
                "planType": "plus"
            ],
            "rateLimitResetCredits": [
                "availableCount": 3,
                "credits": [["expiresAt": 2_000_200_000]]
            ]
        ]

        let result = try CodexUsageService.parse(
            accountResult: account,
            rateLimitResult: limits,
            checkedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )

        XCTAssertEqual(result.accountName, "coder@example.com")
        XCTAssertEqual(result.usage.planName, "Plus")
        XCTAssertEqual(result.usage.primary?.title, "Session")
        XCTAssertEqual(result.usage.primary?.remainingPercent, 80)
        XCTAssertEqual(result.usage.secondary?.title, "Weekly")
        XCTAssertEqual(result.usage.secondary?.remainingPercent, 74)
        XCTAssertEqual(result.usage.availableResetCredits, 3)
        XCTAssertEqual(result.usage.resetCreditExpirations.count, 1)
    }

    func testOpenCodeStatsBecomeRichUsageMetrics() throws {
        let output = """
        ┌────────────────────────────────────────┐
        │ OVERVIEW                               │
        │Sessions                              12 │
        │Messages                              84 │
        ├────────────────────────────────────────┤
        │ COST & TOKENS                          │
        │Total Cost                         $4.25 │
        │Input                             120000 │
        │Output                             45000 │
        ├────────────────────────────────────────┤
        │ MODEL USAGE                            │
        │ anthropic/claude-sonnet-4-5            │
        └────────────────────────────────────────┘
        """

        let usage = try XCTUnwrap(LocalToolUsageService.parseOpenCodeStats(output))

        XCTAssertEqual(usage.planName, "30-day local stats")
        XCTAssertEqual(usage.metrics?.first?.value, "12")
        XCTAssertEqual(usage.metrics?.first(where: { $0.label == "Local cost" })?.value, "$4.25")
        XCTAssertEqual(usage.modelName, "anthropic/claude-sonnet-4-5")
    }

    func testClaudeHistoryBecomesRichUsageMetrics() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("TracketClaudeUsage-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let rows: [[String: Any]] = [
            [
                "timestamp": timestamp,
                "message": [
                    "model": "claude-sonnet-4-5",
                    "usage": ["input_tokens": 1_200, "output_tokens": 300, "cache_read_input_tokens": 500]
                ]
            ],
            [
                "timestamp": timestamp,
                "message": [
                    "model": "claude-sonnet-4-5",
                    "usage": ["input_tokens": 800, "output_tokens": 200, "cache_read_input_tokens": 100]
                ]
            ]
        ]
        var data = Data()
        for row in rows {
            data.append(try JSONSerialization.data(withJSONObject: row))
            data.append(0x0A)
        }
        try data.write(to: file)

        let usage = try XCTUnwrap(LocalToolUsageService.parseClaudeHistory(
            files: [file],
            since: Date().addingTimeInterval(-60)
        ))

        XCTAssertEqual(usage.metrics?.first(where: { $0.label == "Sessions" })?.value, "1")
        XCTAssertEqual(usage.metrics?.first(where: { $0.label == "Messages" })?.value, "2")
        XCTAssertEqual(usage.metrics?.first(where: { $0.label == "Input tokens" })?.value, "2,000")
        XCTAssertEqual(usage.modelName, "claude-sonnet-4-5")
    }

    func testAppStaysRunningWhenMainWindowCloses() {
        XCTAssertFalse(
            TracketAppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
        )
    }

    private func makeProject(
        lastActivityAt: Date,
        commits: Int,
        statuses: [RoadmapStatus]
    ) -> TracketProject {
        let items = statuses.enumerated().map { index, status in
            RoadmapItem(
                title: "Step \(index)",
                detail: "Detail",
                status: status,
                priority: .medium,
                dueDate: Date().addingTimeInterval(Double(index + 1) * 86_400)
            )
        }
        return TracketProject(
            name: "Test",
            path: "/tmp/test",
            goal: "Ship",
            stage: .building,
            lastActivityAt: lastActivityAt,
            deadline: Date().addingTimeInterval(604_800),
            branch: "main",
            remoteURL: nil,
            deploymentURL: nil,
            uncommittedChanges: 0,
            commitCountLast7Days: commits,
            detectedTools: [.git],
            languages: ["Swift"],
            roadmap: items,
            aiSummary: nil,
            nextSuggestion: nil
        )
    }
}
