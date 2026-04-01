# GitBar PRD

## Overview
GitBar is a macOS Tahoe-only menu bar app that gives LEOZUDO direct visibility into GitHub pull requests from the system menu bar. It must match PullBar's current functional surface area while being rebuilt with a modern Swift and SwiftUI-first architecture, native Apple APIs where practical, and cleaner state management.

## Problem
GitHub pull request monitoring is fragmented across browser tabs, notifications, and ad hoc context switching. PullBar proves the core workflow is useful, but its implementation is older, AppKit-heavy, and tied to dependency choices that GitBar does not need to inherit.

## Product Goal
Ship a native macOS menu bar app that lets a developer monitor assigned, created, and review-requested pull requests, inspect build/check status quickly, open relevant GitHub pages immediately, and manage authentication/settings without leaving the Mac menu bar workflow.

## Target User
- Primary user: LEOZUDO, a developer who wants low-friction GitHub PR awareness directly in the menu bar.
- Secondary user: any GitHub-heavy macOS developer using GitHub.com or a GitHub Enterprise API endpoint.

## Success Criteria
- GitBar reproduces PullBar's functional PR-monitoring feature set.
- The app uses a new GitBar codebase and branding instead of being a forked shipping product.
- Authentication works with a GitHub personal access token and auto-discovers the viewer account.
- The menu bar experience is reliable on macOS 26 Tahoe and behaves like a native menu bar utility, not a regular docked app.
- Settings changes persist and take effect without restarting the app.

## Non-Goals
- OAuth or device-flow authentication in v1.
- Broader GitHub write actions such as merge, comment, reassign, label editing, or review submission.
- Support for macOS versions earlier than 26 Tahoe.
- PullBar-specific donations, app promotions, or cloned branding.
- Backward-compatibility with PullBar internals or package choices.

## Core User Stories
- As a developer, I can see my assigned pull requests in the menu bar app.
- As a developer, I can see my created pull requests in the menu bar app.
- As a developer, I can see pull requests where my review is requested.
- As a developer, I can configure which of those sections are shown.
- As a developer, I can see PR title, number, repository, author, approvals, additions/deletions, labels, draft state, unread state, and relative age.
- As a developer, I can inspect build/check results from the menu without opening the PR page first.
- As a developer, I can click a PR or a check item to open the relevant GitHub page.
- As a developer, I can set the refresh interval and trigger a manual refresh.
- As a developer, I can choose which count, if any, appears next to the menu bar icon.
- As a developer, I can store my token securely and validate that it works.
- As a developer, I can target a custom GitHub API base URL for GitHub Enterprise-style setups.
- As a developer, I can add an extra GitHub search query suffix to narrow the PR feed.
- As a developer, I can toggle launch-at-login from the app settings.

## Functional Requirements

### Authentication
- Support GitHub personal access token input through the Preferences window.
- Persist the token in the macOS keychain, not plain defaults storage.
- Validate the token against the GitHub API.
- Auto-discover the viewer login from the token; do not require separate username input.
- Surface validation state in the UI.

### Pull Request Data
- Query GitHub with the following open PR buckets:
  - Assigned to the viewer
  - Authored by the viewer
  - Review requested from the viewer
- Respect an additional query suffix configured by the user.
- Respect a configurable GitHub API base URL.
- Fetch up to 30 results per section, matching PullBar's current behavior.

### Menu Bar Experience
- Display a native menu bar status item.
- Show an optional numeric counter in the status item for:
  - Assigned count
  - Created count
  - Review requested count
  - None
- Render PR sections only when enabled and non-empty.
- Include footer actions:
  - Refresh
  - Preferences…
  - About GitBar
  - Quit

### PR Row Content
- Show unread marker when the PR has not been read by the viewer.
- Show draft indicator for draft PRs.
- Show title and PR number.
- Show repository name and author login.
- Optionally show labels.
- Optionally show author avatar.
- Show approval count, additions, deletions, and relative creation time.
- Show summarized check/build status indicators inline when available.

### Check Status
- Support three display modes:
  - None
  - Check suites
  - Commit status rollup
- Build/check entries should appear in nested menu items and open their detail URLs.
- Unknown or incomplete statuses should still render with a neutral fallback.

### Preferences and About
- Provide a Preferences window for auth, filtering, display, refresh, and launch settings.
- Provide an About window with app identity, version, repository/help links, and a short status legend.

### Notifications
- Use user notifications for significant refresh/auth/API failures where appropriate.

## UX Requirements
- The app should run as a menu bar utility without dock presence.
- Settings UI should be clear, compact, and modern SwiftUI.
- State changes should feel immediate; avoid requiring app relaunch for normal settings updates.
- The app should be robust when no token is configured, when the token is invalid, and when zero PRs match.

## Technical Constraints
- macOS 26 Tahoe minimum target.
- Swift 6.2.
- SwiftUI-first UI with modern Observation APIs.
- AppKit permitted for the actual status item and native menu shell.
- Prefer native Apple APIs over third-party dependencies when they provide equivalent behavior.
- Local build verification requires full Xcode, not only Command Line Tools.

## Acceptance Criteria
- GitBar launches as a menu bar app on macOS 26.
- A valid PAT populates PR sections and updates the menu bar count correctly.
- An invalid PAT is clearly reflected in Preferences and does not crash the app.
- Each enabled section shows the correct PR list and row metadata.
- Check/build submenu items open working URLs.
- Refresh interval changes reschedule the background refresh loop.
- Launch-at-login toggle reflects actual app service registration state.
- Preferences persist across launches.

