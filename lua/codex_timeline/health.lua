local M = {}

function M.check()
  vim.health.start("Codex Timeline")

  if vim.fn.executable("git") == 1 then
    vim.health.ok("Git is available")
  else
    vim.health.error("Git is not available on PATH")
    return
  end

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim 0.10+ is available")
  else
    vim.health.error("Neovim 0.10 or newer is required")
  end

  local git = require("codex_timeline.git")
  local root = git.root()
  if not root then
    vim.health.info("Current directory is not a Git repository")
    return
  end

  vim.health.ok("Repository: " .. root)
  if git.enabled(root) then
    vim.health.ok("Automatic recording is enabled (default for Git repositories)")
  else
    vim.health.warn("Automatic recording is explicitly disabled; run :CodexTimelineEnable to resume")
  end

  local ref = git.latest_ref(root)
  if ref then
    vim.health.ok("Latest recorded session: " .. ref:gsub("^refs/codex%-timeline/", ""))
  else
    vim.health.info("No timeline has been recorded yet; restart Codex after installing hooks")
  end
end

return M
