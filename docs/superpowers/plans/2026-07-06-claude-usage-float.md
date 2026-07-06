# Claude Usage Floating Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS accessory app that shows Claude subscription usage (5-hour + weekly), live availability, and optional API spend in a compact, draggable, always-on-top floating panel with an optional menu bar item.

**Architecture:** Fully AppKit-driven entry point (`main.swift` → `NSApplication` in `.accessory` mode) hosting SwiftUI views via `NSHostingView`. A `UsageStore` (`@Observable`) owns a refresh timer and three protocol-backed network clients, merging their results into one `UsageSnapshot` that drives the panel, menu bar item, and threshold notifications. Credentials live in the Keychain; settings in UserDefaults.

**Tech Stack:** Swift 6.3, SwiftPM executable target (buildable from CLI, openable in Xcode via `Package.swift`), SwiftUI + AppKit + WebKit + UserNotifications + ServiceManagement, XCTest. Packaged into a `.app` bundle by `scripts/build_app.sh` (ad-hoc codesigned).

## Global Constraints

- Deployment target: **macOS 14.0**. Set in `Package.swift` (`.macOS(.v14)`) and `Info.plist` (`LSMinimumSystemVersion` = `14.0`).
- Bundle identifier: `com.marccramer.ClaudeUsageTracker` (used verbatim by Keychain service names, UserDefaults suite, notifications, login item).
- App runs as an accessory (`LSUIElement` = `true`, `NSApp.setActivationPolicy(.accessory)`): **no Dock icon**.
- English only. No App Sandbox (simplest network + Keychain access for a local MVP).
- Refresh interval: user slider, range **10–300 seconds, default 30**.
- Notification thresholds: **0.75 / 0.90 / 0.95**, upward-crossing only, per window, reset when the window's utilization drops.
- The claude.ai usage endpoint and the Anthropic cost-report endpoint are **unofficial / version-sensitive**: each parser is isolated in its own file and tested against a documented fixture. If a live response differs, only that one parser changes. Every client logs its raw response body to stderr when the env var `CUT_DEBUG=1` is set.
- Executable/product/target name everywhere: `ClaudeUsageTracker`.

---

## File Structure

```
ClaudeUsageTracker/
  Package.swift
  Resources/
    Info.plist
  scripts/
    build_app.sh              # swift build -c release + assemble .app + ad-hoc sign
    run.sh                    # build_app.sh then open the .app
  Sources/ClaudeUsageTracker/
    main.swift                # NSApplication bootstrap (.accessory)
    AppDelegate.swift         # wires store, panel, menu bar, settings window
    Models/
      UsageModels.swift       # WindowUsage, UsageSnapshot, ServiceStatus, Source, WindowKind
      TimeProgress.swift      # pure elapsed-fraction / formatting helpers
    Networking/
      UsageClients.swift      # client protocols + shared HTTP helper
      StatusClient.swift      # status.claude.com parsing
      SubscriptionUsageClient.swift
      ConsoleSpendClient.swift
    Store/
      ThresholdTracker.swift  # pure upward-crossing logic
      UsageStore.swift        # @Observable orchestrator + refresh timer
    Persistence/
      KeychainStore.swift
      AppSettings.swift       # @Observable, UserDefaults-backed
    Platform/
      NotificationManager.swift
      LoginItemManager.swift
      MenuBarController.swift
      FloatingPanel.swift     # NSPanel subclass
      SignInWebView.swift     # WKWebView sessionKey extraction
    Views/
      PanelView.swift
      SettingsView.swift
      UsageBar.swift          # small reusable bar + time line row
  Tests/ClaudeUsageTrackerTests/
    TimeProgressTests.swift
    StatusClientTests.swift
    SubscriptionUsageClientTests.swift
    ConsoleSpendClientTests.swift
    ThresholdTrackerTests.swift
    UsageStoreTests.swift
    Fixtures/
      status.json
      organizations.json
      usage.json
      cost_report.json
```

Testable pure logic (models, time math, parsers, threshold tracker, store-with-fakes) is separated from UI/platform glue (panel, views, menu bar, web view), which is verified by running the app.

---

### Task 1: Project scaffold + buildable empty accessory app

**Files:**
- Create: `Package.swift`
- Create: `Resources/Info.plist`
- Create: `scripts/build_app.sh`, `scripts/run.sh`
- Create: `Sources/ClaudeUsageTracker/main.swift`
- Create: `Sources/ClaudeUsageTracker/AppDelegate.swift`
- Create: `Tests/ClaudeUsageTrackerTests/TimeProgressTests.swift` (temporary smoke test, replaced in Task 2)

