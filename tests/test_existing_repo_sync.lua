local project_root = assert(vim.env.CODEX_TIMELINE_PROJECT)
local test_repo = assert(vim.env.CODEX_TIMELINE_TEST_REPO)
vim.opt.runtimepath:prepend(project_root)

local timeline = require("codex_timeline")
timeline.setup({ auto_sync = true, annotate_on_buf_enter = false })
vim.cmd.cd(vim.fn.fnameescape(test_repo))
timeline.open()

local git = require("codex_timeline.git")
local synchronized = vim.wait(5000, function()
  return git.has_ref(test_repo, "refs/codex-timeline/session-project")
end, 25)
assert(synchronized, "existing repository was not synchronized on first open")
local opened = vim.wait(5000, function()
  return #require("codex_timeline.ui")._state.events == 4
end, 25)
assert(opened, ":CodexTimeline did not open the imported commit history and synchronization snapshot")
local events = require("codex_timeline.ui")._state.events
assert(events[1].sequence == 1 and events[1].subject == "create existing project", "root commit was not imported as #1")
assert(events[2].sequence == 2 and events[2].subject == "add project settings", "second commit was not imported as #2")
assert(events[3].sequence == 3 and events[3].subject == "extend existing feature", "third commit was not imported as #3")
assert(events[4].sequence == 4 and events[4].subject == "existing project baseline", "local sync state was not #4")
local root_changes = assert(git.changes(test_repo, events[1]))
assert(root_changes["existing.txt"].kind == "A", "root commit files were not treated as additions")
local _, root_highlights = assert(git.file_snapshot(test_repo, events[1], "existing.txt", root_changes["existing.txt"]))
assert(#root_highlights > 0 and root_highlights[1].kind == "add", "root commit lines were not highlighted")
assert(
  require("codex_timeline.ui")._state.ref == "refs/codex-timeline/session-project",
  ":CodexTimeline did not prefer the continuous project timeline over a legacy ref"
)
require("codex_timeline.ui").close()

print("existing repository Neovim sync passed")
