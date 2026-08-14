local git = require("codex_timeline.git")

local M = {}
local namespace = vim.api.nvim_create_namespace("codex_timeline_snapshot")
local search_namespace = vim.api.nvim_create_namespace("timeline_search")
local file_search_namespace = vim.api.nvim_create_namespace("timeline_file_search")
local code_search_namespace = vim.api.nvim_create_namespace("timeline_code_search")
local update_search_bar
local render_code_search
local apply_file_filter

local function empty_code_search(scope)
  return { query = "", matches = {}, index = 0, scope = scope or "file" }
end

local state = {
  windows = {},
  buffers = {},
  events = {},
  visible_events = {},
  files = {},
  visible_files = {},
  changes = {},
  root = nil,
  ref = nil,
  event = nil,
  augroup = nil,
  search = { query = "", matches = {}, index = 0 },
  file_search = { query = "", matches = {}, index = 0 },
  code_search = empty_code_search(),
  snapshot_cache = {},
  navigating_code_search = false,
  search_bars = {},
}

local function valid_window(window)
  return window and vim.api.nvim_win_is_valid(window)
end

local function close()
  local windows = state.windows
  local search_bars = state.search_bars
  state.windows = {}
  state.buffers = {}
  state.search_bars = {}
  state.visible_events = {}
  state.visible_files = {}
  state.search = { query = "", matches = {}, index = 0 }
  state.file_search = { query = "", matches = {}, index = 0 }
  state.code_search = empty_code_search()
  state.snapshot_cache = {}
  state.navigating_code_search = false
  state.event = nil
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    state.augroup = nil
  end
  for _, bar in pairs(search_bars) do
    if valid_window(bar.window) then
      vim.api.nvim_win_close(bar.window, true)
    end
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

local function search_bar_open(role)
  local bar = state.search_bars[role]
  return bar and valid_window(bar.window)
end

local function pane_offset(role, height)
  return search_bar_open(role) and height >= 4 and 3 or 0
end

local function apply_layout()
  if not valid_window(state.windows.changes)
    or not valid_window(state.windows.files)
    or not valid_window(state.windows.source) then
    return
  end

  local size = dimensions()
  local changes_offset = pane_offset("commits", size.height)
  local files_offset = pane_offset("files", size.height)
  local source_offset = pane_offset("code", size.height)
  vim.api.nvim_win_set_config(state.windows.changes, {
    relative = "editor", row = size.row + changes_offset, col = size.col,
    width = size.changes_width, height = math.max(1, size.height - changes_offset),
  })
  vim.api.nvim_win_set_config(state.windows.files, {
    relative = "editor", row = size.row + files_offset, col = size.col + size.changes_width + 2,
    width = size.files_width, height = math.max(1, size.height - files_offset),
  })
  vim.api.nvim_win_set_config(state.windows.source, {
    relative = "editor", row = size.row + source_offset,
    col = size.col + size.changes_width + size.files_width + 4,
    width = size.source_width, height = math.max(1, size.height - source_offset),
  })

  local commit_bar = state.search_bars.commits
  if commit_bar and valid_window(commit_bar.window) then
    vim.api.nvim_win_set_config(commit_bar.window, {
      relative = "editor", row = size.row, col = size.col,
      width = size.changes_width, height = 1,
    })
  end
  local file_bar = state.search_bars.files
  if file_bar and valid_window(file_bar.window) then
    vim.api.nvim_win_set_config(file_bar.window, {
      relative = "editor", row = size.row, col = size.col + size.changes_width + 2,
      width = size.files_width, height = 1,
    })
  end
  local code_bar = state.search_bars.code
  if code_bar and valid_window(code_bar.window) then
    vim.api.nvim_win_set_config(code_bar.window, {
      relative = "editor", row = size.row,
      col = size.col + size.changes_width + size.files_width + 4,
      width = size.source_width, height = 1,
    })
  end
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
  return state.visible_events[vim.api.nvim_win_get_cursor(state.windows.changes)[1]]
end

