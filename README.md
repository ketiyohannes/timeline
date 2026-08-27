# Timeline

Timeline is a Neovim time machine for Git repositories changed by Codex. It imports existing commits, records future Codex tool calls in order, and lets you browse the complete codebase at every point without touching your branch, `HEAD`, worktree, or staging area.

## What you get

- One continuous change sequence across future Codex tasks.
- Existing Git history imported as `#001`, `#002`, and so on.
- A complete repository tree and full source files at every event.
- Bold green additions, red deletions, and amber modified files.
- Added and removed lines interleaved in their original full-file context.
- Per-line annotations showing which event introduced the current line.
- Hidden Codex session, turn, tool, and tool-use context for diagnostics.
- Automatic recording in every Git repository unless explicitly disabled.

Timeline stores snapshots on isolated Git refs using a temporary index. Normal commits, branches, checkout state, and staged changes remain untouched.

## Requirements

- Neovim 0.10 or newer
- Git 2.20 or newer
- Python 3 for the Codex hook installer and adapter
- Codex with lifecycle-hook support

## Installation

### lazy.nvim

Add this to your Neovim plugin configuration:

```lua
{
  "ketiyohannes/timeline",
  name = "timeline",
  lazy = false,
  config = function()
    require("timeline").setup()
  end,
}
```

Restart Neovim and run `:Lazy sync`.

Then install the Codex lifecycle hooks directly from Neovim:

```vim
:TimelineInstallHooks
```

The installer merges Timeline into `~/.codex/hooks.json`, preserves unrelated handlers, and creates a timestamped backup. Installing the definitions does not approve them; complete the approval step below before testing Timeline.

### Manual local installation

```sh
git clone https://github.com/ketiyohannes/timeline.git ~/.local/share/timeline
cd ~/.local/share/timeline
./bin/install-hooks
```

Point your plugin manager at the clone:

```lua
{
  dir = vim.fn.expand("~/.local/share/timeline"),
  name = "timeline",
  lazy = false,
  config = function()
    require("timeline").setup()
  end,
}
```

### Approve the Codex hooks

Open a terminal and start the Codex CLI:

```sh
codex
```

If the desktop app is installed on macOS but `codex` is not available on your `PATH`, use its bundled CLI:

```sh
"/Applications/ChatGPT.app/Contents/Resources/codex"
```

At the startup warning, choose **Review hooks**. You can also open the hook browser from the CLI by entering:

```text
/hooks
```

Open the `~/.codex/hooks.json` source, then review and trust every command whose path ends in `/bin/timeline-hook` (press `t` on each entry). Timeline installs six handlers: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, and `SessionEnd`. Approve all six so Timeline can establish a baseline, record ordered tool changes, and flush pending changes when a task finishes. Review the commands individually instead of choosing **Trust all** when the source contains unrelated hooks.

Codex records approval against the exact hook definition. If Timeline's install path or hook definitions change after an update, open `/hooks` in the CLI and approve the changed entries again. Do not bypass hook trust; inspect the command before approving it. The desktop chat composer does not open the hook browser. See the [official Codex hooks documentation](https://learn.chatgpt.com/docs/hooks.md) for details.

After approval, start a fresh Codex task or restart Codex so `SessionStart` can establish the repository baseline.

## Verify the installation

Open a file inside a Git repository and run:

```vim
:checkhealth timeline
```

A healthy setup reports that Git and Neovim are available, automatic recording is enabled, and the repository is synchronized. `:checkhealth timeline` checks the repository side; it cannot tell whether Codex has approved the hooks. Use `/hooks` in the Codex CLI to verify that Timeline's six entries are trusted and enabled.

Then open the browser:

```vim
:Timeline
```

Make one Codex edit in the repository, then open `:Timeline`. The new task should appear as an ordered change without requiring you to reopen the browser.

## Commands

| Command | Description |
|---|---|
| `:Timeline` | Open the chronological codebase browser |
| `:TimelineSync` | Import existing commits and synchronize current local state |
| `:TimelineAnnotate` | Show the event that introduced each current line |
| `:TimelineSession` | Select a continuous, demo, or legacy timeline |
| `:TimelineClear` | Clear line annotations |
| `:TimelineEnable` | Enable automatic recording for this repository |
| `:TimelineDisable` | Disable automatic recording for this repository |
| `:TimelineInstallHooks` | Safely install Codex lifecycle hooks |
| `:TimelineUninstallHooks` | Remove only Timeline's Codex hooks |
| `]t` / `[t` | Outside the Timeline browser, jump to the next or previous annotated line |

