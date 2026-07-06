import Foundation

struct ThresholdTracker {
    static let thresholds: [Double] = [0.75, 0.90, 0.95]

    private var highestNotified: [WindowKind: Double] = [:]

    mutating func crossings(kind: WindowKind, utilization: Double) -> [Double] {
        let previous = highestNotified[kind] ?? 0
        // Reset if the window clearly rolled over (usage dropped below what we last notified).
        if utilization < previous { highestNotified[kind] = 0 }
        let floor = highestNotified[kind] ?? 0
        let newlyCrossed = Self.thresholds.filter { $0 > floor && utilization >= $0 }
        if let maxCrossed = newlyCrossed.max() { highestNotified[kind] = maxCrossed }
        return newlyCrossed
    }
}
