import CryptoKit
import Foundation
import Observation

/// PageShareConfig is where `session.overlay.share` publishes: a GitLab instance, a project path or id, and an
/// access token. nil unless all three are set, which is also what shows the Share button. `oauthAppID` is the
/// optional GitLab OAuth application a published page signs its viewers in with to comment.
public struct PageShareConfig: Equatable, Sendable {
    public let baseURL: String
    public let project: String
    public let token: String
    public let oauthAppID: String?

    public init?(gitLabURL: String?, project: String?, token: String?, oauthAppID: String? = nil) {
        guard var base = gitLabURL?.trimmedOrNil,
              let project = project?.trimmedOrNil,
              let token = token?.trimmedOrNil else { return nil }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        self.baseURL = base
        self.project = project
        self.token = token
        self.oauthAppID = oauthAppID?.trimmedOrNil
    }
}

/// GitLabTransport sends one GitLab API request and returns its body and HTTP status.
public protocol GitLabTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public enum PageShareState: String, Sendable {
    case idle, publishing, failed
}

/// PageShare is one page's share: its link once known, where it stands, the pipeline deploying it, and why it
/// failed.
public struct PageShare: Equatable, Sendable {
    public var url: String?
    public var state: PageShareState
    public var pipelineURL: String?
    public var error: String?

    public var node: ControlPageShareNode {
        ControlPageShareNode(url: url, state: state.rawValue, pipelineURL: pipelineURL, error: error)
    }

    /// response is the `session.overlay.share` reply: the link as text and the share in full, or the failure.
    public func response(session: UUID) -> ControlResponse {
        if state == .failed {
            return ControlResponse(ok: false, error: error)
        }
        return ControlResponse(ok: true, result: ControlResult(id: session.uuidString, text: url, share: node))
    }
}

/// ControlPageShareNode is a page's share as `tree` (`htmlOverlays[].share`) and `session.overlay.share` report it.
public struct ControlPageShareNode: Codable, Sendable, Equatable {
    public let url: String?
    /// state is `idle`, `publishing` or `failed`.
    public let state: String
    public let pipelineURL: String?
    public let error: String?

    public init(url: String?, state: String, pipelineURL: String? = nil, error: String? = nil) {
        self.url = url
        self.state = state
        self.pipelineURL = pipelineURL
        self.error = error
    }
}

public enum PageShareError {
    public static let notConfigured = "sharing is not configured: set the GitLab URL, project and token in Settings > Sharing"
    public static let notFile = "only a file page can be shared"
    public static let noComments = "comments are not configured: set the OAuth Application ID in Settings > Sharing"
    static let timedOut = "the pipeline did not finish in 5 minutes"
}

/// PageShares publishes file pages to GitLab Pages and keeps each share in memory by `id(forFile:)`, so a file
/// shared again lands on the same URL and the button, the tree and the control reply read one state.
@MainActor
@Observable
public final class PageShares {
    public static let shared = PageShares()

    public internal(set) var shares: [String: PageShare] = [:]
    @ObservationIgnored var pollInterval: Duration = .milliseconds(2500)
    @ObservationIgnored var pollLimit: Duration = .seconds(300)
    @ObservationIgnored private var pagesURLs: [String: String] = [:]

    init() {}

    /// id is the first 12 hex digits of the SHA-256 of the standardized path: the page's folder on GitLab Pages.
    public nonisolated static func id(forFile path: String) -> String {
        String(sha256(Data(URL(fileURLWithPath: path).standardizedFileURL.path.utf8)).prefix(12))
    }

    public func share(forFile path: String) -> PageShare? {
        shares[Self.id(forFile: path)]
    }

    /// publish puts the file at `path` on GitLab Pages, handing its link to `onLink` before anything is uploaded.
    /// It returns once the commit landed, or at once when GitLab already holds these bytes, and polls the
    /// pipeline after that. A share still publishing is returned as it is.
    @discardableResult
    public func publish(file path: String, config: PageShareConfig, transport: any GitLabTransport,
                        onLink: (String) -> Void = { _ in }) async -> PageShare {
        let id = Self.id(forFile: path)
        if let current = shares[id], current.state == .publishing {
            return current
        }
        var share = PageShare(url: shares[id]?.url, state: .publishing)
        shares[id] = share
        let gitLab = GitLab(config: config, transport: transport)
        do {
            let url = try await pagesURL(gitLab) + "/\(id)/"
            share.url = url
            shares[id] = share
            onLink(url)
            let actions = try await uploads(path, id: id, url: url, gitLab: gitLab)
            let message = "Share \(URL(fileURLWithPath: path).lastPathComponent)"
            if let commit = try await commit(actions, message: message, gitLab: gitLab) {
                let finished = try await gitLab.pipeline(sha: commit).map { Self.advance(&share, $0) } ?? false
                if !finished {
                    Task { await poll(id, commit: commit, gitLab: gitLab) }
                }
            } else {
                share.state = .idle
            }
        } catch {
            share.state = .failed
            share.error = error.localizedDescription
        }
        shares[id] = share
        return share
    }

    /// uploads are the commit actions a share needs, none when GitLab already holds every byte. With comments on
    /// they add the site's callback page, and the page's issue is made sure of first.
    private func uploads(_ path: String, id: String, url: String, gitLab: GitLab) async throws -> [[String: String]] {
        let content = try Data(contentsOf: URL(fileURLWithPath: path))
        let file = "snippets/\(id)/index.html"
        guard let appID = gitLab.config.oauthAppID else {
            return try await [gitLab.write(file, content)].compactMap { $0 }
        }
        try await gitLab.ensureIssue(page: id, title: PageComments.title(content, file: path), url: url)
        return try await [
            gitLab.write(file, PageComments.page(content, config: gitLab.config, appID: appID)),
            gitLab.write(PageComments.callbackFile, PageComments.callback(config: gitLab.config, appID: appID)),
        ].compactMap { $0 }
    }

