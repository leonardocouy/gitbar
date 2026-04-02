import AppKit
import Observation
import SwiftUI

private extension Error {
    var gitBarMessage: String {
        (self as? LocalizedError)?.errorDescription ?? localizedDescription
    }
}

@MainActor
@Observable
final class GitBarAppModel {
    let settings: GitBarSettingsStore
    let tokenValidator = GitHubTokenValidator()

    private let keychain: GitBarKeychain
    private let client: GitHubClient
    private let notifier: GitBarNotifier

    var viewerLogin = ""
    var viewerName = ""
    var sections: [PullRequestSectionKind: [PullRequestSummary]] = [:]
    var refreshState: RefreshState = .idle
    var lastRefreshDate: Date?
    var rateLimitCooldownUntil: Date?
    var rateLimitMessage: String?

    init(
        settings: GitBarSettingsStore,
        keychain: GitBarKeychain = GitBarKeychain(),
        client: GitHubClient = GitHubClient(),
        notifier: GitBarNotifier = GitBarNotifier()
    ) {
        self.settings = settings
        self.keychain = keychain
        self.client = client
        self.notifier = notifier
    }

    var authToken: String {
        get { (try? keychain.string(for: .githubToken)) ?? "" }
        set {
            do {
                let trimmed = newValue.trimmed
                if trimmed.isEmpty {
                    try keychain.removeValue(for: .githubToken)
                    viewerLogin = ""
                    viewerName = ""
                    sections = [:]
                    tokenValidator.state = .idle
                } else {
                    try keychain.set(trimmed, for: .githubToken)
                }
                clearRateLimitCooldown()
                NotificationCenter.default.post(name: .gitBarAuthenticationDidChange, object: self)
            } catch {
                notifier.notify(body: error.gitBarMessage)
            }
        }
    }

    var hasValidToken: Bool {
        if case .valid = tokenValidator.state {
            return true
        }
        return false
    }

    var hasVisiblePullRequests: Bool {
        settings.enabledSections.contains { !(sections[$0] ?? []).isEmpty }
    }

    func counterText() -> String? {
        switch settings.counterMode {
        case .assigned:
            return settings.showAssigned ? String(sections[.assigned, default: []].count) : nil
        case .created:
            return settings.showCreated ? String(sections[.created, default: []].count) : nil
        case .reviewRequested:
            return settings.showReviewRequested ? String(sections[.reviewRequested, default: []].count) : nil
        case .custom:
            return settings.showCustom && !settings.customSectionQuery.trimmed.isEmpty ? String(sections[.custom, default: []].count) : nil
        case .none:
            return nil
        }
    }

    func bootstrap() async {
        await validateToken(sendNotification: false)
        if hasValidToken {
            await refresh(sendNotification: false)
        }
    }

    func validateToken(sendNotification: Bool) async {
        let token = authToken.trimmed
        guard !token.isEmpty else {
            tokenValidator.state = .idle
            viewerLogin = ""
            viewerName = ""
            sections = [:]
            return
        }

        tokenValidator.state = .validating

        do {
            let viewer = try await client.fetchViewer(baseURL: settings.normalizedAPIBaseURL, token: token)
            clearRateLimitCooldown()
            viewerLogin = viewer.login
            viewerName = viewer.name ?? ""
            tokenValidator.state = .valid(viewer.login)
        } catch {
            if let rateLimit = (error as? GitHubAPIError)?.rateLimit {
                applyRateLimitCooldown(rateLimit)
                tokenValidator.state = .rateLimited(rateLimit.description)
                if sendNotification {
                    notifier.notify(body: rateLimit.description)
                }
                return
            }

            viewerLogin = ""
            viewerName = ""
            sections = [:]
            tokenValidator.state = .invalid(error.gitBarMessage)
            if sendNotification {
                notifier.notify(body: error.gitBarMessage)
            }
        }
    }

