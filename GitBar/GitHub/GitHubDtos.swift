import AppKit
import Foundation

enum GitHubAPIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case httpStatus(Int, String)
    case missingViewer
    case graphQLErrors([String])
    case rateLimited(GitHubRateLimit)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "The GitHub API base URL is invalid."
        case .invalidResponse:
            "GitHub returned an invalid response."
        case .httpStatus(let status, let message):
            message.isEmpty ? "GitHub request failed with status \(status)." : message
        case .missingViewer:
            "GitHub did not return a valid viewer account."
        case .graphQLErrors(let messages):
            messages.joined(separator: "\n")
        case .rateLimited(let limit):
            limit.description
        }
    }
}

extension GitHubAPIError {
    var rateLimit: GitHubRateLimit? {
        guard case .rateLimited(let limit) = self else { return nil }
        return limit
    }
}

enum RefreshState: Equatable {
    case idle
    case refreshing
    case failed(String)
}

enum GitHubRateLimitKind: String, Equatable {
    case primary
    case secondary
}

struct GitHubRateLimit: Equatable {
    let kind: GitHubRateLimitKind
    let message: String
    let limit: Int?
    let remaining: Int?
    let resetAt: Date?
    let retryAfterSeconds: Int?
    let retryAt: Date?

    var description: String {
        let prefix = switch kind {
        case .primary:
            "GitHub API rate limit exceeded."
        case .secondary:
            "GitHub API secondary rate limit exceeded."
        }

        guard let retryAt else {
            return message.isEmpty ? prefix : "\(prefix) \(message)"
        }

        let formattedRetryAt = retryAt.formatted(date: .abbreviated, time: .shortened)
        return "\(prefix) Retry after \(formattedRetryAt)."
    }
}

enum TokenValidationState: Equatable {
    case idle
    case validating
    case valid(String)
    case invalid(String)

    var symbolName: String {
        switch self {
        case .idle:
            "questionmark.circle"
        case .validating:
            "clock"
        case .valid:
            "checkmark.circle.fill"
        case .invalid:
            "exclamationmark.circle.fill"
        }
    }

    var color: NSColor {
        switch self {
        case .idle:
            .secondaryLabelColor
        case .validating:
            .systemOrange
        case .valid:
            .systemGreen
        case .invalid:
            .systemRed
        }
    }

    var description: String {
        switch self {
        case .idle:
            "No token stored"
        case .validating:
            "Validating token…"
        case .valid(let login):
            "Authenticated as \(login)"
        case .invalid(let message):
            message
        }
    }
}

enum BuildCheckStatus: String, Hashable {
    case success
    case failure
    case pending
    case actionRequired
    case neutral

    var dotColor: NSColor {
        switch self {
        case .success:
            NSColor(named: "green") ?? .systemGreen
        case .failure:
            NSColor(named: "red") ?? .systemRed
        case .pending, .actionRequired:
            NSColor(named: "yellow") ?? .systemYellow
        case .neutral:
            .systemGray
        }
    }

    var itemImageName: String {
        switch self {
        case .success:
            "check-circle-fill"
        case .failure:
            "x-circle-fill"
        case .pending, .actionRequired:
            "issue-draft"
        case .neutral:
            "question"
        }
    }

    static func from(graphQLStatus value: String?) -> BuildCheckStatus {
        switch value?.uppercased() {
        case "SUCCESS":
            .success
        case "FAILURE", "ERROR", "TIMED_OUT", "STARTUP_FAILURE":
            .failure
        case "PENDING", "IN_PROGRESS", "QUEUED", "EXPECTED":
            .pending
        case "ACTION_REQUIRED":
            .actionRequired
        default:
            .neutral
        }
    }
}

struct BuildCheckItem: Hashable, Identifiable {
    let id: String
    let name: String
    let subtitle: String?
    let detailsURL: URL?
    let status: BuildCheckStatus
}

struct BuildCheckGroup: Hashable, Identifiable {
    let id: String
    let title: String
    let items: [BuildCheckItem]
}

struct PullRequestLabel: Decodable, Hashable, Identifiable {
    let name: String
    let color: String

    var id: String { name }
}

struct PullRequestAuthor: Decodable, Hashable {
    let login: String
    let avatarUrl: URL?

    static let ghost = PullRequestAuthor(login: "ghost", avatarUrl: nil)
}

enum PullRequestReviewEvent: String {
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"
    case comment = "COMMENT"
}

struct PullRequestSummary: Hashable, Identifiable {
    let id: String
    let nodeId: String
    let url: URL
    let title: String
    let number: Int
    let repositoryName: String
    let author: PullRequestAuthor
    let labels: [PullRequestLabel]
    let approvalCount: Int
    let approvedByViewer: Bool
    let additions: Int
    let deletions: Int
    let createdAt: Date
    let isDraft: Bool
    let isReadByViewer: Bool
    let buildChecks: [BuildCheckGroup]
}

struct GraphQLSearchResponse: Decodable {
    let data: GraphQLSearchData?
    let errors: [GraphQLError]?
}

struct GraphQLSearchData: Decodable {
    let search: GraphQLSearchResult
}

struct GraphQLSearchResult: Decodable {
    let issueCount: Int
    let edges: [GraphQLEdge]
}

struct GraphQLEdge: Decodable {
    let node: GraphQLPullRequestNode
}

struct GraphQLError: Decodable {
    let message: String
}

