import Foundation
import Observation
import os
import Security
import agtermCore

private let logger = Logger(subsystem: "com.umputun.agterm", category: "PageSharing")

/// PageSharing is the app side of Share: the token in the Keychain, the URLSession transport and the clipboard.
/// The share, its state and its GitLab calls are `PageShares` in agtermCore.
@MainActor
@Observable
final class PageSharing {
    static let shared = PageSharing()

    /// settings supplies the GitLab URL and project; agtermApp points it at the settings model.
    @ObservationIgnored var settings: @MainActor () -> AppSettings = { AppSettings() }
    @ObservationIgnored var transport: any GitLabTransport = URLSessionGitLabTransport()
    /// token is what the Keychain holds; `setToken` is the write that keeps it there.
    var token: String?

    private init() {
        token = TokenKeychain.read()
    }

    /// config is nil until the URL, project and token are all set, which is what hides the Share button.
    var config: PageShareConfig? {
        let settings = settings()
        return PageShareConfig(gitLabURL: settings.shareGitLabURL, project: settings.shareGitLabProject, token: token)
    }

    func setToken(_ value: String) {
        token = value.isEmpty ? nil : value
        TokenKeychain.write(token)
    }

    /// share publishes the page at `path`; with `copyLink` its link goes on the clipboard as soon as it is known.
    /// nil when sharing is not configured.
    @discardableResult
    func share(file path: String, copyLink: Bool) async -> PageShare? {
        guard let config else { return nil }
        return await PageShares.shared.publish(file: path, config: config, transport: transport) { url in
            if copyLink {
                HtmlOverlayRegistry.shared.sharing.copy(url)
            }
        }
    }
}

struct URLSessionGitLabTransport: GitLabTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// TokenKeychain keeps the GitLab token as a generic password, per bundle id, so a Debug build has its own.
private enum TokenKeychain {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(Bundle.main.bundleIdentifier ?? "com.umputun.agterm").gitlab-token",
            kSecAttrAccount as String: "gitlab",
        ]
    }

    static func read() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func write(_ token: String?) {
        SecItemDelete(query as CFDictionary)
        guard let token else { return }
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("could not save the GitLab token to the Keychain: \(status)")
        }
    }
}
