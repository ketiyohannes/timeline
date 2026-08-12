local git = require("codex_timeline.git")

local M = {}
local state = { windows = {}, buffers = {}, events = {}, root = nil, ref = nil }

local function valid_window(window)
  return window and vim.api.nvim_win_is_valid(window)
end

local function close()
  for _, window in pairs(state.windows) do
    if valid_window(window) then
      vim.api.nvim_win_close(window, true)
    end
  end
  state.windows = {}
  state.buffers = {}
end

local function dimensions()
  local total_width = vim.o.columns
  local total_height = vim.o.lines - vim.o.cmdheight
  local width = math.max(72, math.floor(total_width * 0.88))
  local height = math.max(12, math.floor(total_height * 0.72))
  width = math.min(width, total_width - 4)
  height = math.min(height, total_height - 4)
  local list_width = math.max(28, math.floor(width * 0.34))
  return {
    row = math.floor((total_height - height) / 2),
    col = math.floor((total_width - width) / 2),
    width = width,
    height = height,
    list_width = list_width,
    diff_width = width - list_width - 2,
  }
end

local function set_lines(buffer, lines)
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].modifiable = false
end

local function preview()
  if not valid_window(state.windows.list) or not state.buffers.diff then
    return
  end
  local row = vim.api.nvim_win_get_cursor(state.windows.list)[1]
  local event = state.events[row]
  if not event then
    return
  end

  local patch, err = git.diff(state.root, event)
  local lines
  if not patch then
    lines = { "Unable to read event diff", "", err or "Unknown Git error" }
  elseif patch == "" then
    lines = { "Baseline snapshot", "", "No previous event exists to compare." }
  else
    lines = vim.split(patch, "\n", { plain = true })
  end
  set_lines(state.buffers.diff, lines)
  vim.api.nvim_win_set_config(state.windows.diff, {
    title = string.format(" Change #%03d · %s ", event.sequence, event.subject),
    title_pos = "center",
  })
end

local function open_file()
  local row = vim.api.nvim_win_get_cursor(state.windows.list)[1]
  local event = state.events[row]
  if not event then
    return
  end
  local files = git.files(state.root, event)
  if #files == 0 then
    return
  end
  local path = state.root .. "/" .. files[1]
  if vim.fn.filereadable(path) ~= 1 then
    vim.notify("Codex Timeline: file no longer exists: " .. files[1], vim.log.levels.INFO)
    return
  end
  close()
  vim.cmd.edit(vim.fn.fnameescape(path))
end

function M.open(opts)
  close()
  local root = git.root(vim.api.nvim_buf_get_name(0) ~= "" and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":h") or nil)
  if not root then
    vim.notify("Codex Timeline: current buffer is not in a Git repository", vim.log.levels.WARN)
    return
  end
  local ref = opts.ref or (opts.session and ("refs/codex-timeline/session-" .. opts.session)) or git.latest_ref(root)
  if not ref then
    vim.notify("Codex Timeline: no recorded session found", vim.log.levels.INFO)
    return
  end
  local events, err = git.events(root, ref)
  if not events then
    vim.notify("Codex Timeline: " .. (err or "unable to load events"), vim.log.levels.ERROR)
    return
  end

  state.root, state.ref, state.events = root, ref, events
  local size = dimensions()
  local list_buffer = vim.api.nvim_create_buf(false, true)
  local diff_buffer = vim.api.nvim_create_buf(false, true)
  state.buffers = { list = list_buffer, diff = diff_buffer }

  state.windows.list = vim.api.nvim_open_win(list_buffer, true, {
    relative = "editor", row = size.row, col = size.col,
    width = size.list_width, height = size.height,
    style = "minimal", border = "rounded", title = " Codex timeline ", title_pos = "center",
  })
  state.windows.diff = vim.api.nvim_open_win(diff_buffer, false, {
    relative = "editor", row = size.row, col = size.col + size.list_width + 2,
    width = size.diff_width, height = size.height,
    style = "minimal", border = "rounded", title = " Change ", title_pos = "center",
  })

  local lines = {}
  for _, item in ipairs(events) do
    local marker = item.sequence == 0 and "base" or string.format("#%03d", item.sequence)
    lines[#lines + 1] = string.format("%-4s  %s  %s", marker, item.time, item.subject)
  end
  set_lines(list_buffer, lines)
  vim.bo[list_buffer].filetype = "codex-timeline"
  vim.bo[diff_buffer].filetype = "diff"
  vim.wo[state.windows.list].cursorline = true
  vim.wo[state.windows.list].wrap = false
  vim.wo[state.windows.diff].wrap = false

  local map_opts = { buffer = list_buffer, silent = true, nowait = true }
  vim.keymap.set("n", "q", close, map_opts)
  vim.keymap.set("n", "<Esc>", close, map_opts)
  vim.keymap.set("n", "<CR>", open_file, map_opts)
  vim.keymap.set("n", "r", function()
    close()
    vim.schedule(function() M.open(opts) end)
  end, map_opts)
  vim.api.nvim_create_autocmd("CursorMoved", { buffer = list_buffer, callback = preview })
  vim.api.nvim_create_autocmd("BufWipeout", { buffer = list_buffer, once = true, callback = close })

  if #events > 1 then
    vim.api.nvim_win_set_cursor(state.windows.list, { #events, 0 })
  end
  preview()
end

function M.select_session(callback)
  local root = git.root(vim.api.nvim_buf_get_name(0) ~= "" and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":h") or nil)
  if not root then
    vim.notify("Codex Timeline: current buffer is not in a Git repository", vim.log.levels.WARN)
    return
  end
  local refs, err = git.refs(root)
  if not refs then
    vim.notify("Codex Timeline: " .. (err or "unable to load sessions"), vim.log.levels.ERROR)
    return
  end
  if #refs == 0 then
    vim.notify("Codex Timeline: no recorded session found", vim.log.levels.INFO)
    return
  end
  vim.ui.select(refs, {
    prompt = "Codex timeline session",
    format_item = function(item)
      local name = item.ref:gsub("^refs/codex%-timeline/session%-", "")
      return string.format("%s  %s", item.time, name)
    end,
  }, function(item)
    if item then
      callback(item.ref)
    end
  end)
end

M.close = close

return M
