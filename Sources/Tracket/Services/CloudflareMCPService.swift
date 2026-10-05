import Foundation

struct CloudflareMCPService: Sendable {
    private let endpoint = URL(string: "https://mcp.cloudflare.com/mcp?truncateToolResult=false")!
    private let protocolVersion = "2025-06-18"

    func fetchProjects(accessToken: String) async throws -> CloudImportResult {
        var sessionID: String?
        _ = try await send(
            method: "initialize",
            id: 1,
            params: [
                "protocolVersion": protocolVersion,
                "capabilities": [:],
                "clientInfo": ["name": "Tracket", "version": "0.2.0"]
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

        let code = #"""
        async () => {
          const accountResponse = await cloudflare.request({ method: "GET", path: "/accounts", query: { per_page: 50 } });
          const accounts = Array.isArray(accountResponse.result) ? accountResponse.result : [];
          const projects = [];
          for (const account of accounts) {
            const response = await cloudflare.request({
              method: "GET",
              path: `/accounts/${account.id}/pages/projects`,
              query: { per_page: 100 }
            });
            for (const project of (Array.isArray(response.result) ? response.result : [])) {
              projects.push({ ...project, account_id: account.id, account_name: account.name });
            }
          }
          return { accounts: accounts.map(({ id, name }) => ({ id, name })), projects };
        }
        """#
        guard let response = try await send(
            method: "tools/call",
            id: 2,
            params: ["name": "execute", "arguments": ["code": code]],
            accessToken: accessToken,
            sessionID: &sessionID
        ) else {
            throw ProjectImportError.invalidResponse
        }
        return try Self.importResult(from: response)
    }

    private func send(
        method: String,
        id: Int?,
        params: [String: Any],
        accessToken: String,
        sessionID: inout String?
    ) async throws -> [String: Any]? {
        var payload: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        if let id { payload["id"] = id }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProjectImportError.invalidResponse }
        if let newSessionID = http.value(forHTTPHeaderField: "Mcp-Session-Id"), !newSessionID.isEmpty {
            sessionID = newSessionID
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProjectImportError.provider(
                Self.errorMessage(from: data)
                    ?? "Cloudflare MCP returned \(http.statusCode). Reconnect Cloudflare and try again."
            )
        }
        guard !data.isEmpty else { return nil }
        guard let object = Self.responseObject(from: data) else { throw ProjectImportError.invalidResponse }
        if let error = object["error"] as? [String: Any] {
            throw ProjectImportError.provider(error["message"] as? String ?? "Cloudflare MCP request failed.")
        }
        return object
    }

    static func importResult(from response: [String: Any]) throws -> CloudImportResult {
        guard let payload = decodedToolPayload(response) as? [String: Any] else {
            throw ProjectImportError.invalidResponse
        }
        let accounts = payload["accounts"] as? [[String: Any]] ?? []
        let projects = payload["projects"] as? [[String: Any]] ?? []
        let descriptors = projects.compactMap { item -> ImportedProjectDescriptor? in
            guard let name = item["name"] as? String else { return nil }
            let accountID = item["account_id"] as? String ?? "cloudflare"
            let subdomain = (item["subdomain"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let deployment = subdomain.flatMap { $0.isEmpty ? nil : "https://\($0)" }
            let latest = item["latest_deployment"] as? [String: Any]
            return ImportedProjectDescriptor(
                name: name,
                externalID: "\(accountID):\(name)",
                provider: .cloudflare,
                remoteURL: nil,
                deploymentURL: deployment,
                updatedAt: date(latest?["modified_on"] ?? item["created_on"]) ?? Date(),
                stage: deployment == nil ? .launchReady : .live
            )
        }
        let names = accounts.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
        return CloudImportResult(
            accountName: names.isEmpty ? "Cloudflare account" : names.joined(separator: ", "),
            projects: descriptors
        )
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

    private static func responseObject(from data: Data) -> [String: Any]? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return object }
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

    private static func date(_ value: Any?) -> Date? {
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
