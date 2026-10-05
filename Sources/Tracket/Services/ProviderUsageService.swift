import Foundation

struct ProviderUsageService: Sendable {
    func status(provider: ConnectionProvider, accessToken: String) async throws -> ProviderUsageStatus? {
        switch provider {
        case .github:
            return try await github(accessToken)
        case .cloudflare:
            return try await headerStatus(
                url: URL(string: "https://api.cloudflare.com/client/v4/accounts?per_page=1")!,
                token: accessToken,
                provider: provider
            )
        case .vercel:
            return try await headerStatus(
                url: URL(string: "https://api.vercel.com/v2/user")!,
                token: accessToken,
                provider: provider
            )
        case .render:
            return try await render(accessToken)
        default:
            return nil
        }
    }

    func accountUsage(provider: ConnectionProvider, accessToken: String) async throws -> ProviderAccountUsage? {
        switch provider {
        case .cloudflare:
            try await cloudflareAccountUsage(accessToken)
        case .vercel:
            try await vercelAccountUsage(accessToken)
        default:
            nil
        }
    }

    private func github(_ token: String) async throws -> ProviderUsageStatus? {
        var request = URLRequest(url: URL(string: "https://api.github.com/rate_limit")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resources = body["resources"] as? [String: Any],
              let core = resources["core"] as? [String: Any],
              let remaining = Self.integer(core["remaining"]),
              let limit = Self.integer(core["limit"]) else { return nil }
        let reset = Self.integer(core["reset"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return ProviderUsageStatus(
            label: "GitHub API requests",
            remaining: remaining,
            limit: limit,
            resetAt: reset,
            checkedAt: Date()
        )
    }

    private func headerStatus(
        url: URL,
        token: String,
        provider: ConnectionProvider
    ) async throws -> ProviderUsageStatus? {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }

        if provider == .cloudflare {
            guard let rate = http.value(forHTTPHeaderField: "Ratelimit"),
                  let policy = http.value(forHTTPHeaderField: "Ratelimit-Policy"),
                  let remaining = Self.parameter("r", in: rate),
                  let limit = Self.parameter("q", in: policy) else { return nil }
            let reset = Self.parameter("t", in: rate).map { Date().addingTimeInterval(TimeInterval($0)) }
            return ProviderUsageStatus(
                label: "Cloudflare API requests",
                remaining: remaining,
                limit: limit,
                resetAt: reset,
                checkedAt: Date()
            )
        }

        guard let remaining = Self.headerInteger("X-RateLimit-Remaining", response: http),
              let limit = Self.headerInteger("X-RateLimit-Limit", response: http) else { return nil }
        let resetValue = Self.headerInteger("X-RateLimit-Reset", response: http)
        let reset = resetValue.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return ProviderUsageStatus(
            label: "Vercel API requests",
            remaining: remaining,
            limit: limit,
            resetAt: reset,
            checkedAt: Date()
        )
    }

    private func render(_ token: String) async throws -> ProviderUsageStatus? {
        var request = URLRequest(url: URL(string: "https://mcp.render.com/mcp")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-06-18",
                "capabilities": [:],
                "clientInfo": ["name": "Tracket", "version": "0.2.0"]
            ]
        ])
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let remaining = Self.headerInteger("Ratelimit-Remaining", response: http),
              let limit = Self.headerInteger("Ratelimit-Limit", response: http)
                ?? Self.headerInteger("Rate-Limit", response: http) else { return nil }
        let resetValue = Self.headerInteger("Ratelimit-Reset", response: http)
        let reset = resetValue.map { value in
            value > 1_000_000_000
                ? Date(timeIntervalSince1970: TimeInterval(value))
                : Date().addingTimeInterval(TimeInterval(value))
        }
        return ProviderUsageStatus(
            label: "Render API requests",
            remaining: remaining,
            limit: limit,
            resetAt: reset,
            checkedAt: Date()
        )
    }

    private func cloudflareAccountUsage(_ token: String) async throws -> ProviderAccountUsage? {
        let accountResponse = try await json(
            URL(string: "https://api.cloudflare.com/client/v4/accounts?per_page=50")!,
            token: token
        )
        guard let accounts = (accountResponse as? [String: Any])?["result"] as? [[String: Any]],
              let account = accounts.first,
              let accountID = account["id"] as? String else { return nil }

        async let creditsResponse = optionalJSON(
            URL(string: "https://api.cloudflare.com/client/v4/accounts/\(accountID)/billing/credits")!,
            token: token
        )
        async let subscriptionsResponse = optionalJSON(
            URL(string: "https://api.cloudflare.com/client/v4/accounts/\(accountID)/subscriptions")!,
            token: token
        )
        let (creditsEnvelope, subscriptionsEnvelope) = await (creditsResponse, subscriptionsResponse)
        let credit = (creditsEnvelope as? [String: Any])?["result"] as? [String: Any]
        let subscriptions = (subscriptionsEnvelope as? [String: Any])?["result"] as? [[String: Any]]
        let subscription = subscriptions?.first
        guard credit != nil || subscription != nil else { return nil }

        let plan = subscription?["rate_plan"] as? [String: Any]
        let planName = Self.string(plan?["public_name"] ?? plan?["id"])
        let percentConsumed = Self.double(credit?["percent_consumed"])
        let currentPeriodEnd = Self.date(subscription?["current_period_end"])
        let creditEnd = Self.date(credit?["valid_to"])
        let confirmedCents = Self.double(credit?["confirmed_balance_cents"])
        let originalCents = Self.double(credit?["original_amount_cents"])
        let currency = Self.string(credit?["currency"])?.uppercased()
        var metrics: [ProviderUsageMetric] = []
        if let originalCents {
            metrics.append(ProviderUsageMetric(
                label: "Original credit",
                value: Self.money(cents: originalCents, currency: currency)
            ))
        }
        if let days = Self.integer(credit?["days_remaining"]) {
            metrics.append(ProviderUsageMetric(label: "Credit validity", value: "\(days) days left"))
        }
        if let state = Self.string(subscription?["state"]) {
            metrics.append(ProviderUsageMetric(label: "Subscription", value: state))
        }

        return ProviderAccountUsage(
            accountEmail: nil,
            planName: planName,
            primary: percentConsumed.map {
                ProviderUsageWindow(
                    title: "Account credits",
                    usedPercent: Int($0.rounded()),
                    durationMinutes: nil,
                    resetAt: creditEnd ?? currentPeriodEnd
                )
            },
            secondary: nil,
            creditBalance: confirmedCents.map { String(format: "%.2f", $0 / 100) },
            unlimitedCredits: false,
            availableResetCredits: nil,
            resetCreditExpirations: creditEnd.map { [$0] } ?? [],
            modelName: nil,
            checkedAt: Date(),
            creditCurrency: currency,
            metrics: metrics.isEmpty ? nil : metrics,
            note: credit == nil ? "Billing-credit permission was not granted; subscription details are shown when available." : nil,
            detailsURL: "https://dash.cloudflare.com/?to=/:account/billing"
        )
    }

