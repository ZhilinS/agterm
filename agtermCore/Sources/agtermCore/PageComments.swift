import Foundation

/// PageComments is what a share adds when `PageShareConfig.oauthAppID` is set: the meta tags the page's comment
/// script reads, the site's OAuth callback page, and the page's GitLab issue, whose discussions are its comments.
/// agterm and the page script pick the same issue: the oldest whose title holds `· <id> ·`.
public enum PageComments {
    static let callbackFile = "snippets/callback.html"

    /// page is `content` with the gl-* meta tags right after its first `<head>` tag, or first when it has none.
    static func page(_ content: Data, config: PageShareConfig, appID: String) -> Data {
        let tags = [("gl-url", config.baseURL), ("gl-project", config.project), ("gl-app-id", appID)]
            .map { #"<meta name="\#($0.0)" content="\#(escape($0.1))">"# }
            .joined()
        guard let text = String(data: content, encoding: .utf8),
              let head = text.firstMatch(of: #/<head(\s(?:[^>"']|"[^"]*"|'[^']*')*)?>/#.ignoresCase()) else {
            return Data(tags.utf8) + content
        }
        return Data((text[..<head.range.upperBound] + tags + text[head.range.upperBound...]).utf8)
    }

    /// title is the text of the page's `<title>`, else the file name.
    static func title(_ content: Data, file: String) -> String {
        let text = String(decoding: content, as: UTF8.self)
        let title = text.firstMatch(of: #/<title[^>]*>([^<]*)<\/title>/#.ignoresCase()).map { String($0.1) }
        return title?.trimmedOrNil ?? URL(fileURLWithPath: file).lastPathComponent
    }

    static func callback(config: PageShareConfig, appID: String) -> Data {
        Data(callbackTemplate
            .replacingOccurrences(of: "{{GITLAB}}", with: jsString(config.baseURL))
            .replacingOccurrences(of: "{{APP_ID}}", with: jsString(appID))
            .utf8)
    }

    /// response is the `session.overlay.comments` reply for the shared file at `path`: every discussion of its issue,
    /// none before the first comment.
    public static func response(file path: String, config: PageShareConfig, transport: any GitLabTransport) async
        -> ControlResponse {
        guard config.oauthAppID != nil else { return ControlResponse(ok: false, error: PageShareError.noComments) }
        let gitLab = GitLab(config: config, transport: transport)
        do {
            var discussions: [ControlPageDiscussion] = []
            if let issue = try await gitLab.issue(page: PageShares.id(forFile: path)) {
                discussions = try await gitLab.discussions(issue: issue.iid)
            }
            return ControlResponse(ok: true, result: ControlResult(discussions: discussions))
        } catch {
            return ControlResponse(ok: false, error: error.localizedDescription)
        }
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// jsString is `value` as a JS string literal; JSONEncoder escapes `/`, so no `</script>` survives.
    private static func jsString(_ value: String) -> String {
        String(decoding: (try? JSONEncoder().encode(value)) ?? Data(#""""#.utf8), as: UTF8.self)
    }

    private static let callbackTemplate = #"""
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<title>Вход через GitLab</title>
<style>body { font: 14px -apple-system, sans-serif; padding: 24px; }</style>
</head>
<body>
<p id="msg">Входим через GitLab…</p>
<script>
// OAuth PKCE callback shared by every snippet: swaps the code for a token and returns to the page.
(async () => {
  const GITLAB = {{GITLAB}};
  const APP_ID = {{APP_ID}};
  const msg = document.getElementById('msg');
  const q = new URLSearchParams(location.search);
  let pending = null;
  const sameOrigin = url => { try { const u = new URL(url, location.origin); return u.origin === location.origin ? u.href : null; } catch (e) { return null; } };
  const stop = text => {
    const back = (pending && sameOrigin(pending.back)) || location.origin + '/';
    msg.textContent = 'Вход не удался: ' + text + '. ';
    const link = document.createElement('a'); link.href = back; link.textContent = 'Вернуться на страницу и войти заново';
    msg.append(link);
  };
  try {
  pending = JSON.parse(sessionStorage.getItem('gl-oauth:' + q.get('state')) || 'null');
  sessionStorage.removeItem('gl-oauth:' + q.get('state'));
  if (!pending || !q.get('code')) {
    stop(q.get('error_description') || q.get('error') || 'нет кода или состояния входа');
    return;
  }
  const res = await fetch(GITLAB + '/oauth/token', {
    method: 'POST',
    body: new URLSearchParams({
      grant_type: 'authorization_code', client_id: APP_ID, code: q.get('code'),
      redirect_uri: location.origin + location.pathname, code_verifier: pending.verifier,
    }),
  });
  const tok = await res.json().catch(() => ({}));
  if (!res.ok || !tok.access_token) { stop('GitLab не выдал токен (' + (tok.error_description || tok.error || res.status) + ')'); return; }
  localStorage.setItem('gl-token', JSON.stringify({
    access: tok.access_token, refresh: tok.refresh_token,
    expires: (tok.created_at + tok.expires_in) * 1000,
  }));
  location.replace(sameOrigin(pending.back) || location.origin + '/');
  } catch (e) { stop(e.message); }
})();
</script>
</body>
</html>
"""#
}

/// ControlPageDiscussion is one discussion of a shared page's issue, as `session.overlay.comments` returns it.
public struct ControlPageDiscussion: Codable, Sendable, Equatable {
    public let id: String
    public let notes: [ControlPageNote]

    public init(id: String, notes: [ControlPageNote]) {
        self.id = id
        self.notes = notes
    }
}

/// ControlPageNote is one note as GitLab holds it: the raw body, the author's display name, GitLab's ISO timestamp.
public struct ControlPageNote: Codable, Sendable, Equatable {
    public let id: Int
    public let author: String
    public let body: String
    public let createdAt: String
    public let system: Bool

    public init(id: Int, author: String, body: String, createdAt: String, system: Bool) {
        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.system = system
    }
}

extension GitLab {
    struct Issue: Decodable {
        let iid: Int
        let title: String
    }

    /// issue is the page's issue, nil until the first share with comments on creates it.
    func issue(page id: String) async throws -> Issue? {
        let query = "issues?in=title&search=\(id)&state=all&order_by=created_at&sort=asc&per_page=20"
        return try decode([Issue].self, try await call("GET", query)).first { $0.title.contains("· \(id) ·") }
    }

    func ensureIssue(page id: String, title: String, url: String) async throws {
        guard try await issue(page: id) == nil else { return }
        let body = ["title": "Комментарии · \(id) · \(title)", "description": url]
        _ = try await call("POST", "issues", body: try JSONSerialization.data(withJSONObject: body))
    }

    /// discussions reads every page of the issue's discussions, asking for the next while one comes back full.
    func discussions(issue iid: Int) async throws -> [ControlPageDiscussion] {
        struct Author: Decodable { let name: String }
        struct Note: Decodable {
            let id: Int
            let body: String
            let author: Author
            let createdAt: String
            let system: Bool
        }
        struct Discussion: Decodable {
            let id: String
            let notes: [Note]
        }
        var all: [Discussion] = []
        var page = 1
        while true {
            let batch = try decode([Discussion].self, try await call("GET", "issues/\(iid)/discussions?per_page=100&page=\(page)"))
            all += batch
            if batch.count < 100 { break }
            page += 1
        }
        return all.map { discussion in
            ControlPageDiscussion(id: discussion.id, notes: discussion.notes.map {
                ControlPageNote(id: $0.id, author: $0.author.name, body: $0.body, createdAt: $0.createdAt, system: $0.system)
            })
        }
    }
}