The old `:CodexTimeline*` commands remain as compatibility aliases, but new configurations should use `:Timeline*`.

## Browser navigation

The browser contains three panes:

1. **Commits** — real Git commits, always ordered by Git history.
2. **Codebase** — every file at the selected point, with Codex change numbers attached directly to touched paths.
3. **Code** — the complete selected file with the selected Codex change highlighted.

Timeline never promotes an individual Codex tool snapshot to the commit list. It matches the snapshot trees to real Git commits and keeps the captured ordering inside the commit. If the latest recorded work has not been committed yet, it is collected under `WIP Uncommitted changes`. A Git-only repository simply shows its commits and file trees without invented indicators.

### Change indicators on files and code

Inside a recorded commit, Codebase prefixes every touched file with the ordered changes that affected it:

```text
01,03 │ README.md
02    │ src/service.ts
```

`README.md` was first touched by Change 1 and touched again by Change 3. `src/service.ts` was first touched by Change 2. Files unchanged by Codex have no prefix. If one Codex tool call changes several files, those files share the same change number because Timeline records that tool call as one atomic change rather than inventing an order Git cannot prove.

Code uses the same numbering. Every surviving changed line remains highlighted and carries a right-aligned marker such as `Δ01` or `Δ03`, so earlier and later diffs stay visible together in the complete historical file. Every touched file remains highlighted in Codebase as well. The actively selected change uses stronger styling: event-local additions and removals keep their bold green/red `+` and `-` signs and backgrounds. A removed line is labeled with the change that removed it; a surviving line retains the change that last introduced or modified it.

Keys:

| Key | Action |
|---|---|
| `j` / `k` | Move through commits or files |
| `Enter` (panes) | Move from Commits to Codebase, then to Code |
| `1` / `2` / `3` | Focus a pane directly |
| `[c` / `]c` | Select the previous or next Git commit |
| `[t` / `]t` | Select the previous or next recorded Codex change inside that commit |
| `/` | Toggle real-time commit search |
| `n` / `N` | Jump to the next or previous search match |
| `F` | Toggle real-time file search for the selected commit |
| `[f` / `]f` | Jump to the previous or next file match |
| `C` | Toggle real-time code search for the opened file or selected commit |
| `Tab` | Toggle `This file` / `All files` while the code-search bar is open |
| `Enter` (Code search) | Open the active result in the normal editor |
| `o` | Open the active result after the code-search bar has been hidden |
| `[s` / `]s` | Jump to the previous or next code match |
| `r` | Refresh the browser |
| `q` / `Esc` | Close the browser |

Changed files are selected automatically. Added files are green, deleted files are red, and modified files are amber. Deleted files remain visible at their deletion event so their complete previous content can be inspected.

While the browser is open, it watches the selected Timeline ref and Git `HEAD`. A completed Codex tool call appears automatically under WIP, and a new Git commit automatically regroups those changes beneath the commit—there is no need to reopen `:Timeline`. If you were viewing the newest change, the browser follows it; an older selection stays in place. The `r` mapping remains available as a manual full reopen.

The three panes resize and recenter automatically whenever the Neovim window changes size. Neither Commits nor Codebase adds standalone turn/change rows. Codebase attaches ordering directly to touched files, while Code attaches it directly to changed lines. Raw task, turn, and tool-use UUIDs stay hidden. The Code pane shows only the Git commit number and message in its title, with the opened repository-relative file path fixed directly beneath it.

When you select a changed file, the Code pane keeps the complete file loaded but scrolls so its first highlighted line is at the top of the viewport. A change beginning at line 300 therefore opens with line 300 visible first.

### Code pane header

The Code pane keeps the commit and file identity visible as two separate fixed rows:

```text
╭──────────── #012 · refactor authentication ────────────────╮
│                     src/auth/session.ts                     │
│  1  export function createSession() {                       │
│  2    // complete historical source                         │
```

- The border title contains only the real Git commit number and message.
- The row beneath it is the repository-relative path of the file currently open in Code.
- Selecting a different Codebase row or file-search result updates the path immediately.
- Scrolling the source keeps both rows fixed, including when Timeline starts at a deep highlighted line.

The path is display-only: it is not inserted into the historical buffer, does not alter line numbers, and does not interfere with copying source or diff highlights. Long paths are visually truncated to the available Code-pane width; the complete path remains visible in Codebase and searchable with `F`.

### Searching commits

Press `/` from any pane to open a dedicated `Search commits` bar above Commits. The pane makes room for the bar, and both stay aligned as Neovim resizes. Nothing is entered through Neovim's bottom command line.