struct GraphQLPullRequestNode: Decodable {
    let id: String
    let url: URL
    let createdAt: Date
    let title: String
    let number: Int
    let deletions: Int?
    let additions: Int?
    let reviews: GraphQLReviewConnection
    let author: PullRequestAuthor?
    let repository: GraphQLRepository
    let commits: GraphQLCommitConnection?
    let labels: GraphQLNodes<PullRequestLabel>
    let isDraft: Bool
    let isReadByViewer: Bool

    func toSummary(viewerLogin: String) -> PullRequestSummary {
        let author = author ?? .ghost
        let approvedByViewer = reviews.edges.contains { $0.node.author?.login == viewerLogin }
        let checks = GraphQLBuildMapper.mapBuildChecks(from: commits)

        return PullRequestSummary(
            id: url.absoluteString,
            nodeId: id,
            url: url,
            title: title,
            number: number,
            repositoryName: repository.name,
            author: author,
            labels: labels.nodes,
            approvalCount: reviews.totalCount,
            approvedByViewer: approvedByViewer,
            additions: additions ?? 0,
            deletions: deletions ?? 0,
            createdAt: createdAt,
            isDraft: isDraft,
            isReadByViewer: isReadByViewer,
            buildChecks: checks
        )
    }
}

struct GraphQLNodes<T: Decodable & Hashable>: Decodable, Hashable {
    let nodes: [T]
}

struct GraphQLRepository: Decodable {
    let name: String
}

struct GraphQLReviewConnection: Decodable {
    let totalCount: Int
    let edges: [GraphQLUserEdge]
}

struct GraphQLUserEdge: Decodable {
    let node: GraphQLUserNode
}

struct GraphQLUserNode: Decodable {
    let author: PullRequestAuthor?
}

struct GraphQLCommitConnection: Decodable {
    let nodes: [GraphQLCommitNode]
}

struct GraphQLCommitNode: Decodable {
    let commit: GraphQLCommitPayload
}

struct GraphQLCommitPayload: Decodable {
    let checkSuites: GraphQLCheckSuiteConnection?
    let statusCheckRollup: GraphQLStatusCheckRollup?
}

struct GraphQLCheckSuiteConnection: Decodable {
    let nodes: [GraphQLCheckSuite]
}

struct GraphQLCheckSuite: Decodable {
    let app: GraphQLCheckApp?
    let checkRuns: GraphQLCheckRunConnection
}

struct GraphQLCheckApp: Decodable {
    let name: String?
}

struct GraphQLCheckRunConnection: Decodable {
    let totalCount: Int
    let nodes: [GraphQLCheckRun]
}

struct GraphQLCheckRun: Decodable {
    let name: String
    let conclusion: String?
    let detailsUrl: URL?
}

struct GraphQLStatusCheckRollup: Decodable {
    let state: String
    let contexts: GraphQLStatusContextConnection
}

struct GraphQLStatusContextConnection: Decodable {
    let nodes: [GraphQLStatusContextNode]
}

struct GraphQLStatusContextNode: Decodable {
    let name: String?
    let context: String?
    let conclusion: String?
    let state: String?
    let title: String?
    let description: String?
    let detailsUrl: URL?
    let targetUrl: String?
}

struct GitHubViewer: Decodable {
    let login: String
    let name: String?
}

struct GraphQLReviewMutationResponse: Decodable {
    let data: GraphQLReviewMutationData?
    let errors: [GraphQLError]?
}

struct GraphQLReviewMutationData: Decodable {
    let addPullRequestReview: GraphQLReviewPayload
}

struct GraphQLReviewPayload: Decodable {
    let pullRequestReview: GraphQLReviewState
}

struct GraphQLReviewState: Decodable {
    let state: String
}

enum GraphQLBuildMapper {
    static func mapBuildChecks(from commits: GraphQLCommitConnection?) -> [BuildCheckGroup] {
        guard let commit = commits?.nodes.first?.commit else { return [] }

        if let suites = commit.checkSuites?.nodes, !suites.isEmpty {
            return suites.compactMap { suite in
                let items = suite.checkRuns.nodes.map { run in
                    BuildCheckItem(
                        id: [suite.app?.name ?? "suite", run.name, run.detailsUrl?.absoluteString ?? UUID().uuidString].joined(separator: "|"),
                        name: run.name,
                        subtitle: run.conclusion,
                        detailsURL: run.detailsUrl,
                        status: .from(graphQLStatus: run.conclusion)
                    )
                }

                guard !items.isEmpty else { return nil }
                return BuildCheckGroup(
                    id: suite.app?.name ?? UUID().uuidString,
                    title: suite.app?.name ?? "Checks",
                    items: items
                )
            }
        }

        if let rollup = commit.statusCheckRollup, !rollup.contexts.nodes.isEmpty {
            let items = rollup.contexts.nodes.map { context in
                let url = context.detailsUrl ?? context.targetUrl.flatMap(URL.init(string:))
                let name = context.name ?? context.context ?? "Status"
                let subtitle = context.description ?? context.title
                let status = BuildCheckStatus.from(graphQLStatus: context.conclusion ?? context.state)

                return BuildCheckItem(
                    id: [name, url?.absoluteString ?? UUID().uuidString].joined(separator: "|"),
                    name: name,
                    subtitle: subtitle,
                    detailsURL: url,
                    status: status
                )
            }

            return [
                BuildCheckGroup(
                    id: "status-rollup",
                    title: "Checks",
                    items: items
                )
            ]
        }

        return []
    }
}