local function current_file()
  if not valid_window(state.windows.files) then
    return nil
  end
  return state.visible_files[vim.api.nvim_win_get_cursor(state.windows.files)[1]]
end

local function source_title(event)
  return string.format(" %s · %s ", event_marker(event), event.subject)
end

local function source_winbar(path)
  local escaped = path:gsub("%%", "%%%%")
  return string.format("%%#CodexTimelineFilePath#%%=%%< %s %%=", escaped)
end

local function get_file_snapshot(path)
  local cached = state.snapshot_cache[path]
  if cached then
    return cached.lines, cached.highlights, cached.err
  end
  local lines, highlights, err = git.file_snapshot(state.root, state.event, path, state.changes[path])
  state.snapshot_cache[path] = { lines = lines, highlights = highlights, err = err }
  return lines, highlights, err
end

local function render_source()
  local event, path = state.event, current_file()
  if not event or not path or not state.buffers.source then
    return
  end

  local lines, highlights, err = get_file_snapshot(path)
  if not lines then
    vim.notify("Timeline: " .. (err or "unable to read snapshot file"), vim.log.levels.ERROR)
    lines, highlights = { "" }, {}
  end

  local buffer = state.buffers.source
  local previous_path = vim.b[buffer].codex_timeline_path
  if previous_path and previous_path ~= path and not state.navigating_code_search then
    state.code_search = empty_code_search()
    if update_search_bar then
      update_search_bar("code", "")
    end
  end
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
  vim.api.nvim_buf_clear_namespace(buffer, code_search_namespace, 0, -1)
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
    vim.wo[state.windows.source].winbar = source_winbar(path)
    local first_changed_line = highlights and highlights[1] and highlights[1].line or 1
    first_changed_line = math.max(1, math.min(first_changed_line, #lines))
    vim.api.nvim_win_set_cursor(state.windows.source, { first_changed_line, 0 })
    vim.api.nvim_win_call(state.windows.source, function()
      vim.cmd("normal! zt")
    end)
    if state.code_search.query ~= "" and render_code_search then
      render_code_search(true)
    end
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

local function match_title(label, query, count)
  if query == "" then
    return string.format(" %s ", label)
  end
  if count == 0 then
    return string.format(" %s · no matches ", label)
  end
  return string.format(" %s · %d %s ", label, count, count == 1 and "match" or "matches")
end

local function render_match_highlights(buffer, search_ns, count, current)
  vim.api.nvim_buf_clear_namespace(buffer, search_ns, 0, -1)
  for index = 1, count do
    vim.api.nvim_buf_set_extmark(buffer, search_ns, index - 1, 0, {
      line_hl_group = index == current and "TimelineSearchCurrent" or "TimelineSearchMatch",
      priority = index == current and 80 or 60,
    })
  end
end

render_code_search = function(jump)
  local buffer = state.buffers.source
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  local path = current_file()
  vim.api.nvim_buf_clear_namespace(buffer, code_search_namespace, 0, -1)
  for index, match in ipairs(state.code_search.matches) do
    if match.path == path then
      local current = index == state.code_search.index
      local group = current and "TimelineCodeSearchCurrent" or "TimelineCodeSearchMatch"
      local options = { priority = current and 170 or 150 }
      if match.line_only then
        options.line_hl_group = group
      else
        options.end_col = match.end_col
        options.hl_group = group
      end
      vim.api.nvim_buf_set_extmark(buffer, code_search_namespace, match.line - 1, match.start_col, options)
    end
  end
  if update_search_bar then
    update_search_bar("code", state.code_search.query)
  end

  local match = state.code_search.matches[state.code_search.index]
  if jump and match and match.path == path and valid_window(state.windows.source) then
    vim.api.nvim_win_set_cursor(state.windows.source, { match.line, match.start_col })
    vim.api.nvim_win_call(state.windows.source, function()
      vim.cmd("normal! zz")
    end)
  end
end

local function append_code_matches(matches, path, lines, needle)
  for line_number, line in ipairs(lines or {}) do
    local searchable = line:lower()
    local from = 1
    while true do
      local start_index, end_index = searchable:find(needle, from, true)
      if not start_index then
        break
      end
      matches[#matches + 1] = {
        path = path,
        line = line_number,
        start_col = start_index - 1,
        end_col = end_index,
      }
      from = end_index + 1
    end
  end
end

local function navigate_code_match(index)
  local count = #state.code_search.matches
  if count == 0 then
    render_code_search(false)
    return
  end
  state.code_search.index = ((index - 1) % count) + 1
  local match = state.code_search.matches[state.code_search.index]
  if match.path ~= current_file() then
    state.navigating_code_search = true
    apply_file_filter("", match.path)
    state.navigating_code_search = false
    if update_search_bar then
      update_search_bar("files", "")
    end
  end
  render_code_search(true)
end

function M.search_code(query)
  if query == nil then
    M.toggle_search_bar("code")
    return
  end
  query = vim.trim(query)
  local path = current_file()
  if not path then
    return
  end

  local cursor = valid_window(state.windows.source)
      and vim.api.nvim_win_get_cursor(state.windows.source)
    or { 1, 0 }
  local matches = {}
  local requested_line = query:match("^:(%d+)$")
  if requested_line then
    local lines = get_file_snapshot(path)
    lines = lines or {}
    requested_line = tonumber(requested_line)
    if requested_line >= 1 and requested_line <= #lines then
      matches[1] = { path = path, line = requested_line, start_col = 0, line_only = true }
    end
  elseif query ~= "" then
    local needle = query:lower()
    if state.code_search.scope == "commit" then
      local candidates = {}
      for _, candidate in ipairs(git.search_paths(state.root, state.event, query)) do
        candidates[candidate] = true
      end
      -- Git grep sees only the selected tree. Changed files are also scanned
      -- so removed lines in Timeline's event-local source remain searchable.
      for changed_path, _ in pairs(state.changes) do
        candidates[changed_path] = true
      end
      for _, candidate in ipairs(state.files) do
        if candidates[candidate] then
          local lines = get_file_snapshot(candidate)
          append_code_matches(matches, candidate, lines, needle)
        end
      end
    else
      local lines = get_file_snapshot(path)
      append_code_matches(matches, path, lines, needle)
    end
  end

  local selected = 0
  if #matches > 0 then
    local path_order = {}
    for index, candidate in ipairs(state.files) do
      path_order[candidate] = index
    end
    local current_order = path_order[path] or 0
    selected = 1
    for index, match in ipairs(matches) do
      local order = path_order[match.path] or 0
      local after_cursor = match.path == path
        and (match.line > cursor[1] or (match.line == cursor[1] and match.start_col >= cursor[2]))
      if order > current_order or after_cursor then
        selected = index
        break
      end
    end
  end
  state.code_search = {
    query = query,
    matches = matches,
    index = selected,
    scope = state.code_search.scope or "file",
  }
  if query ~= "" and #matches > 0 then
    navigate_code_match(selected)
  else
    render_code_search(false)
  end
end

function M.next_code_match(direction)
  local count = #state.code_search.matches
  if state.code_search.query == "" or count == 0 then
    return
  end
  navigate_code_match(state.code_search.index + (direction or 1))
end

function M.toggle_code_search_scope()
  state.code_search.scope = state.code_search.scope == "commit" and "file" or "commit"
  M.search_code(state.code_search.query)
end

local function render_files(preferred_path)
  local buffer = state.buffers.files
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    return
  end

  local selected = 1
  for index, path in ipairs(state.visible_files) do
    if path == preferred_path then
      selected = index
      break
    end
  end
  state.file_search.index = state.file_search.query == "" and 0 or selected

  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
  vim.api.nvim_buf_clear_namespace(buffer, file_search_namespace, 0, -1)
  set_lines(buffer, state.visible_files)
  for index, path in ipairs(state.visible_files) do
    local group = file_highlight(state.changes[path])
    if group then
      vim.api.nvim_buf_set_extmark(buffer, namespace, index - 1, 0, {
        line_hl_group = group,
        priority = 50,
      })
    end
  end
  if state.file_search.query ~= "" then
    render_match_highlights(buffer, file_search_namespace, #state.visible_files, state.file_search.index)
  end

  if valid_window(state.windows.files) then
    vim.api.nvim_win_set_config(state.windows.files, {
      title = match_title("Codebase", state.file_search.query, #state.visible_files),
      title_pos = "center",
    })
  end

  if #state.visible_files == 0 or not valid_window(state.windows.files) then
    return
  end
  vim.api.nvim_win_set_cursor(state.windows.files, { selected, 0 })
  render_source()
end

apply_file_filter = function(query, preferred_path)
  query = vim.trim(query or "")
  local needle = query:lower()
  local matches, visible = {}, {}
  for row, path in ipairs(state.files) do
    if query == "" or path:lower():find(needle, 1, true) then
      visible[#visible + 1] = path
      if query ~= "" then
        matches[#matches + 1] = row
      end
    end
  end
  state.file_search = { query = query, matches = matches, index = 0 }
  state.visible_files = visible

  if preferred_path then
    local previous_path = preferred_path
    local found = false
    for _, path in ipairs(visible) do
      if path == preferred_path then
        found = true
        break
      end
    end
    if not found then
      preferred_path = nil
      for _, path in ipairs(visible) do
        if path >= previous_path then
          preferred_path = path
          break
        end
      end
    end
  end
  render_files(preferred_path)
end

function M.search_files(query)
  if query == nil then
    M.toggle_search_bar("files")
    return
  end
  local preferred_path = current_file()
  apply_file_filter(query, preferred_path)
end

function M.next_file_match(direction)
  local count = #state.visible_files
  if state.file_search.query == "" or count == 0 or not valid_window(state.windows.files) then
    return
  end
  local row = vim.api.nvim_win_get_cursor(state.windows.files)[1]
  row = ((row - 1 + (direction or 1)) % count) + 1
  state.file_search.index = row
  vim.api.nvim_win_set_cursor(state.windows.files, { row, 0 })
  render_match_highlights(state.buffers.files, file_search_namespace, count, row)
  render_source()
end

local function sync_file_search_to_cursor()
  if state.file_search.query == "" or not valid_window(state.windows.files) then
    return
  end
  state.file_search.index = vim.api.nvim_win_get_cursor(state.windows.files)[1]
  render_match_highlights(
    state.buffers.files,
    file_search_namespace,
    #state.visible_files,
    state.file_search.index
  )
end

local function render_event()
  local event = current_event()
  if not event then
    return
  end
  local event_changed = state.event ~= event
  state.event = event
  if event_changed then
    state.file_search = { query = "", matches = {}, index = 0 }
    state.code_search = empty_code_search()
    state.snapshot_cache = {}
    if update_search_bar then
      update_search_bar("files", "")
      update_search_bar("code", "")
    end
  end

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

  local selected
  for _, path in ipairs(files) do
    if changes[path] then
      selected = path
      break
    end
  end
  apply_file_filter("", selected)
end

local function render_commits(preferred_event)
  local buffer = state.buffers.changes
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  local selected = 1
  for index, event in ipairs(state.visible_events) do
    if event == preferred_event then
      selected = index
      break
    end
  end
  state.search.index = state.search.query == "" and 0 or selected

  local lines = {}
  for _, event in ipairs(state.visible_events) do
    lines[#lines + 1] = string.format("%-5s %s", event_marker(event), event.subject)
  end
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
  vim.api.nvim_buf_clear_namespace(buffer, search_namespace, 0, -1)
  set_lines(buffer, lines)
  for index, _ in ipairs(state.visible_events) do
    vim.api.nvim_buf_add_highlight(buffer, namespace, "CodexTimelineChangeNumber", index - 1, 0, 4)
  end
  if state.search.query ~= "" then
    render_match_highlights(buffer, search_namespace, #state.visible_events, state.search.index)
  end
  if valid_window(state.windows.changes) then
    vim.api.nvim_win_set_config(state.windows.changes, {
      title = match_title("Changes", state.search.query, #state.visible_events),
      title_pos = "center",
    })
  end
  if #state.visible_events == 0 or not valid_window(state.windows.changes) then
    return
  end
  vim.api.nvim_win_set_cursor(state.windows.changes, { selected, 0 })
  render_event()
end

function M.search(query)
  if query == nil then
    M.toggle_search_bar("commits")
    return
  end
  query = vim.trim(query)
  local previous_event = state.event or current_event()
  local previous_row = 1
  for row, event in ipairs(state.events) do
    if event == previous_event then
      previous_row = row
      break
    end
  end

  local needle = query:lower()
  local matches, visible = {}, {}
  for row, event in ipairs(state.events) do
    local searchable = string.format("%s %s", event_marker(event), event.subject):lower()
    if query == "" or searchable:find(needle, 1, true) then
      visible[#visible + 1] = event
      if query ~= "" then
        matches[#matches + 1] = row
      end
    end
  end
  state.search = { query = query, matches = matches, index = 0 }
  state.visible_events = visible

  local preferred = previous_event
  local found = false
  for _, event in ipairs(visible) do
    if event == preferred then
      found = true
      break
    end
  end
  if not found then
    preferred = nil
    for index, row in ipairs(matches) do
      if row >= previous_row then
        preferred = visible[index]
        break
      end
    end
    preferred = preferred or visible[1]
  end
  render_commits(preferred)
end

function M.next_match(direction)
  local count = #state.visible_events
  if state.search.query == "" or count == 0 or not valid_window(state.windows.changes) then
    return
  end
  local row = vim.api.nvim_win_get_cursor(state.windows.changes)[1]
  row = ((row - 1 + (direction or 1)) % count) + 1
  state.search.index = row
  vim.api.nvim_win_set_cursor(state.windows.changes, { row, 0 })
  render_match_highlights(state.buffers.changes, search_namespace, count, row)
  render_event()
end

local function sync_search_to_cursor()
  if state.search.query == "" or not valid_window(state.windows.changes) then
    return
  end
  state.search.index = vim.api.nvim_win_get_cursor(state.windows.changes)[1]
  render_match_highlights(
    state.buffers.changes,
    search_namespace,
    #state.visible_events,
    state.search.index
  )
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
  row = math.max(1, math.min(#state.visible_events, row + direction))
  vim.api.nvim_win_set_cursor(state.windows.changes, { row, 0 })
  render_event()
end

local function map_all(lhs, callback, description)
  for _, buffer in pairs(state.buffers) do
    vim.keymap.set("n", lhs, callback, { buffer = buffer, silent = true, nowait = true, desc = description })
  end
end

local function close_search_bar(role)
  local bar = state.search_bars[role]
  if not bar then
    return
  end
  state.search_bars[role] = nil
  if valid_window(bar.window) then
    vim.api.nvim_win_close(bar.window, true)
  end
  apply_layout()
  focus(role == "commits" and "changes" or role == "files" and "files" or "source")
end

local function search_bar_title(role)
  if role == "commits" then
    return " Search commits "
  elseif role == "code" then
    local scope = state.code_search.scope == "commit" and "all files" or "this file"
    local toggle = state.code_search.scope == "commit" and "Tab: this file" or "Tab: all files"
    return match_title(string.format("Code · %s · %s", scope, toggle), state.code_search.query,
      #state.code_search.matches)
  end
  local marker = state.event and event_marker(state.event) or "current"
  return string.format(" Search files in %s ", marker)
end

update_search_bar = function(role, text)
  local bar = state.search_bars[role]
  if not bar or not vim.api.nvim_buf_is_valid(bar.buffer) then
    return
  end
  text = text or ""
  local current = vim.api.nvim_buf_get_lines(bar.buffer, 0, 1, false)[1] or ""
  if current ~= text then
    state.updating_bar = true
    vim.api.nvim_buf_set_lines(bar.buffer, 0, -1, false, { text })
    state.updating_bar = false
  end
  if valid_window(bar.window) then
    vim.api.nvim_win_set_config(bar.window, {
      title = search_bar_title(role),
      title_pos = "center",
    })
  end
end

function M.toggle_search_bar(role)
  if role ~= "commits" and role ~= "files" and role ~= "code" then
    return
  end
  if search_bar_open(role) then
    close_search_bar(role)
    return
  end

  local size = dimensions()
  local is_commits = role == "commits"
  local is_files = role == "files"
  local query = is_commits and state.search.query
    or is_files and state.file_search.query
    or state.code_search.query
  local col = size.col
  local width = size.changes_width
  if is_files then
    col = size.col + size.changes_width + 2
    width = size.files_width
  elseif role == "code" then
    col = size.col + size.changes_width + size.files_width + 4
    width = size.source_width
  end
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = "timeline-search"
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { query })

  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    row = size.row,
    col = col,
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
    title = search_bar_title(role),
    title_pos = "center",
  })
  state.search_bars[role] = { buffer = buffer, window = window }
  vim.wo[window].wrap = false
  vim.wo[window].number = false
  vim.wo[window].relativenumber = false
  vim.wo[window].signcolumn = "no"
  vim.wo[window].winhighlight = table.concat({
    "FloatBorder:CodexTimelineBorder",
    "FloatTitle:CodexTimelineTitle",
  }, ",")

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = state.augroup,
    buffer = buffer,
    callback = function()
      if state.updating_bar or not vim.api.nvim_buf_is_valid(buffer) then
        return
      end
      local value = vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] or ""
      if is_commits then
        M.search(value)
      elseif is_files then
        M.search_files(value)
      else
        M.search_code(value)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = state.augroup,
    buffer = buffer,
    once = true,
    callback = function()
      local active = state.search_bars[role]
      if active and active.buffer == buffer then
        state.search_bars[role] = nil
        vim.schedule(apply_layout)
      end
    end,
  })

  local function finish_search()
    vim.cmd("stopinsert")
    close_search_bar(role)
  end
  vim.keymap.set("i", "<CR>", finish_search, { buffer = buffer, silent = true, nowait = true })
  vim.keymap.set("i", "<Esc>", finish_search, { buffer = buffer, silent = true, nowait = true })
  vim.keymap.set("i", "<C-c>", finish_search, { buffer = buffer, silent = true, nowait = true })
  vim.keymap.set("n", "q", function() close_search_bar(role) end, { buffer = buffer, silent = true })
  vim.keymap.set("n", "<Esc>", function() close_search_bar(role) end, { buffer = buffer, silent = true })
  if role == "code" then
    local function toggle_scope()
      M.toggle_code_search_scope()
    end
    vim.keymap.set("i", "<Tab>", toggle_scope, { buffer = buffer, silent = true, nowait = true })
    vim.keymap.set("n", "<Tab>", toggle_scope, { buffer = buffer, silent = true, nowait = true })
  end

  apply_layout()
  vim.api.nvim_win_set_cursor(window, { 1, #query })
  vim.cmd("startinsert!")
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
  state.visible_events = events
  state.files, state.visible_files = {}, {}
  state.search = { query = "", matches = {}, index = 0 }
  state.file_search = { query = "", matches = {}, index = 0 }
  state.code_search = empty_code_search()
  state.snapshot_cache = {}
  state.navigating_code_search = false
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
    "WinBar:NormalFloat",
    "WinBarNC:NormalFloat",
  }, ",")

  state.augroup = vim.api.nvim_create_augroup("TimelineUI", { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = state.augroup, buffer = state.buffers.changes, callback = function()
      sync_search_to_cursor()
      render_event()
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = state.augroup, buffer = state.buffers.files, callback = function()
      sync_file_search_to_cursor()
      render_source()
    end,
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
  map_all("F", function() M.search_files() end, "Search files in selected commit")
  map_all("[f", function() M.next_file_match(-1) end, "Previous file search match")
  map_all("]f", function() M.next_file_match(1) end, "Next file search match")
  map_all("C", function() M.search_code() end, "Search code in selected historical snapshot")
  map_all("[s", function() M.next_code_match(-1) end, "Previous code search match")
  map_all("]s", function() M.next_code_match(1) end, "Next code search match")
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
