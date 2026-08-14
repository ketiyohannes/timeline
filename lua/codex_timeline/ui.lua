local git = require("codex_timeline.git")

local M = {}
local namespace = vim.api.nvim_create_namespace("codex_timeline_snapshot")
local search_namespace = vim.api.nvim_create_namespace("timeline_search")
local state = {
  windows = {},
  buffers = {},
  events = {},
  files = {},
  changes = {},
  root = nil,
  ref = nil,
  event = nil,
  augroup = nil,
  search = { query = "", matches = {}, index = 0 },
}

local function valid_window(window)
  return window and vim.api.nvim_win_is_valid(window)
end

local function close()
  local windows = state.windows
  state.windows = {}
  state.buffers = {}
  state.search = { query = "", matches = {}, index = 0 }
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    state.augroup = nil
  end
  for _, window in pairs(windows) do
    if valid_window(window) then
      vim.api.nvim_win_close(window, true)
    end
  end
end

local function event_marker(event)
  return event.sequence == 0 and "base" or string.format("#%03d", event.sequence)
end

local function dimensions()
  local columns = math.max(vim.o.columns, 9)
  local rows = math.max(vim.o.lines - vim.o.cmdheight, 4)
  local outer_width = math.min(columns, math.max(9, math.floor(columns * 0.96)))
  local outer_height = math.min(rows, math.max(4, math.floor(rows * 0.88)))
  local content_width = outer_width - 6 -- three pairs of vertical borders
  local changes_width = math.max(1, math.floor(content_width * 0.22))
  local files_width = math.max(1, math.floor(content_width * 0.25))
  local source_width = math.max(1, content_width - changes_width - files_width)
  return {
    row = math.max(0, math.floor((rows - outer_height) / 2)),
    col = math.max(0, math.floor((columns - outer_width) / 2)),
    width = outer_width,
    height = outer_height - 2,
    changes_width = changes_width,
    files_width = files_width,
    source_width = source_width,
  }
end

local function apply_layout()
  if not valid_window(state.windows.changes)
    or not valid_window(state.windows.files)
    or not valid_window(state.windows.source) then
    return
  end

  local size = dimensions()
  vim.api.nvim_win_set_config(state.windows.changes, {
    relative = "editor", row = size.row, col = size.col,
    width = size.changes_width, height = size.height,
  })
  vim.api.nvim_win_set_config(state.windows.files, {
    relative = "editor", row = size.row, col = size.col + size.changes_width + 2,
    width = size.files_width, height = size.height,
  })
  vim.api.nvim_win_set_config(state.windows.source, {
    relative = "editor", row = size.row, col = size.col + size.changes_width + size.files_width + 4,
    width = size.source_width, height = size.height,
  })
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
  return string.format(" %s · %s ", event_marker(event), event.subject)
end

