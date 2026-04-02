# GitBar Implementation Plan

## Summary
Implement GitBar as a new macOS 26 menu bar app using a hybrid architecture:
- AppKit for `NSStatusItem` and native `NSMenu`
- SwiftUI for Preferences and About windows
- Observation-based app state and settings
- Native networking, keychain, notifications, and launch-at-login integrations

## Architecture

### App Shell
- Keep an `AppDelegate` entry point because the app is menu bar first.
- Set activation policy to accessory.
- Own the `NSStatusItem`, `NSMenu`, refresh timer, and utility windows in the app delegate.

### State and Settings
- Use `@Observable` `@MainActor` stores for app state and persisted preferences.
- Store non-secret configuration in `UserDefaults`.
- Store the GitHub token in Keychain via Security APIs.
- Trigger app-wide refresh/menu rebuild notifications when settings or auth change.

### GitHub Integration
- Use `URLSession` with async/await.
- Use REST `/user` for token validation and viewer discovery.
- Use GraphQL search queries for PR sections and build/check payloads.
- Normalize raw API responses into domain models that menu rendering can consume directly.

### UI Surfaces
- Preferences:
  - General toggles for section visibility
  - Display controls for counter mode, label/avatar visibility, refresh interval, and build mode
  - Authentication tab for PAT and validation
  - Advanced tab for API base URL and extra query suffix
  - Launch-at-login toggle
- About:
  - App name
  - Version
  - Repository/help links
  - Status legend

## Project Changes
- Rename the copied PullBar Xcode project/target/product to `GitBar`.
- Remove storyboard references and old Swift package dependencies.
- Keep and reuse only asset files that help the PR menu rendering.
- Replace the copied source files with GitBar's new implementation.
- Add `PRD.md` and `PLAN.md` at repo root as the living spec.

## Verification
- Typecheck Swift sources locally where possible with the installed toolchain.
- Verify the project graph is internally coherent after renaming/removing copied references.
- If full Xcode becomes available, build and run the app target as the final acceptance step.

## Current Environment Caveat
- This machine currently has Swift Command Line Tools active and not full Xcode. Implementation can proceed, but full app build/run verification remains blocked until Xcode is installed and selected.
