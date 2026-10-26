# agterm fork additions

This build is the ZhilinS/agterm fork. Everything below adds to or overrides SKILL.md and reference.md.

## Sharing a page with the team

- `session overlay share [--pane left|right] [--target] [--window W]` publishes a FILE page to the GitLab
  Pages project set in Settings > Sharing, then prints its link, `<pages URL>/<id>/`. The id is derived from
  the file's path, so sharing the same file again keeps the link. Unchanged bytes publish nothing.
  Otherwise the page is committed, and the reply comes before the pipeline deploys it.
  The command never touches the clipboard; the strip's Share button copies the link.
  The reply and the read-back `htmlOverlays[].share` are `{url, state, pipelineURL?, error?}`.
  `state` stays `publishing` until the pipeline succeeds (`idle`), or fails or runs past five minutes
  (`failed`).
  Errors: `sharing is not configured: …`, `only a file page can be shared`, GitLab's message for a refused
  call, and the two `reload` errors.
- `session overlay comments [--pane left|right] [--target] [--window W]` prints a shared FILE page's
  comments as JSON. It needs the OAuth Application ID in Settings > Sharing. With that set, each share
  adds `gl-url`/`gl-project`/`gl-app-id` meta tags to the published copy, writes `callback.html` at the
  site root, and creates the page's GitLab issue if it does not exist yet.
  `result.discussions` is `[{id, notes: [{id, author, body, createdAt, system}]}]`. Bodies are raw, and the
  list is empty before the first comment.
  Errors: `comments are not configured: …`, the `share` errors, and GitLab's message.

## Session folders

- A workspace can group sessions into folders, one level deep. A session's tree node carries
  `folder: <name>` when it is in one; the field is absent for a loose session.

## Quick terminal

- The panel is 4:3: 90% of the focused screen's shorter side, capped at 1000 points, unless
  Settings > Interface sets a share. ⌘-drag moves it, and it reopens where it was left on that display
  for the rest of the launch.
