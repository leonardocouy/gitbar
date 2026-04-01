# GitBar

A native macOS menu bar app that monitors GitHub pull requests. See assigned, created, and review-requested PRs directly from the menu bar without switching to the browser.

## Key Features

- Monitor assigned, created, and review-requested pull requests
- Inline build/check status indicators (check suites or commit status rollup)
- Quick-approve, request changes, or comment on PRs from the menu
- Configurable refresh interval and menu bar counter
- GitHub Enterprise support via custom API base URL
- Additional search query filtering (e.g., `org:your-org`, `label:critical`)
- Secure token storage in macOS Keychain
- Launch at login

## Tech Stack

- **Language**: Swift 6.2
- **UI**: SwiftUI (Preferences, About) + AppKit (NSStatusItem, NSMenu)
- **Minimum OS**: macOS 26 Tahoe
- **Networking**: URLSession with async/await
- **GitHub API**: REST (`/user` for auth) + GraphQL (PR search, review mutations)
- **Storage**: UserDefaults (settings), macOS Keychain (token)
- **State**: Swift Observation framework (`@Observable`)
- **Launch at Login**: ServiceManagement (`SMAppService`)

## Prerequisites

- macOS 26 Tahoe or later
- Xcode (full installation, not just Command Line Tools)
- A GitHub personal access token with `repo` scope

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/leonardocouy/gitbar.git
cd gitbar
```

### 2. Open in Xcode

```bash
open GitBar.xcodeproj
```

There are no external dependencies. The project uses only Apple frameworks.

### 3. Build and Run

Select the `GitBar` scheme and press `Cmd+R`. The app launches as a menu bar utility (no Dock icon).

### 4. Configure Authentication

1. Click the GitBar icon in the menu bar
2. Open **Preferences...**
3. Paste your GitHub personal access token
4. Click **Validate** to confirm it works

Generate a token at [github.com/settings/tokens](https://github.com/settings/tokens) with `repo` read access.

## Architecture

### Directory Structure

```
GitBar/
├── GitBarApp.swift                  # @main entry point, bridges to AppDelegate
├── AppDelegate.swift                # NSStatusItem, NSMenu, refresh loop, windows
├── Keychain.swift                   # macOS Keychain wrapper (Security framework)
├── Notifications.swift              # UNUserNotificationCenter wrapper
├── GitHub/
│   ├── GitHubClient.swift           # REST + GraphQL networking
│   ├── GitHubDtos.swift             # API response types, domain models, mappers
│   └── GithubTokenValidator.swift   # Observable token validation state
├── Views/
│   ├── PreferencesView.swift        # SwiftUI preferences window
│   ├── AboutView.swift              # SwiftUI about window
│   ├── AppView.swift                # StatusLegendItemView component
│   ├── AppPromotionView.swift       # StatusLegendView component
│   └── BottomItemView.swift         # (empty, reserved)
├── Extensions/
│   ├── DefaultsExtensions.swift     # Settings store, enums, notification names
│   ├── StringExtensions.swift       # String truncation and trimming
│   ├── DateExtensions.swift         # Relative date formatting
│   ├── NSImageExtensions.swift      # Async loading, tinting, resizing
│   └── NSMutableAttributedStringExtensions.swift  # Menu item text builder
└── Assets.xcassets/                 # App icon, status icons, color assets
```

### How It Works

1. `GitBarApp` uses `@NSApplicationDelegateAdaptor` to hand control to `AppDelegate`
2. `AppDelegate` sets the activation policy to `.accessory` (menu bar only, no Dock icon)
3. It creates an `NSStatusItem` with the pull request icon and wires up an `NSMenu`
4. `GitBarAppModel` (an `@Observable` class) holds all app state:
   - Viewer identity (login, name)
   - PR sections (assigned, created, review-requested)
   - Refresh state and token validation state
5. On launch, the model validates the stored token and fetches PRs
6. A repeating `Timer` triggers background refreshes at the configured interval
7. `NotificationCenter` observers react to settings and auth changes, triggering re-fetch and menu rebuild

### Data Flow

```
Menu Bar Click
  → NSMenu displays cached PR sections from GitBarAppModel
  → Click PR item → opens GitHub URL in browser
  → Click Approve/Comment → GraphQL mutation → re-fetch → rebuild menu

