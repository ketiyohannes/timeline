local git = require("codex_timeline.git")

local M = {}
local namespace = vim.api.nvim_create_namespace("codex_timeline_snapshot")
local state = {
  windows = {},
  buffers = {},
  events = {},
  files = {},
  changes = {},
  root = nil,
  ref = nil,
  event = nil,
}

local function valid_window(window)
  return window and vim.api.nvim_win_is_valid(window)
end

local function close()
  local windows = state.windows
  state.windows = {}
  state.buffers = {}
  for _, window in pairs(windows) do
    if valid_window(window) then
      vim.api.nvim_win_close(window, true)
    end
  end
end

local function dimensions()
  local columns = vim.o.columns
  local rows = vim.o.lines - vim.o.cmdheight
  local width = math.max(74, math.floor(columns * 0.96))
  local height = math.max(14, math.floor(rows * 0.88))
  width = math.min(width, columns - 2)
  height = math.min(height, rows - 2)

  local changes_width = math.max(24, math.floor(width * 0.23))
  local files_width = math.max(25, math.floor(width * 0.25))
  if changes_width + files_width > width - 30 then
    changes_width = math.max(18, math.floor(width * 0.25))
    files_width = math.max(20, math.floor(width * 0.28))
  end
  return {
    row = math.floor((rows - height) / 2),
    col = math.floor((columns - width) / 2),
    width = width,
    height = height,
    changes_width = changes_width,
    files_width = files_width,
    source_width = width - changes_width - files_width - 4,
  }
end

local function set_lines(buffer, lines)
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, #lines > 0 and lines or { "" })
  vim.bo[buffer].modifiable = false
end

local function current_event()
  if not valid_window(state.windows.changes) then
    return nil
  end
  return state.events[vim.api.nvim_win_get_cursor(state.windows.changes)[1]]
end

local function current_file()
  if not valid_window(state.windows.files) then
    return nil
  end
  return state.files[vim.api.nvim_win_get_cursor(state.windows.files)[1]]
end

local function source_title(event)
  local marker = event.sequence == 0 and "base" or string.format("#%03d", event.sequence)
  return string.format(" %s · %s ", marker, event.subject)
end

local function render_source()
  local event, path = state.event, current_file()
  if not event or not path or not state.buffers.source then
    return
  end

  local lines, highlights, err = git.file_snapshot(state.root, event, path, state.changes[path])
  if not lines then
    vim.notify("Codex Timeline: " .. (err or "unable to read snapshot file"), vim.log.levels.ERROR)
    lines, highlights = { "" }, {}
  end

  local buffer = state.buffers.source
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
  set_lines(buffer, lines)
  vim.b[buffer].codex_timeline_path = path
  vim.bo[buffer].filetype = vim.filetype.match({ filename = path }) or ""

  for _, highlight in ipairs(highlights or {}) do
    local added = highlight.kind == "add"
    vim.api.nvim_buf_set_extmark(buffer, namespace, highlight.line - 1, 0, {
      sign_text = added and "+" or "-",
      sign_hl_group = added and "CodexTimelineAddSign" or "CodexTimelineDeleteSign",
      line_hl_group = added and "CodexTimelineAddLine" or "CodexTimelineDeleteLine",
      priority = 100,
    })
  end

  if valid_window(state.windows.source) then
    vim.api.nvim_win_set_config(state.windows.source, {
      title = source_title(event),
      title_pos = "center",
    })
    vim.api.nvim_win_set_cursor(state.windows.source, { 1, 0 })
  end
end

local function file_highlight(change)
  if not change then
    return nil
  end
  if change.kind == "A" then
    return "CodexTimelineAddFile"
  elseif change.kind == "D" then
    return "CodexTimelineDeleteFile"
  end
  return "CodexTimelineChangeFile"
end

