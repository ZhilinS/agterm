# Fork changelog

## v0.38.1-fork.1 - 2026-10-26

### Improved

- **Up to date with agterm 0.38.1.** Everything upstream shipped through [v0.38.1](https://github.com/umputun/agterm/releases/tag/v0.38.1) is included. Session folders, quick-terminal drag and page sharing behave as before.

## v0.36.0-fork.5 - 2026-10-21

### New

- **Colleagues can comment a shared page.** Set an OAuth Application ID in Settings ▸ Sharing (a non-confidential GitLab app, `api` scope, redirect `<pages URL>/callback.html`) and Share also publishes the sign-in page and gives the page its own GitLab issue. On GitLab Pages anyone with access to the project signs in and comments the page's blocks; the threads live in that issue. `session.overlay.comments` (and `agtermctl session overlay comments`) reads them back, which is how a page inside agterm shows them.

## v0.36.0-fork.4 - 2026-10-16

### Improved

- **The quick terminal is a 4:3 panel.** It takes 90% of the focused screen's shorter side, up to 1000 points wide, instead of 90% of each side up to 1100x700, so a wide display gives it rows rather than a strip of columns. A size set in Settings ▸ Interface is now a share of the shorter side too.

## v0.36.0-fork.3 - 2026-10-15

### New

- **Share an HTML page to GitLab Pages.** With a GitLab URL, project and a Maintainer `api` token in Settings ▸ Sharing, a file page's strip gets Share: a click copies the page's link and publishes it, the button spins while the pipeline deploys (a click opens the pipeline) and shows GitLab's error if it fails. The same file always gets the same link, and an unchanged page publishes nothing. `agtermctl session overlay share` does the same from a script; `tree` reads it back as `htmlOverlays[].share`. Without these settings the button does not appear.

## v0.36.0-fork.2 - 2026-10-14

### Improved

- **A folder lives while it holds sessions.** Closing the last session of a folder, dragging it out or moving it elsewhere removes the folder; an empty folder is only made on purpose. Reopen Closed Item and Open Recent bring the folder back with the session, at its old place, with its name and collapsed state. Undoing a workspace close keeps its folders.
- **New session at the active session's level.** ⌘N, New Session and the row `+` add the session inside the active session's folder when it has one, with the "end" placement as well as "after current". Folder rows get the hover `+` a workspace row has.

## v0.36.0-fork.1 - 2026-10-14

First release of the [ZhilinS/agterm](https://github.com/ZhilinS/agterm) fork, on top of upstream v0.36.0.

### New Features

- **Session folders.** A workspace can group sessions into folders, one level, folders and loose sessions in any order. Right-click a session → New Folder puts it in a new folder; right-click a workspace → New Folder makes an empty one. Drag sessions into and out of folders, Move to lists folders under the workspaces, Delete Folder closes its sessions after a confirmation and Reopen Closed Item brings them back. Folders survive a relaunch. `tree` reports `folder` on a session node. The state file format changes: `items` replaces `sessions`, and a file written by this fork is not read by upstream agterm.
- **Rename on double-click** (Settings ▸ General ▸ Mouse, on by default). Off, a click on a workspace or folder row expands or collapses it at once instead of waiting for the double-click interval, and double-click no longer renames those rows; sessions still rename on double-click.
- **Quick terminal ⌘-drag.** Hold ⌘ and drag the quick terminal to move it; the position is remembered per screen.


