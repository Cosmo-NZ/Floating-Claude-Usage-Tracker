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

    func fetchUsage() async throws -> (five: WindowUsage?, seven: WindowUsage?, opus: WindowUsage?) {
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

    static func parseUsage(_ data: Data, now: Date) throws -> (five: WindowUsage?, seven: WindowUsage?, opus: WindowUsage?) {
        struct Window: Decodable { let utilization: Double?; let resets_at: String? }
        struct Response: Decodable { let five_hour: Window?; let seven_day: Window?; let seven_day_opus: Window? }
        let iso = ISO8601DateFormatter()
        func map(_ w: Window?, _ kind: WindowKind) -> WindowUsage? {
            guard let w, let util = w.utilization, let resetString = w.resets_at,
                  let resetsAt = iso.date(from: resetString) else { return nil }
            return WindowUsage(utilization: util / 100.0, resetsAt: resetsAt, windowLength: kind.length)
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        return (map(r.five_hour, .fiveHour), map(r.seven_day, .sevenDay), map(r.seven_day_opus, .sevenDayOpus))
    }
}
