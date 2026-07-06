import SwiftUI

struct UsageBar: View {
    let kind: WindowKind
    let usage: WindowUsage?
    let hasError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(kind.title).font(.system(size: 12, weight: .semibold))
                if hasError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow).font(.system(size: 10))
                }
                Spacer()
                Text(usage.map { "\(Int($0.utilization * 100))%" } ?? "—")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 6)
                    Capsule().fill(barColor)
                        .frame(width: geo.size.width * (usage?.utilization ?? 0), height: 6)
                }
            }.frame(height: 6)
            if let usage {
                Text("⧗ \(TimeProgress.elapsedString(resetsAt: usage.resetsAt, windowLength: usage.windowLength)) · \(TimeProgress.resetString(resetsAt: usage.resetsAt))")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            } else {
                Text("Not connected").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    private var barColor: Color {
        switch usage?.utilization ?? 0 {
        case 0.9...: return .red
        case 0.75...: return .orange
        default: return .accentColor
        }
    }
}
