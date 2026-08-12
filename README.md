# Codex Timeline

See Codex changes in Neovim in the order they happened.

Codex Timeline captures the repository after each completed Codex tool call, stores the snapshots as commits on hidden Git refs, and renders that history as a timeline plus diff preview. Your branch, `HEAD`, and staging area are left alone.

## What it shows

- A chronological event list with one entry per state-changing Codex tool call.
- The exact patch introduced by each event.
- Two-character signs beside current lines: `01`, `02`, and so on identify the event that introduced each line.
- Navigation between annotated lines with `]t` and `[t`.
- Multiple Codex sessions per repository.

The event order is exact at the tool-call level. Codex applies patches or writes files atomically, so this cannot reconstruct fictional keystroke order inside a single tool call.

## Architecture

```text
Codex lifecycle hook -> isolated Git snapshot -> refs/codex-timeline/session-*
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

Restart Codex, then opt each repository into recording:

```sh
./bin/codex-timeline enable --repo /path/to/project
```

This opt-in prevents a global hook from silently recording every Git repository you open.

## Use

Open a tracked project in Neovim and run:

| Command | Action |
|---|---|
| `:CodexTimeline` | Open the event list and diff preview |
| `:CodexTimelineAnnotate` | Refresh line annotations |
| `:CodexTimelineSession` | Select a different recorded session |
| `:CodexTimelineClear` | Remove annotations |
| `:CodexTimelineEnable` / `:CodexTimelineDisable` | Toggle recording for this repository |
| `]t` / `[t` | Jump to next/previous annotated line |

Inside the timeline, use `j`/`k`, press `Enter` to open the first changed file, `r` to refresh, and `q` to close.

Optional configuration:

```lua
require("codex_timeline").setup({
  annotate_on_buf_enter = true,
  virtual_text = false,
  session = nil,
})
```

## Recorder CLI

```sh
bin/codex-timeline status --repo .
bin/codex-timeline sessions --repo .
bin/codex-timeline list --repo . --session SESSION_ID
bin/codex-timeline diff 3 --repo . --session SESSION_ID
bin/codex-timeline disable --repo .
```

Timeline commits are stored at `refs/codex-timeline/session-<session-id>`. Temporary state lives inside `.git/codex-timeline/`. Normal commits, checkout, and staging remain untouched.

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

The suite verifies snapshot ordering, no-op deduplication, branch and index isolation, official hook payload handling, installer coexistence/idempotency, Neovim command loading, gutter annotations, and diff previews.

Run `:checkhealth codex_timeline` inside Neovim to diagnose Git availability, repository opt-in, and timeline discovery.

## Caveats

- The snapshot covers all non-ignored worktree changes present when a checkpoint is taken. Git alone cannot prove whether Codex or another process made a concurrent edit.
- Ignored files are intentionally excluded.
- Hooks are a useful observation boundary, not a security boundary; specialized Codex tool paths may opt out of normal tool hooks.

Codex hook behavior and payload fields follow the [official lifecycle-hooks documentation](https://learn.chatgpt.com/docs/hooks).
