# agterm — fork with session folders

A personal fork of [umputun/agterm](https://github.com/umputun/agterm), a native macOS terminal with a
small interface and a full control API. The app, its documentation, command reference and cookbook are
the original project's.

This README covers only what the fork changes. Everything not listed here works exactly as upstream
describes it.

## Install

```sh
brew install --cask zhilins/apps/agterm
```

Or download the `.dmg` from [Releases](https://github.com/ZhilinS/agterm/releases) and drag `agterm.app`
into `/Applications`. Builds are for Apple Silicon Macs on macOS 14 or later, signed with a Developer ID
and notarized.

The fork and the original share the bundle id and the app name, so install one or the other, not both.
If you have upstream installed: `brew uninstall --cask agterm` first.

## What the fork adds

![Session folders, rename on double-click and ⌘-drag of the quick terminal](docs/screenshots/gif/dragging+folders.gif)

### Session folders

Group sessions inside a workspace: `workspace → folder → session`, one level deep. Folders and loose
sessions interleave in any order, so a workspace can be a repo and a folder a branch or a task.

- **New Folder** in a session row's menu wraps that session (or every selected session) in a folder at
  its position. The same item in a workspace row's menu appends an empty folder. Both open inline rename.
- **Move to** in a session row's menu lists every folder of every workspace; dropping onto another
  workspace's folder is a cross-workspace move that lands inside it.
- Drag sessions onto or between rows inside a folder, or back out to the workspace level. Folder rows
  spring-load open on hover like workspace rows.
- **Delete Folder** closes its sessions after the same confirmation as Delete Workspace. Undo restores
  the sessions in order.
- `agtermctl tree` reports `folder: <name>` on sessions inside one. No other control commands change.

Upstream declined folders as a model change ([#293](https://github.com/umputun/agterm/discussions/293),
[#397](https://github.com/umputun/agterm/pull/397),
[#406](https://github.com/umputun/agterm/discussions/406)), which is why this is a fork and not a PR.

### Rename on double-click

**Settings ▸ General ▸ Mouse ▸ Rename on double-click.** With it on, a single click on a workspace or
folder row toggles it immediately instead of waiting out the double-click delay, and renaming moves to
double-click.

### Move the quick terminal with ⌘-drag

⌘-drag anywhere on the quick terminal panel to move it. The position is remembered per display for the
current launch; a display with no record centers the panel as before. ⌘-click still opens links.

## Known differences from upstream

- The saved sidebar tree (`workspaces.json`) has a different format to carry folders, and neither
  build reads the other's. Switching between the fork and the original starts with an empty tree.
- Dragging folder rows themselves (reorder, across workspaces) is not implemented yet.

## Keeping up with upstream

Fork `master` carries the features on top of upstream `master`:

```sh
git fetch upstream && git merge upstream/master
```

Releases are cut from the fork and follow upstream's version numbers with a patch bump.

## Issues

Problems with folders, the rename setting or ⌘-drag go to this fork's
[Issues](https://github.com/ZhilinS/agterm/issues). Anything else is upstream behavior; please check it
against the original build before reporting it upstream.

## License

MIT, same as upstream. Copyright remains with Umputun; see [LICENSE](LICENSE). agterm embeds [libghostty](https://github.com/ghostty-org/ghostty) (MIT) for
rendering, VT parsing and shell I/O; the original README carries the full attribution.
