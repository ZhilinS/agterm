import SwiftUI
import agtermCore

/// Sharing tab: where an HTML page's Share button publishes. All three fields set show the button.
struct SharingSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section("GitLab Pages") {
                TextField("GitLab URL", text: gitLabURL, prompt: Text("https://gitlab.example.com"))
                    .accessibilityIdentifier("settings-share-gitlab-url")
                TextField("Project", text: project, prompt: Text("group/project"))
                    .accessibilityIdentifier("settings-share-gitlab-project")
                SecureField("Access token", text: token, prompt: Text("api scope"))
                    .accessibilityIdentifier("settings-share-gitlab-token")
                Text("The token is kept in the Keychain. A shared page lands at <pages URL>/<id>/.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var gitLabURL: Binding<String> {
        Binding(get: { model.settings.shareGitLabURL ?? "" }, set: { model.setShareGitLabURL($0) })
    }

    private var project: Binding<String> {
        Binding(get: { model.settings.shareGitLabProject ?? "" }, set: { model.setShareGitLabProject($0) })
    }

    private var token: Binding<String> {
        Binding(get: { PageSharing.shared.token ?? "" }, set: { PageSharing.shared.setToken($0) })
    }
}
