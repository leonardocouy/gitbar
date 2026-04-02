import Foundation
import Observation
import ServiceManagement

extension Notification.Name {
    static let gitBarConfigurationDidChange = Notification.Name("GitBarConfigurationDidChange")
    static let gitBarAuthenticationDidChange = Notification.Name("GitBarAuthenticationDidChange")
}

enum GitBarConfigurationChangeEffect: String {
    case refreshImmediately
    case refreshDebounced
    case rebuildMenu
}

enum PullRequestSectionKind: String, CaseIterable, Codable, Identifiable, Hashable {
    case assigned
    case created
    case reviewRequested
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .assigned:
            "Assigned"
        case .created:
            "Created"
        case .reviewRequested:
            "Review Requested"
        case .custom:
            "Custom"
        }
    }

    func queryQualifier(for viewerLogin: String) -> String {
        switch self {
        case .assigned:
            "assignee:\(viewerLogin)"
        case .created:
            "author:\(viewerLogin)"
        case .reviewRequested:
            "review-requested:\(viewerLogin)"
        case .custom:
            ""
        }
    }
}

enum BuildInfoMode: String, CaseIterable, Codable, Identifiable {
    case none
    case checkSuites
    case commitStatus

    var id: Self { self }

    var title: String {
        switch self {
        case .none:
            "None"
        case .checkSuites:
            "Check Suites"
        case .commitStatus:
            "Commit Status"
        }
    }
}

enum CounterMode: String, CaseIterable, Codable, Identifiable {
    case assigned
    case created
    case reviewRequested
    case custom
    case none

    var id: Self { self }

    var title: String {
        switch self {
        case .assigned:
            "Assigned"
        case .created:
            "Created"
        case .reviewRequested:
            "Review Requested"
        case .custom:
            "Custom"
        case .none:
            "None"
        }
    }
}

struct GitHubQuerySettings: Sendable {
    let baseURL: String
    let additionalQuery: String
    let buildInfoMode: BuildInfoMode
    let customSectionQuery: String
}

@MainActor
@Observable
final class GitBarSettingsStore {
    enum Key: String {
        case githubAPIBaseURL
        case githubAdditionalQuery
        case showAssigned
        case showCreated
        case showReviewRequested
        case showCustom
        case showAvatar
        case showLabels
        case refreshIntervalMinutes
        case buildInfoMode
        case counterMode
        case customSectionTitle
        case customSectionQuery
    }

    static let refreshIntervals = [1, 5, 10, 15, 30]

    private let defaults: UserDefaults
    private let launchService: SMAppService

    var githubAPIBaseURL: String {
        didSet { persistString(githubAPIBaseURL, for: .githubAPIBaseURL) }
    }

    var githubAdditionalQuery: String {
        didSet { persistString(githubAdditionalQuery, for: .githubAdditionalQuery) }
    }

    var showAssigned: Bool {
        didSet { persistBool(showAssigned, for: .showAssigned) }
    }

    var showCreated: Bool {
        didSet { persistBool(showCreated, for: .showCreated) }
    }

    var showReviewRequested: Bool {
        didSet { persistBool(showReviewRequested, for: .showReviewRequested) }
    }

    var showCustom: Bool {
        didSet { persistBool(showCustom, for: .showCustom) }
    }

    var showAvatar: Bool {
        didSet { persistBool(showAvatar, for: .showAvatar) }
    }

    var showLabels: Bool {
        didSet { persistBool(showLabels, for: .showLabels) }
    }

    var refreshIntervalMinutes: Int {
        didSet {
            if Self.refreshIntervals.contains(refreshIntervalMinutes) {
                persistInt(refreshIntervalMinutes, for: .refreshIntervalMinutes)
            } else {
                refreshIntervalMinutes = oldValue
            }
        }
    }

    var buildInfoMode: BuildInfoMode {
        didSet { persistEnum(buildInfoMode, for: .buildInfoMode) }
    }

    var counterMode: CounterMode {
        didSet { persistEnum(counterMode, for: .counterMode) }
    }

    var customSectionTitle: String {
        didSet { persistString(customSectionTitle, for: .customSectionTitle) }
    }

    var customSectionQuery: String {
        didSet { persistString(customSectionQuery, for: .customSectionQuery) }
    }

