# Claude Usage Tracker (floating panel)

A native macOS accessory app that shows your Claude subscription usage (5-hour + weekly),
live availability, and optional API console spend in a compact, draggable, always-on-top
floating panel. Optional menu bar item included.

## Build & run

```bash
# Run tests
swift test

# Build the .app bundle and launch it
./scripts/run.sh            # debug build + open
./scripts/build_app.sh      # release build only -> build/ClaudeUsageTracker.app

# Package a drag-to-Applications installer
./scripts/make_dmg.sh       # -> build/ClaudeUsageTracker.dmg
```

## Distribution

`make_dmg.sh` produces `build/ClaudeUsageTracker.dmg` with the standard drag-to-Applications
layout. It's signed with the local self-signed identity, so it installs cleanly on **this** Mac.
To share it with **other** people's Macs without Gatekeeper warnings, the app must be signed with
an Apple **Developer ID** certificate and **notarized** (`xcrun notarytool`). Without that, other
users would need to right-click → Open the first time (or run
`xattr -dr com.apple.quarantine /Applications/ClaudeUsageTracker.app`).

Open in Xcode with **File ▸ Open** on `Package.swift` if you prefer the IDE.

Requires macOS 14+, Xcode 26 / Swift 6.3. The app runs as an accessory (no Dock icon):
look for the floating panel in the top-right of your screen.

## Using it

- **Session / Weekly bars** — each shows the % of quota used plus a `⧗ … elapsed · resets …`
  line showing how far through the time window you are.
- **Connect Claude.ai** — gear ▸ *Claude.ai* ▸ **Sign in to Claude.ai** opens an embedded
  login. After you sign in, the `sessionKey` cookie is captured into the Keychain and the bars
  populate. (Advanced: paste the `sessionKey` cookie manually.)
- **API spend** — off by default. gear ▸ *API Console* ▸ toggle on, then paste an Anthropic
  Admin API key (`sk-ant-admin…`). The spend row then appears in the panel.
- **Availability** — the footer dot/label comes from status.claude.com (no setup).
- **General** — refresh-interval slider (10–300s, default 30s), threshold notifications
  (75/90/95%), launch at login.
- **Appearance** — always-on-top toggle, show/hide the menu bar icon.

Credentials are stored in the macOS Keychain; settings in UserDefaults. Set `CUT_DEBUG=1`
in the environment to dump raw API responses to stderr.

## Known MVP caveats

- **Unofficial endpoints.** The claude.ai usage JSON and the Anthropic cost-report shape are
  version-sensitive. Each parser is isolated (`SubscriptionUsageClient.parseUsage`,
  `ConsoleSpendClient.parseSpend`). If the live data doesn't populate, run with `CUT_DEBUG=1`,
  capture the real response, and adjust only that parser. The assumed usage shape is
  `{ five_hour|seven_day|seven_day_opus: { utilization: <0–100>, resets_at: <ISO8601> } }`.
- **Launch at login / notifications** behave best when the app is signed and in a stable
  location. The build is ad-hoc signed from `build/`; for reliable launch-at-login, move
  `ClaudeUsageTracker.app` to `/Applications`.

## Layout

- `Sources/ClaudeUsageTracker/Models` — data models + time-progress math
- `Sources/ClaudeUsageTracker/Networking` — the three API clients (isolated parsers)
- `Sources/ClaudeUsageTracker/Store` — `UsageStore` orchestrator + threshold tracker
- `Sources/ClaudeUsageTracker/Persistence` — Keychain + settings
- `Sources/ClaudeUsageTracker/Platform` — panel, menu bar, notifications, login item, web sign-in
- `Sources/ClaudeUsageTracker/Views` — SwiftUI panel + settings
- `Tests/` — unit tests over parsers, time math, threshold logic, and the store
- `docs/superpowers/` — design spec and implementation plan
```