    private func vercelAccountUsage(_ token: String) async throws -> ProviderAccountUsage? {
        let teamsResponse = try await json(URL(string: "https://api.vercel.com/v2/teams?limit=20")!, token: token)
        guard let teams = (teamsResponse as? [String: Any])?["teams"] as? [[String: Any]],
              let team = teams.first,
              let teamID = Self.string(team["id"]) else { return nil }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var components = URLComponents(string: "https://api.vercel.com/v1/billing/charges")!
        components.queryItems = [
            URLQueryItem(name: "teamId", value: teamID),
            URLQueryItem(name: "from", value: formatter.string(from: monthStart)),
            URLQueryItem(name: "to", value: formatter.string(from: tomorrow))
        ]
        guard let url = components.url,
              let records = try? await jsonLines(url, token: token),
              !records.isEmpty else { return nil }

        var billed = 0.0
        var effective = 0.0
        var currency = "USD"
        var serviceTotals: [String: Double] = [:]
        for row in records {
            let billedCost = Self.double(row["BilledCost"] ?? row["billedCost"]) ?? 0
            let effectiveCost = Self.double(row["EffectiveCost"] ?? row["effectiveCost"]) ?? billedCost
            billed += billedCost
            effective += effectiveCost
            currency = Self.string(row["BillingCurrency"] ?? row["billingCurrency"]) ?? currency
            let service = Self.string(row["ServiceName"] ?? row["serviceName"]) ?? "Other"
            serviceTotals[service, default: 0] += billedCost
        }
        let topService = serviceTotals.max(by: { $0.value < $1.value })
        let billing = team["billing"] as? [String: Any]
        let plan = Self.string(billing?["plan"] ?? team["plan"])
        var metrics = [
            ProviderUsageMetric(label: "Billed this month", value: Self.money(amount: billed, currency: currency)),
            ProviderUsageMetric(label: "Effective cost", value: Self.money(amount: effective, currency: currency)),
            ProviderUsageMetric(label: "Charge records", value: records.count.formatted())
        ]
        if let topService {
            metrics.append(ProviderUsageMetric(
                label: "Top service",
                value: topService.key,
                detail: Self.money(amount: topService.value, currency: currency)
            ))
        }
        return ProviderAccountUsage(
            accountEmail: nil,
            planName: plan?.capitalized ?? "Team billing",
            primary: nil,
            secondary: nil,
            creditBalance: nil,
            unlimitedCredits: false,
            availableResetCredits: nil,
            resetCreditExpirations: [],
            modelName: nil,
            checkedAt: Date(),
            creditCurrency: currency,
            metrics: metrics,
            note: "Billing totals cover the current calendar month. Vercel exposes this only to billing-scoped Pro and Enterprise integrations.",
            detailsURL: "https://vercel.com/dashboard/usage"
        )
    }

    private func json(_ url: URL, token: String) async throws -> Any {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func optionalJSON(_ url: URL, token: String) async -> Any? {
        try? await json(url, token: token)
    }

    private func jsonLines(_ url: URL, token: String) async throws -> [[String: Any]] {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-ndjson, application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] { return array }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["charges", "data", "items"] {
                if let rows = object[key] as? [[String: Any]] { return rows }
            }
            return [object]
        }
        return data.split(separator: 0x0A).compactMap { line in
            try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        }
    }

    private static func headerInteger(_ name: String, response: HTTPURLResponse) -> Int? {
        response.value(forHTTPHeaderField: name).flatMap(Int.init)
    }

    private static func parameter(_ name: String, in value: String) -> Int? {
        let pattern = "(?:^|[;,]\\s*)\(NSRegularExpression.escapedPattern(for: name))=(\\d+)"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return Int(value[range])
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func money(cents: Double, currency: String?) -> String {
        let amount = cents / 100
        if currency == "USD" || currency == nil { return String(format: "$%.2f", amount) }
        return "\(currency!) \(String(format: "%.2f", amount))"
    }

    private static func money(amount: Double, currency: String) -> String {
        if currency == "USD" { return String(format: "$%.2f", amount) }
        return "\(currency) \(String(format: "%.2f", amount))"
    }
}