**Interfaces:**
- Produces: an executable target `ClaudeUsageTracker`; `scripts/build_app.sh` emitting `build/ClaudeUsageTracker.app`; a running accessory app that shows an empty floating window titled "Claude Usage".

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsageTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeUsageTracker",
            path: "Sources/ClaudeUsageTracker"
        ),
        .testTarget(
            name: "ClaudeUsageTrackerTests",
            dependencies: ["ClaudeUsageTracker"],
            path: "Tests/ClaudeUsageTrackerTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: Create `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Claude Usage Tracker</string>
    <key>CFBundleDisplayName</key><string>Claude Usage Tracker</string>
    <key>CFBundleIdentifier</key><string>com.marccramer.ClaudeUsageTracker</string>
    <key>CFBundleExecutable</key><string>ClaudeUsageTracker</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Marc Cramer</string>
</dict>
</plist>
```

- [ ] **Step 3: Create `Sources/ClaudeUsageTracker/main.swift`**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 4: Create a minimal `Sources/ClaudeUsageTracker/AppDelegate.swift`**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Usage"
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 5: Create `scripts/build_app.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/ClaudeUsageTracker"
APP="build/ClaudeUsageTracker.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeUsageTracker"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"
echo "Built $APP"
```

- [ ] **Step 6: Create `scripts/run.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build_app.sh "${1:-debug}"
open build/ClaudeUsageTracker.app
```

- [ ] **Step 7: Create a temporary smoke test `Tests/ClaudeUsageTrackerTests/TimeProgressTests.swift`**

```swift
import XCTest

final class SmokeTests: XCTestCase {
    func testScaffoldCompiles() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 8: Create the fixtures directory placeholder so the test resource copy succeeds**

Run: `mkdir -p Tests/ClaudeUsageTrackerTests/Fixtures && echo '{}' > Tests/ClaudeUsageTrackerTests/Fixtures/.keep.json`

- [ ] **Step 9: Build and test**

Run: `chmod +x scripts/*.sh && swift build && swift test`
Expected: build succeeds; `SmokeTests.testScaffoldCompiles` PASSES.

- [ ] **Step 10: Verify the app bundle launches**

Run: `./scripts/build_app.sh && open build/ClaudeUsageTracker.app`
Expected: a 280×200 window titled "Claude Usage" appears, no Dock icon. Close it, then `killall ClaudeUsageTracker 2>/dev/null || true`.

- [ ] **Step 11: Commit**

```bash
git init 2>/dev/null || true
cat > .gitignore <<'EOF'
.build/
build/
.DS_Store
EOF
git add -A
git commit -m "chore: scaffold ClaudeUsageTracker accessory app"
```

---

### Task 2: Core models + time-progress math

**Files:**
- Create: `Sources/ClaudeUsageTracker/Models/UsageModels.swift`
- Create: `Sources/ClaudeUsageTracker/Models/TimeProgress.swift`
- Replace: `Tests/ClaudeUsageTrackerTests/TimeProgressTests.swift`

**Interfaces:**
- Produces:
  - `enum WindowKind { case fiveHour, sevenDay, sevenDayOpus }` with `var length: TimeInterval`
  - `enum Source: String, CaseIterable { case subscription, spend, status }`
  - `enum ServiceStatus { case operational, degraded, outage, unknown; var label: String; var color: StatusColor }` where `enum StatusColor { case green, yellow, red, gray }`
  - `struct WindowUsage { let utilization: Double; let resetsAt: Date; let windowLength: TimeInterval }`
  - `struct UsageSnapshot { var fiveHour, sevenDay, sevenDayOpus: WindowUsage?; var monthlySpendUSD: Double?; var status: ServiceStatus; var lastUpdated: Date?; var sourceErrors: [Source: String] }` with a `static var empty`
  - `enum TimeProgress { static func elapsedFraction(resetsAt:windowLength:now:) -> Double; static func elapsedString(resetsAt:windowLength:now:) -> String; static func resetString(resetsAt:now:) -> String }`

- [ ] **Step 1: Write failing tests — replace `Tests/ClaudeUsageTrackerTests/TimeProgressTests.swift`**

```swift
import XCTest
@testable import ClaudeUsageTracker

final class TimeProgressTests: XCTestCase {
    func testElapsedFractionMidway() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(2.5 * 3600) // 2.5h left of a 5h window
        let f = TimeProgress.elapsedFraction(resetsAt: resetsAt, windowLength: 5 * 3600, now: now)
        XCTAssertEqual(f, 0.5, accuracy: 0.0001)
    }

    func testElapsedFractionClampsAboveOne() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(-3600) // reset already passed
        let f = TimeProgress.elapsedFraction(resetsAt: resetsAt, windowLength: 5 * 3600, now: now)
        XCTAssertEqual(f, 1.0, accuracy: 0.0001)
    }

    func testElapsedFractionClampsBelowZero() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(6 * 3600) // more than a full window away
        let f = TimeProgress.elapsedFraction(resetsAt: resetsAt, windowLength: 5 * 3600, now: now)
        XCTAssertEqual(f, 0.0, accuracy: 0.0001)
    }

    func testElapsedStringHoursAndMinutes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(1.8 * 3600) // 3h 12m elapsed of 5h
        let s = TimeProgress.elapsedString(resetsAt: resetsAt, windowLength: 5 * 3600, now: now)
        XCTAssertEqual(s, "3h 12m elapsed")
    }

    func testElapsedStringDaysAndHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval((7 - 3.25) * 24 * 3600) // 3d 6h elapsed of 7d
        let s = TimeProgress.elapsedString(resetsAt: resetsAt, windowLength: 7 * 24 * 3600, now: now)
        XCTAssertEqual(s, "3d 6h elapsed")
    }

    func testWindowKindLengths() {
        XCTAssertEqual(WindowKind.fiveHour.length, 5 * 3600)
        XCTAssertEqual(WindowKind.sevenDay.length, 7 * 24 * 3600)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TimeProgressTests`
Expected: FAIL — `TimeProgress` / `WindowKind` not defined.

- [ ] **Step 3: Create `Sources/ClaudeUsageTracker/Models/UsageModels.swift`**

```swift
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
```

- [ ] **Step 4: Create `Sources/ClaudeUsageTracker/Models/TimeProgress.swift`**

```swift
import Foundation

enum TimeProgress {
    static func elapsedFraction(resetsAt: Date, windowLength: TimeInterval, now: Date = Date()) -> Double {
        let start = resetsAt.addingTimeInterval(-windowLength)
        let elapsed = now.timeIntervalSince(start)
        return min(max(elapsed / windowLength, 0), 1)
    }

    static func elapsedString(resetsAt: Date, windowLength: TimeInterval, now: Date = Date()) -> String {
        let start = resetsAt.addingTimeInterval(-windowLength)
        let elapsed = max(now.timeIntervalSince(start), 0)
        if windowLength >= 24 * 3600 {
            let days = Int(elapsed) / 86_400
            let hours = (Int(elapsed) % 86_400) / 3600
            return "\(days)d \(hours)h elapsed"
        } else {
            let hours = Int(elapsed) / 3600
            let minutes = (Int(elapsed) % 3600) / 60
            return "\(hours)h \(minutes)m elapsed"
        }
    }

    static func resetString(resetsAt: Date, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDate(resetsAt, inSameDayAs: now) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "EEE"
        }
        return "resets \(formatter.string(from: resetsAt))"
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter TimeProgressTests`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: core usage models and time-progress helpers"
```

---

### Task 3: StatusClient (status.claude.com)

**Files:**
- Create: `Sources/ClaudeUsageTracker/Networking/UsageClients.swift`
- Create: `Sources/ClaudeUsageTracker/Networking/StatusClient.swift`
- Create: `Tests/ClaudeUsageTrackerTests/StatusClientTests.swift`
- Create: `Tests/ClaudeUsageTrackerTests/Fixtures/status.json`

**Interfaces:**
- Produces:
  - `protocol StatusProviding { func fetchStatus() async throws -> ServiceStatus }`
  - `protocol SubscriptionProviding { func fetchUsage() async throws -> (five: WindowUsage?, seven: WindowUsage?, opus: WindowUsage?) }`
  - `protocol SpendProviding { func fetchMonthlySpendUSD() async throws -> Double }`
  - `enum HTTP { static func get(_ url: URL, headers: [String:String], debugLabel: String) async throws -> Data }`
  - `struct StatusClient: StatusProviding` with `static func parse(_ data: Data) throws -> ServiceStatus`
- Consumes: `ServiceStatus` (Task 2).

- [ ] **Step 1: Create fixture `Tests/ClaudeUsageTrackerTests/Fixtures/status.json`**

```json
{ "page": { "name": "Claude" }, "status": { "indicator": "minor", "description": "Partially Degraded Service" } }
```

- [ ] **Step 2: Write failing test `Tests/ClaudeUsageTrackerTests/StatusClientTests.swift`**

```swift
import XCTest
@testable import ClaudeUsageTracker

final class StatusClientTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testParsesMinorAsDegraded() throws {
        let status = try StatusClient.parse(fixture("status"))
        XCTAssertEqual(status, .degraded)
    }

    func testMapsIndicators() throws {
        XCTAssertEqual(try StatusClient.parse(Data(#"{"status":{"indicator":"none"}}"#.utf8)), .operational)
        XCTAssertEqual(try StatusClient.parse(Data(#"{"status":{"indicator":"critical"}}"#.utf8)), .outage)
        XCTAssertEqual(try StatusClient.parse(Data(#"{"status":{"indicator":"maintenance"}}"#.utf8)), .degraded)
        XCTAssertEqual(try StatusClient.parse(Data(#"{"status":{"indicator":"weird"}}"#.utf8)), .unknown)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter StatusClientTests`
Expected: FAIL — `StatusClient` not defined.

- [ ] **Step 4: Create `Sources/ClaudeUsageTracker/Networking/UsageClients.swift`**

```swift
import Foundation

protocol StatusProviding { func fetchStatus() async throws -> ServiceStatus }
protocol SubscriptionProviding {
    func fetchUsage() async throws -> (five: WindowUsage?, seven: WindowUsage?, opus: WindowUsage?)
}
protocol SpendProviding { func fetchMonthlySpendUSD() async throws -> Double }

struct HTTPError: Error, LocalizedError {
    let status: Int
    let body: String
    var errorDescription: String? { "HTTP \(status)" }
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    static func get(_ url: URL, headers: [String: String] = [:], debugLabel: String) async throws -> Data {
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: request)
        if ProcessInfo.processInfo.environment["CUT_DEBUG"] == "1" {
            FileHandle.standardError.write(Data("[\(debugLabel)] \(String(data: data, encoding: .utf8) ?? "<binary>")\n".utf8))
        }
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
```

- [ ] **Step 5: Create `Sources/ClaudeUsageTracker/Networking/StatusClient.swift`**

```swift
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
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter StatusClientTests`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: status.claude.com availability client"
```

---

### Task 4: SubscriptionUsageClient (claude.ai usage)

**Files:**
- Create: `Sources/ClaudeUsageTracker/Networking/SubscriptionUsageClient.swift`
- Create: `Tests/ClaudeUsageTrackerTests/SubscriptionUsageClientTests.swift`
- Create: `Tests/ClaudeUsageTrackerTests/Fixtures/organizations.json`, `Tests/ClaudeUsageTrackerTests/Fixtures/usage.json`

**Interfaces:**
- Consumes: `WindowUsage`, `WindowKind` (Task 2); `HTTP`, `SubscriptionProviding` (Task 3).
- Produces: `struct SubscriptionUsageClient: SubscriptionProviding` with:
  - `init(sessionKey: String)`
  - `static func parseOrgID(_ data: Data) throws -> String`
  - `static func parseUsage(_ data: Data, now: Date) throws -> (five: WindowUsage?, seven: WindowUsage?, opus: WindowUsage?)`
  - `struct SubscriptionError: Error` with a `.unauthorized` case for expired keys.

**NOTE (unofficial endpoint):** This parser targets the documented assumed shape below. The three usage keys carry `utilization` (0–100 integer percent) and `resets_at` (ISO-8601). If the live response differs, adjust only `parseUsage`. Run the app once with `CUT_DEBUG=1` to capture the real body.

- [ ] **Step 1: Create `Tests/ClaudeUsageTrackerTests/Fixtures/organizations.json`**

```json
[ { "uuid": "org-abc-123", "name": "Marc Cramer" } ]
```

- [ ] **Step 2: Create `Tests/ClaudeUsageTrackerTests/Fixtures/usage.json`**

```json
{
  "five_hour":       { "utilization": 42, "resets_at": "2026-07-06T17:00:00Z" },
  "seven_day":       { "utilization": 63, "resets_at": "2026-07-09T00:00:00Z" },
  "seven_day_opus":  { "utilization": 12, "resets_at": "2026-07-09T00:00:00Z" }
}
```

- [ ] **Step 3: Write failing test `Tests/ClaudeUsageTrackerTests/SubscriptionUsageClientTests.swift`**

```swift
import XCTest
@testable import ClaudeUsageTracker

final class SubscriptionUsageClientTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testParsesOrgID() throws {
        XCTAssertEqual(try SubscriptionUsageClient.parseOrgID(fixture("organizations")), "org-abc-123")
    }

    func testParsesUsageWindows() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let result = try SubscriptionUsageClient.parseUsage(fixture("usage"), now: now)
        XCTAssertEqual(result.five?.utilization ?? 0, 0.42, accuracy: 0.0001)
        XCTAssertEqual(result.five?.windowLength, 5 * 3600)
        XCTAssertEqual(result.seven?.utilization ?? 0, 0.63, accuracy: 0.0001)
        XCTAssertEqual(result.seven?.windowLength, 7 * 24 * 3600)
        XCTAssertEqual(result.opus?.utilization ?? 0, 0.12, accuracy: 0.0001)
        let expected = ISO8601DateFormatter().date(from: "2026-07-06T17:00:00Z")
        XCTAssertEqual(result.five?.resetsAt, expected)
    }

    func testMissingWindowsBecomeNil() throws {
        let result = try SubscriptionUsageClient.parseUsage(Data("{}".utf8), now: Date())
        XCTAssertNil(result.five)
        XCTAssertNil(result.seven)
        XCTAssertNil(result.opus)
    }
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `swift test --filter SubscriptionUsageClientTests`
Expected: FAIL — `SubscriptionUsageClient` not defined.

- [ ] **Step 5: Create `Sources/ClaudeUsageTracker/Networking/SubscriptionUsageClient.swift`**

```swift
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
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter SubscriptionUsageClientTests`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: claude.ai subscription usage client"
```

---

### Task 5: ConsoleSpendClient (Anthropic cost report)

**Files:**
- Create: `Sources/ClaudeUsageTracker/Networking/ConsoleSpendClient.swift`
- Create: `Tests/ClaudeUsageTrackerTests/ConsoleSpendClientTests.swift`
- Create: `Tests/ClaudeUsageTrackerTests/Fixtures/cost_report.json`

**Interfaces:**
- Consumes: `HTTP`, `SpendProviding` (Task 3).
- Produces: `struct ConsoleSpendClient: SpendProviding` with `init(adminKey: String)`, `static func parseSpend(_ data: Data) throws -> Double`, `static func monthStartISO(now: Date) -> String`.

**NOTE (version-sensitive endpoint):** Targets `GET https://api.anthropic.com/v1/organizations/cost_report` with headers `x-api-key` and `anthropic-version: 2023-06-01`. Response has `data[].results[].amount` (string USD). Sums all amounts. Adjust only `parseSpend` if the live shape differs.

- [ ] **Step 1: Create `Tests/ClaudeUsageTrackerTests/Fixtures/cost_report.json`**

```json
{
  "data": [
    { "results": [ { "amount": "12.50", "currency": "USD" } ] },
    { "results": [ { "amount": "29.68", "currency": "USD" }, { "amount": "0.00", "currency": "USD" } ] }
  ]
}
```

- [ ] **Step 2: Write failing test `Tests/ClaudeUsageTrackerTests/ConsoleSpendClientTests.swift`**

```swift
import XCTest
@testable import ClaudeUsageTracker

final class ConsoleSpendClientTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testSumsAllAmounts() throws {
        let total = try ConsoleSpendClient.parseSpend(fixture("cost_report"))
        XCTAssertEqual(total, 42.18, accuracy: 0.001)
    }

    func testEmptyDataIsZero() throws {
        XCTAssertEqual(try ConsoleSpendClient.parseSpend(Data(#"{"data":[]}"#.utf8)), 0.0, accuracy: 0.001)
    }

    func testMonthStartIsFirstOfMonthUTC() {
        let now = ISO8601DateFormatter().date(from: "2026-07-06T14:00:00Z")!
        XCTAssertTrue(ConsoleSpendClient.monthStartISO(now: now).hasPrefix("2026-07-01"))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter ConsoleSpendClientTests`
Expected: FAIL — `ConsoleSpendClient` not defined.

- [ ] **Step 4: Create `Sources/ClaudeUsageTracker/Networking/ConsoleSpendClient.swift`**

```swift
import Foundation

struct ConsoleSpendClient: SpendProviding {
    let adminKey: String

    func fetchMonthlySpendUSD() async throws -> Double {
        var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/cost_report")!
        components.queryItems = [URLQueryItem(name: "starting_at", value: Self.monthStartISO(now: Date()))]
        let data = try await HTTP.get(components.url!, headers: [
            "x-api-key": adminKey,
            "anthropic-version": "2023-06-01",
        ], debugLabel: "cost_report")
        return try Self.parseSpend(data)
    }

    static func monthStartISO(now: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month], from: now)
        let start = cal.date(from: comps)!
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(identifier: "UTC")
        return iso.string(from: start)
    }

    static func parseSpend(_ data: Data) throws -> Double {
        struct Result: Decodable { let amount: String? }
        struct Bucket: Decodable { let results: [Result]? }
        struct Response: Decodable { let data: [Bucket]? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return (response.data ?? []).reduce(0.0) { sum, bucket in
            sum + (bucket.results ?? []).reduce(0.0) { $0 + (Double($1.amount ?? "0") ?? 0) }
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ConsoleSpendClientTests`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: Anthropic console spend client"
```

---

### Task 6: KeychainStore + AppSettings

**Files:**
- Create: `Sources/ClaudeUsageTracker/Persistence/KeychainStore.swift`
- Create: `Sources/ClaudeUsageTracker/Persistence/AppSettings.swift`
- Create: `Tests/ClaudeUsageTrackerTests/KeychainStoreTests.swift`

**Interfaces:**
- Produces:
  - `enum KeychainStore { static func set(_ value: String?, for key: Key); static func get(_ key: Key) -> String?; enum Key: String { case sessionKey, adminKey } }`
  - `@Observable final class AppSettings` with: `var refreshInterval: Double` (10–300, default 30), `var spendEnabled: Bool`, `var notificationsEnabled: Bool`, `var launchAtLogin: Bool`, `var alwaysOnTop: Bool`, `var showMenuBarIcon: Bool`, persisted panel origin `var panelOriginX/Y: Double`. All backed by `UserDefaults(suiteName:)`. Plus `static let shared`.

- [ ] **Step 1: Write failing test `Tests/ClaudeUsageTrackerTests/KeychainStoreTests.swift`**

```swift
import XCTest
@testable import ClaudeUsageTracker

final class KeychainStoreTests: XCTestCase {
    func testRoundTripAndDelete() {
        KeychainStore.set("secret-123", for: .sessionKey)
        XCTAssertEqual(KeychainStore.get(.sessionKey), "secret-123")
        KeychainStore.set(nil, for: .sessionKey)
        XCTAssertNil(KeychainStore.get(.sessionKey))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter KeychainStoreTests`
Expected: FAIL — `KeychainStore` not defined.

- [ ] **Step 3: Create `Sources/ClaudeUsageTracker/Persistence/KeychainStore.swift`**

```swift
import Foundation
import Security

enum KeychainStore {
    enum Key: String { case sessionKey, adminKey }

    private static let service = "com.marccramer.ClaudeUsageTracker"

    static func set(_ value: String?, for key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

- [ ] **Step 4: Create `Sources/ClaudeUsageTracker/Persistence/AppSettings.swift`**

```swift
import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults(suiteName: "com.marccramer.ClaudeUsageTracker") ?? .standard

    var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: "refreshInterval") } }
    var spendEnabled: Bool { didSet { defaults.set(spendEnabled, forKey: "spendEnabled") } }
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }
    var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    var panelOriginX: Double { didSet { defaults.set(panelOriginX, forKey: "panelOriginX") } }
    var panelOriginY: Double { didSet { defaults.set(panelOriginY, forKey: "panelOriginY") } }

    private init() {
        defaults.register(defaults: [
            "refreshInterval": 30.0,
            "alwaysOnTop": true,
            "notificationsEnabled": true,
            "panelOriginX": -1.0,
            "panelOriginY": -1.0,
        ])
        refreshInterval = defaults.double(forKey: "refreshInterval")
        spendEnabled = defaults.bool(forKey: "spendEnabled")
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        panelOriginX = defaults.double(forKey: "panelOriginX")
        panelOriginY = defaults.double(forKey: "panelOriginY")
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter KeychainStoreTests`
Expected: PASS. (If the CI environment has no Keychain, this test may need to run on the host Mac — it passes on a normal macOS session.)

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: keychain credential store and app settings"
```

---

### Task 7: ThresholdTracker + NotificationManager

**Files:**
- Create: `Sources/ClaudeUsageTracker/Store/ThresholdTracker.swift`
- Create: `Sources/ClaudeUsageTracker/Platform/NotificationManager.swift`
- Create: `Tests/ClaudeUsageTrackerTests/ThresholdTrackerTests.swift`

**Interfaces:**
- Produces:
  - `struct ThresholdTracker` with `static let thresholds: [Double] = [0.75, 0.90, 0.95]`; `mutating func crossings(kind: WindowKind, utilization: Double) -> [Double]` returning newly-crossed thresholds (upward only); resets a window's memory when its utilization drops below the lowest crossed level.
  - `enum NotificationManager { static func requestAuthorization(); static func notify(kind: WindowKind, threshold: Double) }`
- Consumes: `WindowKind` (Task 2).

- [ ] **Step 1: Write failing test `Tests/ClaudeUsageTrackerTests/ThresholdTrackerTests.swift`**

```swift
import XCTest
@testable import ClaudeUsageTracker

final class ThresholdTrackerTests: XCTestCase {
    func testFiresOnUpwardCrossingOnce() {
        var t = ThresholdTracker()
        XCTAssertEqual(t.crossings(kind: .fiveHour, utilization: 0.50), [])
        XCTAssertEqual(t.crossings(kind: .fiveHour, utilization: 0.76), [0.75])
        XCTAssertEqual(t.crossings(kind: .fiveHour, utilization: 0.80), []) // no new threshold
        XCTAssertEqual(t.crossings(kind: .fiveHour, utilization: 0.96), [0.90, 0.95])
    }

    func testResetsWhenWindowDrops() {
        var t = ThresholdTracker()
        _ = t.crossings(kind: .fiveHour, utilization: 0.96)
        XCTAssertEqual(t.crossings(kind: .fiveHour, utilization: 0.10), []) // window reset
        XCTAssertEqual(t.crossings(kind: .fiveHour, utilization: 0.76), [0.75]) // fires again
    }

    func testWindowsAreIndependent() {
        var t = ThresholdTracker()
        XCTAssertEqual(t.crossings(kind: .fiveHour, utilization: 0.80), [0.75])
        XCTAssertEqual(t.crossings(kind: .sevenDay, utilization: 0.80), [0.75])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ThresholdTrackerTests`
Expected: FAIL — `ThresholdTracker` not defined.

- [ ] **Step 3: Create `Sources/ClaudeUsageTracker/Store/ThresholdTracker.swift`**

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ThresholdTrackerTests`
Expected: all PASS.

- [ ] **Step 5: Create `Sources/ClaudeUsageTracker/Platform/NotificationManager.swift`**

```swift
import Foundation
import UserNotifications

enum NotificationManager {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(kind: WindowKind, threshold: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Claude \(kind.title) usage"
        content.body = "You've used \(Int(threshold * 100))% of your \(kind.title.lowercased()) limit."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: threshold-crossing tracker and notifications"
```

---

### Task 8: UsageStore orchestrator

**Files:**
- Create: `Sources/ClaudeUsageTracker/Store/UsageStore.swift`
- Create: `Tests/ClaudeUsageTrackerTests/UsageStoreTests.swift`

**Interfaces:**
- Consumes: all clients + protocols (Tasks 3–5), `ThresholdTracker` (Task 7), `UsageSnapshot`, `Source` (Task 2), `AppSettings`, `KeychainStore` (Task 6).
- Produces: `@MainActor @Observable final class UsageStore` with:
  - `init(settings: AppSettings, clientFactory: ClientFactory = LiveClientFactory())`
  - `struct ClientProviders { let status: StatusProviding?; let subscription: SubscriptionProviding?; let spend: SpendProviding? }`
  - `protocol ClientFactory { func makeProviders(settings: AppSettings) -> ClientProviders }`
  - `var snapshot: UsageSnapshot`
  - `func refresh() async`
  - `func start()` / `func stop()` (timer honoring `settings.refreshInterval`, spend throttled to ≥120 s)
  - a closure `var onThresholdCrossed: ((WindowKind, Double) -> Void)?`

- [ ] **Step 1: Write failing test `Tests/ClaudeUsageTrackerTests/UsageStoreTests.swift`**

```swift
import XCTest
@testable import ClaudeUsageTracker

@MainActor
final class UsageStoreTests: XCTestCase {
    struct FakeStatus: StatusProviding {
        let value: ServiceStatus
        func fetchStatus() async throws -> ServiceStatus { value }
    }
    struct FakeSubscription: SubscriptionProviding {
        let five: WindowUsage?
        func fetchUsage() async throws -> (five: WindowUsage?, seven: WindowUsage?, opus: WindowUsage?) {
            (five, nil, nil)
        }
    }
    struct FailingSpend: SpendProviding {
        func fetchMonthlySpendUSD() async throws -> Double { throw HTTPError(status: 500, body: "boom") }
    }
    struct FakeFactory: ClientFactory {
        let providers: UsageStore.ClientProviders
        func makeProviders(settings: AppSettings) -> UsageStore.ClientProviders { providers }
    }

    func testRefreshMergesResultsAndRecordsPerSourceErrors() async {
        let five = WindowUsage(utilization: 0.5, resetsAt: Date().addingTimeInterval(3600), windowLength: 5 * 3600)
        let factory = FakeFactory(providers: .init(
            status: FakeStatus(value: .operational),
            subscription: FakeSubscription(five: five),
            spend: FailingSpend()))
        let settings = AppSettings.shared
        settings.spendEnabled = true
        let store = UsageStore(settings: settings, clientFactory: factory)

        await store.refresh()

        XCTAssertEqual(store.snapshot.status, .operational)
        XCTAssertEqual(store.snapshot.fiveHour, five)
        XCTAssertNil(store.snapshot.monthlySpendUSD)
        XCTAssertNotNil(store.snapshot.sourceErrors[.spend])
        XCTAssertNotNil(store.snapshot.lastUpdated)
    }

    func testThresholdCallbackFires() async {
        let five = WindowUsage(utilization: 0.96, resetsAt: Date().addingTimeInterval(3600), windowLength: 5 * 3600)
        let factory = FakeFactory(providers: .init(
            status: nil, subscription: FakeSubscription(five: five), spend: nil))
        let store = UsageStore(settings: AppSettings.shared, clientFactory: factory)
        var fired: [Double] = []
        store.onThresholdCrossed = { _, t in fired.append(t) }

        await store.refresh()

        XCTAssertEqual(fired.sorted(), [0.75, 0.90, 0.95])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UsageStoreTests`
Expected: FAIL — `UsageStore` not defined.

- [ ] **Step 3: Create `Sources/ClaudeUsageTracker/Store/UsageStore.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    struct ClientProviders {
        let status: StatusProviding?
        let subscription: SubscriptionProviding?
        let spend: SpendProviding?
    }

    protocol_placeholder: Void = () // (removed below)

    private(set) var snapshot: UsageSnapshot = .empty
    var onThresholdCrossed: ((WindowKind, Double) -> Void)?

    private let settings: AppSettings
    private let clientFactory: ClientFactory
    private var tracker = ThresholdTracker()
    private var timer: Timer?
    private var lastSpendFetch: Date?

    init(settings: AppSettings, clientFactory: ClientFactory = LiveClientFactory()) {
        self.settings = settings
        self.clientFactory = clientFactory
    }

    func start() {
        stop()
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Rebuild the timer after the user changes the interval.
    func restartTimer() { if timer != nil { start() } }

    func refresh() async {
        let providers = clientFactory.makeProviders(settings: settings)
        var next = snapshot
        next.sourceErrors = [:]

        if let status = providers.status {
            do { next.status = try await status.fetchStatus() }
            catch { next.sourceErrors[.status] = error.localizedDescription }
        }

        if let subscription = providers.subscription {
            do {
                let u = try await subscription.fetchUsage()
                next.fiveHour = u.five; next.sevenDay = u.seven; next.sevenDayOpus = u.opus
            } catch { next.sourceErrors[.subscription] = error.localizedDescription }
        }

        if settings.spendEnabled, let spend = providers.spend, shouldFetchSpend() {
            do { next.monthlySpendUSD = try await spend.fetchMonthlySpendUSD(); lastSpendFetch = Date() }
            catch { next.sourceErrors[.spend] = error.localizedDescription }
        }
        if !settings.spendEnabled { next.monthlySpendUSD = nil }

        next.lastUpdated = Date()
        snapshot = next

        if settings.notificationsEnabled {
            for kind in WindowKind.allCases {
                guard let usage = next.usage(for: kind) else { continue }
                for threshold in tracker.crossings(kind: kind, utilization: usage.utilization) {
                    onThresholdCrossed?(kind, threshold)
                }
            }
        }
    }

    private func shouldFetchSpend() -> Bool {
        guard let last = lastSpendFetch else { return true }
        return Date().timeIntervalSince(last) >= 120
    }
}

protocol ClientFactory {
    func makeProviders(settings: AppSettings) -> UsageStore.ClientProviders
}

struct LiveClientFactory: ClientFactory {
    func makeProviders(settings: AppSettings) -> UsageStore.ClientProviders {
        let status = StatusClient()
        let subscription = KeychainStore.get(.sessionKey).map { SubscriptionUsageClient(sessionKey: $0) }
        let spend = (settings.spendEnabled ? KeychainStore.get(.adminKey) : nil).map { ConsoleSpendClient(adminKey: $0) }
        return .init(status: status, subscription: subscription, spend: spend)
    }
}
```

- [ ] **Step 4: Remove the placeholder line**

Delete the line `    protocol_placeholder: Void = () // (removed below)` from `UsageStore.swift` (it exists only to flag that the `ClientFactory` protocol is declared at file scope below the class). Final class must not contain it.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter UsageStoreTests`
Expected: all PASS.

- [ ] **Step 6: Run the whole suite**

Run: `swift test`
Expected: all tests across all files PASS.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: usage store orchestrator with per-source error handling"
```

---

### Task 9: PanelView + FloatingPanel

**Files:**
- Create: `Sources/ClaudeUsageTracker/Views/UsageBar.swift`
- Create: `Sources/ClaudeUsageTracker/Views/PanelView.swift`
- Create: `Sources/ClaudeUsageTracker/Platform/FloatingPanel.swift`
- Modify: `Sources/ClaudeUsageTracker/AppDelegate.swift` (host `PanelView` in a `FloatingPanel`)

**Interfaces:**
- Consumes: `UsageStore`, `AppSettings`, `WindowKind`, `TimeProgress`, `ServiceStatus` (earlier tasks).
- Produces:
  - `final class FloatingPanel: NSPanel` with `init(store:settings:onOpenSettings:)`, `func applyAlwaysOnTop(_:)`, and origin persistence.
  - `struct PanelView: View` taking `store` + `settings` + `onOpenSettings` closure.
  - `struct UsageBar: View` (kind + WindowUsage row: title, % bar, time-elapsed line).

- [ ] **Step 1: Create `Sources/ClaudeUsageTracker/Views/UsageBar.swift`**

```swift
import SwiftUI

struct UsageBar: View {
    let kind: WindowKind
    let usage: WindowUsage?
    let hasError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(kind.title).font(.system(size: 12, weight: .semibold))
                if hasError { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).font(.system(size: 10)) }
                Spacer()
                Text(usage.map { "\(Int($0.utilization * 100))%" } ?? "—")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 6)
                    Capsule().fill(barColor).frame(width: geo.size.width * (usage?.utilization ?? 0), height: 6)
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
```

- [ ] **Step 2: Create `Sources/ClaudeUsageTracker/Views/PanelView.swift`**

```swift
import SwiftUI

struct PanelView: View {
    @Bindable var store: UsageStore
    @Bindable var settings: AppSettings
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude Usage").font(.system(size: 13, weight: .bold))
                Spacer()
                Toggle("", isOn: $settings.alwaysOnTop).toggleStyle(.switch).labelsHidden().scaleEffect(0.7)
                    .help("Always on top")
            }
            UsageBar(kind: .fiveHour, usage: store.snapshot.fiveHour, hasError: store.snapshot.sourceErrors[.subscription] != nil)
            UsageBar(kind: .sevenDay, usage: store.snapshot.sevenDay, hasError: store.snapshot.sourceErrors[.subscription] != nil)
            if let opus = store.snapshot.sevenDayOpus {
                UsageBar(kind: .sevenDayOpus, usage: opus, hasError: false)
            }
            if settings.spendEnabled {
                HStack {
                    Text("API spend").font(.system(size: 12, weight: .semibold))
                    if store.snapshot.sourceErrors[.spend] != nil {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).font(.system(size: 10))
                    }
                    Spacer()
                    Text(store.snapshot.monthlySpendUSD.map { String(format: "$%.2f this month", $0) } ?? "—")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(store.snapshot.status.label).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if let updated = store.snapshot.lastUpdated {
                    Text(updated, style: .time).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh now")
                Button { onOpenSettings() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help("Settings")
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusColor: Color {
        switch store.snapshot.status.color {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        case .gray: return .gray
        }
    }
}
```

- [ ] **Step 3: Create `Sources/ClaudeUsageTracker/Platform/FloatingPanel.swift`**

```swift
import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    private let settings: AppSettings

    init(store: UsageStore, settings: AppSettings, onOpenSettings: @escaping () -> Void) {
        self.settings = settings
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 240),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = PanelView(store: store, settings: settings, onOpenSettings: onOpenSettings)
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting

        applyAlwaysOnTop(settings.alwaysOnTop)
        restoreOrigin()
    }

    func applyAlwaysOnTop(_ on: Bool) {
        level = on ? .floating : .normal
    }

    private func restoreOrigin() {
        if settings.panelOriginX >= 0, settings.panelOriginY >= 0 {
            setFrameOrigin(NSPoint(x: settings.panelOriginX, y: settings.panelOriginY))
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.maxX - 300, y: f.maxY - 280))
        }
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        settings.panelOriginX = point.x
        settings.panelOriginY = point.y
    }

    override var canBecomeKey: Bool { true }
}
```

- [ ] **Step 4: Replace `AppDelegate.swift` to host the panel**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings.shared
    private(set) var store: UsageStore!
    private var panel: FloatingPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.requestAuthorization()
        store = UsageStore(settings: settings)
        store.onThresholdCrossed = { kind, threshold in
            NotificationManager.notify(kind: kind, threshold: threshold)
        }

        panel = FloatingPanel(store: store, settings: settings, onOpenSettings: { [weak self] in
            self?.openSettings()
        })
        panel.orderFront(nil)

        store.start()
        observeAlwaysOnTop()
    }

    private var alwaysOnTopObservation: NSKeyValueObservation?
    private func observeAlwaysOnTop() {
        // Re-apply window level whenever the setting changes.
        withObservationTracking {
            _ = settings.alwaysOnTop
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.panel.applyAlwaysOnTop(self.settings.alwaysOnTop)
                self.observeAlwaysOnTop()
            }
        }
    }

    func openSettings() {
        // Implemented in Task 10.
    }
}
```

- [ ] **Step 5: Build and run**

Run: `./scripts/build_app.sh && open build/ClaudeUsageTracker.app`
Expected: a translucent rounded floating panel appears top-right, always on top, showing "Session"/"Weekly" rows reading "Not connected" and status "Unknown" (no credentials yet). Drag it — it moves. `swift build` also succeeds.

- [ ] **Step 6: Verify build compiles cleanly**

Run: `swift build 2>&1 | tail -5`
Expected: `Compiling`/`Build complete` with no errors.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: floating panel UI hosting usage rows and status footer"
```

---

### Task 10: SettingsView + SignInWebView

**Files:**
- Create: `Sources/ClaudeUsageTracker/Platform/SignInWebView.swift`
- Create: `Sources/ClaudeUsageTracker/Views/SettingsView.swift`
- Modify: `Sources/ClaudeUsageTracker/AppDelegate.swift` (`openSettings()` shows a settings window)

**Interfaces:**
- Consumes: `AppSettings`, `KeychainStore`, `UsageStore`.
- Produces:
  - `struct SignInWebView: NSViewRepresentable` that loads `https://claude.ai/login` and calls `onSessionKey(String)` when the `sessionKey` cookie appears.
  - `struct SettingsView: View` with sidebar (Credentials / API Console / General / Appearance) and detail panes; calls `store.restartTimer()` / `store.refresh()` and `LoginItemManager` / `MenuBarController` toggles via closures passed in.
  - `final class SettingsWindowController: NSWindowController` (created in AppDelegate).

- [ ] **Step 1: Create `Sources/ClaudeUsageTracker/Platform/SignInWebView.swift`**

```swift
import SwiftUI
import WebKit

struct SignInWebView: NSViewRepresentable {
    var onSessionKey: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        context.coordinator.startPolling(webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSessionKey: onSessionKey) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onSessionKey: (String) -> Void
        private var timer: Timer?
        private var delivered = false

        init(onSessionKey: @escaping (String) -> Void) { self.onSessionKey = onSessionKey }

        func startPolling(_ webView: WKWebView) {
            timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView, !self.delivered else { return }
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    if let cookie = cookies.first(where: { $0.name == "sessionKey" }), !cookie.value.isEmpty {
                        self.delivered = true
                        self.timer?.invalidate()
                        self.onSessionKey(cookie.value)
                    }
                }
            }
        }

        deinit { timer?.invalidate() }
    }
}
```

- [ ] **Step 2: Create `Sources/ClaudeUsageTracker/Views/SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var store: UsageStore
    var onLaunchAtLoginChanged: (Bool) -> Void
    var onMenuBarChanged: (Bool) -> Void

    enum Section: String, CaseIterable, Identifiable {
        case claude = "Claude.ai", api = "API Console", general = "General", appearance = "Appearance"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .claude: return "key.fill"
            case .api: return "dollarsign.circle"
            case .general: return "gearshape"
            case .appearance: return "paintbrush"
            }
        }
    }

    @State private var selection: Section = .claude
    @State private var showSignIn = false
    @State private var manualKey = ""
    @State private var manualAdminKey = ""

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .frame(minWidth: 180)
        } detail: {
            ScrollView { detail.padding(24).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .frame(width: 640, height: 420)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .claude: claudePane
        case .api: apiPane
        case .general: generalPane
        case .appearance: appearancePane
        }
    }

    private var connected: Bool { KeychainStore.get(.sessionKey) != nil }

    private var claudePane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personal Usage").font(.title2.bold())
            Text("Track your Claude.ai usage and sessions").foregroundStyle(.secondary)
            HStack {
                Circle().fill(connected ? .green : .gray).frame(width: 8, height: 8)
                Text(connected ? "Connected" : "Not connected")
                Spacer()
                if connected {
                    Button("Remove", role: .destructive) {
                        KeychainStore.set(nil, for: .sessionKey); Task { await store.refresh() }
                    }
                }
            }
            Button {
                showSignIn = true
            } label: { Label("Sign in to Claude.ai", systemImage: "globe") }
                .buttonStyle(.borderedProminent)
            Divider()
            Text("Advanced: paste session key").font(.caption).foregroundStyle(.secondary)
            HStack {
                SecureField("sessionKey value", text: $manualKey)
                Button("Save") {
                    guard !manualKey.isEmpty else { return }
                    KeychainStore.set(manualKey, for: .sessionKey); manualKey = ""; Task { await store.refresh() }
                }
            }
        }
        .sheet(isPresented: $showSignIn) {
            VStack {
                HStack { Text("Sign in to Claude.ai").font(.headline); Spacer(); Button("Cancel") { showSignIn = false } }.padding()
                SignInWebView { key in
                    KeychainStore.set(key, for: .sessionKey)
                    showSignIn = false
                    Task { await store.refresh() }
                }
            }.frame(width: 520, height: 600)
        }
    }

    private var apiPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API Console Spend").font(.title2.bold())
            Toggle("Track API spend", isOn: $settings.spendEnabled)
            if settings.spendEnabled {
                Text("Admin API key (sk-ant-admin…)").font(.caption).foregroundStyle(.secondary)
                HStack {
                    SecureField("sk-ant-admin…", text: $manualAdminKey)
                    Button("Save") {
                        guard !manualAdminKey.isEmpty else { return }
                        KeychainStore.set(manualAdminKey, for: .adminKey); manualAdminKey = ""; Task { await store.refresh() }
                    }
                }
                if KeychainStore.get(.adminKey) != nil {
                    Label("Key saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General").font(.title2.bold())
            VStack(alignment: .leading) {
                Text("Refresh interval: \(Int(settings.refreshInterval))s")
                Slider(value: $settings.refreshInterval, in: 10...300, step: 5) { editing in
                    if !editing { store.restartTimer() }
                }
                HStack { Text("10s").font(.caption2); Spacer(); Text("300s").font(.caption2) }.foregroundStyle(.secondary)
            }
            Toggle("Threshold notifications (75 / 90 / 95%)", isOn: $settings.notificationsEnabled)
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                .onChange(of: settings.launchAtLogin) { _, newValue in onLaunchAtLoginChanged(newValue) }
        }
    }

    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Appearance").font(.title2.bold())
            Toggle("Always on top", isOn: $settings.alwaysOnTop)
            Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                .onChange(of: settings.showMenuBarIcon) { _, newValue in onMenuBarChanged(newValue) }
        }
    }
}
```

- [ ] **Step 3: Wire `openSettings()` in `AppDelegate.swift`**

Add a stored property and replace the `openSettings()` stub:

```swift
    private var settingsWindow: NSWindow?

    func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(
            settings: settings,
            store: store,
            onLaunchAtLoginChanged: { LoginItemManager.setEnabled($0) },
            onMenuBarChanged: { [weak self] on in self?.menuBar.setVisible(on, store: self!.store, onOpenSettings: { self?.openSettings() }) }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
```

Add `import SwiftUI` at the top of `AppDelegate.swift`. (`menuBar` and `LoginItemManager` are added in Task 11; this task's build step temporarily stubs them — see Step 4.)

- [ ] **Step 4: Add temporary stubs so this task builds independently**

At the bottom of `AppDelegate.swift`, add temporary stubs to be replaced in Task 11:

```swift
// TEMP stubs replaced in Task 11
enum LoginItemManager { static func setEnabled(_ enabled: Bool) {} }
extension AppDelegate {
    var menuBar: MenuBarStub { MenuBarStub() }
}
struct MenuBarStub { func setVisible(_ on: Bool, store: UsageStore, onOpenSettings: @escaping () -> Void) {} }
```

- [ ] **Step 5: Build and run**

Run: `./scripts/build_app.sh && open build/ClaudeUsageTracker.app`
Expected: click the gear in the panel → Settings window opens with the four-section sidebar. The "Sign in to Claude.ai" button opens a sheet with the Claude login page. After a real login, the panel populates with usage within a couple seconds. General → refresh slider moves 10–300s.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: settings window with web sign-in, spend opt-in, refresh slider"
```

---

### Task 11: MenuBarController + LoginItemManager + final wiring

**Files:**
- Create: `Sources/ClaudeUsageTracker/Platform/MenuBarController.swift`
- Create: `Sources/ClaudeUsageTracker/Platform/LoginItemManager.swift`
- Modify: `Sources/ClaudeUsageTracker/AppDelegate.swift` (remove Task 10 stubs; wire real menu bar + login item + observe menu bar/interval)

**Interfaces:**
- Consumes: `UsageStore`, `AppSettings`, `UsageSnapshot`.
- Produces:
  - `enum LoginItemManager { static func setEnabled(_ enabled: Bool) }` using `SMAppService.mainApp`.
  - `final class MenuBarController` with `func setVisible(_ on: Bool, store: UsageStore, onOpenSettings: @escaping () -> Void)` and `func update(with snapshot: UsageSnapshot)`.

- [ ] **Step 1: Create `Sources/ClaudeUsageTracker/Platform/LoginItemManager.swift`**

```swift
import Foundation
import ServiceManagement

enum LoginItemManager {
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            FileHandle.standardError.write(Data("[loginItem] \(error.localizedDescription)\n".utf8))
        }
    }
}
```

- [ ] **Step 2: Create `Sources/ClaudeUsageTracker/Platform/MenuBarController.swift`**

```swift
import AppKit

final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var onOpenSettings: (() -> Void)?

    func setVisible(_ on: Bool, store: UsageStore, onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        if on {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = "◔ —"
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            menu.items.first?.target = self
            item.menu = menu
            statusItem = item
            update(with: store.snapshot)
        } else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
        }
    }

    func update(with snapshot: UsageSnapshot) {
        guard let button = statusItem?.button else { return }
        if let five = snapshot.fiveHour {
            button.title = "◔ \(Int(five.utilization * 100))%"
        } else {
            button.title = "◔ —"
        }
    }

    @objc private func openSettings() { onOpenSettings?() }
}
```

- [ ] **Step 3: Finalize `AppDelegate.swift`**

Remove the TEMP stubs block added in Task 10, add a real `menuBar` property, apply the login item on launch, and observe both the menu-bar setting and snapshot updates. The full file:

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings.shared
    private(set) var store: UsageStore!
    private var panel: FloatingPanel!
    let menuBar = MenuBarController()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.requestAuthorization()
        store = UsageStore(settings: settings)
        store.onThresholdCrossed = { kind, threshold in
            NotificationManager.notify(kind: kind, threshold: threshold)
        }

        panel = FloatingPanel(store: store, settings: settings, onOpenSettings: { [weak self] in
            self?.openSettings()
        })
        panel.orderFront(nil)

        if settings.showMenuBarIcon {
            menuBar.setVisible(true, store: store, onOpenSettings: { [weak self] in self?.openSettings() })
        }
        LoginItemManager.setEnabled(settings.launchAtLogin)

        store.start()
        observeAlwaysOnTop()
        observeSnapshot()
    }

    private func observeAlwaysOnTop() {
        withObservationTracking { _ = settings.alwaysOnTop } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.panel.applyAlwaysOnTop(self.settings.alwaysOnTop)
                self.observeAlwaysOnTop()
            }
        }
    }

    private func observeSnapshot() {
        withObservationTracking { _ = store.snapshot.fiveHour } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.menuBar.update(with: self.store.snapshot)
                self.observeSnapshot()
            }
        }
    }

    func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(
            settings: settings,
            store: store,
            onLaunchAtLoginChanged: { LoginItemManager.setEnabled($0) },
            onMenuBarChanged: { [weak self] on in
                guard let self else { return }
                self.menuBar.setVisible(on, store: self.store, onOpenSettings: { self.openSettings() })
            })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
```

- [ ] **Step 4: Build the whole app**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete` with no errors.

- [ ] **Step 5: Run the full app and verify all features**

Run: `./scripts/build_app.sh && open build/ClaudeUsageTracker.app`
Expected checklist (manual):
- Floating panel appears, always-on-top by default; toggling "Always on top" in Appearance drops/raises it above other apps.
- Settings → Appearance → "Show menu bar icon" on → a `◔ —`/`◔ NN%` item appears in the menu bar; off → it disappears.
- Settings → General → refresh slider changes cadence; API spend toggle reveals the admin-key field and the panel's spend row.
- Sign in to Claude.ai populates the usage bars.
- Quit via the menu bar item.

- [ ] **Step 6: Run the full test suite**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: menu bar item, launch-at-login, final app wiring"
```

---

## Self-Review Notes

- **Spec coverage:** compact always-on-top panel (Task 9), 5h + weekly quota bars + time-elapsed lines (Tasks 2, 9), availability footer (Tasks 3, 9), opt-in API spend (Tasks 5, 10), sessionKey via embedded web sign-in + manual paste (Task 10), refresh slider 10–300s default 30 (Tasks 6, 10), threshold notifications (Tasks 7, 8, 11), launch at login (Task 11), menu bar on/off (Task 11), Keychain storage (Task 6), per-source error handling (Task 8), accessory app / no Dock icon (Task 1). All covered.
- **Unofficial endpoints** (subscription usage, cost report) are isolated in single parsers with fixtures and a `CUT_DEBUG=1` raw-body dump so real-response mismatches are one-file fixes.
- **Known MVP caveats to verify at runtime:** UserNotifications and `SMAppService` behave best when the app is signed and located stably; ad-hoc signing from `build/` is fine for local use but launch-at-login may need the app moved to `/Applications`. The claude.ai usage JSON shape is assumed — confirm against a live `CUT_DEBUG=1` capture during Task 4/10 runtime verification and adjust `parseUsage` if needed.
```