Settings Change (Preferences window)
  → GitBarSettingsStore persists to UserDefaults
  → Posts .gitBarConfigurationDidChange notification
  → AppDelegate reschedules timer + refreshes data + rebuilds menu

Token Change
  → GitBarAppModel writes to Keychain
  → Posts .gitBarAuthenticationDidChange notification
  → AppDelegate validates token + refreshes + rebuilds menu
```

### GitHub API Integration

**Authentication**: REST `GET /user` validates the token and discovers the viewer's login.

**Pull Request Search**: GraphQL `search` query with type `ISSUE` fetches open PRs using qualifiers like `assignee:`, `author:`, and `review-requested:`. Up to 30 results per section.

**Build Status**: Two modes available:
- **Check Suites** - fetches `checkSuites` → `checkRuns` from the last commit
- **Commit Status** - fetches `statusCheckRollup` → `contexts` from the last commit

**Review Actions**: GraphQL `addPullRequestReview` mutation for approve, request changes, and comment.

### Key Types

| Type | Role |
|------|------|
| `GitBarAppModel` | Central `@Observable` state: auth, PRs, refresh lifecycle |
| `GitBarSettingsStore` | `@Observable` settings backed by UserDefaults |
| `GitBarKeychain` | Security framework wrapper for token storage |
| `GitHubClient` | Stateless networking: REST auth + GraphQL queries/mutations |
| `PullRequestSummary` | Domain model for a single PR row |
| `BuildCheckGroup` / `BuildCheckItem` | Nested build/check status models |
| `GraphQLBuildMapper` | Maps raw GraphQL commit data into `BuildCheckGroup` arrays |

## Configuration

### Preferences

| Setting | Description | Default |
|---------|-------------|---------|
| Personal access token | GitHub PAT stored in Keychain | (none) |
| Show Assigned | Display PRs assigned to you | `true` |
| Show Created | Display PRs you authored | `true` |
| Show Review Requested | Display PRs requesting your review | `true` |
| Refresh interval | Background refresh period | 5 min |
| Launch at login | Start GitBar on macOS login | `false` |
| Show avatars | Display author avatar in PR rows | `false` |
| Show labels | Display PR labels in rows | `true` |
| Counter mode | Which count to show in the menu bar | Review Requested |
| Build status | How to fetch CI/build info | Check Suites |
| API base URL | GitHub API endpoint | `https://api.github.com` |
| Additional search query | Extra GitHub search qualifiers | (empty) |

### GitHub Enterprise

Set the **API base URL** in Preferences > Advanced to your GitHub Enterprise API endpoint (e.g., `https://github.yourcompany.com/api/v3`).

### Entitlements

The app is sandboxed with:
- `com.apple.security.app-sandbox` - App Sandbox enabled
- `com.apple.security.files.user-selected.read-only` - User-selected file read access
- `com.apple.security.network.client` - Outbound network access (GitHub API)

## Troubleshooting

### Token validation fails

1. Confirm the token has `repo` scope at [github.com/settings/tokens](https://github.com/settings/tokens)
2. Check the API base URL is correct (default: `https://api.github.com`)
3. If behind a proxy or VPN, ensure the GitHub API endpoint is reachable

### No pull requests appear

1. Open Preferences and verify the correct sections are enabled
2. Click **Refresh** in the menu to force an update
3. Check the additional search query is not too restrictive
4. Confirm you have open PRs matching the enabled sections

### Build checks not showing

1. Open Preferences > Display and set **Build status** to "Check Suites" or "Commit Status" depending on your CI setup
2. GitHub Actions typically uses Check Suites; older CI integrations use Commit Status

### App does not appear in menu bar

1. Verify the build target is macOS 26+
2. Check that the `git-pull-request` asset exists in the asset catalog
3. The app runs as a menu bar utility only (no Dock icon is expected)

### Keychain errors

If the token cannot be saved or retrieved, check that the app's sandbox entitlements include Keychain access. The Keychain service identifier is `com.softaworks.GitBar`.
