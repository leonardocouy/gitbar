# Architecture

## App Lifecycle

`GitBarApp` (@main) → `@NSApplicationDelegateAdaptor` → `AppDelegate` owns everything:
- `NSStatusItem` + `NSMenu` (menu bar)
- `GitBarAppModel` (@Observable, central state)
- Refresh timer, notification observers, window controllers

## State Flow

```
GitBarAppModel (@Observable)
├── GitBarSettingsStore (UserDefaults, @Observable)
├── GitHubClient (stateless, async)
├── GitBarKeychain (Security framework)
├── GitHubTokenValidator (@Observable)
└── GitBarNotifier (UNUserNotificationCenter)
```

Changes propagate via `NotificationCenter`:
- `.gitBarConfigurationDidChange` → settings changed → re-fetch + rebuild menu
- `.gitBarAuthenticationDidChange` → token changed → validate + re-fetch + rebuild menu

## UI Split

| Layer | Framework | What |
|-------|-----------|------|
| Menu bar | AppKit | `NSStatusItem`, `NSMenu`, `NSMenuItem` (incl. attributed titles, submenus) |
| Preferences | SwiftUI | `Form` with `.formStyle(.grouped)`, hosted in `NSWindow` via `NSHostingView` |
| About | SwiftUI | Same hosting pattern |
| Review panel | AppKit | `NSPanel` for text input (request changes / comment) |

## File Responsibilities

| File | Owns |
|------|------|
| `AppDelegate.swift` | `GitBarAppModel` + menu bar lifecycle + menu rendering + window creation + review action handlers |
| `GitHubClient.swift` | All HTTP: REST auth, GraphQL queries, GraphQL mutations |
| `GitHubDtos.swift` | All API types, domain models (`PullRequestSummary`), mappers (`GraphQLBuildMapper`) |
| `DefaultsExtensions.swift` | `GitBarSettingsStore`, setting enums (`BuildInfoMode`, `CounterMode`, `PullRequestSectionKind`) |
| `Keychain.swift` | Keychain CRUD wrapper |
| `Notifications.swift` | `GitBarNotifier` (system notifications) |

## Adding a New Setting

1. Add a `Key` case in `GitBarSettingsStore.Key`
2. Add a stored property with `didSet { persistX(...) }`
3. Initialize from `UserDefaults` in `init()`
4. Add UI control in `PreferencesView.swift` using `setting(\.propertyName)` binding
5. If it affects data fetching, the existing `postConfigurationChange()` in `didSet` handles the refresh cycle automatically