    func refresh(sendNotification: Bool) async {
        let token = authToken.trimmed
        guard !token.isEmpty else {
            sections = [:]
            refreshState = .idle
            return
        }

        guard refreshState != .refreshing else { return }

        if let cooldownMessage = activeRateLimitMessage() {
            refreshState = .failed(cooldownMessage)
            if sendNotification {
                notifier.notify(body: cooldownMessage)
            }
            return
        }

        if viewerLogin.isEmpty || !hasValidToken {
            await validateToken(sendNotification: sendNotification)
        }

        guard hasValidToken, !viewerLogin.isEmpty else { return }

        refreshState = .refreshing

        do {
            var nextSections: [PullRequestSectionKind: [PullRequestSummary]] = [:]
            let querySettings = settings.querySettings

            try await withThrowingTaskGroup(of: (PullRequestSectionKind, [PullRequestSummary]).self) { group in
                for section in settings.enabledSections {
                    group.addTask {
                        let items = try await self.client.fetchPullRequests(
                            section: section,
                            viewerLogin: self.viewerLogin,
                            settings: querySettings,
                            token: token
                        )
                        return (section, items)
                    }
                }

                for try await (section, items) in group {
                    nextSections[section] = items
                }
            }

            clearRateLimitCooldown()
            sections = nextSections
            refreshState = .idle
            lastRefreshDate = .now
        } catch {
            if let rateLimit = (error as? GitHubAPIError)?.rateLimit {
                applyRateLimitCooldown(rateLimit)
                refreshState = .failed(rateLimit.description)
                if sendNotification {
                    notifier.notify(body: rateLimit.description)
                }
                return
            }

            refreshState = .failed(error.gitBarMessage)
            if sendNotification {
                notifier.notify(body: error.gitBarMessage)
            }
        }
    }

    func submitReview(pullRequestId: String, event: PullRequestReviewEvent, body: String?) async {
        let token = authToken.trimmed
        guard !token.isEmpty, hasValidToken else {
            notifier.notify(body: "Cannot submit review: not authenticated.")
            return
        }

        do {
            try await client.submitReview(
                pullRequestId: pullRequestId,
                event: event,
                body: body,
                baseURL: settings.normalizedAPIBaseURL,
                token: token
            )
            clearRateLimitCooldown()
            notifier.notify(body: "Review submitted: \(event.rawValue.lowercased().replacingOccurrences(of: "_", with: " "))")
            await refresh(sendNotification: false)
        } catch {
            if let rateLimit = (error as? GitHubAPIError)?.rateLimit {
                applyRateLimitCooldown(rateLimit)
                notifier.notify(body: rateLimit.description)
                return
            }

            notifier.notify(body: "Review failed: \(error.gitBarMessage)")
        }
    }

    private func applyRateLimitCooldown(_ rateLimit: GitHubRateLimit) {
        rateLimitCooldownUntil = rateLimit.retryAt
        rateLimitMessage = rateLimit.description
    }

    private func clearRateLimitCooldown() {
        rateLimitCooldownUntil = nil
        rateLimitMessage = nil
    }

    private func activeRateLimitMessage() -> String? {
        guard let cooldownUntil = rateLimitCooldownUntil else { return nil }

        if cooldownUntil <= .now {
            clearRateLimitCooldown()
            if case .rateLimited = tokenValidator.state {
                tokenValidator.state = viewerLogin.isEmpty ? .idle : .valid(viewerLogin)
            }
            return nil
        }

        return rateLimitMessage ?? "GitHub API rate limit is still active."
    }
}

struct ReviewActionContext {
    let nodeId: String
    let prNumber: Int
    let event: PullRequestReviewEvent
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = GitBarAppModel(settings: GitBarSettingsStore())
    private var statusBarItem: NSStatusItem?
    private let menu = NSMenu()

    private var refreshTimer: Timer?
    private var debouncedConfigurationRefreshTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var preferencesWindowController: NSWindowController?
    private var aboutWindowController: NSWindowController?
    private var reviewPanel: NSPanel?
    private var reviewTextView: NSTextView?
    private var reviewNodeId: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem()
        installObservers()

        rebuildMenu()

