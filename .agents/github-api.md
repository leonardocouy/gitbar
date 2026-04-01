# GitHub API Integration

## Endpoints

| Purpose | Method | Endpoint | Format |
|---------|--------|----------|--------|
| Validate token / get viewer | `GET` | `/user` | REST JSON |
| Search pull requests | `POST` | `/graphql` | GraphQL |
| Submit PR review | `POST` | `/graphql` | GraphQL mutation |

All requests use `Authorization: Bearer {token}` header.

## GraphQL Query Structure

The PR search query is built dynamically in `GitHubClient.buildQuery()`:

- Search string: `is:open is:pr {section_qualifier} archived:false {additional_query}`
- Section qualifiers: `assignee:`, `author:`, `review-requested:` (based on viewer login)
- Build info fragment is conditionally included based on `BuildInfoMode` setting
- Returns up to 30 PRs per section

### Key Fields Fetched

- `id` — GraphQL node ID (needed for mutations like `addPullRequestReview`)
- `number`, `title`, `url`, `createdAt`, `additions`, `deletions`, `isDraft`, `isReadByViewer`
- `author { login, avatarUrl }`
- `repository { name }` — repo name only, owner is not fetched (parsed from URL if needed)
- `reviews(states: APPROVED)` — approval count + whether viewer approved
- `labels(first: 5)` — label name + hex color
- Build info (conditional): `checkSuites` or `statusCheckRollup`

## GraphQL Mutations

### addPullRequestReview

Used for approve, request changes, and comment actions.

```graphql
mutation {
  addPullRequestReview(input: {
    pullRequestId: "PR_kwDOABC..."  # GraphQL node ID, NOT the PR number
    event: APPROVE                   # or REQUEST_CHANGES or COMMENT
    body: "optional review body"
  }) {
    pullRequestReview { state }
  }
}
```

Events are modeled as `PullRequestReviewEvent` enum in `GitHubDtos.swift`.

## Adding a New API Call

1. Add response DTOs in `GitHubDtos.swift`
2. Add the method in `GitHubClient.swift` — follow the pattern of `submitReview()` for mutations or `fetchPullRequests()` for queries
3. Add a wrapper in `GitBarAppModel` that handles auth check, calls the client, notifies on error, and refreshes if needed
4. Wire it up in `AppDelegate` via `@objc` handler on the relevant `NSMenuItem`

## Token Scope

The PAT needs `repo` scope (read access) for PR search. Write access is needed for review mutations.
