local project_root = vim.env.CODEX_TIMELINE_PROJECT
assert(project_root and project_root ~= "", "CODEX_TIMELINE_PROJECT is required")
vim.opt.runtimepath:prepend(project_root)

require("codex_timeline").setup({ auto_sync = false, annotate_on_buf_enter = false })
vim.cmd.runtime("plugin/codex_timeline.lua")

assert(vim.fn.exists(":CodexTimeline") == 2, "CodexTimeline command was not registered")
assert(vim.fn.exists(":CodexTimelineAnnotate") == 2, "annotation command was not registered")
assert(vim.fn.exists(":CodexTimelineEnable") == 2, "enable command was not registered")
assert(vim.fn.exists(":CodexTimelineSync") == 2, "sync command was not registered")
assert(type(require("codex_timeline.git").events) == "function", "Git module did not load")
assert(type(require("codex_timeline.health").check) == "function", "health module did not load")

print("neovim test passed")