        Task {
            await model.bootstrap()
            rebuildMenu()
            rescheduleRefreshTimer()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        debouncedConfigurationRefreshTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc
    private func handleConfigurationChange(_ notification: Notification) {
        let effect = configurationChangeEffect(from: notification)

        switch effect {
        case .refreshImmediately:
            rescheduleRefreshTimer()
            debouncedConfigurationRefreshTask?.cancel()
            Task {
                await model.refresh(sendNotification: false)
                rebuildMenu()
            }
        case .refreshDebounced:
            rescheduleRefreshTimer()
            scheduleDebouncedConfigurationRefresh()
        case .rebuildMenu:
            rebuildMenu()
        }
    }

    @objc
    private func handleAuthenticationChange() {
        Task {
            await model.validateToken(sendNotification: false)
            await model.refresh(sendNotification: false)
            rebuildMenu()
        }
    }

    @objc
    private func handleRefreshTimer() {
        Task {
            await model.refresh(sendNotification: false)
            rebuildMenu()
        }
    }

    @objc
    private func refreshNow() {
        Task {
            await model.refresh(sendNotification: true)
            rebuildMenu()
        }
    }

    @objc
    private func openRepresentedURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc
    private func approvePullRequest(_ sender: NSMenuItem) {
        guard let nodeId = sender.representedObject as? String else { return }
        Task {
            await model.submitReview(pullRequestId: nodeId, event: .approve, body: nil)
            rebuildMenu()
        }
    }

    @objc
    private func reviewPullRequestWithBody(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? ReviewActionContext else { return }
        showReviewPanel(context: context)
    }

    private func showReviewPanel(context: ReviewActionContext) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "\(context.event == .requestChanges ? "Request Changes" : "Comment") on #\(context.prNumber)"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let textView = NSTextView(frame: NSRect(x: 16, y: 50, width: 328, height: 110))
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .controlBackgroundColor

        let scrollView = NSScrollView(frame: NSRect(x: 16, y: 50, width: 328, height: 110))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let sendButton = NSButton(title: "Send", target: nil, action: nil)
        sendButton.frame = NSRect(x: 264, y: 12, width: 80, height: 28)
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"

        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.frame = NSRect(x: 176, y: 12, width: 80, height: 28)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        contentView.addSubview(scrollView)
        contentView.addSubview(sendButton)
        contentView.addSubview(cancelButton)
        panel.contentView = contentView

        sendButton.target = self
        sendButton.action = #selector(submitReviewFromPanel(_:))
        sendButton.tag = context.event == .requestChanges ? 0 : 1

        cancelButton.target = self
        cancelButton.action = #selector(closeReviewPanel(_:))

        reviewPanel = panel
        reviewTextView = textView
        reviewNodeId = context.nodeId

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        textView.window?.makeFirstResponder(textView)
    }

    @objc
    private func submitReviewFromPanel(_ sender: NSButton) {
        guard let nodeId = reviewNodeId else { return }
        let body = reviewTextView?.string ?? ""
        let event: PullRequestReviewEvent = sender.tag == 0 ? .requestChanges : .comment

        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        reviewPanel?.close()
        reviewPanel = nil
        reviewTextView = nil
        reviewNodeId = nil

        Task {
            await model.submitReview(pullRequestId: nodeId, event: event, body: body)
            rebuildMenu()
        }
    }

    @objc
    private func closeReviewPanel(_ sender: Any?) {
        reviewPanel?.close()
        reviewPanel = nil
        reviewTextView = nil
        reviewNodeId = nil
    }

