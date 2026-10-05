import Foundation

enum ProjectImportError: LocalizedError {
    case noProjects
    case invalidResponse
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .noProjects: "No projects were found in that location or account."
        case .invalidResponse: "The provider returned an unreadable response."
        case .provider(let message): message
        }
    }
}

struct LocalProjectDiscovery: Sendable {
    private let markers = Set([
        "Package.swift", "package.json", "Cargo.toml", "go.mod", "pyproject.toml",
        "requirements.txt", "Podfile", "Gemfile", "composer.json", "build.gradle",
        "render.yaml", "vercel.json"
    ])
    private let ignored = Set([
        ".git", ".build", "node_modules", "DerivedData", "Pods", "vendor", "dist",
        "build", ".next", ".cache", "Library", "Applications"
    ])

    func discover(in roots: [URL], maximumDepth: Int = 4) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()

        for root in roots {
            let normalized = root.standardizedFileURL
            var queue: [(url: URL, depth: Int)] = [(normalized, 0)]
            var inspected = 0

            while !queue.isEmpty, found.count < 200, inspected < 4_000 {
                let candidate = queue.removeFirst()
                inspected += 1
                let path = candidate.url.path
                guard seen.insert(path).inserted else { continue }

                if isProject(candidate.url) {
                    found.append(candidate.url)
                    continue
                }
                guard candidate.depth < maximumDepth else { continue }

                let children = (try? FileManager.default.contentsOfDirectory(
                    at: candidate.url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )) ?? []
                for child in children {
                    guard !ignored.contains(child.lastPathComponent) else { continue }
                    let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                    guard values?.isDirectory == true, values?.isPackage != true else { continue }
                    queue.append((child, candidate.depth + 1))
                }
            }
        }

        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func isProject(_ url: URL) -> Bool {
        if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) { return true }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        if !markers.isDisjoint(with: names) { return true }
        return names.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }
}

struct CloudImportResult: Sendable {
    let accountName: String
    let projects: [ImportedProjectDescriptor]
}

struct CloudProjectImportService: Sendable {
    func fetchProjects(provider: ConnectionProvider, credential: String) async throws -> CloudImportResult {
        switch provider {
        case .github: try await github(credential)
        case .cloudflare: try await cloudflare(credential)
        case .vercel: try await vercel(credential)
        case .render: throw ProjectImportError.provider("Render projects are imported through Render's OAuth-protected hosted MCP server.")
        default: throw ProjectImportError.provider("\(provider.title) uses a local folder adapter.")
        }
    }

    private func github(_ token: String) async throws -> CloudImportResult {
        let user = try await json(
            URL(string: "https://api.github.com/user")!,
            token: token,
            headers: ["Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"]
        )
        guard let profile = user as? [String: Any], let login = profile["login"] as? String else {
            throw ProjectImportError.invalidResponse
        }
        let repositories = try await json(
            URL(string: "https://api.github.com/user/repos?per_page=100&sort=pushed&affiliation=owner,collaborator,organization_member")!,
            token: token,
            headers: ["Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"]
        )
        let projects = (repositories as? [[String: Any]] ?? []).compactMap { item -> ImportedProjectDescriptor? in
            guard let id = item["id"], let name = item["full_name"] as? String else { return nil }
            let homepage = (item["homepage"] as? String)?.nilIfBlank
            return ImportedProjectDescriptor(
                name: name,
                externalID: String(describing: id),
                provider: .github,
                remoteURL: item["html_url"] as? String,
                deploymentURL: homepage,
                updatedAt: Self.date(item["pushed_at"]) ?? Date(),
                stage: homepage == nil ? .building : .live
            )
        }
        return CloudImportResult(accountName: login, projects: projects)
    }

    private func cloudflare(_ token: String) async throws -> CloudImportResult {
        let accountEnvelope = try await json(
            URL(string: "https://api.cloudflare.com/client/v4/accounts?per_page=50")!,
            token: token
        )
        guard let accountObject = accountEnvelope as? [String: Any],
              let accounts = accountObject["result"] as? [[String: Any]] else {
            throw ProjectImportError.invalidResponse
        }

        var imported: [ImportedProjectDescriptor] = []
        for account in accounts {
            guard let accountID = account["id"] as? String else { continue }
            let envelope = try await json(
                URL(string: "https://api.cloudflare.com/client/v4/accounts/\(accountID)/pages/projects?per_page=100")!,
                token: token
            )
            let items = (envelope as? [String: Any])?["result"] as? [[String: Any]] ?? []
            imported.append(contentsOf: items.compactMap { item in
                guard let name = item["name"] as? String else { return nil }
                let subdomain = (item["subdomain"] as? String)?.nilIfBlank
                let deployment = subdomain.map { "https://\($0)" }
                return ImportedProjectDescriptor(
                    name: name,
                    externalID: "\(accountID):\(name)",
                    provider: .cloudflare,
                    remoteURL: nil,
                    deploymentURL: deployment,
                    updatedAt: Self.date(item["latest_deployment"] as? [String: Any], key: "modified_on")
                        ?? Self.date(item["created_on"]) ?? Date(),
                    stage: deployment == nil ? .launchReady : .live
                )
            })
        }
        let accountName = accounts.first?["name"] as? String ?? "Cloudflare account"
        return CloudImportResult(accountName: accountName, projects: imported)
    }

    private func vercel(_ token: String) async throws -> CloudImportResult {
        let userEnvelope = try await json(URL(string: "https://api.vercel.com/v2/user")!, token: token)
        let user = (userEnvelope as? [String: Any])?["user"] as? [String: Any]
        let accountName = user?["username"] as? String ?? user?["name"] as? String ?? "Vercel account"
        let envelope = try await json(URL(string: "https://api.vercel.com/v9/projects?limit=100")!, token: token)
        let items = (envelope as? [String: Any])?["projects"] as? [[String: Any]] ?? []
        let projects = items.compactMap { item -> ImportedProjectDescriptor? in
            guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
            let targets = item["targets"] as? [String: Any]
            let production = targets?["production"] as? [String: Any]
            let alias = (production?["alias"] as? [String])?.first
            let deployment = alias.map { $0.hasPrefix("http") ? $0 : "https://\($0)" }
            let updatedMilliseconds = item["updatedAt"] as? Double
            return ImportedProjectDescriptor(
                name: name,
                externalID: id,
                provider: .vercel,
                remoteURL: "https://vercel.com/\(accountName)/\(name)",
                deploymentURL: deployment,
                updatedAt: updatedMilliseconds.map { Date(timeIntervalSince1970: $0 / 1_000) } ?? Date(),
                stage: deployment == nil ? .launchReady : .live
            )
        }
        return CloudImportResult(accountName: accountName, projects: projects)
    }

    private func json(_ url: URL, token: String, headers: [String: String] = [:]) async throws -> Any {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProjectImportError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let nested = body?["error"] as? [String: Any]
            let message = nested?["message"] as? String
                ?? body?["message"] as? String
                ?? "\(http.statusCode) from provider. Check the credential and its read permissions."
            throw ProjectImportError.provider(message)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return ISO8601DateFormatter.tracketFractional.date(from: text)
            ?? ISO8601DateFormatter.tracketStandard.date(from: text)
    }

    private static func date(_ object: [String: Any]?, key: String) -> Date? {
        date(object?[key])
    }
}

private extension ISO8601DateFormatter {
    static let tracketFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let tracketStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
