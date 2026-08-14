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

The installer merges Timeline into `~/.codex/hooks.json`, preserves unrelated handlers, and creates a timestamped backup. Restart Codex after installing or changing hooks.

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

## Verify the installation

Open a file inside a Git repository and run:

```vim
:checkhealth timeline
```

A healthy setup reports that Git and Neovim are available, automatic recording is enabled, and the repository is synchronized.

Then open the browser:

```vim
:Timeline
```

If you installed hooks while Codex was already running, restart Codex before testing a new recorded change.

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
| `]t` / `[t` | Jump to the next or previous annotated line |

The old `:CodexTimeline*` commands remain as compatibility aliases, but new configurations should use `:Timeline*`.

## Browser navigation

The browser contains three panes:

1. **Changes** — the ordered change number and message only.
2. **Codebase** — every file that existed at the selected event.
3. **Code** — the complete selected file with event-local changes highlighted.

Keys:

| Key | Action |
|---|---|
| `j` / `k` | Move through changes or files |
| `Enter` | Move from Changes to Codebase, then to Code |
| `1` / `2` / `3` | Focus a pane directly |
| `[c` / `]c` | Select the previous or next event from any pane |
| `/` | Search commit messages or change numbers such as `#012` |
| `n` / `N` | Jump to the next or previous search match |
| `F` | Search file paths in the selected commit |
| `[f` / `]f` | Jump to the previous or next file match |
| `r` | Refresh the browser |
| `q` / `Esc` | Close the browser |

Changed files are selected automatically. Added files are green, deleted files are red, and modified files are amber. Deleted files remain visible at their deletion event so their complete previous content can be inspected.

The three panes resize and recenter automatically whenever the Neovim window changes size. When you select a changed file, the Code pane keeps the complete file loaded but scrolls so its first highlighted line is at the top of the viewport. A change beginning at line 300 therefore opens with line 300 visible first.

### Searching commits

Press `/` from any pane to open the `Search commits:` prompt. Search is case-insensitive and performs a plain-text match against each visible change number and commit message.

Examples:

- `auth` finds messages such as `add authentication` and `fix AUTH redirect`.
- `#012` jumps directly to change 12.
- `base` finds the imported baseline event.

The first match at or after the currently selected commit is opened immediately. Every match is highlighted in the Changes pane, and its title shows the number of results. Press `n` or `N` from any pane to move forward or backward; navigation wraps when it reaches either end.

Selecting a search result reconstructs that event across the entire browser. Codebase shows every file that existed then, while Code opens the first changed file with its highlighted change at the top. The full file remains available for normal scrolling.

Run `/` and submit an empty value to clear the query and its highlights. A query with no results leaves the current event selected and shows `no matches` in the Changes title. Commit search covers change numbers and messages only; use `F` to search paths in the selected snapshot. It does not search file contents, timestamps, or commit hashes.

### Searching files in a commit

Press `F` from any pane to search the complete file tree at the selected commit. The prompt includes the active change number, such as `Search files in #012:`, so it is always clear which historical snapshot is being searched.

The query is a case-insensitive plain-text match against complete repository-relative paths. For example:

- `auth` finds every path containing `auth`.
- `src/api` limits matches to that directory.
- `.lua` finds Lua files anywhere in the snapshot.

The first match at or after the currently selected file opens immediately in Code. Every result is highlighted in Codebase, whose title displays the match count. Use `]f` and `[f` from any pane to move forward and backward with wraparound.

File search uses the historical tree, not the current working directory. Files unchanged at that commit remain searchable, and a deleted file remains searchable at its deletion event because Timeline preserves its previous contents for inspection. Selecting a result shows the complete file as it existed then, including any event-local addition or removal highlights.

Press `F` and submit an empty value to clear the file query. Switching to another commit clears it automatically because that commit can have a different filesystem. File search matches paths only, not file contents.

## How synchronization works

When Timeline first sees an existing repository, it imports every commit reachable from the current `HEAD` in deterministic parent-before-child order. The root commit is `#001`, and all of its lines are treated as additions.

If modified or untracked files exist at synchronization time, their complete state becomes the next `existing project baseline` event. Git cannot recover edit order inside an old commit; imported history therefore has commit-level ordering. Future Codex activity has tool-call-level ordering.

Codex lifecycle hooks capture a pending label before each tool call and create a snapshot after successful completion. Different Codex tasks append to the same continuous project timeline rather than resetting the numbering.

Ignored files are excluded. A snapshot covers every non-ignored worktree change present at checkpoint time, so Git cannot prove whether a concurrent non-Codex process made a particular edit.

## Configuration

```lua
require("timeline").setup({
  annotate_on_buf_enter = true,
  auto_sync = true,
  virtual_text = false,
  session = nil,
  colors = {},
})
```

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

Run `:TimelineInstallHooks` once after upgrading so `hooks.json` uses the new executable path. The installer removes the old Timeline handler entries before adding the new ones.

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

Run `:TimelineInstallHooks`, restart Codex, and check:

```vim
:checkhealth timeline
```

Make sure recording was not disabled with `:TimelineDisable`.

### Existing commits do not appear

Run `:TimelineSync` from a buffer inside the repository, close the browser, and reopen it with `:Timeline`.

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
