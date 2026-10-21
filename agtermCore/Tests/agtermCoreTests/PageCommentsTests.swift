import Foundation
import Testing
@testable import agtermCore

/// CommentsGitLab answers `METHOD path` from a queue and records every request, each issue it was asked to create, and
/// each commit as its file paths mapped to decoded contents.
private actor CommentsGitLab: GitLabTransport {
    private var routes: [String: [(Int, String)]]
    private(set) var keys: [String] = []
    private(set) var issuePosts: [[String: String]] = []
    private(set) var files: [[String: String]] = []

    init(_ routes: [String: [(Int, String)]]) {
        self.routes = routes
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.absoluteString.components(separatedBy: "/api/v4/projects/team%2Fsnippets/").last ?? ""
        let key = "\(request.httpMethod ?? "") \(path)"
        keys.append(key)
        let body = try request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if key == "POST issues", let body = body as? [String: String] {
            issuePosts.append(body)
        }
        if key == "POST repository/commits", let actions = body?["actions"] as? [[String: String]] {
            files.append(Dictionary(uniqueKeysWithValues: actions.map {
                ($0["file_path"] ?? "", String(decoding: Data(base64Encoded: $0["content"] ?? "") ?? Data(), as: UTF8.self))
            }))
        }
        guard let queue = routes[key], let answer = queue.first else { return (Data(#"{"message":"404 Not Found"}"#.utf8), 404) }
        if queue.count > 1 { routes[key] = Array(queue.dropFirst()) }
        return (Data(answer.1.utf8), answer.0)
    }
}

@MainActor
struct PageCommentsTests {
    private let config = PageShareConfig(gitLabURL: "https://gitlab.example.com", project: "team/snippets", token: "secret",
                                         oauthAppID: "app-1")!

    private func page(_ text: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("comments-\(UUID().uuidString).html")
        try Data(text.utf8).write(to: url)
        return url.path
    }

    private func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    private let metas = #"<meta name="gl-url" content="https://gitlab.example.com"><meta name="gl-project" content="team/snippets">"#
        + #"<meta name="gl-app-id" content="app-1">"#

    private func issues(_ id: String) -> String {
        "GET issues?in=title&search=\(id)&state=all&order_by=created_at&sort=asc&per_page=20"
    }

    private func routes(_ path: String, issues found: String, page: (Int, String) = (404, "{}"),
                        callback: (Int, String) = (404, "{}")) -> [String: [(Int, String)]] {
        let id = PageShares.id(forFile: path)
        return [
            "GET pages": [(200, #"{"url":"https://snippets.pages.example.com"}"#)],
            issues(id): [(200, found)],
            "POST issues": [(201, #"{"iid":7,"title":"x"}"#)],
            "GET repository/files/snippets%2F\(id)%2Findex.html?ref=main": [page],
            "GET repository/files/snippets%2Fcallback.html?ref=main": [callback],
            "POST repository/commits": [(201, #"{"id":"c0ffee"}"#)],
            "GET pipelines?sha=c0ffee": [(200, #"[{"status":"success","web_url":"https://gitlab.example.com/p/1"}]"#)],
        ]
    }

    @Test func theMetaTagsFollowTheFirstHeadTagWhateverItsCasingOrAttributes() {
        #expect(text(PageComments.page(Data("<html><HEAD lang=\"ru\"><title>t</title></head>".utf8), config: config, appID: "app-1"))
            == "<html><HEAD lang=\"ru\">\(metas)<title>t</title></head>")
        #expect(text(PageComments.page(Data("<header>x</header><head>".utf8), config: config, appID: "app-1"))
            == "<header>x</header><head>\(metas)")
    }

    @Test func aPageWithoutAHeadGetsTheMetaTagsFirst() {
        #expect(text(PageComments.page(Data("<h1>hi</h1>".utf8), config: config, appID: "app-1")) == metas + "<h1>hi</h1>")
    }

    @Test func theMetaValuesAreAttributeEscaped() {
        let page = text(PageComments.page(Data("<head>".utf8), config: config, appID: #"a"b<c>&'d"#))
        #expect(page.contains(#"<meta name="gl-app-id" content="a&quot;b&lt;c&gt;&amp;&#39;d">"#))
    }

    @Test func theTitleIsThePagesTitleElseTheFileName() {
        #expect(PageComments.title(Data("<title>\n Plan </title>".utf8), file: "/tmp/a.html") == "Plan")
        #expect(PageComments.title(Data("<title> </title>".utf8), file: "/tmp/a.html") == "a.html")
    }

    @Test func theCallbackCarriesTheInstanceAndTheAppAsScriptStrings() {
        let callback = text(PageComments.callback(config: config, appID: "app</script>"))
        #expect(callback.contains(#"const GITLAB = "https:\/\/gitlab.example.com";"#))
        #expect(callback.contains(#"const APP_ID = "app<\/script>";"#))
        #expect(!callback.contains("{{"))
    }

    @Test func aFirstShareCreatesTheIssueAndCommitsThePageWithTheCallback() async throws {
        let path = try page("<head><title>Plan</title></head>")
        let id = PageShares.id(forFile: path)
        let gitLab = CommentsGitLab(routes(path, issues: #"[{"iid":3,"title":"Комментарии · other · x"}]"#))

        let share = await PageShares().publish(file: path, config: config, transport: gitLab)

        #expect(share.state == .idle)
        let issue = try #require(await gitLab.issuePosts.first)
        #expect(issue["title"] == "Комментарии · \(id) · Plan")
        #expect(issue["description"] == "https://snippets.pages.example.com/\(id)/")
        let files = await gitLab.files
        #expect(files.count == 1)
        #expect(files.first?["snippets/\(id)/index.html"] == "<head>\(metas)<title>Plan</title></head>")
        #expect(files.first?["snippets/callback.html"] == text(PageComments.callback(config: config, appID: "app-1")))
    }

    @Test func unchangedBytesStillEnsureTheIssueButCommitNothing() async throws {
        let path = try page("<h1>hi</h1>")
        let pageSHA = PageShares.sha256(PageComments.page(Data("<h1>hi</h1>".utf8), config: config, appID: "app-1"))
        let callbackSHA = PageShares.sha256(PageComments.callback(config: config, appID: "app-1"))
        let gitLab = CommentsGitLab(routes(path, issues: "[]", page: (200, #"{"content_sha256":"\#(pageSHA)"}"#),
                                           callback: (200, #"{"content_sha256":"\#(callbackSHA)"}"#)))

        let share = await PageShares().publish(file: path, config: config, transport: gitLab)

        #expect(share.state == .idle)
        #expect(await gitLab.keys.contains("POST issues"))
        #expect(await !gitLab.keys.contains("POST repository/commits"))
    }

    @Test func aFoundIssueIsKeptAndAnUnchangedCallbackIsNotRewritten() async throws {
        let path = try page("<h1>hi</h1>")
        let id = PageShares.id(forFile: path)
        let callbackSHA = PageShares.sha256(PageComments.callback(config: config, appID: "app-1"))
        let gitLab = CommentsGitLab(routes(path, issues: #"[{"iid":3,"title":"Комментарии · \#(id) · hi"}]"#,
                                           callback: (200, #"{"content_sha256":"\#(callbackSHA)"}"#)))

        _ = await PageShares().publish(file: path, config: config, transport: gitLab)

        #expect(await !gitLab.keys.contains("POST issues"))
        #expect(await gitLab.files.map { Array($0.keys) } == [["snippets/\(id)/index.html"]])
    }

    @Test func aCommitRefusedOverACallbackAnotherShareJustCreatedIsRetriedWithoutIt() async throws {
        let path = try page("<h1>hi</h1>")
        let id = PageShares.id(forFile: path)
        let callbackSHA = PageShares.sha256(PageComments.callback(config: config, appID: "app-1"))
        var routes = routes(path, issues: "[]")
        routes["GET repository/files/snippets%2Fcallback.html?ref=main"] = [(404, "{}"), (200, #"{"content_sha256":"\#(callbackSHA)"}"#)]
        routes["POST repository/commits"] = [(400, #"{"message":"A file with this name already exists"}"#), (201, #"{"id":"c0ffee"}"#)]
        let gitLab = CommentsGitLab(routes)

        let share = await PageShares().publish(file: path, config: config, transport: gitLab)

        #expect(share.state == .idle)
        #expect(await gitLab.files.map { Set($0.keys) } == [["snippets/\(id)/index.html", "snippets/callback.html"],
                                                            ["snippets/\(id)/index.html"]])
    }

    @Test func aRefusedIssueSearchFailsTheShareWithGitLabsMessage() async throws {
        let path = try page("<h1>hi</h1>")
        var routes = routes(path, issues: "[]")
        routes[issues(PageShares.id(forFile: path))] = [(403, #"{"message":"403 Forbidden"}"#)]
        let gitLab = CommentsGitLab(routes)

        let share = await PageShares().publish(file: path, config: config, transport: gitLab)

        #expect(share.state == .failed)
        #expect(share.error == "GitLab 403: 403 Forbidden")
        #expect(await !gitLab.keys.contains("POST repository/commits"))
    }

    @Test func withoutAnAppIDTheShareTouchesNoIssueAndPublishesTheFileAsIs() async throws {
        let path = try page("<head></head>")
        let plain = PageShareConfig(gitLabURL: "https://gitlab.example.com", project: "team/snippets", token: "secret")!
        let gitLab = CommentsGitLab(routes(path, issues: "[]"))

        _ = await PageShares().publish(file: path, config: plain, transport: gitLab)

        #expect(await !gitLab.keys.contains { $0.contains("issues") })
        #expect(await gitLab.files == [["snippets/\(PageShares.id(forFile: path))/index.html": "<head></head>"]])
    }

    @Test func commentsReadEveryPageOfTheIssuesDiscussions() async throws {
        let path = "/tmp/page.html"
        let id = PageShares.id(forFile: path)
        let note = #"{"id":%d,"body":"b<!-- agterm-anchor: a rev: 1 -->","author":{"name":"Ann","username":"ann"},"#
            + #""created_at":"2026-10-21T10:00:00.000Z","system":false}"#
        let full = "[" + (1...100).map { #"{"id":"d\#($0)","notes":[\#(String(format: note, $0))]}"# }.joined(separator: ",") + "]"
        let gitLab = CommentsGitLab([
            issues(id): [(200, #"[{"iid":7,"title":"Комментарии · \#(id) · p"}]"#)],
            "GET issues/7/discussions?per_page=100&page=1": [(200, full)],
            "GET issues/7/discussions?per_page=100&page=2": [(200, #"[{"id":"last","notes":[\#(String(format: note, 101))]}]"#)],
        ])

        let response = await PageComments.response(file: path, config: config, transport: gitLab)

        let discussions = try #require(response.result?.discussions)
        #expect(discussions.count == 101)
        #expect(discussions.last == ControlPageDiscussion(id: "last", notes: [
            ControlPageNote(id: 101, author: "Ann", body: "b<!-- agterm-anchor: a rev: 1 -->",
                            createdAt: "2026-10-21T10:00:00.000Z", system: false),
        ]))
        #expect(await !gitLab.keys.contains { $0.contains("page=3") })
    }

    @Test func commentsBeforeTheIssueExistsAreEmptyAndCreateNothing() async throws {
        let gitLab = CommentsGitLab([issues(PageShares.id(forFile: "/tmp/page.html")): [(200, "[]")]])

        let response = await PageComments.response(file: "/tmp/page.html", config: config, transport: gitLab)

        #expect(response == ControlResponse(ok: true, result: ControlResult(discussions: [])))
        #expect(await gitLab.keys.count == 1)
    }

    @Test func commentsNeedAnAppID() async throws {
        let plain = PageShareConfig(gitLabURL: "https://gitlab.example.com", project: "team/snippets", token: "secret")!

        let response = await PageComments.response(file: "/tmp/page.html", config: plain, transport: CommentsGitLab([:]))

        #expect(response == ControlResponse(ok: false, error: PageShareError.noComments))
    }
}
