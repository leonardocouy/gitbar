import SwiftUI

struct PreferencesView: View {
    let model: GitBarAppModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                generalTab
            }

            Tab("Authentication", systemImage: "lock") {
                authenticationTab
            }

            Tab("Display", systemImage: "rectangle.grid.1x2") {
                displayTab
            }

            Tab("Advanced", systemImage: "slider.horizontal.3") {
                advancedTab
            }
        }
        .padding(20)
        .frame(width: 720, height: 520)
    }

    private var generalTab: some View {
        Form {
            Section("Pull Request Sections") {
                Toggle("Show assigned pull requests", isOn: setting(\.showAssigned))
                Toggle("Show created pull requests", isOn: setting(\.showCreated))
                Toggle("Show review requested pull requests", isOn: setting(\.showReviewRequested))
            }

            Section("Refresh") {
                Picker("Refresh interval", selection: setting(\.refreshIntervalMinutes)) {
                    ForEach(GitBarSettingsStore.refreshIntervals, id: \.self) { value in
                        Text("\(value) minute\(value == 1 ? "" : "s")").tag(value)
                    }
                }

                Toggle("Launch at login", isOn: setting(\.launchesAtLogin))
            }

            Section {
                SettingsHintView(
                    title: "Token-only authentication",
                    message: "GitBar validates the personal access token and discovers the viewer account automatically."
                )
            }
        }
    }

    private var authenticationTab: some View {
        Form {
            Section("GitHub Personal Access Token") {
                SecureField("Paste PAT", text: tokenBinding)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Label(model.tokenValidator.description, systemImage: model.tokenValidator.symbolName)
                        .foregroundStyle(Color(nsColor: model.tokenValidator.color))

                    Button("Validate") {
                        Task {
                            await model.validateToken(sendNotification: true)
                        }
                    }
                }

                if !model.viewerLogin.isEmpty {
                    LabeledContent("Viewer") {
                        Text(model.viewerLogin)
                    }
                }
            }

            Section {
                Text("Generate a personal access token with repository read access and store it securely in the macOS keychain.")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: model.authToken) {
            await model.validateToken(sendNotification: false)
        }
    }

    private var displayTab: some View {
        Form {
            Section("Menu Content") {
                Toggle("Show avatars", isOn: setting(\.showAvatar))
                Toggle("Show labels", isOn: setting(\.showLabels))
            }

            Section("Menu Bar Counter") {
                Picker("Counter mode", selection: setting(\.counterMode)) {
                    ForEach(CounterMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section("Build Information") {
                Picker("Build status mode", selection: setting(\.buildInfoMode)) {
                    ForEach(BuildInfoMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                StatusLegendView()
            }
        }
    }

    private var advancedTab: some View {
        Form {
            Section("GitHub API") {
                TextField("https://api.github.com", text: setting(\.githubAPIBaseURL))
                    .textFieldStyle(.roundedBorder)

                TextField("Additional search query", text: setting(\.githubAdditionalQuery))
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                Text("Use the additional query field to append valid GitHub search syntax such as `org:your-org` or `label:critical`.")
                    .foregroundStyle(.secondary)
            }
        }
    }

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

