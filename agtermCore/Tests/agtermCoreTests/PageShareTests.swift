import Foundation
import Testing
@testable import agtermCore

/// FakeGitLab answers each call from a queue per `METHOD path`, repeating the last answer once the queue runs out.
private actor FakeGitLab: GitLabTransport {
    private var routes: [String: [(Int, String)]]
    private(set) var requests: [URLRequest] = []

    init(_ routes: [String: [(Int, String)]]) {
        self.routes = routes
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = request.url?.absoluteString.components(separatedBy: "/api/v4/projects/team%2Fsnippets/").last ?? ""
        let key = "\(request.httpMethod ?? "") \(path)"
        guard let queue = routes[key], let answer = queue.first else { return (Data(#"{"message":"404 Not Found"}"#.utf8), 404) }
        if queue.count > 1 { routes[key] = Array(queue.dropFirst()) }
        return (Data(answer.1.utf8), answer.0)
    }

    func keys() -> [String] {
        requests.map { "\($0.httpMethod ?? "") \($0.url?.absoluteString.components(separatedBy: "/team%2Fsnippets/").last ?? "")" }
    }
}

@MainActor
struct PageShareTests {
    private let config = PageShareConfig(gitLabURL: "https://gitlab.example.com/", project: "team/snippets", token: "secret")!

    private func page(_ text: String = "<h1>hi</h1>") throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString).html")
        try Data(text.utf8).write(to: url)
        return url.path
    }

    private func shares() -> PageShares {
        let shares = PageShares()
        shares.pollInterval = .zero
        return shares
    }

    private func routes(for path: String, file: (Int, String), pipelines: [(Int, String)]) -> [String: [(Int, String)]] {
        let id = PageShares.id(forFile: path)
        return [
            "GET pages": [(200, #"{"url":"https://snippets.pages.example.com/"}"#)],
            "GET repository/files/snippets%2F\(id)%2Findex.html?ref=main": [file],
            "POST repository/commits": [(201, #"{"id":"c0ffee"}"#)],
            "GET pipelines?sha=c0ffee": pipelines,
        ]
    }

    private func settle(_ shares: PageShares, _ path: String) async throws {
        for _ in 0..<400 where shares.share(forFile: path)?.state == .publishing {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func theIDIsTwelveHexDigitsOfTheStandardizedPath() {
        let id = PageShares.id(forFile: "/tmp/a/page.html")
        #expect(id.count == 12)
        #expect(id.allSatisfy { $0.isHexDigit })
        #expect(PageShares.id(forFile: "/tmp/a/../a/./page.html") == id)
        #expect(PageShares.id(forFile: "/tmp/b/page.html") != id)
    }

    @Test func theConfigNeedsAllThreeAndDropsTrailingSlashes() {
        #expect(config.baseURL == "https://gitlab.example.com")
        #expect(PageShareConfig(gitLabURL: "https://gitlab.example.com", project: " ", token: "t") == nil)
        #expect(PageShareConfig(gitLabURL: nil, project: "p", token: "t") == nil)
        #expect(PageShareConfig(gitLabURL: "https://g", project: "p", token: nil) == nil)
    }

    @Test func aNewFileIsCreatedThenDeployed() async throws {
        let path = try page()
        let gitLab = FakeGitLab(routes(for: path, file: (404, #"{"message":"404 File Not Found"}"#), pipelines: [
            (200, "[]"),
            (200, #"[{"status":"running","web_url":"https://gitlab.example.com/p/1"}]"#),
            (200, #"[{"status":"success","web_url":"https://gitlab.example.com/p/1"}]"#),
        ]))
        let shares = shares()
        var link: String?

        let share = await shares.publish(file: path, config: config, transport: gitLab) { link = $0 }

        let url = "https://snippets.pages.example.com/\(PageShares.id(forFile: path))/"
        #expect(link == url)
        #expect(share == PageShare(url: url, state: .publishing))
        try await settle(shares, path)
        #expect(shares.share(forFile: path) == PageShare(url: url, state: .idle, pipelineURL: "https://gitlab.example.com/p/1"))
        let commit = try #require(await gitLab.requests.first { $0.httpMethod == "POST" })
        #expect(commit.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "secret")
        let body = try #require(try JSONSerialization.jsonObject(with: commit.httpBody ?? Data()) as? [String: Any])
        #expect(body["branch"] as? String == "main")
        let action = try #require((body["actions"] as? [[String: String]])?.first)
        #expect(action["action"] == "create")
        #expect(action["file_path"] == "snippets/\(PageShares.id(forFile: path))/index.html")
        #expect(action["encoding"] == "base64")
        #expect(action["content"] == Data("<h1>hi</h1>".utf8).base64EncodedString())
    }

    @Test func bytesGitLabAlreadyHoldsAreNotCommitted() async throws {
        let path = try page()
        let sha = PageShares.sha256(Data("<h1>hi</h1>".utf8))
        let gitLab = FakeGitLab(routes(for: path, file: (200, #"{"content_sha256":"\#(sha)"}"#), pipelines: []))

        let share = await shares().publish(file: path, config: config, transport: gitLab)

        #expect(share.state == .idle)
        #expect(await gitLab.keys().allSatisfy { $0.hasPrefix("GET") })
    }

    @Test func changedBytesUpdateTheFileAndAFinishedPipelineEndsIdle() async throws {
        let path = try page()
        let gitLab = FakeGitLab(routes(for: path, file: (200, #"{"content_sha256":"0000"}"#), pipelines: [
            (200, #"[{"status":"success","web_url":"https://gitlab.example.com/p/2"}]"#),
        ]))

        let share = await shares().publish(file: path, config: config, transport: gitLab)

        #expect(share.state == .idle)
        #expect(share.pipelineURL == "https://gitlab.example.com/p/2")
        let commit = try #require(await gitLab.requests.first { $0.httpMethod == "POST" })
        let body = try #require(try JSONSerialization.jsonObject(with: commit.httpBody ?? Data()) as? [String: Any])
        #expect((body["actions"] as? [[String: String]])?.first?["action"] == "update")
    }

    @Test func aRefusedCallFailsWithGitLabsMessage() async throws {
        let path = try page()
        let gitLab = FakeGitLab(["GET pages": [(401, #"{"message":"401 Unauthorized"}"#)]])

        let share = await shares().publish(file: path, config: config, transport: gitLab)

        #expect(share == PageShare(url: nil, state: .failed, error: "GitLab 401: 401 Unauthorized"))
        #expect(share.response(session: UUID()) == ControlResponse(ok: false, error: "GitLab 401: 401 Unauthorized"))
    }

    @Test func aFailedPipelineFailsTheShareAndKeepsItsLink() async throws {
        let path = try page()
        let gitLab = FakeGitLab(routes(for: path, file: (404, "{}"), pipelines: [
            (200, #"[{"status":"failed","web_url":"https://gitlab.example.com/p/3"}]"#),
        ]))

        let share = await shares().publish(file: path, config: config, transport: gitLab)

        #expect(share.state == .failed)
        #expect(share.error == "pipeline failed")
        #expect(share.pipelineURL == "https://gitlab.example.com/p/3")
    }

    @Test func aPipelineThatNeverFinishesStopsSpinning() async throws {
        let path = try page()
        let gitLab = FakeGitLab(routes(for: path, file: (404, "{}"), pipelines: [
            (200, #"[{"status":"pending","web_url":"https://gitlab.example.com/p/4"}]"#),
        ]))
        let shares = shares()
        shares.pollLimit = .zero

        _ = await shares.publish(file: path, config: config, transport: gitLab)

        try await settle(shares, path)
        #expect(shares.share(forFile: path)?.state == .failed)
        #expect(shares.share(forFile: path)?.error == PageShareError.timedOut)
    }

    @Test func aShareInFlightIsReturnedWithoutCallingGitLab() async throws {
        let path = try page()
        let gitLab = FakeGitLab([:])
        let shares = shares()
        let inFlight = PageShare(url: "https://x/1/", state: .publishing, pipelineURL: "https://p/9")
        shares.shares[PageShares.id(forFile: path)] = inFlight

        #expect(await shares.publish(file: path, config: config, transport: gitLab) == inFlight)
        #expect(await gitLab.requests.isEmpty)
    }

    @Test func thePagesAddressIsAskedOnce() async throws {
        let path = try page()
        let sha = PageShares.sha256(Data("<h1>hi</h1>".utf8))
        let gitLab = FakeGitLab(routes(for: path, file: (200, #"{"content_sha256":"\#(sha)"}"#), pipelines: []))
        let shares = shares()

        _ = await shares.publish(file: path, config: config, transport: gitLab)
        _ = await shares.publish(file: path, config: config, transport: gitLab)

        #expect(await gitLab.keys().filter { $0 == "GET pages" }.count == 1)
    }

    @Test func theReplyCarriesTheLinkAsTextAndTheShare() {
        let session = UUID()
        let share = PageShare(url: "https://x/1/", state: .publishing, pipelineURL: "https://p/1")

        let response = share.response(session: session)

        #expect(response == ControlResponse(ok: true, result: ControlResult(id: session.uuidString, text: "https://x/1/",
                                                                             share: share.node)))
        #expect(share.node == ControlPageShareNode(url: "https://x/1/", state: "publishing", pipelineURL: "https://p/1"))
    }
}
