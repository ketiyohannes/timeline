local project_root = assert(vim.env.TIMELINE_PROJECT)
local test_repo = assert(vim.env.TIMELINE_TEST_REPO)
vim.opt.runtimepath:prepend(project_root)

local timeline = require("timeline")
timeline.setup({
  auto_sync = false,
  annotate_on_buf_enter = false,
  session = "nvim",
  refresh_interval = 100,
})
vim.cmd.edit(vim.fn.fnameescape(test_repo .. "/example.txt"))
timeline.annotate()

local namespace = vim.api.nvim_get_namespaces().codex_timeline
local marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })
assert(#marks == 1, "expected exactly one annotated line")
assert(marks[1][2] == 1, "expected gamma on the second line")
assert(marks[1][4].sign_text == "02", "expected event #2 sign")

-- Normal editor buffers stay clean unless annotation is explicitly invoked.
timeline.clear()
vim.cmd.edit(vim.fn.fnameescape(test_repo .. "/shared.lua"))
vim.wait(100, function() return false end, 20)
local normal_marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {})
assert(#normal_marks == 0, "Timeline counters leaked into a normal Neovim buffer")

timeline.open()
local ui_state = require("codex_timeline.ui")._state
assert(#ui_state.commits == 2, "Timeline snapshots were not grouped into the two real Git commits")
assert(#ui_state.commits[2].events == 2, "Codex changes were not nested inside the feature commit")
assert(ui_state.commits[2].events[1].commit_turn_number == 1, "first in-commit turn was not numbered first")
assert(ui_state.commits[2].events[2].commit_turn_number == 2, "second in-commit turn was not numbered second")

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
assert(change_text:find("#001 baseline", 1, true), "baseline Git commit was not shown")
assert(change_text:find("#002 build realistic feature", 1, true), "feature Git commit was not shown")
assert(not change_text:find("Turn ", 1, true), "Codex turns leaked into the commit pane")
assert(not change_text:find("%d%d:%d%d:%d%d"), "timeline leaked timestamp metadata")
assert(not change_text:find("[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]"), "timeline leaked commit hash metadata")
assert(not change_text:find("01turn%-"), "timeline leaked raw Codex turn metadata")

local codebase_text = table.concat(vim.api.nvim_buf_get_lines(roles.files, 0, -1, false), "\n")
assert(not codebase_text:find("Turn ", 1, true), "standalone turn rows remain in Codebase")
assert(not codebase_text:find("Change ", 1, true), "standalone change rows remain in Codebase")
assert(codebase_text:find("01,02 │ example.txt", 1, true), "change ordering is not attached directly to files")
assert(not codebase_text:find("01turn%-"), "codebase pane leaked raw Codex turn metadata")

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
assert(
  window_title(ui_state.windows.source) == " #002 · build realistic feature ",
  "source title should show only the Git commit and message"
)

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
assert(#filtered_commits == 1 and filtered_commits[1]:find("build realistic feature", 1, true), "commit search did not filter nonmatches")
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

ui.search("realistic")
assert(#ui_state.search.matches == 1, "commit search should match the Git commit message")
assert(
  vim.api.nvim_buf_get_lines(roles.changes, 0, -1, false)[1]:find("build realistic feature", 1, true),
  "commit search returned the wrong commit"
)
ui.search("")
ui.search("a")
assert(#ui_state.search.matches == 2, "message-fragment search did not find every commit")
assert(vim.api.nvim_win_get_cursor(ui_state.windows.changes)[1] == 2, "search should start at the current matching commit")
ui.next_match(1)
assert(vim.api.nvim_win_get_cursor(ui_state.windows.changes)[1] == 1, "next search match did not wrap")
ui.next_match(-1)
assert(vim.api.nvim_win_get_cursor(ui_state.windows.changes)[1] == 2, "previous search match did not wrap")
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
assert(filtered_files[#filtered_files]:sub(-#"deep.txt") == "deep.txt", "file search did not filter nonmatching paths")
assert(not table.concat(filtered_files, "\n"):find("Turn ", 1, true), "file search restored a standalone turn row")
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
assert(#ui_state.file_search.matches == 5, "file search did not cover the complete snapshot tree")
ui.next_file_match(1)
ui.next_file_match(1)
ui.next_file_match(1)
ui.next_file_match(1)
local selected_row = ui_state.file_rows[vim.api.nvim_win_get_cursor(ui_state.windows.files)[1]]
assert(selected_row and selected_row.path == ui_state.visible_files[1], "next file match did not wrap")
ui.next_file_match(-1)
selected_row = ui_state.file_rows[vim.api.nvim_win_get_cursor(ui_state.windows.files)[1]]
assert(selected_row and selected_row.path == ui_state.visible_files[5], "previous file match did not wrap")
ui.search_files("")
assert(ui_state.file_search.query == "" and #ui_state.file_search.matches == 0, "empty file search did not clear")
assert(#vim.api.nvim_buf_get_extmarks(roles.files, file_search_namespace, 0, -1, {}) == 0, "file search highlights remain")

local file_text = table.concat(vim.api.nvim_buf_get_lines(roles.files, 0, -1, false), "\n")
assert(file_text:find("01,02 │ example.txt", 1, true), "file does not show every in-commit change that touched it")
assert(file_text:find("02 │ deep.txt", 1, true), "file does not show its first Codex change indicator")
assert(file_text:find("01 │ early.txt", 1, true), "earlier touched file lost its change indicator")
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
local file_groups = {}
for _, mark in ipairs(changed_file_marks) do
  if mark[4].line_hl_group then file_groups[mark[4].line_hl_group] = true end
end
assert(file_groups.CodexTimelineAddFile, "added files should use the stronger add highlight")
assert(file_groups.CodexTimelineDeleteFile, "deleted files should use the stronger delete highlight")
assert(file_groups.CodexTimelineChangeFile, "modified files should use the stronger change highlight")

local file_lines = vim.api.nvim_buf_get_lines(roles.files, 0, -1, false)
local example_row, deep_row, early_row
for index, path in ipairs(file_lines) do
  if path:sub(-#"example.txt") == "example.txt" then example_row = index end
  if path:sub(-#"deep.txt") == "deep.txt" then deep_row = index end
  if path:sub(-#"early.txt") == "early.txt" then early_row = index end
end
assert(example_row, "example file is missing")
assert(deep_row, "deep file is missing")
assert(early_row, "earlier changed file is missing")

-- A file changed by an earlier Codex change remains highlighted in the later
-- snapshot, and its surviving code keeps both the number and background.
vim.api.nvim_set_current_win(ui_state.windows.files)
vim.api.nvim_win_set_cursor(ui_state.windows.files, { early_row, 0 })
vim.cmd.doautocmd("CursorMoved")
local persistent_marks = vim.api.nvim_buf_get_extmarks(
  roles.source,
  vim.api.nvim_get_namespaces().timeline_change_provenance,
  0,
  -1,
  { details = true }
)
assert(#persistent_marks == 1, "earlier surviving diff is not marked in the later snapshot")
assert(persistent_marks[1][4].virt_text[1][1]:find("Δ01", 1, true), "earlier diff has the wrong indicator")
assert(persistent_marks[1][4].line_hl_group == "CodexTimelineChangeLine",
  "earlier surviving diff is numbered but not highlighted")

vim.api.nvim_set_current_win(ui_state.windows.files)
vim.api.nvim_win_set_cursor(ui_state.windows.files, { example_row, 0 })
vim.cmd.doautocmd("CursorMoved")

local source_lines = vim.api.nvim_buf_get_lines(roles.source, 0, -1, false)
assert(vim.wo[ui_state.windows.source].winbar:find("example.txt", 1, true), "opened file path is missing below the commit title")
assert(
  source_lines[1] == "alpha" and source_lines[2] == "beta" and source_lines[3] == "gamma",
  "source pane did not interleave the complete file with its removed and added lines"
)

-- Code search uses its own responsive bar, highlights matches in place, and
-- keeps every nonmatching source line available for context.
local source_before_search = vim.api.nvim_win_get_config(ui_state.windows.source)
ui.toggle_search_bar("code")
local code_bar = assert(ui_state.search_bars.code, "code search bar did not open")
local code_bar_config = vim.api.nvim_win_get_config(code_bar.window)
local source_with_search = vim.api.nvim_win_get_config(ui_state.windows.source)
assert(code_bar_config.relative == "editor", "code search is not an in-browser floating bar")
assert(source_with_search.row > code_bar_config.row, "source did not move below its search bar")
assert(source_with_search.height < source_before_search.height, "source pane did not make room for code search")
vim.o.columns = 150
vim.cmd.doautocmd("VimResized")
local wide_code_bar = vim.api.nvim_win_get_config(code_bar.window)
vim.o.columns = 110
vim.cmd.doautocmd("VimResized")
local narrow_code_bar = vim.api.nvim_win_get_config(code_bar.window)
assert(narrow_code_bar.width < wide_code_bar.width, "code search bar did not resize with the browser")

vim.api.nvim_buf_set_lines(code_bar.buffer, 0, -1, false, { "gamma" })
vim.cmd.doautocmd("TextChangedI")
assert(ui_state.code_search.query == "gamma", "code search query was not retained")
assert(#ui_state.code_search.matches == 1, "code search should find gamma once")
assert(vim.api.nvim_win_get_cursor(ui_state.windows.source)[1] == 3, "code search did not jump to gamma")
assert(#vim.api.nvim_buf_get_lines(roles.source, 0, -1, false) == 3, "code search removed nonmatching source lines")
local code_search_namespace = vim.api.nvim_get_namespaces().timeline_code_search
local code_search_marks = vim.api.nvim_buf_get_extmarks(
  roles.source,
  code_search_namespace,
  0,
  -1,
  { details = true }
)
assert(#code_search_marks == 1, "code search result was not highlighted")
assert(code_search_marks[1][4].hl_group == "TimelineCodeSearchCurrent", "current code result is not distinct")
assert(window_title(code_bar.window):find("1 match", 1, true), "code search bar lacks its result count")

vim.api.nvim_buf_set_lines(code_bar.buffer, 0, -1, false, { "beta" })
vim.cmd.doautocmd("TextChangedI")
assert(
  #ui_state.code_search.matches == 1 and ui_state.code_search.matches[1].line == 2,
  "code search did not include the event-local removed line"
)

vim.api.nvim_buf_set_lines(code_bar.buffer, 0, -1, false, { "a" })
vim.cmd.doautocmd("TextChangedI")
assert(#ui_state.code_search.matches == 5, "code search did not find every matching occurrence")
local steps_to_wrap = #ui_state.code_search.matches - ui_state.code_search.index + 1
for _ = 1, steps_to_wrap do ui.next_code_match(1) end
assert(vim.api.nvim_win_get_cursor(ui_state.windows.source)[1] == 1, "next code match did not wrap")
ui.next_code_match(-1)
assert(vim.api.nvim_win_get_cursor(ui_state.windows.source)[1] == 3, "previous code match did not wrap")

vim.api.nvim_buf_set_lines(code_bar.buffer, 0, -1, false, { ":2" })
vim.cmd.doautocmd("TextChangedI")
assert(vim.api.nvim_win_get_cursor(ui_state.windows.source)[1] == 2, "line-number search did not jump to line 2")
local line_jump_marks = vim.api.nvim_buf_get_extmarks(roles.source, code_search_namespace, 0, -1, { details = true })
assert(line_jump_marks[1][4].line_hl_group == "TimelineCodeSearchCurrent", "line-number result was not highlighted")

vim.api.nvim_buf_set_lines(code_bar.buffer, 0, -1, false, { "" })
vim.cmd.doautocmd("TextChangedI")
assert(ui_state.code_search.query == "" and #ui_state.code_search.matches == 0, "empty code search did not clear")
assert(#vim.api.nvim_buf_get_extmarks(roles.source, code_search_namespace, 0, -1, {}) == 0, "code highlights remain")
ui.toggle_search_bar("code")
assert(ui_state.search_bars.code == nil, "code search bar did not toggle closed")
assert(vim.api.nvim_win_get_config(ui_state.windows.source).height == source_before_search.height, "source pane did not reclaim space")

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
local provenance_namespace = vim.api.nvim_get_namespaces().timeline_change_provenance
local provenance_marks = vim.api.nvim_buf_get_extmarks(
  roles.source, provenance_namespace, 0, -1, { details = true }
)
assert(#provenance_marks == 2, "current code diff lines are missing their change-order indicators")
for _, mark in ipairs(provenance_marks) do
  assert(mark[4].virt_text[1][1]:find("Δ02", 1, true), "code line has the wrong in-commit change indicator")
end

-- Code search can switch between the opened file and every file in the
-- selected historical snapshot. Cross-file results update both source panes.
ui.toggle_search_bar("code")
code_bar = assert(ui_state.search_bars.code, "scoped code search bar did not open")
assert(window_title(code_bar.window):find("this file", 1, true), "code search did not default to this file")
local has_tab_mapping = false
local has_enter_mapping = false
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(code_bar.buffer, "i")) do
  if mapping.lhs == "<Tab>" then has_tab_mapping = true end
  if mapping.lhs == "<CR>" then has_enter_mapping = true end
end
assert(has_tab_mapping, "code search bar does not expose the Tab scope toggle")
assert(has_enter_mapping, "code search bar does not expose Enter to open the selected result")

vim.api.nvim_buf_set_lines(code_bar.buffer, 0, -1, false, { "sharedSearchTarget" })
vim.cmd.doautocmd("TextChangedI")
assert(#ui_state.code_search.matches == 0, "this-file search leaked a result from another file")
ui.toggle_code_search_scope()
assert(ui_state.code_search.scope == "commit", "code search did not switch to all-files scope")
assert(window_title(code_bar.window):find("all files", 1, true), "search bar does not show all-files scope")
assert(#ui_state.code_search.matches == 1, "all-files search missed an untouched historical file")
assert(ui_state.code_search.matches[1].path == "shared.lua", "all-files search returned the wrong path")
assert(vim.b[roles.source].codex_timeline_path == "shared.lua", "all-files result did not open its file")
assert(vim.wo[ui_state.windows.source].winbar:find("shared.lua", 1, true), "result path did not update")

vim.api.nvim_buf_set_lines(code_bar.buffer, 0, -1, false, { "stable" })
vim.cmd.doautocmd("TextChangedI")
assert(#ui_state.code_search.matches == 1, "all-files search missed event-local deleted code")
assert(ui_state.code_search.matches[1].path == "unchanged.txt", "deleted-code result has the wrong path")
assert(vim.b[roles.source].codex_timeline_path == "unchanged.txt", "deleted-code result did not open its file")

vim.api.nvim_buf_set_lines(code_bar.buffer, 0, -1, false, { "a" })
vim.cmd.doautocmd("TextChangedI")
local matching_paths = {}
for _, match in ipairs(ui_state.code_search.matches) do matching_paths[match.path] = true end
assert(matching_paths["deep.txt"] and matching_paths["example.txt"] and matching_paths["shared.lua"],
  "all-files search did not aggregate matches across the snapshot")
ui.next_code_match(1)
assert(vim.b[roles.source].codex_timeline_path == "deep.txt", "next code result did not wrap into another file")
assert(vim.api.nvim_win_get_cursor(ui_state.windows.source)[1] == 301, "cross-file result did not jump to its line")

vim.api.nvim_buf_set_lines(code_bar.buffer, 0, -1, false, { "alpha" })
vim.cmd.doautocmd("TextChangedI")
assert(vim.b[roles.source].codex_timeline_path == "example.txt", "all-files search did not return to example.txt")
ui.toggle_code_search_scope()
assert(ui_state.code_search.scope == "file", "code search did not switch back to this-file scope")
vim.api.nvim_buf_set_lines(code_bar.buffer, 0, -1, false, { "" })
vim.cmd.doautocmd("TextChangedI")
ui.toggle_search_bar("code")

-- Moving to a file with a deep change keeps the complete file but starts the
-- source viewport at the first highlighted line.
ui.search_code("gamma")
vim.api.nvim_set_current_win(ui_state.windows.files)
vim.api.nvim_win_set_cursor(ui_state.windows.files, { deep_row, 0 })
vim.cmd.doautocmd("CursorMoved")
assert(
  ui_state.code_search.query == "",
  "code search was not cleared when the opened file changed: " .. ui_state.code_search.query
)
local deep_lines = vim.api.nvim_buf_get_lines(roles.source, 0, -1, false)
assert(#deep_lines > 400, "deep file was reduced to a diff instead of retaining full context")
assert(deep_lines[300] == "line 300" and deep_lines[301] == "changed line 300", "deep replacement is misplaced")
local deep_topline = vim.api.nvim_win_call(ui_state.windows.source, function()
  return vim.fn.line("w0")
end)
assert(deep_topline == 300, "source viewport did not start at the first highlighted line")
assert(vim.api.nvim_win_get_cursor(ui_state.windows.source)[1] == 300, "source cursor did not jump to the change")
assert(vim.wo[ui_state.windows.source].winbar:find("deep.txt", 1, true), "file path did not update with selection")

-- Moving backward inside the selected Git commit reconstructs the full
-- earlier Codex turn and its event-local highlights.
ui.search_files("added.txt")
ui.move_change(-1)
assert(ui_state.file_search.query == "", "file search was not cleared when the selected change changed")
assert(window_title(ui_state.windows.files) == " Codebase ", "codebase title retained a stale commit search")
local earlier_files = table.concat(vim.api.nvim_buf_get_lines(roles.files, 0, -1, false), "\n")
assert(earlier_files:find("unchanged.txt", 1, true), "earlier snapshot lost an unchanged file")
assert(not earlier_files:find("added.txt", 1, true), "earlier snapshot leaked a future file")
for row, item in ipairs(ui_state.file_rows) do
  if item.kind == "file" and item.path == "example.txt" then
    vim.api.nvim_win_set_cursor(ui_state.windows.files, { row, 0 })
    vim.cmd.doautocmd("CursorMoved")
    break
  end
end
local earlier_source = vim.api.nvim_buf_get_lines(roles.source, 0, -1, false)
assert(earlier_source[1] == "alpha" and earlier_source[2] == "beta", "earlier source snapshot was not reconstructed")
local earlier_marks = vim.api.nvim_buf_get_extmarks(roles.source, snapshot_namespace, 0, -1, { details = true })
assert(#earlier_marks == 1 and vim.trim(earlier_marks[1][4].sign_text) == "+", "earlier addition highlight is wrong")
local earlier_provenance = vim.api.nvim_buf_get_extmarks(
  roles.source, provenance_namespace, 0, -1, { details = true }
)
assert(#earlier_provenance == 1 and earlier_provenance[1][4].virt_text[1][1]:find("Δ01", 1, true),
  "first code diff does not retain its Change 1 indicator")

-- Confirming a code result exits the floating browser and opens the real file
-- at the matching code in the normal editor.
ui.search_code("alpha")
ui.toggle_search_bar("code")
local accept_result
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(ui_state.search_bars.code.buffer, "i")) do
  if mapping.lhs == "<CR>" then accept_result = mapping.callback end
end
assert(type(accept_result) == "function", "code search Enter mapping has no action")
accept_result()
assert(
  vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)) == vim.uv.fs_realpath(test_repo .. "/example.txt"),
  "code result opened the wrong worktree file: " .. vim.api.nvim_buf_get_name(0)
)
assert(vim.api.nvim_win_get_cursor(0)[1] == 1, "editor did not jump to the matching worktree code")
assert(next(ui_state.windows) == nil, "Timeline windows remained open after accepting a code result")

-- Deleted historical results open read-only in a normal editor buffer instead
-- of silently recreating a missing worktree file.
timeline.open()
ui.search_code("stable")
ui.toggle_code_search_scope()
assert(ui_state.code_search.matches[1].path == "unchanged.txt", "deleted result was not selected")
assert(ui.open_code_match(), "deleted historical result did not open")
assert(vim.api.nvim_buf_get_name(0):find("timeline://", 1, true) == 1, "deleted result is not a historical buffer")
assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "stable", "historical editor buffer has wrong code")
assert(vim.bo.readonly and not vim.bo.modifiable and not vim.bo.modified, "historical editor buffer is not safely read-only")
assert(vim.uv.fs_stat(test_repo .. "/unchanged.txt") == nil, "opening a deleted result recreated the file")

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

-- An open browser follows a newly recorded snapshot without being closed and
-- recalled. The selected latest event advances and reconstructs its changed file.
vim.cmd.edit(vim.fn.fnameescape(test_repo .. "/example.txt"))
timeline.open()
local live_state = require("codex_timeline.ui")._state
local previous_event_count = #live_state.events
assert(live_state.refresh_timer, "live refresh watcher did not start")
vim.fn.writefile({ "created while Timeline is open" }, test_repo .. "/live.txt")
local checkpoint = vim.system({
  project_root .. "/bin/timeline", "checkpoint",
  "--repo", test_repo,
  "--session", "nvim",
  "--label", "live refresh",
}, { text = true }):wait()
assert(checkpoint.code == 0, "live refresh fixture checkpoint failed: " .. (checkpoint.stderr or ""))
local refreshed = vim.wait(3000, function()
  return #live_state.events == previous_event_count + 1
end, 25)
assert(refreshed, "open Timeline browser did not receive the new snapshot")
assert(live_state.event.subject == "live refresh", "browser did not follow the new latest event")
assert(vim.b[live_state.buffers.source].codex_timeline_path == "live.txt", "new snapshot file did not open live")
assert(
  vim.api.nvim_buf_get_lines(live_state.buffers.source, 0, 1, false)[1] == "created while Timeline is open",
  "live snapshot source did not render"
)

vim.api.nvim_set_current_win(live_state.windows.changes)
vim.api.nvim_win_set_cursor(live_state.windows.changes, { 1, 0 })
vim.cmd.doautocmd("CursorMoved")
local inspected_hash = live_state.event.hash
vim.fn.writefile({ "another live snapshot" }, test_repo .. "/live-two.txt")
local second_checkpoint = vim.system({
  project_root .. "/bin/timeline", "checkpoint",
  "--repo", test_repo,
  "--session", "nvim",
  "--label", "live refresh while browsing history",
}, { text = true }):wait()
assert(second_checkpoint.code == 0, "second live checkpoint failed: " .. (second_checkpoint.stderr or ""))
local refreshed_in_history = vim.wait(3000, function()
  return #live_state.events == previous_event_count + 2
end, 25)
assert(refreshed_in_history, "new snapshot did not appear while browsing an older event")
assert(live_state.event.hash == inspected_hash, "live refresh moved an intentional historical selection")
require("codex_timeline.ui").close()
assert(live_state.refresh_timer == nil, "live refresh watcher survived browser close")

print("neovim integration test passed")
