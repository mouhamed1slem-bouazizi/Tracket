import Foundation

struct RenderMCPService: Sendable {
    private let endpoint = URL(string: "https://mcp.render.com/mcp")!
    private let protocolVersion = "2025-06-18"

    func fetchProjects(accessToken: String) async throws -> CloudImportResult {
        var sessionID: String?
        _ = try await send(
            method: "initialize",
            id: 1,
            params: [
                "protocolVersion": protocolVersion,
                "capabilities": [:],
                "clientInfo": ["name": "Tracket", "version": "0.1.0"]
            ],
            accessToken: accessToken,
            sessionID: &sessionID
        )
        _ = try await send(
            method: "notifications/initialized",
            id: nil,
            params: [:],
            accessToken: accessToken,
            sessionID: &sessionID
        )

        let workspaceResponse = try await send(
            method: "tools/call",
            id: 2,
            params: ["name": "list_workspaces", "arguments": [:]],
            accessToken: accessToken,
            sessionID: &sessionID
        )
        let workspaces = workspaceResponse.map(Self.workspaceRecords) ?? []
        let targets: [(id: String?, name: String)] = workspaces.isEmpty
            ? [(nil, "Render account")]
            : workspaces

        var descriptors: [ImportedProjectDescriptor] = []
        var nextID = 3
        for workspace in targets {
            var arguments: [String: Any] = ["includePreviews": false]
            if let workspaceID = workspace.id { arguments["workspaceId"] = workspaceID }
            let response = try await send(
                method: "tools/call",
                id: nextID,
                params: ["name": "list_services", "arguments": arguments],
                accessToken: accessToken,
                sessionID: &sessionID
            )
            nextID += 1
            if let response {
                descriptors.append(contentsOf: Self.serviceDescriptors(from: response))
            }
        }

        var seen = Set<String>()
        let unique = descriptors.filter { seen.insert($0.externalID).inserted }
        let accountName = workspaces.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
        return CloudImportResult(
            accountName: accountName.isEmpty ? "Render account" : accountName,
            projects: unique
        )
    }

    private func send(
        method: String,
        id: Int?,
        params: [String: Any],
        accessToken: String,
        sessionID: inout String?
    ) async throws -> [String: Any]? {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        if let id { payload["id"] = id }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProjectImportError.invalidResponse }
        if let newSessionID = http.value(forHTTPHeaderField: "Mcp-Session-Id"), !newSessionID.isEmpty {
            sessionID = newSessionID
        }
        guard (200...299).contains(http.statusCode) else {
            let message = Self.errorMessage(from: data)
                ?? "Render MCP returned \(http.statusCode). Reconnect Render and try again."
            throw ProjectImportError.provider(message)
        }
        guard !data.isEmpty else { return nil }
        guard let object = Self.responseObject(from: data) else { throw ProjectImportError.invalidResponse }
        if let error = object["error"] as? [String: Any] {
            throw ProjectImportError.provider(error["message"] as? String ?? "Render MCP request failed.")
        }
        return object
    }

    private static func responseObject(from data: Data) -> [String: Any]? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines).reversed() {
            guard line.hasPrefix("data:") else { continue }
            let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard value != "[DONE]", let eventData = value.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else { continue }
            return object
        }
        return nil
    }

    private static func decodedToolPayload(_ response: [String: Any]) -> Any {
        guard let result = response["result"] as? [String: Any] else { return response }
        if let structured = result["structuredContent"] { return structured }
        if let content = result["content"] as? [[String: Any]] {
            for item in content {
                guard item["type"] as? String == "text", let text = item["text"] as? String,
                      let data = text.data(using: .utf8),
                      let decoded = try? JSONSerialization.jsonObject(with: data) else { continue }
                return decoded
            }
        }
        return result
    }

    static func workspaceRecords(from response: [String: Any]) -> [(id: String?, name: String)] {
        let dictionaries = records(in: decodedToolPayload(response), collectionKeys: ["workspaces", "owners"])
        var seen = Set<String>()
        return dictionaries.compactMap { item in
            let id = string(item["id"] ?? item["workspaceId"] ?? item["ownerId"])
            let name = string(item["name"] ?? item["displayName"] ?? item["email"]) ?? "Render workspace"
            let key = id ?? name
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return (id, name)
        }
    }

    static func serviceDescriptors(from response: [String: Any]) -> [ImportedProjectDescriptor] {
        records(in: decodedToolPayload(response), collectionKeys: ["services"]).compactMap { raw in
            let item = raw["service"] as? [String: Any] ?? raw
            guard let id = string(item["id"]), let name = string(item["name"]) else {
                return nil
            }
            let details = item["serviceDetails"] as? [String: Any]
            let deployment = string(details?["url"] ?? item["url"])
            let repository = string(item["repo"] ?? item["repository"])
            return ImportedProjectDescriptor(
                name: name,
                externalID: id,
                provider: .render,
                remoteURL: repository,
                deploymentURL: deployment,
                updatedAt: date(item["updatedAt"] ?? item["updated_at"]) ?? Date(),
                stage: deployment == nil ? .launchReady : .live
            )
        }
    }

    private static func records(in value: Any, collectionKeys: Set<String>) -> [[String: Any]] {
        if let array = value as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        guard let dictionary = value as? [String: Any] else { return [] }
        for key in collectionKeys {
            if let array = dictionary[key] as? [Any] {
                return array.compactMap { $0 as? [String: Any] }
            }
        }
        for nested in dictionary.values {
            let found = records(in: nested, collectionKeys: collectionKeys)
            if !found.isEmpty { return found }
        }
        return dictionary["id"] != nil && dictionary["name"] != nil ? [dictionary] : []
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let milliseconds = value as? NSNumber {
            let raw = milliseconds.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
        }
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = body["error"] as? [String: Any] { return error["message"] as? String }
        return body["message"] as? String ?? body["error_description"] as? String
    }
}