Filtering happens after every keystroke. Nonmatching commits disappear immediately, while the Commits title reports the remaining result count. Search is case-insensitive and matches the visible Git commit number and commit message.

Examples:

- `auth` finds messages such as `add authentication` and `fix AUTH redirect`.
- `#012` jumps directly to Git commit 12.
- `base` finds a Git commit whose message contains `base`.

The selected commit is retained while it still matches. Otherwise, the first later match is opened, wrapping to the first result when needed. Press `Enter` or `Esc` to hide the bar while keeping its filter active. Then use `n` or `N` from any pane to move forward or backward through the filtered results; navigation wraps at either end. Pressing `/` again also toggles the bar.

Selecting a search result opens its final recorded state. Codebase shows the complete file tree with change numbers attached to touched paths. Use `[t` and `]t` to reconstruct earlier or later recorded changes inside the commit.

Delete all text in the bar to restore every commit. A query with no results removes every row from Commits, leaves the current snapshot open in the other panes, and shows `no matches` in the title. Use `F` to search paths in the selected snapshot; raw Codex UUIDs, contents, timestamps, and hashes are not searched.

### Searching files in a commit

Press `F` from any pane to open a dedicated file-search bar above Codebase. Its title identifies the commit, such as `Search files in #012`. The bar and Codebase pane resize together with the rest of the browser.

Filtering happens after every keystroke. Nonmatching paths are removed from Codebase immediately instead of merely being highlighted.

The query is a case-insensitive plain-text match against complete repository-relative paths. For example:

- `auth` finds every path containing `auth`.
- `src/api` limits matches to that directory.
- `.lua` finds Lua files anywhere in the snapshot.

The selected file is retained while it still matches. Otherwise, the first later match opens immediately in Code. Press `Enter` or `Esc` to hide the bar while keeping the filter active, then use `]f` and `[f` from any pane to move forward and backward with wraparound. Pressing `F` again also toggles the bar.

File search uses the historical tree, not the current working directory. Files unchanged at that commit remain searchable, and a deleted file remains searchable at its deletion event because Timeline preserves its previous contents for inspection. Selecting a result shows the complete file as it existed then, including any event-local addition or removal highlights.

Delete all text in the bar to restore the complete snapshot tree. Switching to another commit clears the path filter automatically because that commit can have a different filesystem. File search matches paths only, not file contents.

### Searching inside code

Press `C` from any pane to open a dedicated search bar above Code. Results update after every keystroke, and the bar title reports both the active scope and the number of matching occurrences.

Code search starts in **This file** scope. Press `Tab` while the search bar is open to switch to **All files** in the selected commit; press `Tab` again to return to the opened file. The title always shows the current scope and the available toggle, for example `Code · all files · Tab: this file`.

Code search is case-insensitive and matches literal source text. It works well for function names, variables, error messages, imports, and any other line fragment:

- `refreshSession` finds every use of that function.
- `throw new Error` finds matching error paths.
- `:300` jumps directly to line 300.

Unlike commit and file search, code search never removes nonmatching source lines. The complete historical file stays loaded, each occurrence is highlighted in place, and the active match is visually distinct. Searches include event-local removed lines because those lines are intentionally interleaved with additions in Timeline's historical view.

In **All files** scope, Timeline searches every file in that historical snapshot—not the current working tree. Unchanged files are included, and modified or deleted files are searched exactly as Code displays them, including removed lines. Choosing a result, or using `]s` and `[s`, automatically selects the matching path in Codebase and centers its line in Code.

The `:300` form always jumps to line 300 of the currently opened file, regardless of scope. Press `Enter` to accept the active result: Timeline closes, the repository file opens in the normal Neovim editor, and the matching code is centered. If its lines have shifted since that commit, Timeline finds the closest current occurrence. If the historical file has been deleted, it opens the exact snapshot in a read-only normal buffer instead of recreating the file.

Press `Esc` to hide the bar without leaving Timeline. You can then press `o` from any Timeline pane to open the active result in the editor. Use `]s` and `[s` to move through occurrences with wraparound. Delete all search text to clear the highlights. Manually selecting another file or commit clears code search and resets its scope to **This file**.

## How synchronization works

When Timeline first sees an existing repository, it imports every commit reachable from the current `HEAD` in deterministic parent-before-child order. The root commit is `#001`, and all of its lines are treated as additions.

If modified or untracked files exist at synchronization time, their complete state appears as `WIP Uncommitted changes`. Git cannot recover edit order inside an old commit, so imported history has commit-level ordering only. Future Codex activity gains turn/tool ordering inside the eventual Git commit. Once a recorded tree matches a new Git commit, Timeline automatically nests those captured changes beneath it.