local function render_source()
  local event, path = state.event, current_file()
  if not event or not path or not state.buffers.source then
    return
  end

  local lines, highlights, err = git.file_snapshot(state.root, event, path, state.changes[path])
  if not lines then
    vim.notify("Timeline: " .. (err or "unable to read snapshot file"), vim.log.levels.ERROR)
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
    local first_changed_line = highlights and highlights[1] and highlights[1].line or 1
    first_changed_line = math.max(1, math.min(first_changed_line, #lines))
    vim.api.nvim_win_set_cursor(state.windows.source, { first_changed_line, 0 })
    vim.api.nvim_win_call(state.windows.source, function()
      vim.cmd("normal! zt")
    end)
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
    vim.notify("Timeline: " .. (tree_err or changes_err or "unable to read snapshot"), vim.log.levels.ERROR)
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

local function search_title()
  if state.search.query == "" then
    return " Changes "
  end
  local count = #state.search.matches
  if count == 0 then
    return " Changes · no matches "
  end
  return string.format(" Changes · %d %s ", count, count == 1 and "match" or "matches")
end

local function render_search()
  local buffer = state.buffers.changes
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    return
  end

  vim.api.nvim_buf_clear_namespace(buffer, search_namespace, 0, -1)
  for match_index, row in ipairs(state.search.matches) do
    vim.api.nvim_buf_set_extmark(buffer, search_namespace, row - 1, 0, {
      line_hl_group = match_index == state.search.index and "TimelineSearchCurrent" or "TimelineSearchMatch",
      priority = match_index == state.search.index and 80 or 60,
    })
  end

  if valid_window(state.windows.changes) then
    vim.api.nvim_win_set_config(state.windows.changes, {
      title = search_title(),
      title_pos = "center",
    })
  end
end

local function select_search_match(index)
  local matches = state.search.matches
  if #matches == 0 or not valid_window(state.windows.changes) then
    return
  end
  state.search.index = ((index - 1) % #matches) + 1
  vim.api.nvim_win_set_cursor(state.windows.changes, { matches[state.search.index], 0 })
  render_search()
  render_event()
end

local function sync_search_to_cursor()
  if #state.search.matches == 0 or not valid_window(state.windows.changes) then
    return
  end
  local row = vim.api.nvim_win_get_cursor(state.windows.changes)[1]
  for index, match_row in ipairs(state.search.matches) do
    if match_row == row then
      state.search.index = index
      render_search()
      return
    end
  end
end

function M.search(query)
  if query == nil then
    vim.ui.input({ prompt = "Search commits: ", default = state.search.query }, function(input)
      if input ~= nil then
        M.search(input)
      end
    end)
    return
  end

  query = vim.trim(query)
  state.search = { query = query, matches = {}, index = 0 }
  if query == "" then
    render_search()
    return
  end

  local needle = query:lower()
  for row, event in ipairs(state.events) do
    local searchable = string.format("%s %s", event_marker(event), event.subject):lower()
    if searchable:find(needle, 1, true) then
      state.search.matches[#state.search.matches + 1] = row
    end
  end

  if #state.search.matches == 0 then
    render_search()
    vim.notify(string.format('Timeline: no commits match "%s"', query), vim.log.levels.INFO)
    return
  end

  local current_row = valid_window(state.windows.changes)
      and vim.api.nvim_win_get_cursor(state.windows.changes)[1]
    or 1
  local selected = 1
  for index, row in ipairs(state.search.matches) do
    if row >= current_row then
      selected = index
      break
    end
  end
  select_search_match(selected)
end

function M.next_match(direction)
  if #state.search.matches == 0 then
    return
  end
  select_search_match(state.search.index + (direction or 1))
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
    vim.notify("Timeline: current buffer is not in a Git repository", vim.log.levels.WARN)
    return
  end
  local ref = opts.ref or (opts.session and ("refs/codex-timeline/session-" .. opts.session)) or git.latest_ref(root)
  if not ref then
    vim.notify("Timeline: no recorded session found", vim.log.levels.INFO)
    return
  end
  local events, err = git.events(root, ref)
  if not events then
    vim.notify("Timeline: " .. (err or "unable to load events"), vim.log.levels.ERROR)
    return
  end

  state.root, state.ref, state.events = root, ref, events
  state.search = { query = "", matches = {}, index = 0 }
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
    event_lines[#event_lines + 1] = string.format("%-5s %s", event_marker(event), event.subject)
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

  state.augroup = vim.api.nvim_create_augroup("TimelineUI", { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = state.augroup, buffer = state.buffers.changes, callback = function()
      sync_search_to_cursor()
      render_event()
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = state.augroup, buffer = state.buffers.files, callback = render_source,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = state.augroup,
    callback = apply_layout,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = state.augroup, buffer = state.buffers.changes, once = true, callback = close,
  })

  map_all("q", close, "Close Timeline")
  map_all("<Esc>", close, "Close Timeline")
  map_all("[c", function() move_event(-1) end, "Previous recorded change")
  map_all("]c", function() move_event(1) end, "Next recorded change")
  map_all("/", function() M.search() end, "Search commits")
  map_all("n", function() M.next_match(1) end, "Next commit search match")
  map_all("N", function() M.next_match(-1) end, "Previous commit search match")
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
    vim.notify("Timeline: current buffer is not in a Git repository", vim.log.levels.WARN)
    return
  end
  local refs, err = git.refs(root)
  if not refs then
    vim.notify("Timeline: " .. (err or "unable to load sessions"), vim.log.levels.ERROR)
    return
  end
  if #refs == 0 then
    vim.notify("Timeline: no recorded session found", vim.log.levels.INFO)
    return
  end
  vim.ui.select(refs, {
    prompt = "Timeline session",
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
M.resize = apply_layout
M._state = state

return M
