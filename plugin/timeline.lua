if vim.g.loaded_timeline then
  return
end
vim.g.loaded_timeline = true
vim.g.loaded_codex_timeline = true

local timeline = require("timeline")

vim.api.nvim_create_user_command("Timeline", timeline.open, {
  desc = "Open the chronological Codex change timeline",
})
vim.api.nvim_create_user_command("TimelineAnnotate", timeline.annotate, {
  desc = "Annotate lines with the Codex event that introduced them",
})
vim.api.nvim_create_user_command("TimelineClear", function() timeline.clear(0) end, {
  desc = "Clear Timeline annotations",
})
vim.api.nvim_create_user_command("TimelineSession", timeline.select_session, {
  desc = "Select a recorded Timeline session",
})
vim.api.nvim_create_user_command("TimelineEnable", function() timeline.set_enabled(true) end, {
  desc = "Enable or resume Codex timeline recording for this repository",
})
vim.api.nvim_create_user_command("TimelineDisable", function() timeline.set_enabled(false) end, {
  desc = "Disable Codex timeline recording for this repository",
})
vim.api.nvim_create_user_command("TimelineSync", timeline.sync, {
  desc = "Create the existing-project baseline and synchronize future Codex changes",
})
vim.api.nvim_create_user_command("TimelineInstallHooks", timeline.install_hooks, {
  desc = "Install Timeline's Codex lifecycle hooks",
})
vim.api.nvim_create_user_command("TimelineUninstallHooks", timeline.uninstall_hooks, {
  desc = "Remove Timeline's Codex lifecycle hooks",
})

-- Keep the old command names available so upgrading does not break mappings.
vim.api.nvim_create_user_command("CodexTimeline", timeline.open, { desc = "Deprecated alias for :Timeline" })
vim.api.nvim_create_user_command("CodexTimelineAnnotate", timeline.annotate, { desc = "Deprecated alias" })
vim.api.nvim_create_user_command("CodexTimelineClear", function() timeline.clear(0) end, { desc = "Deprecated alias" })
vim.api.nvim_create_user_command("CodexTimelineSession", timeline.select_session, { desc = "Deprecated alias" })
vim.api.nvim_create_user_command("CodexTimelineEnable", function() timeline.set_enabled(true) end, { desc = "Deprecated alias" })
vim.api.nvim_create_user_command("CodexTimelineDisable", function() timeline.set_enabled(false) end, { desc = "Deprecated alias" })
vim.api.nvim_create_user_command("CodexTimelineSync", timeline.sync, { desc = "Deprecated alias" })

vim.keymap.set("n", "]t", function() timeline.jump(1) end, { desc = "Next Timeline change" })
vim.keymap.set("n", "[t", function() timeline.jump(-1) end, { desc = "Previous Timeline change" })
