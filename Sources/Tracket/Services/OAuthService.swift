import AppKit
import CryptoKit
import Foundation
import Network
import Security

struct OAuthCredential: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let clientID: String?
    let tokenEndpoint: String?
    let resource: String?

    init(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date?,
        clientID: String? = nil,
        tokenEndpoint: String? = nil,
        resource: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.clientID = clientID
        self.tokenEndpoint = tokenEndpoint
        self.resource = resource
    }

    var needsRefresh: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 120
    }
}

enum OAuthServiceError: LocalizedError {
    case unsupportedProvider
    case invalidAuthorizationResponse
    case stateMismatch
    case cancelled
    case provider(String)
    case expired

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider: "This provider does not support Tracket's OAuth flow yet."
        case .invalidAuthorizationResponse: "The OAuth provider returned an invalid response."
        case .stateMismatch: "OAuth state validation failed. Please try connecting again."
        case .cancelled: "OAuth authorization was cancelled."
        case .provider(let message): message
        case .expired: "The OAuth authorization request expired. Please try again."
        }
    }
}

@MainActor
final class OAuthService: NSObject {
    private var browserCallbackContinuation: CheckedContinuation<URL, Error>?
    private var browserTimeoutTask: Task<Void, Never>?
    private var renderListener: NWListener?
    private var renderReadyContinuation: CheckedContinuation<NWEndpoint.Port, Error>?
    private var renderCallbackContinuation: CheckedContinuation<URL, Error>?
    private var renderTimeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOAuthCallback(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func authorize(
        provider: ConnectionProvider,
        clientID: String?,
        devicePrompt: @escaping @MainActor (String) -> Void
    ) async throws -> OAuthCredential {
        if provider == .github {
            guard let clientID else { throw OAuthServiceError.unsupportedProvider }
            return try await githubDeviceFlow(clientID: clientID, devicePrompt: devicePrompt)
        }
        if provider == .render {
            return try await renderMCPAuthorizationCodeFlow(clientID: clientID ?? "codex")
        }
        if provider == .cloudflare {
            return try await dynamicAuthorizationCodeFlow(configuration: .cloudflareMCP)
        }
        if provider == .vercel {
            return try await dynamicAuthorizationCodeFlow(configuration: .vercel)
        }
        guard let clientID else { throw OAuthServiceError.unsupportedProvider }
        guard let configuration = configuration(provider: provider) else {
            throw OAuthServiceError.unsupportedProvider
        }
        return try await authorizationCodeFlow(configuration: configuration, clientID: clientID)
    }

    func refresh(
        provider: ConnectionProvider,
        clientID: String,
        refreshToken: String,
        tokenEndpoint: String? = nil,
        resource: String? = nil
    ) async throws -> OAuthCredential {
        let tokenURL: URL
        if let tokenEndpoint, let customURL = URL(string: tokenEndpoint) {
            tokenURL = customURL
        } else { switch provider {
        case .github: tokenURL = URL(string: "https://github.com/login/oauth/access_token")!
        case .cloudflare: tokenURL = URL(string: "https://mcp.cloudflare.com/token")!
        case .vercel: tokenURL = URL(string: "https://api.vercel.com/login/oauth/token")!
        case .render: tokenURL = URL(string: "https://api.render.com/v1/oauth/token")!
        default: throw OAuthServiceError.unsupportedProvider
        }
        }
        var fields = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken
        ]
        if let resource {
            fields["resource"] = resource
        } else if provider == .render {
            fields["resource"] = Self.renderResource
        }
        let response = try await postForm(
            tokenURL,
            fields: fields
        )
        return try credential(
            from: response,
            fallbackRefreshToken: refreshToken,
            clientID: clientID,
            tokenEndpoint: tokenURL.absoluteString,
            resource: resource ?? (provider == .render ? Self.renderResource : nil)
        )
    }