    @objc
    private func openPreferencesWindow() {
        let controller = makeWindowController(
            title: "Preferences",
            size: NSSize(width: 480, height: 580),
            rootView: PreferencesView(model: model)
        )

        preferencesWindowController = controller
        controller.showWindow(self)
        controller.window?.center()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc
    private func openAboutWindow() {
        let controller = makeWindowController(
            title: "About GitBar",
            size: NSSize(width: 360, height: 420),
            rootView: AboutView()
        )

        aboutWindowController = controller
        controller.showWindow(self)
        controller.window?.center()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(self)
    }

    private func configureStatusItem() {
        guard let button = statusBarItem?.button else { return }

        button.image = makeStatusItemImage()
        button.imagePosition = .imageLeading
        button.toolTip = "GitBar"
        button.title = button.image == nil ? " GB" : ""

        statusBarItem?.menu = menu
    }

    private func installObservers() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: .gitBarConfigurationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleConfigurationChange(notification)
            }
        })

        observers.append(center.addObserver(
            forName: .gitBarAuthenticationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAuthenticationChange()
            }
        })
    }

    private func rescheduleRefreshTimer() {
        refreshTimer?.invalidate()

        let interval = TimeInterval(model.settings.refreshIntervalMinutes * 60)
        let timer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(handleRefreshTimer),
            userInfo: nil,
            repeats: true
        )

        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func configurationChangeEffect(from notification: Notification) -> GitBarConfigurationChangeEffect {
        guard
            let rawValue = notification.userInfo?["effect"] as? String,
            let effect = GitBarConfigurationChangeEffect(rawValue: rawValue)
        else {
            return .refreshImmediately
        }

        return effect
    }

    private func scheduleDebouncedConfigurationRefresh() {
        debouncedConfigurationRefreshTask?.cancel()
        debouncedConfigurationRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }

            await model.refresh(sendNotification: false)
            rebuildMenu()
            debouncedConfigurationRefreshTask = nil
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        updateStatusButton()

        if model.authToken.trimmed.isEmpty {
            let item = NSMenuItem(title: "Add a GitHub personal access token in Preferences to start.", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
            addFooterItems()
            return
        }

        if case .invalid(let message) = model.tokenValidator.state {
            let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
            addFooterItems()
            return
        }

        var addedSection = false

        for section in model.settings.enabledSections {
            let items = model.sections[section, default: []]
            guard !items.isEmpty else { continue }

            let header = NSMenuItem(title: "\(model.settings.title(for: section)) (\(items.count))", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for pullRequest in items {
                menu.addItem(makePullRequestMenuItem(for: pullRequest))
            }

            menu.addItem(.separator())
            addedSection = true
        }

        if !addedSection {
            let item = NSMenuItem(title: "No open pull requests match the current settings.", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        addFooterItems()
    }

    private func updateStatusButton() {
        guard let button = statusBarItem?.button else { return }

        let count = model.counterText().flatMap { $0 == "0" ? nil : $0 }
        button.image = makeStatusItemImage()
        button.imagePosition = button.image == nil ? .noImage : .imageLeading

        if let image = button.image {
            image.isTemplate = true
            button.title = count.map { " \($0)" } ?? ""
        } else {
            let parts = ["GB", count].compactMap { $0 }
            button.title = parts.isEmpty ? "" : " " + parts.joined(separator: " ")
        }

        button.toolTip = switch model.refreshState {
        case .idle:
            "GitBar"
        case .refreshing:
            "GitBar is refreshing…"
        case .failed(let message):
            message
        }
    }

    private func makeStatusItemImage() -> NSImage? {
        if let assetImage = NSImage(named: "git-pull-request") {
            let image = assetImage.copy() as? NSImage ?? assetImage
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }

        if let symbolImage = NSImage(
            systemSymbolName: "arrow.triangle.pull",
            accessibilityDescription: "GitBar"
        ) {
            symbolImage.size = NSSize(width: 15, height: 15)
            symbolImage.isTemplate = true
            return symbolImage
        }

        return nil
    }

    private func makePullRequestMenuItem(for pullRequest: PullRequestSummary) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: #selector(openRepresentedURL(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = pullRequest.url
        item.attributedTitle = pullRequestTitle(for: pullRequest)

        if pullRequest.title.count > 50 {
            item.toolTip = pullRequest.title
        }

        if model.settings.showAvatar {
            item.image = NSImage(named: "person")?.resized(to: NSSize(width: 36, height: 36))
            if let avatarURL = pullRequest.author.avatarUrl {
                NSImage.loadImageAsync(from: avatarURL) { [weak item] image in
                    item?.image = image?.resized(to: NSSize(width: 36, height: 36))
                }
            }
        }

        let isOwnPR = pullRequest.author.login == model.viewerLogin
        let hasReviewActions = !isOwnPR && !pullRequest.isDraft
        let hasBuildChecks = !pullRequest.buildChecks.isEmpty

        if hasReviewActions || hasBuildChecks {
            let submenu = NSMenu()

            if hasReviewActions {
                let approveItem = NSMenuItem(title: "Approve", action: #selector(approvePullRequest(_:)), keyEquivalent: "")
                approveItem.target = self
                approveItem.representedObject = pullRequest.nodeId
                approveItem.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Approve")
                submenu.addItem(approveItem)

                let requestChangesItem = NSMenuItem(title: "Request Changes…", action: #selector(reviewPullRequestWithBody(_:)), keyEquivalent: "")
                requestChangesItem.target = self
                requestChangesItem.representedObject = ReviewActionContext(nodeId: pullRequest.nodeId, prNumber: pullRequest.number, event: .requestChanges)
                requestChangesItem.image = NSImage(systemSymbolName: "arrow.uturn.backward.circle", accessibilityDescription: "Request Changes")
                submenu.addItem(requestChangesItem)

                let commentItem = NSMenuItem(title: "Comment…", action: #selector(reviewPullRequestWithBody(_:)), keyEquivalent: "")
                commentItem.target = self
                commentItem.representedObject = ReviewActionContext(nodeId: pullRequest.nodeId, prNumber: pullRequest.number, event: .comment)
                commentItem.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Comment")
                submenu.addItem(commentItem)

                if hasBuildChecks {
                    submenu.addItem(.separator())
                }
            }

            if hasBuildChecks {
                for group in pullRequest.buildChecks {
                    let groupHeader = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
                    groupHeader.isEnabled = false
                    submenu.addItem(groupHeader)

                    for check in group.items {
                        let buildItem = NSMenuItem(title: check.name, action: #selector(openRepresentedURL(_:)), keyEquivalent: "")
                        buildItem.target = self
                        buildItem.representedObject = check.detailsURL
                        buildItem.toolTip = check.subtitle
                        buildItem.image = NSImage(named: check.status.itemImageName)?.tinted(with: check.status.dotColor)
                        submenu.addItem(buildItem)
                    }
                }
            }

            item.submenu = submenu
        }

        return item
    }

    private func pullRequestTitle(for pullRequest: PullRequestSummary) -> NSAttributedString {
        let text = NSMutableAttributedString()

        if !pullRequest.isReadByViewer {
            text.appendString("⏺ ", color: .systemBlue)
        }

        if pullRequest.isDraft {
            text.appendIcon(named: "git-draft-pull-request")
        }

        text
            .appendString(pullRequest.title.trunc(length: 50), color: .labelColor)
            .appendString(" #\(pullRequest.number)", color: .secondaryLabelColor)
            .appendNewLine()
            .appendIcon(named: "repo")
            .appendString(pullRequest.repositoryName)
            .appendSeparator()
            .appendIcon(named: "person")
            .appendString(pullRequest.author.login)

        if model.settings.showLabels && !pullRequest.labels.isEmpty {
            text
                .appendNewLine()
                .appendIcon(named: "tag")

            for label in pullRequest.labels {
                text
                    .appendString(label.name, color: hexColor(label.color), font: .systemFont(ofSize: NSFont.smallSystemFontSize))
                    .appendSeparator()
            }
        }

        text
            .appendNewLine()
            .appendIcon(
                named: "check-circle",
                color: pullRequest.approvedByViewer
                    ? (NSColor(named: "green") ?? .systemGreen)
                    : .secondaryLabelColor
            )
            .appendString("\(pullRequest.approvalCount)")
            .appendSeparator()
            .appendString("+\(pullRequest.additions)", color: NSColor(named: "green") ?? .systemGreen)
            .appendString(" -\(pullRequest.deletions)", color: NSColor(named: "red") ?? .systemRed)
            .appendSeparator()
            .appendIcon(named: "calendar")
            .appendString(pullRequest.createdAt.gitBarRelativeDescription())

        if !pullRequest.buildChecks.isEmpty {
            text.appendSeparator().appendIcon(named: "checklist")
            for group in pullRequest.buildChecks {
                for item in group.items {
                    text.appendIcon(named: "dot-fill", color: item.status.dotColor, size: NSSize(width: 8, height: 8))
                }
            }
        }

        return text
    }

    private func addFooterItems() {
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        let preferences = NSMenuItem(title: "Preferences…", action: #selector(openPreferencesWindow), keyEquivalent: "")
        preferences.target = self
        menu.addItem(preferences)

        let about = NSMenuItem(title: "About GitBar", action: #selector(openAboutWindow), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    private func makeWindowController<Content: View>(title: String, size: NSSize, rootView: Content) -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.styleMask.remove(.resizable)
        return NSWindowController(window: window)
    }

}
