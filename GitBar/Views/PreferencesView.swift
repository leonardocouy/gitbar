import SwiftUI

struct PreferencesView: View {
    let model: GitBarAppModel

    var body: some View {
        Form {
            authenticationSection
            pullRequestsSection
            refreshSection
            displaySection
            advancedSection
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 580)
    }

    // MARK: - Authentication

    private var authenticationSection: some View {
        Section {
            SecureField("Personal access token", text: tokenBinding)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Label(model.tokenValidator.description, systemImage: model.tokenValidator.symbolName)
                    .foregroundStyle(Color(nsColor: model.tokenValidator.color))

                Spacer()

                Button("Validate") {
                    Task {
                        await model.validateToken(sendNotification: true)
                    }
                }
                .buttonStyle(.glassProminent)
            }

            if !model.viewerLogin.isEmpty {
                LabeledContent("Signed in as") {
                    Text(model.viewerLogin)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Authentication", systemImage: "lock.shield")
        } footer: {
            Text("Generate a personal access token with repository read access. Stored securely in the macOS Keychain.")
        }
        .task(id: model.authToken) {
            await model.validateToken(sendNotification: false)
        }
    }

    // MARK: - Pull Requests

    private var pullRequestsSection: some View {
        Section {
            Toggle("Assigned", isOn: setting(\.showAssigned))
            Toggle("Created", isOn: setting(\.showCreated))
            Toggle("Review requested", isOn: setting(\.showReviewRequested))
            Toggle("Custom section", isOn: setting(\.showCustom))

            if model.settings.showCustom {
                TextField("Section title", text: setting(\.customSectionTitle))
                    .textFieldStyle(.roundedBorder)

                TextField("GitHub search query", text: setting(\.customSectionQuery))
                    .textFieldStyle(.roundedBorder)
            }
        } header: {
            Label("Pull Requests", systemImage: "arrow.triangle.branch")
        } footer: {
            Text("Custom section uses any valid GitHub PR search, such as `author:alice`, `org:softaworks label:bug`, or `team-review-requested:platform`.")
        }
    }

    // MARK: - Refresh

    private var refreshSection: some View {
        Section {
            Picker("Interval", selection: setting(\.refreshIntervalMinutes)) {
                ForEach(GitBarSettingsStore.refreshIntervals, id: \.self) { value in
                    Text("\(value) min").tag(value)
                }
            }

            Toggle("Launch at login", isOn: setting(\.launchesAtLogin))
        } header: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        Section {
            Toggle("Show avatars", isOn: setting(\.showAvatar))
            Toggle("Show labels", isOn: setting(\.showLabels))

            Picker("Counter mode", selection: setting(\.counterMode)) {
                ForEach(CounterMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("Build status", selection: setting(\.buildInfoMode)) {
                ForEach(BuildInfoMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            StatusLegendView()
                .font(.caption)
        } header: {
            Label("Display", systemImage: "paintbrush")
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        Section {
            TextField("https://api.github.com", text: setting(\.githubAPIBaseURL))
                .textFieldStyle(.roundedBorder)

            TextField("Additional search query", text: setting(\.githubAdditionalQuery))
                .textFieldStyle(.roundedBorder)
        } header: {
            Label("Advanced", systemImage: "slider.horizontal.3")
        } footer: {
            Text("Append valid GitHub search syntax such as `org:your-org` or `label:critical`.")
        }
    }

    // MARK: - Bindings

    private var tokenBinding: Binding<String> {
        Binding(
            get: { model.authToken },
            set: { model.authToken = $0 }
        )
    }

    private func setting<Value>(_ keyPath: ReferenceWritableKeyPath<GitBarSettingsStore, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { model.settings[keyPath: keyPath] = $0 }
        )
    }
}
