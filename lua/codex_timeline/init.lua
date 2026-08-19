local git = require("codex_timeline.git")
local ui = require("codex_timeline.ui")
local highlights = require("codex_timeline.highlights")

local M = {}
local namespace = vim.api.nvim_create_namespace("codex_timeline")
local config = {
  annotate_on_buf_enter = true,
  auto_sync = true,
  virtual_text = false,
  session = nil,
  live_refresh = true,
  refresh_interval = 750,
  colors = {},
}
local selected_refs = {}
local synced_roots = {}
local syncing_roots = {}
local project_ref = "refs/codex-timeline/session-project"
local module_path = debug.getinfo(1, "S").source:sub(2)
local plugin_root = vim.fn.fnamemodify(module_path, ":p:h:h:h")
local recorder = plugin_root .. "/bin/timeline"
local hook_installer = plugin_root .. "/bin/install-hooks"

local function root_for_current_buffer()
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" and vim.bo.buftype == "" then
    return git.root(vim.fn.fnamemodify(name, ":h"))
  end
  return git.root()
end

local function sync_root(root, notify_user, callback)
  if not root or not git.enabled(root) then
    if callback then callback(false) end
    return
  end
  if synced_roots[root] then
    if notify_user then
      vim.notify("Timeline is synchronized with this repository")
    end
    if callback then callback(true) end
    return
  end
  if syncing_roots[root] then
    syncing_roots[root].notify = syncing_roots[root].notify or notify_user
    if callback then
      table.insert(syncing_roots[root].callbacks, callback)
    end
    return
  end
  if vim.fn.executable(recorder) ~= 1 then
    if notify_user then
      vim.notify("Timeline recorder is not executable: " .. recorder, vim.log.levels.ERROR)
    end
    if callback then callback(false) end
    return
  end

  syncing_roots[root] = { notify = notify_user, callbacks = callback and { callback } or {} }
  vim.system({
    recorder, "sync", "--repo", root,
    "--label", "existing project baseline", "--event", "nvim-sync",
  }, { text = true }, function(result)
    vim.schedule(function()
      local pending = syncing_roots[root] or { notify = notify_user, callbacks = {} }
      syncing_roots[root] = nil
      if result.code == 0 then
        synced_roots[root] = true
        if pending.notify then
          vim.notify("Timeline synchronized existing commits and future Codex changes")
        end
      else
        if pending.notify then
          vim.notify("Timeline sync failed: " .. vim.trim(result.stderr or "unknown error"), vim.log.levels.ERROR)
        end
      end
      for _, queued_callback in ipairs(pending.callbacks) do
        queued_callback(result.code == 0)
      end
    end)
  end)
end

local function current_context()
  local buffer = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buffer)
  if name == "" or vim.bo[buffer].buftype ~= "" then
    return nil
  end
  local root = git.root(vim.fn.fnamemodify(name, ":h"))
  if not root then
    return nil
  end
  local ref = selected_refs[root]
    or (config.session and ("refs/codex-timeline/session-" .. config.session))
    or (git.has_ref(root, project_ref) and project_ref)
    or git.latest_ref(root)
  if not ref then
    return nil
  end
  return buffer, name, root, ref
end

function M.clear(buffer)
  vim.api.nvim_buf_clear_namespace(buffer or 0, namespace, 0, -1)
end

