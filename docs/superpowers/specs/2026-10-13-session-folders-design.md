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

One ordered list per workspace. A folder is an item that owns sessions; a session knows nothing about
folders.

```swift
public struct SessionFolder: Identifiable {
    public let id: UUID
    public var name: String
    public var isExpanded: Bool
    public var sessions: [Session]
}

public enum WorkspaceItem {
    case session(Session)
    case folder(SessionFolder)
}

public struct Workspace {
    public var items: [WorkspaceItem]            // the only order and the only membership
    public var sessions: [Session] { … }         // computed: preorder walk of items, READ ONLY
}
```

- `sessions` stays a computed property so the 184 read sites (navigation, flagged projection,
  recency, focus, control tree, pending close, drop math) compile and behave unchanged: they see the
  preorder, which is the visual order.
- The 16 write sites, all `sessions.remove(at:)` / `insert(at:)` / `append` / `removeAll` in
  `AppStore.swift`, `AppStore+PendingClose.swift`, `AppStore+RecentClosed.swift`, move to three
  `Workspace` methods, each a one-line swap at the call site:
  - `removeSession(id:) -> Session?` searches top level and folders.
  - `insertSession(_:atFlat:)` maps a flat preorder index to the container and slot of the session
    currently at that index; `atFlat == sessions.count` appends at workspace level. This keeps every
    existing flat-index caller (drops, `--after`/`--before`, reopen, duplicate) correct without knowing
    about folders.
  - `appendSession(_:)` at workspace level.
- Folder operations add `insertSession(_:inFolder:at:)`, `addFolder(named:at:containing:)`,
  `removeFolder(id:) -> SessionFolder?`, `renameFolder`, `setFolderExpanded`.
- `location(ofSession:)` keeps returning the flat index; a new `container(ofSession:)` returns the
  folder id when inside one, for menus, drop targets and the control read-back.
- A folder may be empty; it keeps its slot in `items`.

### Store mutators (new, `AppStore+Folders.swift`)

- `addFolder(toWorkspace:name:containing sessionIDs:) -> SessionFolder`. With ids: the folder takes
  the slot of the first id, the ids move inside in tree order. Without: appended.
- `renameFolder(_:to:)`, `setFolderExpanded(_:expanded:)`.
- `deleteFolder(_:)`: `removeFolder` and drop the entry. Only called on an empty folder; the cascade is
  `AppActions` work (below), which closes the sessions first through the existing soft-close path.
- `moveSessions(_:toFolder:at:)`: remove each id with `removeSession`, insert the block with
  `insertSession(_:inFolder:at:)`. Cross-workspace works the same way, the folder's workspace is the
  destination.
- `moveSessions(_:toWorkspace:at:)` is unchanged in shape: `removeSession` then `insertSession(atFlat:)`.
  A drop between two top-level rows therefore lands at the flat slot of the row below it; if that row is
  the first session of a folder the drop lands inside the folder, so `SidebarDrop` resolves a drop that
  targets the folder ROW to the slot before the folder (top level) and a drop ON the folder row to its
  end. Menu Move to (no index) appends loose.

### Snapshot

```swift
// WorkspaceSnapshot
public var sessions: [SessionSnapshot]        // unchanged: the flat preorder, what upstream reads
public var items: [WorkspaceItemSnapshot]?    // only written when the workspace has a folder
// WorkspaceItemSnapshot: {"session": "<uuid>"} | {"folder": {"id", "name", "collapsed"?, "sessions": [uuid]}}
```

- `sessions` keeps being written in full, so an upstream build reads the file and shows a flat list.
- `items` references sessions by id and is lossy-decoded like `collapsed`. On load, `items == nil` means
  every session loose in array order; an id in `items` with no session in `sessions` is dropped, a session
  missing from `items` is appended loose. That is the only reconciliation, and it runs on load only,
  because at runtime there is one list.
- A workspace without folders encodes byte-identically to today's file.

## Sidebar (app target)

- `SidebarNode.Kind` gains `.folder`. A folder node's `children` are its session nodes; a workspace
  node's children follow `items`. `nodeCache` keeps folder nodes by id like the others.
- `Coordinator.workspaceProjection` is unchanged; the per-workspace child build reads `items` instead
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
`store.deleteFolder`. Reopen re-inserts the sessions through `insertSession(atFlat:)` at their old flat slots, loose; the folder is gone.

## Control read-back

`ControlSessionNode.folder: String?`, set from the owning folder's name. Omitted when loose.
`EventFormatter` has nothing new because no event changes.

## Testing

- `agtermCore` (`swift test`): `WorkspaceItemsTests` table-tests `insertSession(atFlat:)` across
  folder boundaries, `removeSession`, and that `sessions` equals the preorder; `AppStoreFolderTests` cover
  every mutator including cross-workspace move into a folder; `SnapshotFolderTests` pin byte-identical
  encoding without folders, round trip with them, lossy decode, an upstream-shaped file loading loose, and
  the load-time drop/append of stray ids; `SidebarDropTests` gains the folder target cases. The existing
  store suites are the regression net for the 16 write-site swaps.
- Hosted (`make test-app`): one `SidebarFolderUITests` with create-from-session, rename, drop into
  folder, drop out, delete with cascade. Run only that class while iterating.
- Gates at the end, once: build, `swift test`, `make test-app`, `make lint`.

## Files

| Area | Files |
| --- | --- |
| model | `agtermCore/.../Workspace.swift` (`items`, `SessionFolder`, `WorkspaceItem`, computed `sessions`, the three write methods), new `AppStore+Folders.swift`, the 16 write sites in `AppStore.swift`, `AppStore+PendingClose.swift`, `AppStore+RecentClosed.swift` |
| snapshot | `Snapshot.swift`, `PersistenceStore.swift` |
| drop math | `SidebarDrop.swift` |
| control | `ControlProjection.swift` (`folder` field) |
| sidebar | `SidebarRowViews.swift` (`Kind.folder`), `WorkspaceSidebar.swift` (child build, expansion set), `+RowRendering`, `+ContextMenu`, `+DragDrop`, `SidebarRenameController.swift` |
| actions | `AppActions.swift` (`deleteFolder`) |

`WorkspaceSidebar.swift` is at 901 lines against a 1000 limit; the child build and expansion changes
should fit, otherwise the child build moves to a new `WorkspaceSidebar+Items.swift`.
