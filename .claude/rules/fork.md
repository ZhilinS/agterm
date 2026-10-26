---
paths:
  - "**/*+Fork.swift"
  - "**/*+Folders.swift"
  - "**/*+Drag.swift"
  - "**/*PageShare*.swift"
  - "**/PageComments*.swift"
  - "**/PageSharing.swift"
  - "**/SharingSettingsView.swift"
  - "**/AppStore+ForkTree.swift"
  - "**/WorkspaceSidebar+FolderMenu.swift"
  - "**/WorkspaceSidebar+Items.swift"
  - ".gitattributes"
  - ".github/workflows/upstream-sync.yml"
  - "scripts/release.sh"
  - "CHANGELOG-fork.md"
---

## Fork (ZhilinS/agterm)

- Upstream (umputun/agterm) releases merge in through `.github/workflows/upstream-sync.yml`, so the fork
  stays merge-friendly. Fork code lives in fork-owned files (`*+Fork`, `*+Folders`, `*+Drag`, `PageShare*`)
  and reaches upstream files through one-line, `// fork`-marked hooks.
  Fork-added stored fields and enum cases go FIRST in an upstream type and are set after `init`, so that
  upstream's tail appends never touch fork lines. Upstream docs, site, plugin manifests and `CHANGELOG.md`
  carry no fork content. `.gitattributes` makes the sync take upstream's side for them.
  The fork's own docs are this file, `plugins/agterm/skills/agterm/fork.md`, `README.md`
  and `CHANGELOG-fork.md`.
- Fork releases are `x.y.z-fork.N` on top of upstream `x.y.z`. The tag, DMG, cask and manifests carry the
  full string; `CURRENT_PROJECT_VERSION` carries only `x.y.z`. `release_notes()` reads `CHANGELOG-fork.md`.
- `renameOnDoubleClick` (nil = on) is mirrored to `GhosttyApp.renameOnDoubleClick`. With it off, a
  workspace or folder double-click does not rename, so the row click toggles at once without the
  double-click deferral.
- Settings > Sharing (seventh tab) holds `shareGitLabURL`, `shareGitLabProject` and the token, which
  `PageSharing` keeps in the Keychain, one generic password per bundle id, never in settings. When all
  three are set, the HTML strip shows Share. The optional `shareGitLabOAuthAppID` turns on page comments.
- Share publishes a FILE page to GitLab Pages. `PageShares` keys the share by `PageShares.id(forFile:)`, a
  hash of the standardized path, so one file keeps one link; the share is held in memory only.
  The toolbar button and `session.overlay.share` both run `PageSharing.share`; only the button copies
  the link. The command leaves the accept thread like `zmx.tree`, replies once the commit has landed and
  before the pipeline runs, and reads back as `htmlOverlays[].share`. The poll gives up after five
  minutes. There is no `tree.changed`, because a share is not a slot change. Replica pages are not
  decorated. A page presented to another Mac (`remoteOverlays`) cannot be shared yet.
- With `shareGitLabOAuthAppID` set, `PageComments` turns a share into a commented page: gl-* meta tags
  in the published bytes only, `snippets/callback.html` in the same commit, and the page's issue created
  if it is missing on every share. `session.overlay.comments` reads that issue's discussions with raw
  bodies, addressed and waiting like `share`. Its human output is the discussions JSON.
- Session folders: `Workspace.items` holds sessions and one-level folders, and `sessions` is their
  preorder walk. Persistence writes `items` in place of upstream's `sessions` key and does not decode
  upstream's shape, so an upstream persistence test's JSON literal needs `items` in the fork.
- Quick terminal: `QuickTerminalMetrics.panelSize` makes the panel 75% as tall as it is wide, taking the
  width from the screen's shorter side. Unset, the width is 90% capped at 1000 points.
  ⌘-drag moves the unzoomed panel. `QuickTerminalPanel.sendEvent` holds the ⌘-mouse-down until the
  pointer passes `dragThreshold`, and otherwise forwards it together with its up, because ⌘-click opens
  links. The drag uses the event's own screen location. The panel remembers its position per display for
  the current launch, clamped by `panelOrigin`. A cancelled gesture is swallowed through its release.
  There is no position control command.
