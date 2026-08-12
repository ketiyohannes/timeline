local project_root = assert(vim.env.CODEX_TIMELINE_PROJECT)
local test_repo = assert(vim.env.CODEX_TIMELINE_TEST_REPO)
vim.opt.runtimepath:prepend(project_root)

local timeline = require("codex_timeline")
timeline.setup({ annotate_on_buf_enter = false, session = "nvim" })
vim.cmd.edit(vim.fn.fnameescape(test_repo .. "/example.txt"))
timeline.annotate()

local namespace = vim.api.nvim_get_namespaces().codex_timeline
local marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })
assert(#marks == 1, "expected exactly one annotated line")
assert(marks[1][2] == 1, "expected beta on the second line")
assert(marks[1][4].sign_text == "01", "expected event #1 sign")

timeline.open()
local diff_found = false
for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[buffer].filetype == "diff" then
    local text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
    if text:find("+beta", 1, true) then
      diff_found = true
    end
  end
end
assert(diff_found, "timeline preview did not contain the expected patch")
require("codex_timeline.ui").close()

-- Commands invoked from virtual buffers (including :checkhealth output) must
-- fall back to Neovim's cwd instead of using a health:// URI as a process cwd.
vim.cmd.enew()
vim.bo.buftype = "nofile"
vim.api.nvim_buf_set_name(0, "health://codex_timeline")
vim.cmd.lcd(vim.fn.fnameescape(test_repo))
require("codex_timeline.ui").open({ session = "nvim" })
local timeline_window_found = false
for _, window in ipairs(vim.api.nvim_list_wins()) do
  local buffer = vim.api.nvim_win_get_buf(window)
  if vim.bo[buffer].filetype == "codex-timeline" then
    timeline_window_found = true
    break
  end
end
assert(timeline_window_found, "timeline did not open from a virtual health buffer")
require("codex_timeline.ui").close()

print("neovim integration test passed")
