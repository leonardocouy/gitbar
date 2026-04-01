# GitBar

Native macOS 26 Tahoe menu bar app for monitoring GitHub pull requests.

## Stack

- Swift 6.2, SwiftUI + AppKit hybrid, Observation framework
- Xcode project (no SPM/external dependencies)
- macOS Keychain for token storage, ServiceManagement for launch-at-login

## Build & Run

```bash
open GitBar.xcodeproj   # then Cmd+R in Xcode
```

No package manager, no CLI build — Xcode only (requires full Xcode, not just CLT).

## Key Constraints

- App is sandboxed — network client entitlement only, no arbitrary file access
- Menu bar app (`NSStatusItem`) — no Dock icon, no main window
- GitHub API via GraphQL for PR data + mutations, REST only for `/user` auth validation

## Guidelines

- [Architecture](.agents/architecture.md)
- [Swift Conventions](.agents/swift-conventions.md)
- [GitHub API](.agents/github-api.md)
