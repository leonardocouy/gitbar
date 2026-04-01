# Swift Conventions

## State Management

- Use `@Observable` (Observation framework) for reference-type state — not `ObservableObject`
- Use `@MainActor` on all observable classes (UI-bound state)
- Pass models explicitly via initializer — not `@Environment` for feature-local state
- Settings bindings use `Binding(get:set:)` wrapping keypaths on `GitBarSettingsStore`

## Async

- Use `async/await` with `Task { }` for fire-and-forget from AppKit `@objc` handlers
- Use `.task(id:)` in SwiftUI for lifecycle-bound async work
- Use `withThrowingTaskGroup` for parallel fetches (see `refresh()` in `GitBarAppModel`)

## AppKit + SwiftUI Hybrid

- SwiftUI views are hosted via `NSHostingView` in `NSWindow` — created by `makeWindowController()`
- Menu items are pure `NSMenuItem` with `attributedTitle` for rich formatting
- `@objc` action methods on `AppDelegate` handle menu item clicks
- `representedObject` on `NSMenuItem` carries context (URL, node ID, `ReviewActionContext`)

## Naming

- Types: `PascalCase` — `PullRequestSummary`, `BuildCheckGroup`
- GraphQL DTOs prefixed with `GraphQL` — `GraphQLPullRequestNode`, `GraphQLSearchResponse`
- Domain types have no prefix — `PullRequestSummary`, `BuildCheckItem`
- Extensions go in `Extensions/` named `{Type}Extensions.swift`
- Views go in `Views/` — one primary view per file

## Error Handling

- `GitHubAPIError` is the single error enum for all API failures
- Errors surface via `GitBarNotifier` (system notification) — no alerts or dialogs
- `error.gitBarMessage` (private extension) extracts localized description
