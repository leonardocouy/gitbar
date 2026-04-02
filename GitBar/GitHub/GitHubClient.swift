import Foundation

struct GitHubClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchViewer(baseURL: String, token: String) async throws -> GitHubViewer {
        let endpoint = try makeURL(baseURL: baseURL, path: "/user")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)

        let viewer = try JSONDecoder().decode(GitHubViewer.self, from: data)
        guard !viewer.login.isEmpty else {
            throw GitHubAPIError.missingViewer
        }
        return viewer
    }

    func fetchPullRequests(
        section: PullRequestSectionKind,
        viewerLogin: String,
        settings: GitHubQuerySettings,
        token: String
    ) async throws -> [PullRequestSummary] {
        let endpoint = try makeURL(baseURL: settings.baseURL, path: "/graphql")
        let query = buildQuery(section: section, viewerLogin: viewerLogin, settings: settings)
        let payload = ["query": query]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(GraphQLSearchResponse.self, from: data)

        if let errors = result.errors, !errors.isEmpty {
            throw graphQLError(from: errors, response: response)
        }

        return result.data?.search.edges.map { $0.node.toSummary(viewerLogin: viewerLogin) } ?? []
    }

    func submitReview(
        pullRequestId: String,
        event: PullRequestReviewEvent,
        body: String?,
        baseURL: String,
        token: String
    ) async throws {
        let endpoint = try makeURL(baseURL: baseURL, path: "/graphql")

        let bodyField: String
        if let body, !body.isEmpty {
            let escaped = body
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            bodyField = ", body: \"\(escaped)\""
        } else {
            bodyField = ""
        }

        let mutation = """
        mutation {
          addPullRequestReview(input: {
            pullRequestId: "\(pullRequestId)"
            event: \(event.rawValue)
            \(bodyField)
          }) {
            pullRequestReview {
              state
            }
          }
        }
        """

        let payload = ["query": mutation]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)

        let result = try JSONDecoder().decode(GraphQLReviewMutationResponse.self, from: data)
        if let errors = result.errors, !errors.isEmpty {
            throw graphQLError(from: errors, response: response)
        }
    }

    private func buildQuery(section: PullRequestSectionKind, viewerLogin: String, settings: GitHubQuerySettings) -> String {
        let sectionQuery = switch section {
        case .custom:
            settings.customSectionQuery
        default:
            section.queryQualifier(for: viewerLogin)
        }

        let additionalQuery = settings.additionalQuery
        let query = [
            "is:open",
            "is:pr",
            sectionQuery,
            "archived:false",
            additionalQuery,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .replacingOccurrences(of: "\"", with: "\\\"")

        let buildFragment: String
        switch settings.buildInfoMode {
        case .none:
            buildFragment = ""
        case .checkSuites:
            buildFragment = """
            commits(last: 1) {
              nodes {
                commit {
                  checkSuites(first: 10) {
                    nodes {
                      app {
                        name
                      }
                      checkRuns(first: 10) {
                        totalCount
                        nodes {
                          name
                          conclusion
                          detailsUrl
                        }
                      }
                    }
                  }
                }
              }
            }
            """
        case .commitStatus:
            buildFragment = """
            commits(last: 1) {
              nodes {
                commit {
                  statusCheckRollup {
                    state
                    contexts(first: 20) {
                      nodes {
                        ... on StatusContext {
                          context
                          description
                          state
                          targetUrl
                        }
                        ... on CheckRun {
                          name
                          conclusion
                          detailsUrl
                          title
                        }
                      }
                    }
                  }
                }
              }
            }
            """
        }

        return """
        {
          search(query: "\(query)", type: ISSUE, first: 30) {
            issueCount
            edges {
              node {
                ... on PullRequest {
                  id
                  number
                  createdAt
                  title
                  url
                  deletions
                  additions
                  isDraft
                  isReadByViewer
                  author {
                    login
                    avatarUrl
                  }
                  repository {
                    name
                  }
                  labels(first: 5) {
                    nodes {
                      name
                      color
                    }
                  }
                  reviews(states: APPROVED, first: 10) {
                    totalCount
                    edges {
                      node {
                        author {
                          login
                          avatarUrl
                        }
                      }
                    }
                  }
                  \(buildFragment)
                }
              }
            }
          }
        }
        """
    }

    private func makeURL(baseURL: String, path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else {
            throw GitHubAPIError.invalidBaseURL
        }
        return url
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            if let rateLimit = parseRateLimit(from: http, message: message) {
                throw GitHubAPIError.rateLimited(rateLimit)
            }
            throw GitHubAPIError.httpStatus(http.statusCode, message)
        }
    }

    private func graphQLError(from errors: [GraphQLError], response: URLResponse) -> GitHubAPIError {
        let message = errors.map(\.message).joined(separator: "\n")

        if
            let http = response as? HTTPURLResponse,
            let rateLimit = parseRateLimit(from: http, message: message)
        {
            return .rateLimited(rateLimit)
        }

        return .graphQLErrors(errors.map(\.message))
    }

    private func parseRateLimit(from response: HTTPURLResponse, message: String) -> GitHubRateLimit? {
        let normalizedMessage = message.lowercased()
        let kind: GitHubRateLimitKind?

        if normalizedMessage.contains("secondary rate limit") {
            kind = .secondary
        } else if normalizedMessage.contains("rate limit") {
            kind = .primary
        } else if response.statusCode == 429 {
            kind = .primary
        } else {
            kind = nil
        }

        guard let kind else { return nil }

        let limit = response.value(forHTTPHeaderField: "x-ratelimit-limit").flatMap(Int.init)
        let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining").flatMap(Int.init)
        let resetAt = response.value(forHTTPHeaderField: "x-ratelimit-reset")
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:))
        let retryAfterSeconds = response.value(forHTTPHeaderField: "retry-after").flatMap(Int.init)
        let now = Date()
        let retryAt: Date? = if let retryAfterSeconds {
            now.addingTimeInterval(TimeInterval(retryAfterSeconds))
        } else if remaining == 0 {
            resetAt
        } else if kind == .secondary {
            now.addingTimeInterval(60)
        } else {
            nil
        }

        return GitHubRateLimit(
            kind: kind,
            message: message,
            limit: limit,
            remaining: remaining,
            resetAt: resetAt,
            retryAfterSeconds: retryAfterSeconds,
            retryAt: retryAt
        )
    }
}