    var launchesAtLogin: Bool {
        didSet {
            guard oldValue != launchesAtLogin else { return }
            do {
                if launchesAtLogin {
                    try launchService.register()
                } else {
                    try launchService.unregister()
                }
                postConfigurationChange()
            } catch {
                launchesAtLogin = oldValue
            }
        }
    }

    init(defaults: UserDefaults = .standard, launchService: SMAppService = .mainApp) {
        self.defaults = defaults
        self.launchService = launchService
        githubAPIBaseURL = defaults.string(forKey: Key.githubAPIBaseURL.rawValue) ?? "https://api.github.com"
        githubAdditionalQuery = defaults.string(forKey: Key.githubAdditionalQuery.rawValue) ?? ""
        showAssigned = defaults.object(forKey: Key.showAssigned.rawValue) as? Bool ?? true
        showCreated = defaults.object(forKey: Key.showCreated.rawValue) as? Bool ?? true
        showReviewRequested = defaults.object(forKey: Key.showReviewRequested.rawValue) as? Bool ?? true
        showCustom = defaults.object(forKey: Key.showCustom.rawValue) as? Bool ?? false
        showAvatar = defaults.object(forKey: Key.showAvatar.rawValue) as? Bool ?? false
        showLabels = defaults.object(forKey: Key.showLabels.rawValue) as? Bool ?? true
        refreshIntervalMinutes = defaults.object(forKey: Key.refreshIntervalMinutes.rawValue) as? Int ?? 5
        buildInfoMode = Self.decodeEnum(BuildInfoMode.self, from: defaults.string(forKey: Key.buildInfoMode.rawValue)) ?? .checkSuites
        counterMode = Self.decodeEnum(CounterMode.self, from: defaults.string(forKey: Key.counterMode.rawValue)) ?? .reviewRequested
        customSectionTitle = defaults.string(forKey: Key.customSectionTitle.rawValue) ?? "Custom"
        customSectionQuery = defaults.string(forKey: Key.customSectionQuery.rawValue) ?? ""
        launchesAtLogin = launchService.status == .enabled
    }

    var enabledSections: [PullRequestSectionKind] {
        var sections: [PullRequestSectionKind] = []
        if showAssigned {
            sections.append(.assigned)
        }
        if showCreated {
            sections.append(.created)
        }
        if showReviewRequested {
            sections.append(.reviewRequested)
        }
        if showCustom, !customSectionQuery.trimmed.isEmpty {
            sections.append(.custom)
        }
        return sections
    }

    func title(for section: PullRequestSectionKind) -> String {
        guard section == .custom else { return section.title }

        let title = customSectionTitle.trimmed
        return title.isEmpty ? section.title : title
    }

    var normalizedAPIBaseURL: String {
        let trimmed = githubAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    var querySettings: GitHubQuerySettings {
        GitHubQuerySettings(
            baseURL: normalizedAPIBaseURL,
            additionalQuery: githubAdditionalQuery.trimmed,
            buildInfoMode: buildInfoMode,
            customSectionQuery: customSectionQuery.trimmed
        )
    }

    private func persistString(_ value: String, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
        let effect: GitBarConfigurationChangeEffect = switch key {
        case .customSectionTitle:
            .rebuildMenu
        case .githubAPIBaseURL, .githubAdditionalQuery, .customSectionQuery:
            .refreshDebounced
        default:
            .refreshImmediately
        }
        postConfigurationChange(effect: effect)
    }

    private func persistBool(_ value: Bool, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
        postConfigurationChange(effect: .refreshImmediately)
    }

    private func persistInt(_ value: Int, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
        postConfigurationChange(effect: .refreshImmediately)
    }

    private func persistEnum<T: RawRepresentable>(_ value: T, for key: Key) where T.RawValue == String {
        defaults.set(value.rawValue, forKey: key.rawValue)
        postConfigurationChange(effect: .refreshImmediately)
    }

    private static func decodeEnum<T: RawRepresentable>(_ type: T.Type, from rawValue: String?) -> T? where T.RawValue == String {
        guard let rawValue else { return nil }
        return T(rawValue: rawValue)
    }

    private func postConfigurationChange(effect: GitBarConfigurationChangeEffect) {
        NotificationCenter.default.post(
            name: .gitBarConfigurationDidChange,
            object: self,
            userInfo: ["effect": effect.rawValue]
        )
    }
}
