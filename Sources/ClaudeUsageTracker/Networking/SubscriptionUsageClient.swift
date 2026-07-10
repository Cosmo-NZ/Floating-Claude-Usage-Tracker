import Foundation

struct SubscriptionUsageClient: SubscriptionProviding {
    enum SubscriptionError: Error, LocalizedError {
        case unauthorized
        case noOrganization
        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Session key expired — reconnect Claude.ai"
            case .noOrganization: return "No organization found for this session"
            }
        }
    }

    let sessionKey: String

    private var commonHeaders: [String: String] {
        [
            "Cookie": "sessionKey=\(sessionKey)",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            "Accept": "application/json",
        ]
    }

    func fetchUsage() async throws -> SubscriptionUsage {
        let orgID = try await fetchOrgID()
        let url = URL(string: "https://claude.ai/api/organizations/\(orgID)/usage")!
        let data: Data
        do {
            data = try await HTTP.get(url, headers: commonHeaders, debugLabel: "usage")
        } catch let e as HTTPError where e.status == 401 || e.status == 403 {
            throw SubscriptionError.unauthorized
        }
        return try Self.parseUsage(data, now: Date())
    }

    private func fetchOrgID() async throws -> String {
        let url = URL(string: "https://claude.ai/api/organizations")!
        let data: Data
        do {
            data = try await HTTP.get(url, headers: commonHeaders, debugLabel: "organizations")
        } catch let e as HTTPError where e.status == 401 || e.status == 403 {
            throw SubscriptionError.unauthorized
        }
        return try Self.parseOrgID(data)
    }

    static func parseOrgID(_ data: Data) throws -> String {
        struct Org: Decodable { let uuid: String }
        guard let first = try JSONDecoder().decode([Org].self, from: data).first else {
            throw SubscriptionError.noOrganization
        }
        return first.uuid
    }

    static func parseUsage(_ data: Data, now: Date) throws -> SubscriptionUsage {
        struct Window: Decodable { let utilization: Double?; let resets_at: String? }
        struct Limit: Decodable {
            struct Scope: Decodable { struct Model: Decodable { let display_name: String? }; let model: Model? }
            let percent: Double?
            let resets_at: String?
            let scope: Scope?
        }
        struct Response: Decodable {
            let five_hour: Window?
            let seven_day: Window?
            let seven_day_opus: Window?
            let limits: [Limit]?
        }
        func map(_ w: Window?, _ kind: WindowKind) -> WindowUsage? {
            guard let w, let util = w.utilization, let resetString = w.resets_at,
                  let resetsAt = parseDate(resetString) else { return nil }
            return WindowUsage(utilization: util / 100.0, resetsAt: resetsAt, windowLength: kind.length)
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        let sevenDay = map(r.seven_day, .sevenDay)

        // Per-model weekly usage (e.g. Fable) lives in the `limits` array as a scoped weekly limit.
        // At 0% usage the API omits its `resets_at`, so fall back to the overall weekly reset
        // (the scoped weekly shares the same 7-day cadence).
        func scopedWeekly(model: String, fallbackReset: Date?) -> WindowUsage? {
            guard let limit = (r.limits ?? []).first(where: {
                      $0.scope?.model?.display_name?.caseInsensitiveCompare(model) == .orderedSame
                  }),
                  let percent = limit.percent else { return nil }
            let resetsAt = limit.resets_at.flatMap { parseDate($0) } ?? fallbackReset
            guard let resetsAt else { return nil }
            return WindowUsage(utilization: percent / 100.0, resetsAt: resetsAt, windowLength: WindowKind.weeklyFable.length)
        }

        return SubscriptionUsage(
            fiveHour: map(r.five_hour, .fiveHour),
            sevenDay: sevenDay,
            sevenDayOpus: map(r.seven_day_opus, .sevenDayOpus),
            weeklyFable: scopedWeekly(model: "Fable", fallbackReset: sevenDay?.resetsAt))
    }

    /// Parses RFC3339 / ISO-8601 timestamps, tolerating fractional seconds of any precision
    /// (the API returns microseconds, e.g. "2026-07-06T03:00:00.249261+00:00").
    static func parseDate(_ s: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: s) { return d }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }

        // Strip fractional seconds (handles >3 fractional digits the formatter rejects).
        if let dot = s.firstIndex(of: "."),
           let tz = s[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            return plain.date(from: String(s[..<dot]) + String(s[tz...]))
        }
        return nil
    }
}
