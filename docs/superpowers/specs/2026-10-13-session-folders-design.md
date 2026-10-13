# Session folders in the sidebar

Personal fork feature. Upstream declined every tree level (#293, #397, #406); this is not meant for an
upstream PR, so the control-API, bundled-skill and site-doc sync rules are out of scope for v1.

## Goal

Group sessions inside a workspace: `workspace → folder → session`, one level, folders and loose sessions
interleaved in any order. A workspace is a repo, a folder is a branch or a task.

## v1 scope

- Folder row in the sidebar: `folder` SF Symbol, disclosure triangle, collapsible, name, unseen badge
  when collapsed (sum of its sessions).
- Create: session row menu **New Folder** (folder appears at the session's position with that session
  inside, name in inline rename); workspace row menu **New Folder** (empty folder appended to the
  workspace, inline rename). Multi-selection on a session row puts every selected session of that
  workspace into the new folder.
- Rename folder: inline rename, same controller as workspaces.
- Delete folder: row menu **Delete Folder**. Cascade: its sessions are closed the way multi-select
  Close does, after the same confirmation style as Delete Workspace. An empty folder deletes without
  confirmation.
- Move: session row **Move to** submenu gains two sections, `Workspaces` and `Folders`, each headed by
  a disabled subtle item and separated by a separator. `Folders` lists every folder of every workspace
  as `folder — workspace`; the session's current container is omitted. Dropping into another
  workspace's folder is a cross-workspace move landing inside that folder.
- Drag and drop: session rows drop onto or between rows inside a folder, or out of it to the workspace
  level. Spring-loaded expansion works on folder rows like on workspace rows.
- Persistence: survives relaunch; an upstream snapshot loads unchanged; a snapshot without folders is
  byte-identical to today's.
- Control API read-back: `tree` session nodes gain `folder: <name>` when inside one. Nothing else.

Out of scope, second iteration: dragging folder rows (reorder, across workspaces), undo that restores the
folder itself, `agtermctl` folder commands, flagged-tree folder rows.

## Model (agtermCore)

```swift
public struct SessionFolder: Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var isExpanded: Bool
    public var sessionIDs: [UUID]
}

public enum SidebarLayoutEntry: Equatable {
    case session(UUID)
    case folder(SessionFolder)
}

// Workspace gains
public var layout: [SidebarLayoutEntry]
```

Roles, which the whole design rests on:

- `Workspace.sessions` stays the only source of **existence** and keeps feeding every flat consumer
  unchanged: navigation, flagged projection, recency, focus, control tree, pending close, reorder.
- `Workspace.layout` is the only source of **order and membership**. It is literally what the outline
  renders. A folder owns its session ids; a `Session` knows nothing about folders.
- A session appears exactly once across `layout`, either as `.session` or inside one folder.

### `Workspace.reconcile()`

One function, host-free, called from `AppStore.save()` for every workspace before the snapshot is taken
(and therefore after every structural mutation, since those all call `save()`), and once in
`PersistenceStore.load` restore. It is idempotent.

1. Drop every id in `layout` that is not in `sessions`. A folder cannot keep a closed session alive.
2. Append as `.session` every session that `layout` does not mention. A folder cannot lose a session.
   This is also what makes every existing mutator correct for free: `addSession`, `moveSession(s)`,
   `duplicate`, restore, reopen all touch only `sessions`, and reconcile places the newcomer loose at
   the end of the workspace.
3. Reorder `sessions` to the preorder walk of `layout`. Invariant after reconcile:
   `sessions.map(\.id) == layout.preorderIDs`. Ctrl-Tab, `session go`, flagged view and the control tree
   therefore follow the visual order without knowing about folders.

A duplicate id (hand-edited file) keeps its first occurrence. Reconcile never touches `isExpanded`.

### Workspace mutators (new, on `AppStore`)

All go through `layout`, then `save()`:

- `addFolder(toWorkspace:name:containing sessionIDs:) -> SessionFolder`. With ids: the folder is
  inserted at the layout position of the first id, the ids removed from wherever they sat. Without ids:
  appended.
- `renameFolder(_:to:)`, `setFolderExpanded(_:expanded:)`.
- `deleteFolder(_:)`: removes the entry only. Cascade closing is `AppActions` work (below), which
  closes the sessions first through the existing soft-close path and then calls this.
- `moveSessions(_:toFolder:at:)`: the folder-targeted twin of `moveSessions(_:toWorkspace:at:)`.
  Cross-workspace: move into the owning workspace's `sessions` (existing code), then place the ids into
  the folder's `sessionIDs` at the index. Same workspace: only `layout` changes, reconcile fixes order.
- `moveSessions(_:toWorkspace:at:)` learns one thing: an explicit `index` is now a **layout** index at
  workspace level, so a drop between two top-level rows lands between them, not inside a folder that
  happens to hold the same flat position. It removes the ids from any folder first. Without an index
  (menu Move to) the behavior is unchanged: append loose.

`location(ofSession:)` and every flat index helper keep working on `sessions`.

### Snapshot

```swift
// WorkspaceSnapshot gains
public var layout: [LayoutEntrySnapshot]?
// LayoutEntrySnapshot: {"session": "<uuid>"} | {"folder": {"id", "name", "collapsed"?, "sessions": [uuid]}}
```

Optional and lossy-decoded like `collapsed`. Encoded only when the workspace has at least one folder;
nil otherwise, so a tree without folders serializes byte-identically to today's file. On load nil
means every session loose in array order. An upstream build ignores the key and shows a flat list; no
session is lost in either direction.

## Sidebar (app target)

- `SidebarNode.Kind` gains `.folder`. A folder node's `children` are its session nodes; a workspace
  node's children follow `layout`. `nodeCache` keeps folder nodes by id like the others.
- `Coordinator.workspaceProjection` is unchanged; the per-workspace child build reads `layout` instead
  of `sessions`. The flagged tree keeps rendering workspace → flagged sessions, no folder rows (v1).
- `expandedWorkspaceIDs` becomes the set of expanded container ids, folders included, so flagged-mode
  round trips restore folder expansion the same way. Persisted expansion goes through
  `setFolderExpanded`, wrapped in `suppressExpansionPersist` where workspace expansion already is.
- Row rendering: `RowContent` works as is; the folder row uses `folder` (SF Symbol) in the same fixed
  16x16 image view, label, badge from `displayedUnseen(for:)` extended to folders. No flagged or focus
  variant.
- Row click on a folder toggles expansion exactly like the workspace row, through the same deferred
  single-click path and `outline.animator()`.
- Rename: `SidebarRenameController.beginEditing(node:)` handles `.folder` like `.workspace`
  (`StaticText` field). A new `agtermBeginRenameFolder` notification is not needed; the menu calls the
  controller directly.
- Accessibility id `folder-row`.

### Context menus

- Session row: **New Folder** right after Duplicate Session. **Move to** becomes sectioned (see scope).
- Workspace row: **New Folder** after Open Directory….
- Folder row: New Session (into the folder, at its end), Rename, Copy Name, separator, Delete Folder.
  New Session inside a folder goes through `addSession` then `moveSessions(_:toFolder:)`.

### Drag and drop

- `SidebarDrop.SessionDropTarget` gains `.folderRow(workspace:folder:sessionCount:)`, and
  `.sessionRow` learns an optional `folder`. `resolveSession(s)` returns the container
  (`workspace` or `folder`) plus a post-removal index in that container's own list. The same-container
  downward `childIndex - 1` rule applies inside a folder too.
- `resolveSessionMove` maps AppKit's `item` to that target: a `.folder` node is a folder row, a session
  node inside a folder is a `sessionRow` with `folder` set. `acceptDrop` calls `moveSessions(toFolder:)`
  or `moveSessions(toWorkspace:)` accordingly.
- Workspace-row drags are untouched. Folder rows are not draggable in v1
  (`pasteboardWriterForItem` returns nil for `.folder`).
- Spring-loaded expansion reuses `scheduleSpringLoadedExpansion` with a folder id.
- Finder directory drops onto a folder row open the session inside that folder.

### Delete folder (AppActions)

`AppActions.deleteFolder(_:in:)`: empty folder → `store.deleteFolder` directly. Otherwise an alert in
the Delete Workspace style naming the session count; on confirm, `softCloseSessions(ids)` (the
multi-select close path, so pending-close undo and recent-closed work for the sessions) then
`store.deleteFolder`. Reopen brings the sessions back loose (reconcile rule 2); the folder is gone.

## Control read-back

`ControlSessionNode.folder: String?`, set from the owning folder's name. Omitted when loose.
`EventFormatter` has nothing new because no event changes.

## Testing

- `agtermCore` (`swift test`): `WorkspaceLayoutTests` table-tests `reconcile()` (drop unknown, append
  missing, reorder, duplicate id, idempotence, nil layout); `AppStoreFolderTests` cover every mutator
  including cross-workspace move into a folder and the index semantics of `moveSessions(toWorkspace:at:)`;
  `SnapshotFolderTests` pin byte-identical encoding without folders, round trip with them, lossy decode
  of a bad `collapsed`, and an upstream-shaped file loading loose; `SidebarDropTests` gains the folder
  target cases.
- Hosted (`make test-app`): one `SidebarFolderUITests` with create-from-session, rename, drop into
  folder, drop out, delete with cascade. Run only that class while iterating.
- Gates at the end, once: build, `swift test`, `make test-app`, `make lint`.

## Files

| Area | Files |
| --- | --- |
| model | `agtermCore/.../Workspace.swift` (+ `SessionFolder`, `SidebarLayoutEntry`, `reconcile`), new `AppStore+Folders.swift`, `AppStore.swift` (`moveSessions` index), `AppStore+Persistence.swift` (reconcile before snapshot) |
| snapshot | `Snapshot.swift`, `PersistenceStore.swift` |
| drop math | `SidebarDrop.swift` |
| control | `ControlProjection.swift` (`folder` field) |
| sidebar | `SidebarRowViews.swift` (`Kind.folder`), `WorkspaceSidebar.swift` (child build, expansion set), `+RowRendering`, `+ContextMenu`, `+DragDrop`, `SidebarRenameController.swift` |
| actions | `AppActions.swift` (`deleteFolder`) |

`WorkspaceSidebar.swift` is at 901 lines against a 1000 limit; the child build and expansion changes
should fit, otherwise the layout build moves to a new `WorkspaceSidebar+Layout.swift`.
