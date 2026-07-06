import Foundation

enum WindowKind: CaseIterable {
    case fiveHour, sevenDay, sevenDayOpus

    var length: TimeInterval {
        switch self {
        case .fiveHour: return 5 * 3600
        case .sevenDay, .sevenDayOpus: return 7 * 24 * 3600
        }
    }

    var title: String {
        switch self {
        case .fiveHour: return "Session"
        case .sevenDay: return "Weekly"
        case .sevenDayOpus: return "Weekly (Opus)"
        }
    }
}

enum Source: String, CaseIterable {
    case subscription, spend, status
}

enum StatusColor { case green, yellow, red, gray }

enum ServiceStatus: Equatable {
    case operational, degraded, outage, unknown

    var label: String {
        switch self {
        case .operational: return "Operational"
        case .degraded: return "Degraded"
        case .outage: return "Outage"
        case .unknown: return "Unknown"
        }
    }

    var color: StatusColor {
        switch self {
        case .operational: return .green
        case .degraded: return .yellow
        case .outage: return .red
        case .unknown: return .gray
        }
    }
}

struct WindowUsage: Equatable {
    let utilization: Double      // 0.0 ... 1.0
    let resetsAt: Date
    let windowLength: TimeInterval
}

struct UsageSnapshot {
    var fiveHour: WindowUsage?
    var sevenDay: WindowUsage?
    var sevenDayOpus: WindowUsage?
    var monthlySpendUSD: Double?
    var status: ServiceStatus
    var lastUpdated: Date?
    var sourceErrors: [Source: String]

    static var empty: UsageSnapshot {
        UsageSnapshot(fiveHour: nil, sevenDay: nil, sevenDayOpus: nil,
                      monthlySpendUSD: nil, status: .unknown,
                      lastUpdated: nil, sourceErrors: [:])
    }

    func usage(for kind: WindowKind) -> WindowUsage? {
        switch kind {
        case .fiveHour: return fiveHour
        case .sevenDay: return sevenDay
        case .sevenDayOpus: return sevenDayOpus
        }
    }
}
