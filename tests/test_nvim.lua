local project_root = vim.env.CODEX_TIMELINE_PROJECT
assert(project_root and project_root ~= "", "CODEX_TIMELINE_PROJECT is required")
vim.opt.runtimepath:prepend(project_root)

require("codex_timeline").setup({ auto_sync = false, annotate_on_buf_enter = false })
vim.cmd.runtime("plugin/codex_timeline.lua")

local add_line = vim.api.nvim_get_hl(0, { name = "CodexTimelineAddLine" })
local delete_sign = vim.api.nvim_get_hl(0, { name = "CodexTimelineDeleteSign" })
assert(add_line.bg and add_line.bold, "added lines should have a bold high-contrast background")
assert(delete_sign.fg and delete_sign.bg and delete_sign.bold, "deletion signs should be bold and high contrast")
local dark_add_bg = add_line.bg
vim.o.background = "light"
vim.cmd.doautocmd("ColorScheme")
local light_add = vim.api.nvim_get_hl(0, { name = "CodexTimelineAddLine" })
assert(light_add.bg and light_add.bg ~= dark_add_bg, "timeline palette should adapt to a light colorscheme")
vim.o.background = "dark"
vim.cmd.doautocmd("ColorScheme")

assert(vim.fn.exists(":CodexTimeline") == 2, "CodexTimeline command was not registered")
assert(vim.fn.exists(":CodexTimelineAnnotate") == 2, "annotation command was not registered")
assert(vim.fn.exists(":CodexTimelineEnable") == 2, "enable command was not registered")
assert(vim.fn.exists(":CodexTimelineSync") == 2, "sync command was not registered")
assert(type(require("codex_timeline.git").events) == "function", "Git module did not load")
assert(type(require("codex_timeline.health").check) == "function", "health module did not load")

print("neovim test passed")
