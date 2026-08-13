# Codex Timeline

See Codex changes in Neovim in the order they happened.

Codex Timeline captures the repository after each completed Codex tool call, stores the snapshots as commits on hidden Git refs, and renders that history as a browsable codebase at each point in time. Your branch, `HEAD`, and staging area are left alone.

## What it shows

- A chronological event list containing existing Git commits followed by state-changing Codex tool calls.
- The entire repository tree and complete source files as they existed at each event.
- Added and removed lines interleaved in full-file context, highlighted with `+` and `-` gutter signs.
- Two-character signs beside current lines: `01`, `02`, and so on identify the event that introduced each line.
- Navigation between annotated lines with `]t` and `[t`.
- One continuous project timeline across future Codex tasks, with legacy and explicitly named timelines still selectable.

The event order is exact at the tool-call level. Codex applies patches or writes files atomically, so this cannot reconstruct fictional keystroke order inside a single tool call.

## Architecture

```text
Codex lifecycle hook -> isolated Git snapshot -> refs/codex-timeline/session-project
                                                    |
Neovim signs and timeline UI <----------------------+
```

Snapshots use a temporary Git index. That isolation is what lets the recorder capture tracked, untracked, renamed, and deleted files without staging anything in your working repository.

## Requirements

- Git 2.20+
- Neovim 0.10+
- Python 3 for the hook adapter and installer
- Codex lifecycle hooks

## Install

With lazy.nvim, add the local plugin:

```lua
{
  dir = "/absolute/path/to/diff-display",
  name = "codex-timeline",
  config = function()
    require("codex_timeline").setup()
  end,
}
```

Install the global hook adapter. The installer preserves unrelated handlers and writes a timestamped backup:

```sh
./bin/install-codex-hook
```

Restart Codex. Recording starts automatically in every Git repository Codex works in—existing or new. Opening an existing repository in Neovim imports every commit reachable from its current `HEAD` into the Changes pane, preserving commit order, messages, full codebase snapshots, and highlighted diffs. The root commit is `#001`. If modified or untracked files exist at synchronization time, that complete local state becomes the next numbered `existing project baseline` entry. Subsequent state-changing Codex tool calls continue the same numbering.

Timelines created by the previous single-baseline version are migrated automatically when they contain only that initial baseline. Git provides commit-level ordering for old history; it cannot reconstruct the order of individual edits inside an old commit.

Automatic events from every future Codex task append to one continuous repository-local ref, `refs/codex-timeline/session-project`. The hidden commits retain the originating Codex session, turn, tool, and tool-use IDs, even though the Neovim interface intentionally displays only the change number, readable message, and code.

To synchronize explicitly instead of waiting for file-open detection:

```vim
:CodexTimelineSync
```

or:

```sh
bin/codex-timeline sync --repo /path/to/existing/project
```

To exclude a repository, run `:CodexTimelineDisable` in Neovim or:

```sh
./bin/codex-timeline disable --repo /path/to/project
```

## Use

Open a tracked project in Neovim and run:

| Command | Action |
|---|---|
| `:CodexTimeline` | Browse the codebase snapshot for each ordered event |
| `:CodexTimelineAnnotate` | Refresh line annotations |
| `:CodexTimelineSession` | Select a different recorded session |
| `:CodexTimelineClear` | Remove annotations |
| `:CodexTimelineEnable` / `:CodexTimelineDisable` | Resume or exclude this repository |
| `:CodexTimelineSync` | Import existing commits and synchronize the current project state |
| `]t` / `[t` | Jump to next/previous annotated line |

Inside the snapshot browser:

- The left pane contains only the change number and commit message.
- The middle pane contains every file in the codebase at that time; files touched by the selected event are highlighted.
- The right pane contains the complete selected file. Added lines use a bold green `+` treatment; removed lines use a bold red `-` treatment. Modified files use amber, and the palette adapts to dark or light backgrounds.
- Use `j`/`k` to traverse changes or files, `Enter` to move right, `1`/`2`/`3` to focus a pane, `[c`/`]c` to change events from any pane, `r` to refresh, and `q` to close.

Optional configuration:

```lua
require("codex_timeline").setup({
  annotate_on_buf_enter = true,
  auto_sync = true,
  virtual_text = false,
  session = nil,
  colors = {},
})
```

The built-in palette can be tuned without replacing highlight groups:

```lua
require("codex_timeline").setup({
  colors = {
    add_bg = "#123D2A",
    add_fg = "#8AFF80",
    delete_bg = "#4A1F2A",
    delete_fg = "#FF6B8A",
    change_bg = "#44391F",
    change_fg = "#FFD866",
    accent_fg = "#8AADF4",
  },
})
```

Colors are reapplied after `:colorscheme`. Advanced configurations can override the `CodexTimeline*` highlight groups after setup.

## Recorder CLI

```sh
bin/codex-timeline status --repo .
bin/codex-timeline sync --repo .
bin/codex-timeline sessions --repo .
bin/codex-timeline list --repo . --session SESSION_ID
bin/codex-timeline diff 3 --repo . --session SESSION_ID
bin/codex-timeline context 3 --repo . --session project
bin/codex-timeline disable --repo .
```

The continuous automatic timeline is stored at `refs/codex-timeline/session-project`; explicitly named demonstration or legacy timelines use `refs/codex-timeline/session-<name>`. Temporary state lives inside `.git/codex-timeline/`. Normal commits, checkout, and staging remain untouched.

To remove the global hooks while preserving other handlers:

```sh
./bin/install-codex-hook --uninstall
```

To delete one recorded session:

```sh
git update-ref -d refs/codex-timeline/session-SESSION_ID
```

## Testing

```sh
make test
```

The suite verifies existing commit-history import, legacy-baseline migration, continuous ordering across Codex tasks, stored Codex context, automatic recording, explicit opt-out, snapshot ordering, no-op deduplication, branch and index isolation, installer coexistence/idempotency, full codebase snapshots, metadata-free source views, and line highlighting.

Run `:checkhealth codex_timeline` inside Neovim to diagnose Git availability, repository opt-in, and timeline discovery.

## Caveats

- The snapshot covers all non-ignored worktree changes present when a checkpoint is taken. Git alone cannot prove whether Codex or another process made a concurrent edit.
- Existing commits retain Git's commit-level ordering. Edit order inside a commit is not recoverable.
- Ignored files are intentionally excluded.
- Hooks are a useful observation boundary, not a security boundary; specialized Codex tool paths may opt out of normal tool hooks.

Codex hook behavior and payload fields follow the [official lifecycle-hooks documentation](https://learn.chatgpt.com/docs/hooks).
