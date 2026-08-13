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
  return #require("codex_timeline.ui")._state.events == 1
end, 25)
assert(opened, ":CodexTimeline did not open after creating the first baseline")
assert(
  require("codex_timeline.ui")._state.ref == "refs/codex-timeline/session-project",
  ":CodexTimeline did not prefer the continuous project timeline over a legacy ref"
)
require("codex_timeline.ui").close()

print("existing repository Neovim sync passed")
