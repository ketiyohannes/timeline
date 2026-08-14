local project_root = assert(vim.env.TIMELINE_PROJECT)
local test_repo = assert(vim.env.TIMELINE_TEST_REPO)
vim.opt.runtimepath:prepend(project_root)

local timeline = require("timeline")
timeline.setup({ auto_sync = false, annotate_on_buf_enter = false, session = "nvim" })
vim.cmd.edit(vim.fn.fnameescape(test_repo .. "/example.txt"))
timeline.annotate()

local namespace = vim.api.nvim_get_namespaces().codex_timeline
local marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })
assert(#marks == 1, "expected exactly one annotated line")
assert(marks[1][2] == 1, "expected gamma on the second line")
assert(marks[1][4].sign_text == "02", "expected event #2 sign")

timeline.open()
local ui_state = require("codex_timeline.ui")._state

-- All three floating panes must respond to editor resizing and remain within
-- the available columns.
vim.o.columns = 180
vim.o.lines = 60
vim.cmd.doautocmd("VimResized")
local wide_changes = vim.api.nvim_win_get_config(ui_state.windows.changes)
local wide_files = vim.api.nvim_win_get_config(ui_state.windows.files)
local wide_source = vim.api.nvim_win_get_config(ui_state.windows.source)
vim.o.columns = 110
vim.o.lines = 38
vim.cmd.doautocmd("VimResized")
local narrow_changes = vim.api.nvim_win_get_config(ui_state.windows.changes)
local narrow_files = vim.api.nvim_win_get_config(ui_state.windows.files)
local narrow_source = vim.api.nvim_win_get_config(ui_state.windows.source)
assert(narrow_changes.width < wide_changes.width, "changes pane did not shrink with the editor")
assert(narrow_files.width < wide_files.width, "codebase pane did not shrink with the editor")
assert(narrow_source.width < wide_source.width, "source pane did not shrink with the editor")
assert(narrow_source.col + narrow_source.width + 2 <= vim.o.columns, "responsive panes overflow the editor")

local roles = {}
for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
  local role = vim.b[buffer].codex_timeline_role
  if role then
    roles[role] = buffer
  end
end
assert(roles.changes and roles.files and roles.source, "snapshot browser panes were not created")

local change_text = table.concat(vim.api.nvim_buf_get_lines(roles.changes, 0, -1, false), "\n")
assert(change_text:find("#001%s+apply_patch"), "first change number and message were not shown")
assert(change_text:find("#002%s+refactor"), "second change number and message were not shown")
assert(not change_text:find("%d%d:%d%d:%d%d"), "timeline leaked timestamp metadata")
assert(not change_text:find("[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]"), "timeline leaked commit hash metadata")

-- Commit search accepts both change numbers and message fragments, highlights
-- every result, and wraps in both directions.
local ui = require("codex_timeline.ui")
local function window_title(window)
  local title = vim.api.nvim_win_get_config(window).title
  if type(title) == "table" then
    local parts = {}
    for _, part in ipairs(title) do parts[#parts + 1] = type(part) == "table" and part[1] or part end
    return table.concat(parts)
  end
  return title
end

local changes_before_search = vim.api.nvim_win_get_config(ui_state.windows.changes)
ui.toggle_search_bar("commits")
local commit_bar = assert(ui_state.search_bars.commits, "commit search bar did not open")
local commit_bar_config = vim.api.nvim_win_get_config(commit_bar.window)
local changes_with_search = vim.api.nvim_win_get_config(ui_state.windows.changes)
assert(commit_bar_config.relative == "editor", "commit search is not an in-browser floating bar")
assert(changes_with_search.row > commit_bar_config.row, "commit results did not move below their search bar")
assert(changes_with_search.height < changes_before_search.height, "commit pane did not make room for search")
vim.o.columns = 150
vim.cmd.doautocmd("VimResized")
local wide_commit_bar = vim.api.nvim_win_get_config(commit_bar.window)
vim.o.columns = 110
vim.cmd.doautocmd("VimResized")
local narrow_commit_bar = vim.api.nvim_win_get_config(commit_bar.window)
assert(narrow_commit_bar.width < wide_commit_bar.width, "commit search bar did not resize with the browser")
vim.api.nvim_buf_set_lines(commit_bar.buffer, 0, -1, false, { "#002" })
vim.cmd.doautocmd("TextChangedI")
assert(ui_state.search.query == "#002", "search query was not retained")
assert(#ui_state.search.matches == 1, "change-number search should find exactly one commit")
local filtered_commits = vim.api.nvim_buf_get_lines(roles.changes, 0, -1, false)
assert(#filtered_commits == 1 and filtered_commits[1]:find("refactor", 1, true), "commit search did not filter nonmatches")
assert(vim.api.nvim_win_get_cursor(ui_state.windows.changes)[1] == 1, "filtered commit was not selected")
ui.toggle_search_bar("commits")
assert(ui_state.search_bars.commits == nil, "commit search bar did not toggle closed")
assert(vim.api.nvim_win_get_config(ui_state.windows.changes).height == changes_before_search.height, "commit pane did not reclaim space")
local search_namespace = vim.api.nvim_get_namespaces().timeline_search
local search_marks = vim.api.nvim_buf_get_extmarks(roles.changes, search_namespace, 0, -1, { details = true })
assert(#search_marks == 1, "search result was not highlighted")
assert(search_marks[1][4].line_hl_group == "TimelineSearchCurrent", "selected search result is not distinct")
local search_title = window_title(ui_state.windows.changes)
assert(search_title:find("1 match", 1, true), "changes title does not show the search result count")

ui.search("a")
assert(#ui_state.search.matches == 3, "message-fragment search did not find every commit")
assert(vim.api.nvim_win_get_cursor(ui_state.windows.changes)[1] == 3, "search should start at the current matching commit")
ui.next_match(1)
assert(vim.api.nvim_win_get_cursor(ui_state.windows.changes)[1] == 1, "next search match did not wrap")
ui.next_match(-1)
assert(vim.api.nvim_win_get_cursor(ui_state.windows.changes)[1] == 3, "previous search match did not wrap")
ui.search("")
assert(ui_state.search.query == "" and #ui_state.search.matches == 0, "empty search did not clear results")
assert(#vim.api.nvim_buf_get_extmarks(roles.changes, search_namespace, 0, -1, {}) == 0, "cleared search left highlights")

-- File search is scoped to the selected commit and opens each result from the
-- historical tree rather than the current worktree.
local files_before_search = vim.api.nvim_win_get_config(ui_state.windows.files)
ui.toggle_search_bar("files")
local file_bar = assert(ui_state.search_bars.files, "file search bar did not open")
local file_bar_config = vim.api.nvim_win_get_config(file_bar.window)
local files_with_search = vim.api.nvim_win_get_config(ui_state.windows.files)
assert(file_bar_config.relative == "editor", "file search is not an in-browser floating bar")
assert(files_with_search.row > file_bar_config.row, "file results did not move below their search bar")
assert(files_with_search.height < files_before_search.height, "codebase pane did not make room for search")
assert(window_title(file_bar.window):find("#002", 1, true), "file search bar does not identify its commit")
vim.api.nvim_buf_set_lines(file_bar.buffer, 0, -1, false, { "deep" })
vim.cmd.doautocmd("TextChangedI")
assert(ui_state.file_search.query == "deep", "file search query was not retained")
assert(#ui_state.file_search.matches == 1, "file search should find one deep file")
local filtered_files = vim.api.nvim_buf_get_lines(roles.files, 0, -1, false)
assert(#filtered_files == 1 and filtered_files[1] == "deep.txt", "file search did not filter nonmatches")
assert(vim.b[roles.source].codex_timeline_path == "deep.txt", "file search did not open its historical result")
ui.toggle_search_bar("files")
assert(ui_state.search_bars.files == nil, "file search bar did not toggle closed")
assert(vim.api.nvim_win_get_config(ui_state.windows.files).height == files_before_search.height, "codebase pane did not reclaim space")
local file_search_namespace = vim.api.nvim_get_namespaces().timeline_file_search
local file_search_marks = vim.api.nvim_buf_get_extmarks(
  roles.files,
  file_search_namespace,
  0,
  -1,
  { details = true }
)
assert(#file_search_marks == 1, "file search result was not highlighted")
assert(file_search_marks[1][4].line_hl_group == "TimelineSearchCurrent", "selected file result is not distinct")
assert(window_title(ui_state.windows.files):find("1 match", 1, true), "codebase title lacks file result count")

ui.search_files(".txt")
assert(#ui_state.file_search.matches == 4, "file search did not cover the complete snapshot tree")
ui.next_file_match(1)
ui.next_file_match(1)
ui.next_file_match(1)
assert(vim.api.nvim_win_get_cursor(ui_state.windows.files)[1] == 1, "next file match did not wrap")
ui.next_file_match(-1)
assert(vim.api.nvim_win_get_cursor(ui_state.windows.files)[1] == 4, "previous file match did not wrap")
ui.search_files("")
assert(ui_state.file_search.query == "" and #ui_state.file_search.matches == 0, "empty file search did not clear")
assert(#vim.api.nvim_buf_get_extmarks(roles.files, file_search_namespace, 0, -1, {}) == 0, "file search highlights remain")

local file_text = table.concat(vim.api.nvim_buf_get_lines(roles.files, 0, -1, false), "\n")
assert(file_text:find("example.txt", 1, true), "changed file is missing from snapshot codebase")
assert(file_text:find("added.txt", 1, true), "added file is missing from snapshot codebase")
assert(file_text:find("unchanged.txt", 1, true), "deleted file is missing from event view")
local changed_file_marks = vim.api.nvim_buf_get_extmarks(
  roles.files,
  vim.api.nvim_get_namespaces().codex_timeline_snapshot,
  0,
  -1,
  { details = true }
)
assert(#changed_file_marks == 4, "all files touched by the event should be highlighted")
local file_groups = {}
for _, mark in ipairs(changed_file_marks) do
  file_groups[mark[4].line_hl_group] = true
end
assert(file_groups.CodexTimelineAddFile, "added files should use the stronger add highlight")
assert(file_groups.CodexTimelineDeleteFile, "deleted files should use the stronger delete highlight")
assert(file_groups.CodexTimelineChangeFile, "modified files should use the stronger change highlight")

local file_lines = vim.api.nvim_buf_get_lines(roles.files, 0, -1, false)
local example_row, deep_row
for index, path in ipairs(file_lines) do
  if path == "example.txt" then example_row = index end
  if path == "deep.txt" then deep_row = index end
end
assert(example_row, "example file is missing")
assert(deep_row, "deep file is missing")
vim.api.nvim_set_current_win(ui_state.windows.files)
vim.api.nvim_win_set_cursor(ui_state.windows.files, { example_row, 0 })
vim.cmd.doautocmd("CursorMoved")

local source_lines = vim.api.nvim_buf_get_lines(roles.source, 0, -1, false)
assert(vim.wo[ui_state.windows.source].winbar:find("example.txt", 1, true), "opened file path is missing below the commit title")
assert(
  source_lines[1] == "alpha" and source_lines[2] == "beta" and source_lines[3] == "gamma",
  "source pane did not interleave the complete file with its removed and added lines"
)
local source_text = table.concat(source_lines, "\n")
assert(not source_text:find("diff %-%-git"), "source pane leaked diff metadata")
assert(not source_text:find("@@", 1, true), "source pane leaked hunk metadata")

local snapshot_namespace = vim.api.nvim_get_namespaces().codex_timeline_snapshot
local source_marks = vim.api.nvim_buf_get_extmarks(roles.source, snapshot_namespace, 0, -1, { details = true })
assert(#source_marks == 2, "expected one removed and one added line")
assert(source_marks[1][2] == 1 and vim.trim(source_marks[1][4].sign_text) == "-", "expected - sign on removed beta")
assert(source_marks[2][2] == 2 and vim.trim(source_marks[2][4].sign_text) == "+", "expected + sign on added gamma")
assert(source_marks[1][4].line_hl_group == "CodexTimelineDeleteLine", "removed line highlight is not theme-aware")
assert(source_marks[1][4].sign_hl_group == "CodexTimelineDeleteSign", "removed sign highlight is not bold")
assert(source_marks[2][4].line_hl_group == "CodexTimelineAddLine", "added line highlight is not theme-aware")
assert(source_marks[2][4].sign_hl_group == "CodexTimelineAddSign", "added sign highlight is not bold")

-- Moving to a file with a deep change keeps the complete file but starts the
-- source viewport at the first highlighted line.
vim.api.nvim_win_set_cursor(ui_state.windows.files, { deep_row, 0 })
vim.cmd.doautocmd("CursorMoved")
local deep_lines = vim.api.nvim_buf_get_lines(roles.source, 0, -1, false)
assert(#deep_lines > 400, "deep file was reduced to a diff instead of retaining full context")
assert(deep_lines[300] == "line 300" and deep_lines[301] == "changed line 300", "deep replacement is misplaced")
local deep_topline = vim.api.nvim_win_call(ui_state.windows.source, function()
  return vim.fn.line("w0")
end)
assert(deep_topline == 300, "source viewport did not start at the first highlighted line")
assert(vim.api.nvim_win_get_cursor(ui_state.windows.source)[1] == 300, "source cursor did not jump to the change")
assert(vim.wo[ui_state.windows.source].winbar:find("deep.txt", 1, true), "file path did not update with selection")

-- Moving backward reconstructs the full earlier codebase and its event-local
-- highlights rather than showing the latest worktree or a raw patch.
vim.api.nvim_set_current_win(ui_state.windows.changes)
ui.search_files("added.txt")
vim.api.nvim_win_set_cursor(ui_state.windows.changes, { 2, 0 })
vim.cmd.doautocmd("CursorMoved")
assert(ui_state.file_search.query == "", "file search was not cleared when the selected commit changed")
assert(window_title(ui_state.windows.files) == " Codebase ", "codebase title retained a stale commit search")
local earlier_files = table.concat(vim.api.nvim_buf_get_lines(roles.files, 0, -1, false), "\n")
assert(earlier_files:find("unchanged.txt", 1, true), "earlier snapshot lost an unchanged file")
assert(not earlier_files:find("added.txt", 1, true), "earlier snapshot leaked a future file")
local earlier_source = vim.api.nvim_buf_get_lines(roles.source, 0, -1, false)
assert(earlier_source[1] == "alpha" and earlier_source[2] == "beta", "earlier source snapshot was not reconstructed")
local earlier_marks = vim.api.nvim_buf_get_extmarks(roles.source, snapshot_namespace, 0, -1, { details = true })
assert(#earlier_marks == 1 and vim.trim(earlier_marks[1][4].sign_text) == "+", "earlier addition highlight is wrong")
ui.close()

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
  if vim.b[buffer].codex_timeline_role == "changes" then
    timeline_window_found = true
    break
  end
end
assert(timeline_window_found, "timeline did not open from a virtual health buffer")
require("codex_timeline.ui").close()

print("neovim integration test passed")
