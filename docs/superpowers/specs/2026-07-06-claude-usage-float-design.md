# Claude Usage Floating Tracker — Design Spec

Date: 2026-07-06
Status: Approved for MVP

## 1. Summary

A native macOS utility that shows **Claude subscription usage**, **live availability**, and
(optionally) **API console spend** in a compact, draggable, always-on-top **floating panel**.
Inspired by the menu-bar app `hamed-elfayome/Claude-Usage-Tracker`, but the primary surface is a
floating window rather than a menu bar popover. An optional menu bar item is also supported.

The app runs as an **accessory app** (no Dock icon): just the floating panel plus an optional
menu bar item.

## 2. Platform & Stack

- **Language:** Swift
- **UI:** SwiftUI for content, with an AppKit `NSPanel` host for the floating window (SwiftUI alone
  cannot cleanly produce a borderless, always-on-top, non-activating floating panel).
- **Menu bar:** AppKit `NSStatusItem`, managed at runtime so it can be toggled on/off.
- **Target OS:** macOS 14 (Sonoma) or later.
- **Build:** Delivered as a buildable Xcode/SwiftPM project that produces a `.app` bundle; runnable
  from the command line for verification and openable in Xcode.
- **Activation policy:** `.accessory` (`LSUIElement`), so there is no Dock icon.

## 3. The Floating Panel

Compact (~280pt wide), draggable, rounded, translucent. Content is three stacked rows plus a footer.

For each usage window the panel shows **two distinct things**:
1. **Quota bar** — percentage of the quota consumed.
2. **Time line** — how far through the time window you currently are.

Rows:

- **Session (5-hour)**
  - Quota bar: `% used`.
  - Time line: `⧗ 3h 12m elapsed · resets 4:45 PM`.
- **Weekly (7-day)**
  - Quota bar: `% used`.
  - Time line: `⧗ 3d 6h elapsed · resets Tue`.
  - Optional smaller Opus-weekly figure when present in the API response.
- **API spend** (only visible when the user has enabled it — see §5.2)
  - `$42.18 this month`.

Footer:
- Status dot + label: 🟢 Operational / 🟡 Degraded / 🔴 Outage (from status.claude.com).
- Last-updated timestamp.
- Refresh button (manual).
- Gear button → opens Settings window.

Behaviour:
- **Always-on-top toggle**: when on, panel window level floats above other apps; when off, normal level.
- Panel position is remembered across launches.

## 4. Data Sources

Three independent clients. Each fails independently: a failing source shows a small ⚠ on its row
with a tooltip and keeps the last-known value; other rows keep working.

| Source | Endpoint | Auth | Cadence |
|---|---|---|---|
| Subscription limits | `claude.ai/api/organizations/{org}/usage` (org id bootstrapped from `claude.ai/api/organizations`) | `sessionKey` cookie | driven by refresh slider |
| Availability | `status.claude.com/api/v2/status.json` | none | driven by refresh slider |
| API spend (opt-in) | Anthropic Admin cost-report endpoint | Admin API key (`sk-ant-admin…`) | throttled: at most ~ every 2 min |

Notes:
- The claude.ai usage endpoint is **unofficial**. Its parsing is isolated in one place so a future
  response-shape change is a one-file fix.
- **Refresh cadence** is user-controlled by a slider, range **10s–300s, default 30s**. The slider
  drives the usage + status refresh loop. API spend is fetched on the same loop but throttled so it
  never hits the billing endpoint more often than ~ every 2 minutes (billing changes slowly).

### Connecting the session key

- **Primary: "Sign in to Claude.ai"** — opens an embedded `WKWebView` login window. After the user
  signs in normally, the app reads the `sessionKey` cookie from the web view's `WKHTTPCookieStore`
  and stores it in the Keychain. No dev-tools copying required.
- **Advanced fallback: paste session key manually** — a text field for users who prefer to paste
  the cookie value directly.

## 5. Settings

Settings window styled after the reference app: a left sidebar with **Credentials** and **Settings**
groups, connection status dots, and a detail pane on the right.

### 5.1 Credentials
- **Claude.ai** — connect via embedded sign-in or manual paste; shows connected/disconnected dot;
  Remove button. This powers the subscription bars (the no-setup-required core once connected).

### 5.2 API Console (opt-in)
- A toggle to **enable API spend tracking**. When enabled, prompts for the Admin API key
  (`sk-ant-admin…`), stored in the Keychain, and reveals the spend row in the panel. When disabled,
  no key is required and the spend row is hidden.