Codex lifecycle hooks capture a pending label before each tool call and create a snapshot after successful completion. Different Codex tasks append to the same continuous project timeline rather than resetting the numbering.

Ignored files are excluded. A snapshot covers every non-ignored worktree change present at checkpoint time, so Git cannot prove whether a concurrent non-Codex process made a particular edit.

## Configuration

```lua
require("timeline").setup({
  annotate_on_buf_enter = true,
  auto_sync = true,
  virtual_text = false,
  session = nil,
  live_refresh = true,
  refresh_interval = 750,
  colors = {},
})
```

`refresh_interval` is measured in milliseconds and has a minimum of `100`. The watcher checks the selected Timeline ref and Git `HEAD`; source trees are rebuilt only when one changes. Set `live_refresh = false` to disable it.

Palette overrides:

```lua
require("timeline").setup({
  colors = {
    add_bg = "#123D2A",
    add_fg = "#8AFF80",
    delete_bg = "#4A1F2A",
    delete_fg = "#FF6B8A",
    change_bg = "#44391F",
    change_fg = "#FFD866",
    accent_bg = "#27365F",
    accent_fg = "#8AADF4",
  },
})
```

The default palette adapts to dark and light backgrounds and is restored after `:colorscheme`.

## Recorder CLI

The `timeline` script is also useful for diagnostics and automation:

```sh
./bin/timeline status --repo .
./bin/timeline sync --repo .
./bin/timeline sessions --repo .
./bin/timeline list --repo . --session project
./bin/timeline diff 3 --repo . --session project
./bin/timeline files 3 --repo . --session project
./bin/timeline context 3 --repo . --session project
./bin/timeline disable --repo .
```

For backward compatibility, `bin/codex-timeline` delegates to `bin/timeline`.

## Storage and safety

Timeline uses the existing internal namespace `refs/codex-timeline/` so upgrades preserve previously recorded sessions. Temporary locks and pending tool state live below `.git/codex-timeline/`.

Snapshots are created with an isolated `GIT_INDEX_FILE` and advanced with atomic `git update-ref` operations. Timeline does not run checkout or stage files in the repository's normal index.

These refs are not pushed by a normal `git push`.

## Upgrade notes

Timeline is the renamed successor to Codex Timeline. Existing installations keep working:

- `require("codex_timeline")` remains supported.
- `:CodexTimeline*` commands remain aliases.
- previously installed hook paths delegate to the renamed scripts.
- existing hidden refs and recorded events remain readable.

New configuration should use `require("timeline")`, `:Timeline`, and `bin/timeline`.

Run `:TimelineInstallHooks` once after upgrading so `hooks.json` uses the new executable path. The installer removes the old Timeline handler entries before adding the new ones. Then open `/hooks` in the Codex CLI and approve any changed Timeline entries again.

## Uninstall

Remove Timeline's Codex hooks:

```vim
:TimelineUninstallHooks
```

or:

```sh
./bin/install-hooks --uninstall
```

Then remove the plugin from your Neovim configuration. Recorded refs are intentionally left in each repository. To remove one manually:

```sh
git update-ref -d refs/codex-timeline/session-project
```

## Troubleshooting

### `:Timeline` is not a command

Confirm the plugin is installed and loaded with `lazy = false`, then restart Neovim. Run `:Lazy log` if lazy.nvim reports an installation error.

### No future Codex changes appear

In the Codex CLI, enter `/hooks`, open the `~/.codex/hooks.json` source, and confirm all six commands ending in `/bin/timeline-hook` are trusted and enabled. Installed hooks do not run until Codex approves them. Entering `/hooks` in the desktop chat composer does not open the hook browser.

If the entries are missing, run `:TimelineInstallHooks`, approve them through `/hooks`, and start a fresh Codex task. Then check the repository side with:

```vim
:checkhealth timeline
```

Make sure recording was not disabled with `:TimelineDisable`.

### Existing commits do not appear

Run `:TimelineSync` from a buffer inside the repository. An open browser updates automatically when synchronization finishes; otherwise, open it with `:Timeline`.

### Git state safety

You can verify that Timeline has not changed normal repository state:

```sh
git status
git branch --show-current
git diff --cached
```

## Development

```sh
make test
```

The suite covers recorder isolation, existing-history import, cross-task Codex ordering, hook installation coexistence and idempotency, Neovim integration, full codebase reconstruction, diff highlighting, dark/light palettes, and legacy compatibility.

The same suite runs on every push and pull request through GitHub Actions.

## License

MIT — see [LICENSE](LICENSE).