    /// commit sends `actions` and returns the commit id, nil when there is nothing to send. A refused commit that
    /// wrote the callback page is rebuilt from its current SHA and retried once: two pages shared at the same moment
    /// can both see it absent and both create it.
    private func commit(_ actions: [[String: String]], message: String, gitLab: GitLab) async throws -> String? {
        guard !actions.isEmpty else { return nil }
        do {
            return try await gitLab.commit(actions, message: message)
        } catch let error as GitLabError {
            guard let callback = actions.first(where: { $0["file_path"] == PageComments.callbackFile }),
                  let content = callback["content"].flatMap({ Data(base64Encoded: $0) }) else { throw error }
            let rebuilt = try await actions.filter { $0 != callback }
                + [gitLab.write(PageComments.callbackFile, content)].compactMap { $0 }
            return rebuilt.isEmpty ? nil : try await gitLab.commit(rebuilt, message: message)
        }
    }

    private func pagesURL(_ gitLab: GitLab) async throws -> String {
        let key = "\(gitLab.config.baseURL)|\(gitLab.config.project)"
        if let cached = pagesURLs[key] {
            return cached
        }
        var url = try await gitLab.pagesURL()
        while url.hasSuffix("/") {
            url.removeLast()
        }
        pagesURLs[key] = url
        return url
    }

    private func poll(_ id: String, commit: String, gitLab: GitLab) async {
        let deadline = ContinuousClock.now + pollLimit
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
            guard var share = shares[id] else { return }
            do {
                guard let pipeline = try await gitLab.pipeline(sha: commit) else { continue }
                let finished = Self.advance(&share, pipeline)
                shares[id] = share
                if finished { return }
            } catch {
                shares[id]?.state = .failed
                shares[id]?.error = error.localizedDescription
                return
            }
        }
        shares[id]?.state = .failed
        shares[id]?.error = PageShareError.timedOut
    }

    /// advance records what the pipeline says and returns whether it finished.
    private static func advance(_ share: inout PageShare, _ pipeline: GitLab.Pipeline) -> Bool {
        share.pipelineURL = pipeline.webUrl
        switch pipeline.status {
        case "success":
            share.state = .idle
            return true
        case "failed", "canceled", "skipped":
            share.state = .failed
            share.error = "pipeline \(pipeline.status)"
            return true
        default:
            return false
        }
    }

    nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// GitLab is the handful of project API calls a share makes, all on `branch`.
struct GitLab: Sendable {
    static let branch = "main"
    let config: PageShareConfig
    let transport: any GitLabTransport

    struct Pipeline: Decodable {
        let status: String
        let webUrl: String
    }

    func pagesURL() async throws -> String {
        struct Pages: Decodable { let url: String }
        return try decode(Pages.self, try await call("GET", "pages")).url
    }

    /// fileSHA is the SHA-256 GitLab holds for `file` on the branch, nil when the file is not there.
    func fileSHA(_ file: String) async throws -> String? {
        struct File: Decodable { let contentSha256: String }
        do {
            return try decode(File.self, try await call("GET", "repository/files/\(Self.encode(file))?ref=\(Self.branch)"))
                .contentSha256
        } catch let error as GitLabError where error.status == 404 {
            return nil
        }
    }

    /// write is the commit action putting `content` at `file`, nil when GitLab already holds these bytes.
    func write(_ file: String, _ content: Data) async throws -> [String: String]? {
        let published = try await fileSHA(file)
        guard published != PageShares.sha256(content) else { return nil }
        return [
            "action": published == nil ? "create" : "update",
            "file_path": file,
            "content": content.base64EncodedString(),
            "encoding": "base64",
        ]
    }

    /// commit applies `actions` in one commit and returns the commit id.
    func commit(_ actions: [[String: String]], message: String) async throws -> String {
        struct Commit: Decodable { let id: String }
        let body: [String: Any] = ["branch": Self.branch, "commit_message": message, "actions": actions]
        let data = try await call("POST", "repository/commits", body: try JSONSerialization.data(withJSONObject: body))
        return try decode(Commit.self, data).id
    }

    /// pipeline is the newest pipeline for `sha`, nil until GitLab has created one.
    func pipeline(sha: String) async throws -> Pipeline? {
        try decode([Pipeline].self, try await call("GET", "pipelines?sha=\(sha)")).first
    }

    func call(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        let address = "\(config.baseURL)/api/v4/projects/\(Self.encode(config.project))/\(path)"
        guard let url = URL(string: address) else { throw GitLabError(message: "invalid GitLab URL: \(config.baseURL)") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(config.token, forHTTPHeaderField: "PRIVATE-TOKEN")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, status) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw GitLabError(status: status, body: data) }
        return data
    }

    func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    /// encode makes `value` one path segment, as GitLab wants a project path and a file path.
    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? value
    }
}

/// GitLabError carries GitLab's own message for a refused call.
struct GitLabError: LocalizedError {
    let message: String
    let status: Int?

    var errorDescription: String? { message }

    init(message: String) {
        self.message = message
        status = nil
    }

    init(status: Int, body: Data) {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let detail = json?["message"].map { "\($0)" }
            ?? json?["error_description"] as? String
            ?? json?["error"] as? String
            ?? HTTPURLResponse.localizedString(forStatusCode: status)
        message = "GitLab \(status): \(detail)"
        self.status = status
    }
}