local function render_event()
  local event = current_event()
  if not event then
    return
  end
  state.event = event

  local files, tree_err = git.tree(state.root, event)
  local changes, changes_err = git.changes(state.root, event)
  if not files or not changes then
    vim.notify("Codex Timeline: " .. (tree_err or changes_err or "unable to read snapshot"), vim.log.levels.ERROR)
    return
  end

  for path, change in pairs(changes) do
    if change.kind == "D" then
      files[#files + 1] = path
    end
  end
  table.sort(files)
  state.files, state.changes = files, changes

  local file_buffer = state.buffers.files
  vim.api.nvim_buf_clear_namespace(file_buffer, namespace, 0, -1)
  set_lines(file_buffer, files)
  for index, path in ipairs(files) do
    local group = file_highlight(changes[path])
    if group then
      vim.api.nvim_buf_set_extmark(file_buffer, namespace, index - 1, 0, {
        line_hl_group = group,
        priority = 50,
      })
    end
  end

  local selected = 1
  for index, path in ipairs(files) do
    if changes[path] then
      selected = index
      break
    end
  end
  if valid_window(state.windows.files) and #files > 0 then
    vim.api.nvim_win_set_cursor(state.windows.files, { selected, 0 })
  end
  render_source()
end

local function focus(role)
  if valid_window(state.windows[role]) then
    vim.api.nvim_set_current_win(state.windows[role])
  end
end

local function move_event(direction)
  if not valid_window(state.windows.changes) then
    return
  end
  local row = vim.api.nvim_win_get_cursor(state.windows.changes)[1]
  row = math.max(1, math.min(#state.events, row + direction))
  vim.api.nvim_win_set_cursor(state.windows.changes, { row, 0 })
  render_event()
end

local function map_all(lhs, callback, description)
  for _, buffer in pairs(state.buffers) do
    vim.keymap.set("n", lhs, callback, { buffer = buffer, silent = true, nowait = true, desc = description })
  end
end

function M.open(opts)
  opts = opts or {}
  close()
  local buffer_name = vim.api.nvim_buf_get_name(0)
  local root = git.root(buffer_name ~= "" and vim.fn.fnamemodify(buffer_name, ":h") or nil)
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
  for _, role in ipairs({ "changes", "files", "source" }) do
    state.buffers[role] = vim.api.nvim_create_buf(false, true)
    vim.b[state.buffers[role]].codex_timeline_role = role
  end

  state.windows.changes = vim.api.nvim_open_win(state.buffers.changes, true, {
    relative = "editor", row = size.row, col = size.col,
    width = size.changes_width, height = size.height,
    style = "minimal", border = "rounded", title = " Changes ", title_pos = "center",
  })
  state.windows.files = vim.api.nvim_open_win(state.buffers.files, false, {
    relative = "editor", row = size.row, col = size.col + size.changes_width + 2,
    width = size.files_width, height = size.height,
    style = "minimal", border = "rounded", title = " Codebase ", title_pos = "center",
  })
  state.windows.source = vim.api.nvim_open_win(state.buffers.source, false, {
    relative = "editor", row = size.row, col = size.col + size.changes_width + size.files_width + 4,
    width = size.source_width, height = size.height,
    style = "minimal", border = "rounded", title = " Code ", title_pos = "center",
  })

  local event_lines = {}
  for _, event in ipairs(events) do
    local marker = event.sequence == 0 and "base" or string.format("#%03d", event.sequence)
    event_lines[#event_lines + 1] = string.format("%-5s %s", marker, event.subject)
  end
  set_lines(state.buffers.changes, event_lines)
  for index, _ in ipairs(events) do
    vim.api.nvim_buf_add_highlight(
      state.buffers.changes,
      namespace,
      "CodexTimelineChangeNumber",
      index - 1,
      0,
      4
    )
  end
  vim.bo[state.buffers.changes].filetype = "codex-timeline"
  vim.bo[state.buffers.files].filetype = "codex-timeline-files"

  for _, role in ipairs({ "changes", "files" }) do
    vim.wo[state.windows[role]].cursorline = true
    vim.wo[state.windows[role]].wrap = false
    vim.wo[state.windows[role]].number = false
    vim.wo[state.windows[role]].relativenumber = false
    vim.wo[state.windows[role]].signcolumn = "no"
    vim.wo[state.windows[role]].winhighlight = table.concat({
      "CursorLine:CodexTimelineCursorLine",
      "FloatBorder:CodexTimelineBorder",
      "FloatTitle:CodexTimelineTitle",
    }, ",")
  end
  vim.wo[state.windows.source].wrap = false
  vim.wo[state.windows.source].number = true
  vim.wo[state.windows.source].relativenumber = false
  vim.wo[state.windows.source].signcolumn = "yes:1"
  vim.wo[state.windows.source].winhighlight = table.concat({
    "FloatBorder:CodexTimelineBorder",
    "FloatTitle:CodexTimelineTitle",
  }, ",")

  vim.api.nvim_create_autocmd("CursorMoved", { buffer = state.buffers.changes, callback = render_event })
  vim.api.nvim_create_autocmd("CursorMoved", { buffer = state.buffers.files, callback = render_source })
  vim.api.nvim_create_autocmd("BufWipeout", { buffer = state.buffers.changes, once = true, callback = close })

  map_all("q", close, "Close Codex timeline")
  map_all("<Esc>", close, "Close Codex timeline")
  map_all("[c", function() move_event(-1) end, "Previous recorded change")
  map_all("]c", function() move_event(1) end, "Next recorded change")
  map_all("1", function() focus("changes") end, "Focus recorded changes")
  map_all("2", function() focus("files") end, "Focus snapshot codebase")
  map_all("3", function() focus("source") end, "Focus snapshot source")
  vim.keymap.set("n", "<CR>", function() focus("files") end, { buffer = state.buffers.changes, silent = true })
  vim.keymap.set("n", "<CR>", function() focus("source") end, { buffer = state.buffers.files, silent = true })
  vim.keymap.set("n", "r", function()
    close()
    vim.schedule(function() M.open(opts) end)
  end, { buffer = state.buffers.changes, silent = true })

  if #events > 1 then
    vim.api.nvim_win_set_cursor(state.windows.changes, { #events, 0 })
  end
  render_event()
end

function M.select_session(callback)
  local buffer_name = vim.api.nvim_buf_get_name(0)
  local root = git.root(buffer_name ~= "" and vim.fn.fnamemodify(buffer_name, ":h") or nil)
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
      return item.ref:gsub("^refs/codex%-timeline/session%-", "")
    end,
  }, function(item)
    if item then
      callback(item.ref)
    end
  end)
end

M.close = close
M._state = state

return M
