import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(.rect(cornerRadius: 16))

            VStack(spacing: 4) {
                Text("GitBar")
                    .font(.title2)
                    .bold()

                Text("GitHub pull requests in the macOS menu bar")
                    .foregroundStyle(.secondary)

                Text("Version \(version)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Button("Open PullBar Reference") {
                    openURL(URL(string: "https://github.com/menubar-apps/PullBar")!)
                }

                Button("GitHub Token Setup") {
                    openURL(URL(string: "https://github.com/settings/tokens")!)
                }

                Button("GitHub Search Syntax") {
                    openURL(URL(string: "https://docs.github.com/en/search-github/getting-started-with-searching-on-github/understanding-the-search-syntax")!)
                }
            }
            .buttonStyle(.link)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            StatusLegendView()

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 340, height: 400)
    }
}