function M.annotate()
  local buffer, name, root, ref = current_context()
  if not buffer then
    return
  end
  M.clear(buffer)

  local events = git.events(root, ref)
  if not events then
    return
  end
  local sequence_by_hash = {}
  for _, event in ipairs(events) do
    sequence_by_hash[event.hash] = event.sequence
  end

  local relative = name:sub(#root + 2)
  local blame = git.blame(root, ref, relative)
  if not blame then
    return
  end

  for line, hash in pairs(blame) do
    local sequence = sequence_by_hash[hash]
    if sequence and sequence > 0 and line <= vim.api.nvim_buf_line_count(buffer) then
      local label = sequence < 100 and string.format("%02d", sequence) or "+"
      local extmark = {
        sign_text = label,
        sign_hl_group = "CodexTimelineSign",
        priority = 20,
      }
      if config.virtual_text then
        extmark.virt_text = { { "  change #" .. sequence, "CodexTimelineVirtualText" } }
        extmark.virt_text_pos = "eol"
      end
      vim.api.nvim_buf_set_extmark(buffer, namespace, line - 1, 0, extmark)
    end
  end
end

function M.jump(direction)
  local buffer = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)[1] - 1
  local marks = vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {})
  if direction > 0 then
    for _, mark in ipairs(marks) do
      if mark[2] > cursor then
        vim.api.nvim_win_set_cursor(0, { mark[2] + 1, 0 })
        return
      end
    end
  else
    for index = #marks, 1, -1 do
      if marks[index][2] < cursor then
        vim.api.nvim_win_set_cursor(0, { marks[index][2] + 1, 0 })
        return
      end
    end
  end
end

function M.open()
  local root = root_for_current_buffer()
  local live_options = {
    live_refresh = config.live_refresh,
    refresh_interval = config.refresh_interval,
  }
  if root and config.auto_sync and not selected_refs[root] and not config.session and not synced_roots[root] then
    sync_root(root, true, function(ok)
      if ok then ui.open(vim.tbl_extend("force", live_options, { ref = project_ref })) end
    end)
    return
  end
  if root and selected_refs[root] then
    ui.open(vim.tbl_extend("force", live_options, { ref = selected_refs[root] }))
  elseif root and not config.session and git.has_ref(root, project_ref) then
    ui.open(vim.tbl_extend("force", live_options, { ref = project_ref }))
  else
    ui.open(vim.tbl_extend("force", live_options, { session = config.session }))
  end
end

function M.select_session()
  local root = root_for_current_buffer()
  if not root then
    vim.notify("Timeline: current buffer is not in a Git repository", vim.log.levels.WARN)
    return
  end
  ui.select_session(function(ref)
    selected_refs[root] = ref
    M.annotate()
    ui.open({
      ref = ref,
      live_refresh = config.live_refresh,
      refresh_interval = config.refresh_interval,
    })
  end)
end

function M.set_enabled(enabled)
  local root = root_for_current_buffer()
  if not root then
    vim.notify("Timeline: current directory is not in a Git repository", vim.log.levels.WARN)
    return
  end
  local ok, err = git.set_enabled(root, enabled)
  if not ok then
    vim.notify("Timeline: " .. (err or "unable to update Git config"), vim.log.levels.ERROR)
    return
  end
  vim.notify("Timeline recording " .. (enabled and "enabled" or "disabled") .. " for " .. root)
end

function M.sync()
  local root = root_for_current_buffer()
  if not root then
    vim.notify("Timeline: current buffer is not in a Git repository", vim.log.levels.WARN)
    return
  end
  sync_root(root, true, function(ok)
    if ok then M.annotate() end
  end)
end

local function configure_hooks(uninstall)
  if vim.fn.executable(hook_installer) ~= 1 then
    vim.notify("Timeline hook installer is not executable: " .. hook_installer, vim.log.levels.ERROR)
    return
  end
  local args = { hook_installer }
  if uninstall then
    args[#args + 1] = "--uninstall"
  end
  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      local output = vim.trim(result.code == 0 and result.stdout or result.stderr)
      vim.notify(output ~= "" and output or (result.code == 0 and "Timeline hooks updated" or "Timeline hook update failed"),
        result.code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
    end)
  end)
end

function M.install_hooks()
  configure_hooks(false)
end

function M.uninstall_hooks()
  configure_hooks(true)
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  highlights.apply(config.colors)

  local group = vim.api.nvim_create_augroup("Timeline", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function() highlights.apply(config.colors) end,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "FileChangedShellPost" }, {
    group = group,
    callback = function()
      vim.schedule(function()
        local root = root_for_current_buffer()
        if config.auto_sync then
          sync_root(root, false, function(ok)
            if ok and config.annotate_on_buf_enter then M.annotate() end
          end)
        elseif config.annotate_on_buf_enter then
          M.annotate()
        end
      end)
    end,
  })
end

return M
