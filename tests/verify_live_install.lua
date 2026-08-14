local root = assert(vim.env.TIMELINE_PROJECT)
local session = assert(vim.env.TIMELINE_SESSION)

local timeline = require("timeline")
timeline.setup({ auto_sync = false, annotate_on_buf_enter = false, session = session })
vim.cmd.edit(vim.fn.fnameescape(root .. "/README.md"))
timeline.annotate()

local namespace = vim.api.nvim_get_namespaces().codex_timeline
local marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })
assert(#marks >= 1, "installed plugin did not add event signs")
for _, mark in ipairs(marks) do
  assert(mark[4].sign_text == "01", "live change should belong to event #1")
end

timeline.open()
local patch_found = false
for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
  if vim.b[buffer].codex_timeline_role == "source" then
    local contents = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
    if contents:find("## Architecture", 1, true) then
      patch_found = true
      break
    end
  end
end
assert(patch_found, "installed plugin did not render the full live snapshot file")
require("codex_timeline.ui").close()

print("live installed Neovim test passed")