### 5.3 General
- **Refresh interval slider** (10s–300s, default 30s).
- **Threshold notifications** on/off.
- **Launch at login** on/off.

### 5.4 Appearance
- **Always-on-top** on/off.
- **Show menu bar icon** on/off — when on, an `NSStatusItem` displays a compact usage number
  (e.g. session %); toggling rebuilds the status item live.

## 6. Features

- **Always-on-top toggle** (Appearance).
- **Menu bar icon on/off** — runtime add/remove of `NSStatusItem` showing session %.
- **Threshold notifications** — macOS notifications at **75 / 90 / 95%** for session and weekly.
  Fire only on **upward** crossings; per-window last-notified level resets when the window resets
  (utilization drops). Uses `UNUserNotificationCenter`.
- **Launch at login** — via `SMAppService.mainApp`.
- **User-configurable refresh** — slider (§5.3).

## 7. Architecture (small, testable units)

Persistence:
- `KeychainStore` — save/load/delete credentials (session key, admin key).
- `AppSettings` — `@Observable`, UserDefaults-backed (refresh interval, toggles, thresholds,
  spend-enabled, panel position, last-notified levels).

Networking (each behind a protocol → fakeable in tests; each parses one API into a model):
- `SubscriptionUsageClient` — bootstraps org id, fetches usage, returns windows.
- `StatusClient` — fetches status.claude.com indicator.
- `ConsoleSpendClient` — fetches monthly cost.

Orchestration:
- `UsageStore` — `@Observable`. Owns the refresh timer(s), calls the clients, merges results into a
  single `UsageSnapshot`, applies spend throttling, and triggers notifications on threshold crossings.

Platform glue:
- `NotificationManager` — threshold crossing → user notification.
- `LoginItemManager` — `SMAppService` register/unregister.
- `MenuBarController` — creates/destroys the `NSStatusItem` based on the setting.
- `FloatingPanel` — `NSPanel` subclass (borderless, floating/non-activating) hosting SwiftUI via
  `NSHostingView`; manages window level from the always-on-top setting and remembers position.
- `SignInWebView` — `WKWebView` wrapper that performs Claude.ai login and extracts `sessionKey`.

Views:
- `PanelView` — the compact panel (rows + footer).
- `SettingsView` — sidebar + detail panes (Credentials / API Console / General / Appearance).
- `MenuBarLabel` — compact status-item content.

## 8. Data Model

```
UsageSnapshot {
  fiveHour:     WindowUsage?     // may be nil if session key not connected / failed
  sevenDay:     WindowUsage?
  sevenDayOpus: WindowUsage?
  monthlySpendUSD: Double?       // nil unless spend enabled + fetched
  status:       ServiceStatus    // operational | degraded | outage | unknown + text
  lastUpdated:  Date
  sourceErrors: [Source: String] // per-source last error for the ⚠ indicators
}

WindowUsage {
  utilization: Double            // 0.0 ... 1.0 (quota used)
  resetsAt:    Date
  windowLength: TimeInterval     // 5h or 7d; window start = resetsAt - windowLength
}
```

Time-progress math (pure, unit-tested): `start = resetsAt - windowLength`;
`elapsedFraction = clamp((now - start) / windowLength, 0, 1)`.

## 9. Error Handling

- Independent per source; last-known values retained with a ⚠ + tooltip on the affected row.
- **Expired / invalid session key** → panel prompts to reconnect; Settings shows Claude.ai as
  disconnected.
- **Network errors** → keep last snapshot, footer timestamp reveals staleness.
- **Spend disabled** → spend client not called at all.

## 10. Testing

Unit tests over pure logic with fixture JSON:
- Response parsing for each client (`SubscriptionUsageClient`, `StatusClient`, `ConsoleSpendClient`).
- Time-progress math.
- Threshold-crossing logic (upward-only, reset on window reset).

`UsageStore` tested with fake clients (protocol-backed). Panel/menu-bar/WKWebView UI stays thin and
is verified by running the app.

## 11. Out of Scope for v1 (YAGNI)

- CLI Account credential source (shown in the reference app) — subscription + optional spend only.
- Multi-profile support.
- Historical charts / per-key breakdown / spend history.
- Localization (English only in v1).
- Full resizable dashboard window (compact panel only).
```
