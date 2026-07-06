import Foundation

struct StatusClient: StatusProviding {
    private let url = URL(string: "https://status.claude.com/api/v2/status.json")!

    func fetchStatus() async throws -> ServiceStatus {
        let data = try await HTTP.get(url, debugLabel: "status")
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> ServiceStatus {
        struct Response: Decodable { struct Status: Decodable { let indicator: String? }; let status: Status }
        let indicator = try JSONDecoder().decode(Response.self, from: data).status.indicator ?? ""
        switch indicator.lowercased() {
        case "none": return .operational
        case "minor", "maintenance": return .degraded
        case "major", "critical": return .outage
        default: return .unknown
        }
    }
}
