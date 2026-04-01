import AppKit
import Observation

@MainActor
@Observable
final class GitHubTokenValidator {
    var state: TokenValidationState = .idle

    var symbolName: String {
        state.symbolName
    }

    var color: NSColor {
        state.color
    }

    var description: String {
        state.description
    }
}