    private func dynamicAuthorizationCodeFlow(configuration: DynamicOAuthConfiguration) async throws -> OAuthCredential {
        let state = Self.randomURLSafe(byteCount: 32)
        let verifier = Self.randomURLSafe(byteCount: 64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let callbackPath = "/oauth/\(configuration.provider.rawValue)"
        let redirectURI = try await startRenderCallbackListener(
            path: callbackPath,
            providerName: configuration.provider.title
        )

        do {
            let registration = try await postJSON(configuration.registrationURL, object: [
                "client_name": "Tracket",
                "redirect_uris": [redirectURI.absoluteString],
                "grant_types": ["authorization_code", "refresh_token"],
                "response_types": ["code"],
                "token_endpoint_auth_method": "none"
            ])
            guard let clientID = registration["client_id"] as? String, !clientID.isEmpty else {
                throw OAuthServiceError.invalidAuthorizationResponse
            }

            var components = URLComponents(url: configuration.authorizationURL, resolvingAgainstBaseURL: false)!
            var query = [
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256")
            ]
            if !configuration.scope.isEmpty {
                query.append(URLQueryItem(name: "scope", value: configuration.scope))
            }
            if let resource = configuration.resource {
                query.append(URLQueryItem(name: "resource", value: resource))
            }
            components.queryItems = query
            guard let authorizationURL = components.url else {
                throw OAuthServiceError.invalidAuthorizationResponse
            }

            let callbackURL = try await waitForRenderCallback(opening: authorizationURL)
            let code = try authorizationCode(from: callbackURL, expectedState: state)
            var fields = [
                "grant_type": "authorization_code",
                "client_id": clientID,
                "code": code,
                "code_verifier": verifier,
                "redirect_uri": redirectURI.absoluteString
            ]
            if let resource = configuration.resource { fields["resource"] = resource }
            let response = try await postForm(configuration.tokenURL, fields: fields)
            return try credential(
                from: response,
                fallbackRefreshToken: nil,
                clientID: clientID,
                tokenEndpoint: configuration.tokenURL.absoluteString,
                resource: configuration.resource
            )
        } catch {
            stopRenderCallbackListener()
            throw error
        }
    }

    private func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw OAuthServiceError.invalidAuthorizationResponse
        }
        let values = Dictionary(uniqueKeysWithValues: (callback.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let error = values["error"] {
            throw OAuthServiceError.provider(values["error_description"] ?? error)
        }
        guard values["state"] == expectedState else { throw OAuthServiceError.stateMismatch }
        guard let code = values["code"], !code.isEmpty else { throw OAuthServiceError.invalidAuthorizationResponse }
        return code
    }

    private func authorizationCodeFlow(
        configuration: OAuthConfiguration,
        clientID: String
    ) async throws -> OAuthCredential {
        let state = Self.randomURLSafe(byteCount: 32)
        let verifier = Self.randomURLSafe(byteCount: 64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let redirectURI = "tracket://oauth/\(configuration.provider.rawValue)"

        var components = URLComponents(url: configuration.authorizationURL, resolvingAgainstBaseURL: false)!
        var query = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        if !configuration.scope.isEmpty {
            query.append(URLQueryItem(name: "scope", value: configuration.scope))
        }
        components.queryItems = query
        guard let authorizationURL = components.url else { throw OAuthServiceError.invalidAuthorizationResponse }

        let callbackURL = try await openDefaultBrowser(url: authorizationURL)
        guard let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw OAuthServiceError.invalidAuthorizationResponse
        }
        let values = Dictionary(uniqueKeysWithValues: (callback.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let error = values["error"] {
            throw OAuthServiceError.provider(values["error_description"] ?? error)
        }
        guard values["state"] == state else { throw OAuthServiceError.stateMismatch }
        guard let code = values["code"], !code.isEmpty else { throw OAuthServiceError.invalidAuthorizationResponse }

        let response = try await postForm(
            configuration.tokenURL,
            fields: [
                "grant_type": "authorization_code",
                "client_id": clientID,
                "code": code,
                "code_verifier": verifier,
                "redirect_uri": redirectURI
            ]
        )
        return try credential(from: response, fallbackRefreshToken: nil)
    }

    private func githubDeviceFlow(
        clientID: String,
        devicePrompt: @escaping @MainActor (String) -> Void
    ) async throws -> OAuthCredential {
        let device = try await postForm(
            URL(string: "https://github.com/login/device/code")!,
            fields: ["client_id": clientID, "scope": "repo read:user"]
        )
        guard let deviceCode = device["device_code"] as? String,
              let userCode = device["user_code"] as? String,
              let verification = device["verification_uri"] as? String,
              let verificationURL = URL(string: verification) else {
            throw OAuthServiceError.invalidAuthorizationResponse
        }
        let expiresIn = device["expires_in"] as? Double ?? 900
        var interval = device["interval"] as? Double ?? 5
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(userCode, forType: .string)
        devicePrompt(userCode)
        NSWorkspace.shared.open(verificationURL)

        let deadline = Date().addingTimeInterval(expiresIn)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            let response = try await postForm(
                URL(string: "https://github.com/login/oauth/access_token")!,
                fields: [
                    "client_id": clientID,
                    "device_code": deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
                ]
            )
            if response["access_token"] != nil {
                return try credential(from: response, fallbackRefreshToken: nil)
            }
            switch response["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "access_denied": throw OAuthServiceError.cancelled
            case "expired_token": throw OAuthServiceError.expired
            case let error?: throw OAuthServiceError.provider(response["error_description"] as? String ?? error)
            case nil: throw OAuthServiceError.invalidAuthorizationResponse
            }
        }
        throw OAuthServiceError.expired
    }

    private func renderMCPAuthorizationCodeFlow(clientID: String) async throws -> OAuthCredential {
        let state = Self.randomURLSafe(byteCount: 32)
        let verifier = Self.randomURLSafe(byteCount: 64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let callbackPath = "/callback/\(Self.renderCallbackID)"
        let redirectURI = try await startRenderCallbackListener(path: callbackPath, providerName: "Render")

        var components = URLComponents(string: "https://api.render.com/v1/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "resource", value: Self.renderResource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authorizationURL = components.url else {
            stopRenderCallbackListener()
            throw OAuthServiceError.invalidAuthorizationResponse
        }

        let callbackURL = try await waitForRenderCallback(opening: authorizationURL)
        guard let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw OAuthServiceError.invalidAuthorizationResponse
        }
        let values = Dictionary(uniqueKeysWithValues: (callback.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let error = values["error"] {
            throw OAuthServiceError.provider(values["error_description"] ?? error)
        }
        guard values["state"] == state else { throw OAuthServiceError.stateMismatch }
        if let issuer = values["iss"], issuer != "https://api.render.com" {
            throw OAuthServiceError.stateMismatch
        }
        guard let code = values["code"], !code.isEmpty else {
            throw OAuthServiceError.invalidAuthorizationResponse
        }

        let response = try await postForm(
            URL(string: "https://api.render.com/v1/oauth/token")!,
            fields: [
                "grant_type": "authorization_code",
                "client_id": clientID,
                "code": code,
                "code_verifier": verifier,
                "redirect_uri": redirectURI.absoluteString,
                "resource": Self.renderResource
            ]
        )
        return try credential(
            from: response,
            fallbackRefreshToken: nil,
            clientID: clientID,
            tokenEndpoint: "https://api.render.com/v1/oauth/token",
            resource: Self.renderResource
        )
    }

    private func startRenderCallbackListener(path: String, providerName: String) async throws -> URL {
        stopRenderCallbackListener()
        let listener = try NWListener(using: .tcp, on: .any)
        renderListener = listener
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener.port else {
                        self.failRenderListener(OAuthServiceError.invalidAuthorizationResponse)
                        return
                    }
                    self.renderReadyContinuation?.resume(returning: port)
                    self.renderReadyContinuation = nil
                case .failed(let error):
                    self.failRenderListener(error)
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, _, error in
                Task { @MainActor in
                    self?.handleRenderCallback(
                        data: data,
                        error: error,
                        connection: connection,
                        expectedPath: path,
                        providerName: providerName
                    )
                }
            }
        }
        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            renderReadyContinuation = continuation
            listener.start(queue: DispatchQueue(label: "app.tracket.render-oauth"))
        }
        return URL(string: "http://127.0.0.1:\(port.rawValue)\(path)")!
    }

    private func waitForRenderCallback(opening authorizationURL: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            renderCallbackContinuation = continuation
            renderTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.failRenderListener(OAuthServiceError.expired) }
            }
            guard NSWorkspace.shared.open(authorizationURL) else {
                failRenderListener(OAuthServiceError.invalidAuthorizationResponse)
                return
            }
        }
    }

    private func handleRenderCallback(
        data: Data?,
        error: NWError?,
        connection: NWConnection,
        expectedPath: String,
        providerName: String
    ) {
        guard error == nil,
              let data,
              let request = String(data: data, encoding: .utf8),
              let requestLine = request.components(separatedBy: "\r\n").first,
              requestLine.hasPrefix("GET "),
              let target = requestLine.split(separator: " ").dropFirst().first,
              let callbackURL = URL(string: "http://127.0.0.1\(target)"),
              callbackURL.path == expectedPath else {
            sendRenderBrowserResponse("Invalid OAuth callback.", status: "400 Bad Request", connection: connection)
            return
        }

        sendRenderBrowserResponse(
            "\(providerName) is connected to Tracket. You can close this window.",
            status: "200 OK",
            connection: connection
        )
        renderCallbackContinuation?.resume(returning: callbackURL)
        renderCallbackContinuation = nil
        stopRenderCallbackListener()
    }

    private func sendRenderBrowserResponse(_ message: String, status: String, connection: NWConnection) {
        let body = "<html><body style=\"font-family:-apple-system;padding:40px\"><h2>\(message)</h2></body></html>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func failRenderListener(_ error: Error) {
        renderReadyContinuation?.resume(throwing: error)
        renderReadyContinuation = nil
        renderCallbackContinuation?.resume(throwing: error)
        renderCallbackContinuation = nil
        stopRenderCallbackListener()
    }

    private func stopRenderCallbackListener() {
        renderTimeoutTask?.cancel()
        renderTimeoutTask = nil
        renderListener?.cancel()
        renderListener = nil
    }

    private func openDefaultBrowser(url: URL) async throws -> URL {
        guard browserCallbackContinuation == nil else {
            throw OAuthServiceError.provider("Another OAuth authorization is already in progress.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            browserCallbackContinuation = continuation
            browserTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.finishBrowserAuthorization(with: .failure(OAuthServiceError.expired))
                }
            }
            if !NSWorkspace.shared.open(url) {
                finishBrowserAuthorization(with: .failure(OAuthServiceError.invalidAuthorizationResponse))
            }
        }
    }

    @objc private func handleOAuthCallback(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard browserCallbackContinuation != nil,
              let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let callbackURL = URL(string: value),
              callbackURL.scheme == "tracket",
              callbackURL.host == "oauth" else { return }
        finishBrowserAuthorization(with: .success(callbackURL))
    }

    private func finishBrowserAuthorization(with result: Result<URL, Error>) {
        guard let continuation = browserCallbackContinuation else { return }
        browserCallbackContinuation = nil
        browserTimeoutTask?.cancel()
        browserTimeoutTask = nil
        continuation.resume(with: result)
    }

    private func postForm(_ url: URL, fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formEncoded(fields).data(using: .utf8)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OAuthServiceError.invalidAuthorizationResponse }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthServiceError.invalidAuthorizationResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw OAuthServiceError.provider(
                object["error_description"] as? String
                    ?? object["message"] as? String
                    ?? object["error"] as? String
                    ?? "OAuth request failed (\(http.statusCode))."
            )
        }
        return object
    }

    private func postJSON(_ url: URL, object: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: object)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthServiceError.invalidAuthorizationResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw OAuthServiceError.provider(
                object["error_description"] as? String
                    ?? object["message"] as? String
                    ?? object["error"] as? String
                    ?? "OAuth client registration failed (\(http.statusCode))."
            )
        }
        return object
    }

    private func credential(
        from response: [String: Any],
        fallbackRefreshToken: String?,
        clientID: String? = nil,
        tokenEndpoint: String? = nil,
        resource: String? = nil
    ) throws -> OAuthCredential {
        guard let accessToken = response["access_token"] as? String, !accessToken.isEmpty else {
            throw OAuthServiceError.invalidAuthorizationResponse
        }
        let expires: Double? = (response["expires_in"] as? NSNumber)?.doubleValue
        return OAuthCredential(
            accessToken: accessToken,
            refreshToken: response["refresh_token"] as? String ?? fallbackRefreshToken,
            expiresAt: expires.map { Date().addingTimeInterval($0) },
            clientID: clientID,
            tokenEndpoint: tokenEndpoint,
            resource: resource
        )
    }

    private func configuration(provider: ConnectionProvider) -> OAuthConfiguration? {
        switch provider {
        case .cloudflare:
            OAuthConfiguration(
                provider: provider,
                authorizationURL: URL(string: "https://dash.cloudflare.com/oauth2/auth")!,
                tokenURL: URL(string: "https://dash.cloudflare.com/oauth2/token")!,
                scope: ""
            )
        case .vercel:
            OAuthConfiguration(
                provider: provider,
                authorizationURL: URL(string: "https://vercel.com/oauth/authorize")!,
                tokenURL: URL(string: "https://api.vercel.com/login/oauth/token")!,
                scope: "openid profile offline_access"
            )
        default: nil
        }
    }

    private static func formEncoded(_ fields: [String: String]) -> String {
        fields.sorted { $0.key < $1.key }.map { key, value in
            "\(formEscape(key))=\(formEscape(value))"
        }.joined(separator: "&")
    }

    private static func formEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    private static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let renderResource = "https://mcp.render.com/mcp"
    private static let renderCallbackID: String = {
        let digest = SHA256.hash(data: Data(renderResource.utf8))
        return base64URL(Data(digest.prefix(9)))
    }()
}

private struct OAuthConfiguration {
    let provider: ConnectionProvider
    let authorizationURL: URL
    let tokenURL: URL
    let scope: String
}

private struct DynamicOAuthConfiguration {
    let provider: ConnectionProvider
    let authorizationURL: URL
    let tokenURL: URL
    let registrationURL: URL
    let scope: String
    let resource: String?

    static let cloudflareMCP = DynamicOAuthConfiguration(
        provider: .cloudflare,
        authorizationURL: URL(string: "https://mcp.cloudflare.com/authorize")!,
        tokenURL: URL(string: "https://mcp.cloudflare.com/token")!,
        registrationURL: URL(string: "https://mcp.cloudflare.com/register")!,
        scope: "offline_access user:read account:read pages.metadata_read",
        resource: "https://mcp.cloudflare.com/mcp"
    )

    static let vercel = DynamicOAuthConfiguration(
        provider: .vercel,
        authorizationURL: URL(string: "https://vercel.com/oauth/authorize")!,
        tokenURL: URL(string: "https://api.vercel.com/login/oauth/token")!,
        registrationURL: URL(string: "https://api.vercel.com/login/oauth/register")!,
        scope: "openid profile offline_access",
        resource: nil
    )
}
