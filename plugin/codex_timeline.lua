if vim.g.loaded_codex_timeline then
  return
end
vim.g.loaded_codex_timeline = true

local timeline = require("codex_timeline")

vim.api.nvim_create_user_command("CodexTimeline", timeline.open, {
  desc = "Open the chronological Codex change timeline",
})
vim.api.nvim_create_user_command("CodexTimelineAnnotate", timeline.annotate, {
  desc = "Annotate lines with the Codex event that introduced them",
})
vim.api.nvim_create_user_command("CodexTimelineClear", function() timeline.clear(0) end, {
  desc = "Clear Codex timeline annotations",
})
vim.api.nvim_create_user_command("CodexTimelineSession", timeline.select_session, {
  desc = "Select a recorded Codex timeline session",
})
vim.api.nvim_create_user_command("CodexTimelineEnable", function() timeline.set_enabled(true) end, {
  desc = "Enable or resume Codex timeline recording for this repository",
})
vim.api.nvim_create_user_command("CodexTimelineDisable", function() timeline.set_enabled(false) end, {
  desc = "Disable Codex timeline recording for this repository",
})
vim.api.nvim_create_user_command("CodexTimelineSync", timeline.sync, {
  desc = "Create the existing-project baseline and synchronize future Codex changes",
})

vim.keymap.set("n", "]t", function() timeline.jump(1) end, { desc = "Next Codex timeline change" })
vim.keymap.set("n", "[t", function() timeline.jump(-1) end, { desc = "Previous Codex timeline change" })
