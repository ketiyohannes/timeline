local M = {}

local function run(args, cwd)
  local options = { text = true }
  if cwd and cwd ~= "" then
    options.cwd = cwd
  end
  local spawned, process_or_error = pcall(vim.system, args, options)
  if not spawned then
    return nil, tostring(process_or_error)
  end
  local result = process_or_error:wait()
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr or "git command failed")
  end
  return result.stdout or ""
end

M.run = run

function M.root(path)
  local candidate = path
  local stat = candidate and vim.uv.fs_stat(candidate) or nil
  if not stat or stat.type ~= "directory" then
    candidate = vim.fn.getcwd()
    stat = vim.uv.fs_stat(candidate)
  end
  if not stat or stat.type ~= "directory" then
    return nil
  end
  local output = run({ "git", "rev-parse", "--show-toplevel" }, candidate)
  return output and vim.trim(output) or nil
end

function M.latest_ref(root)
  local output = run({
    "git", "for-each-ref", "--sort=-committerdate", "--count=1",
    "--format=%(refname)", "refs/codex-timeline/",
  }, root)
  local ref = output and vim.trim(output) or ""
  return ref ~= "" and ref or nil
end

function M.has_ref(root, ref)
  local output = run({ "git", "show-ref", "--verify", "--quiet", ref }, root)
  return output ~= nil
end

function M.ref_hash(root, ref)
  local output = run({ "git", "rev-parse", "--verify", ref }, root)
  return output and vim.trim(output) or nil
end

function M.enabled(root)
  local output = run({ "git", "config", "--bool", "--get", "codex.timeline.enabled" }, root)
  return output == nil or vim.trim(output) ~= "false"
end

function M.set_enabled(root, enabled)
  local _, err = run({ "git", "config", "--local", "codex.timeline.enabled", enabled and "true" or "false" }, root)
  return err == nil, err
end

function M.refs(root)
  local output, err = run({
    "git", "for-each-ref", "--sort=-committerdate",
    "--format=%(refname)%09%(committerdate:format:%Y-%m-%d %H:%M:%S)%09%(subject)",
    "refs/codex-timeline/",
  }, root)
  if not output then
    return nil, err
  end
  local refs = {}
  for line in output:gmatch("[^\n]+") do
    local ref, time, subject = line:match("^([^\t]+)\t([^\t]+)\t(.*)$")
    if ref then
      refs[#refs + 1] = { ref = ref, time = time, subject = subject }
    end
  end
  return refs
end

function M.events(root, ref)
  local output, err = run({
    "git", "log", "--reverse", "--topo-order", "--date=format:%H:%M:%S",
    "-z", "--format=%H%x1f%P%x1f%T%x1f%ad%x1f%s%x1f%B", ref,
  }, root)
  if not output then
    return nil, err
  end

  local events = {}
  local zero_based = nil
  local turns = {}
  local turn_count = 0
  for record in output:gmatch("([^%z]+)%z") do
    local hash, parents, tree, time, subject, body = record:match(
      "^([^\31]+)\31([^\31]*)\31([^\31]+)\31([^\31]+)\31([^\31]*)\31(.*)$"
    )
    if hash then
      local synthetic = subject:match("^timeline:") ~= nil or subject:match("^codex%-timeline:") ~= nil
      if zero_based == nil then
        zero_based = synthetic
      end
      local turn = body:match("[\r\n]Timeline%-Turn:%s*([^\r\n]+)")
        or body:match("^Timeline%-Turn:%s*([^\r\n]+)")
        or body:match("[\r\n]Codex%-Timeline%-Turn:%s*([^\r\n]+)")
        or body:match("^Codex%-Timeline%-Turn:%s*([^\r\n]+)")
      turn = turn and vim.trim(turn) or nil
      if turn == "" or (turn and turn:lower() == "unknown") then
        turn = nil
      end
      if turn and not turns[turn] then
        turn_count = turn_count + 1
        turns[turn] = turn_count
      end
      local sequence = zero_based and #events or (#events + 1)
      events[#events + 1] = {
        hash = hash,
        tree = tree,
        parent = parents:match("^[^ ]+") or "",
        time = time,
        subject = subject:gsub("^timeline:%s*", ""):gsub("^codex%-timeline:%s*", ""),
        sequence = sequence,
        synthetic = synthetic,
        turn = turn,
        turn_number = turn and turns[turn] or nil,
      }
    end
  end
  return events
end

-- Fold Timeline's tool-level snapshots into the ordinary Git commits whose
-- trees they produced. A run of snapshots ends at the first reachable commit
-- with the same tree. Anything newer than HEAD remains a WIP group until the
-- user creates the commit.
function M.commits(root, events)
  local output, err = run({
    "git", "log", "--reverse", "--topo-order", "-z",
    "--date=format:%H:%M:%S", "--format=%H%x1f%P%x1f%T%x1f%ad%x1f%s", "HEAD",
  }, root)
  if not output then
    return nil, err
  end

  local ordinary = {}
  for record in output:gmatch("([^%z]+)%z") do
    local hash, parents, tree, time, subject = record:match(
      "^([^\31]+)\31([^\31]*)\31([^\31]+)\31([^\31]+)\31(.*)$"
    )
    if hash then
      ordinary[#ordinary + 1] = {
        hash = hash,
        parent = parents:match("^[^ ]+") or "",
        tree = tree,
        time = time,
        subject = subject,
      }
    end
  end

  local function number_codex_changes(grouped)
    local commit_turns, turn_count, change_count = {}, 0, 0
    for _, event in ipairs(grouped) do
      if event.turn then
        change_count = change_count + 1
        event.commit_sequence = change_count
        if not commit_turns[event.turn] then
          turn_count = turn_count + 1
          commit_turns[event.turn] = turn_count
        end
        event.commit_turn_number = commit_turns[event.turn]
      end
    end
  end

  local groups, event_index = {}, 1
  for _, commit in ipairs(ordinary) do
    local boundary
    for index = event_index, #events do
      if events[index].tree == commit.tree then
        boundary = index
        break
      end
    end
    local grouped = {}
    if boundary then
      for index = event_index, boundary do
        grouped[#grouped + 1] = events[index]
      end
      event_index = boundary + 1
    else
      -- A Git-only commit is still a top-level Timeline entry. Its own commit
      -- object is sufficient to reconstruct the complete codebase and diff.
      grouped[1] = {
        hash = commit.hash,
        parent = commit.parent,
        tree = commit.tree,
        time = commit.time,
        subject = commit.subject,
        sequence = #groups + 1,
        synthetic = false,
      }
    end
    number_codex_changes(grouped)
    groups[#groups + 1] = {
      hash = commit.hash,
      tree = commit.tree,
      subject = commit.subject,
      events = grouped,
      sequence = #groups + 1,
    }
  end

  if event_index <= #events then
    local grouped = {}
    for index = event_index, #events do
      grouped[#grouped + 1] = events[index]
    end
    groups[#groups + 1] = {
      hash = "wip",
      tree = grouped[#grouped].tree,
      subject = "Uncommitted changes",
      events = grouped,
      sequence = #groups + 1,
      wip = true,
    }
    number_codex_changes(grouped)
  end
  return groups
end

function M.diff(root, event)
  local args
  if event.parent ~= "" then
    args = { "git", "diff", "--no-color", "--no-ext-diff", "--minimal", event.parent, event.hash, "--" }
  else
    args = { "git", "show", "--format=", "--no-color", "--no-ext-diff", event.hash, "--" }
  end
  return run(args, root)
end

function M.files(root, event)
  local args
  if event.parent ~= "" then
    args = { "git", "diff", "--name-only", event.parent, event.hash, "--" }
  else
    args = { "git", "show", "--format=", "--name-only", event.hash, "--" }
  end
  local output = run(args, root) or ""
  return vim.split(vim.trim(output), "\n", { plain = true, trimempty = true })
end

function M.tree(root, event)
  local output, err = run({ "git", "ls-tree", "-r", "--name-only", event.hash }, root)
  if not output then
    return nil, err
  end
  return vim.split(vim.trim(output), "\n", { plain = true, trimempty = true })
end

function M.search_paths(root, event, query)
  if not query or query == "" then
    return {}
  end
  local output = run({
    "git", "grep", "-l", "-I", "-i", "-F", "-z", "-e", query,
    event.hash, "--",
  }, root)
  if not output then
    -- git grep exits with status 1 when there are no matches.
    return {}
  end
  local prefix = event.hash .. ":"
  local paths = {}
  for _, value in ipairs(vim.split(output, "\0", { plain = true, trimempty = true })) do
    if value:sub(1, #prefix) == prefix then
      value = value:sub(#prefix + 1)
    end
    paths[#paths + 1] = value
  end
  return paths
end

function M.changes(root, event)
  if event.parent == "" then
    if event.sequence == 0 then
      return {}
    end
    local files, err = M.tree(root, event)
    if not files then
      return nil, err
    end
    local root_changes = {}
    for _, path in ipairs(files) do
      root_changes[path] = { kind = "A", path = path }
    end
    return root_changes
  end
  local output, err = run({
    "git", "diff", "--name-status", "-M", event.parent, event.hash, "--",
  }, root)
  if not output then
    return nil, err
  end

  local changes = {}
  for line in output:gmatch("[^\n]+") do
    local fields = vim.split(line, "\t", { plain = true })
    local status = fields[1] or "M"
    local kind = status:sub(1, 1)
    if kind == "R" or kind == "C" then
      local old_path, new_path = fields[2], fields[3]
      if new_path then
        changes[new_path] = { kind = kind, old_path = old_path, path = new_path }
      end
    elseif fields[2] then
      changes[fields[2]] = { kind = kind, path = fields[2] }
    end
  end
  return changes
end

function M.file_change_orders(root, commit, selected_event)
  local orders = {}
  for _, event in ipairs(commit.events or {}) do
    if event.commit_sequence then
      local changes, err = M.changes(root, event)
      if not changes then return nil, err end
      for path in pairs(changes) do
        orders[path] = orders[path] or {}
        orders[path][#orders[path] + 1] = event.commit_sequence
      end
    end
    if selected_event and event.hash == selected_event.hash then break end
  end
  return orders
end

function M.line_change_orders(root, commit, event, path)
  local hashes = {}
  for _, candidate in ipairs(commit.events or {}) do
    if candidate.commit_sequence then hashes[candidate.hash] = candidate.commit_sequence end
    if candidate.hash == event.hash then break end
  end
  if next(hashes) == nil then return {} end

  local output = run({ "git", "blame", "--line-porcelain", event.hash, "--", path }, root)
  if not output then return {} end
  local orders = {}
  for line in output:gmatch("[^\n]+") do
    local hash, _, final_line, count = line:match("^%^?([0-9a-f]+) (%d+) (%d+) ?(%d*)$")
    if hash then
      local order = hashes[hash]
      local first = tonumber(final_line)
      local length = tonumber(count) or 1
      if order and first then
        for offset = 0, length - 1 do orders[first + offset] = order end
      end
    end
  end
  return orders
end

function M.file_content(root, event, path)
  local output, err = run({ "git", "show", event.hash .. ":" .. path }, root)
  if not output then
    return nil, err
  end
  return vim.split(output, "\n", { plain = true })
end

local function parse_full_diff(patch)
  local lines, highlights = {}, {}
  local inside_hunk = false
  for line in patch:gmatch("([^\n]*)\n?") do
    if line:sub(1, 2) == "@@" then
      inside_hunk = true
    elseif inside_hunk and line:sub(1, 1) == "+" then
      lines[#lines + 1] = line:sub(2)
      highlights[#highlights + 1] = { line = #lines, kind = "add" }
    elseif inside_hunk and line:sub(1, 1) == "-" then
      lines[#lines + 1] = line:sub(2)
      highlights[#highlights + 1] = { line = #lines, kind = "delete" }
    elseif inside_hunk and line:sub(1, 1) == " " then
      lines[#lines + 1] = line:sub(2)
    elseif inside_hunk and line == "\\ No newline at end of file" then
      -- Git metadata is intentionally omitted from the source view.
    end
  end
  return lines, highlights
end

function M.file_snapshot(root, event, path, change)
  if not change or (event.parent == "" and event.sequence == 0) then
    local lines, err = M.file_content(root, event, path)
    return lines, {}, err
  end

  local args
  if event.parent == "" then
    args = {
      "git", "show", "--format=", "--no-color", "--no-ext-diff", "--minimal", "--unified=999999",
      event.hash, "--", path,
    }
  else
    args = {
      "git", "diff", "--no-color", "--no-ext-diff", "--minimal", "--unified=999999",
      event.parent, event.hash, "--", path,
    }
  end
  local output, err = run(args, root)
  if not output then
    return nil, nil, err
  end
  local lines, highlights = parse_full_diff(output)
  if #lines > 0 or #highlights > 0 then
    return lines, highlights
  end

  -- Binary files and rare diff formats have no textual hunk. Show the file at
  -- the selected snapshot without inventing patch metadata.
  if change.kind ~= "D" then
    local content, content_err = M.file_content(root, event, path)
    return content, {}, content_err
  end
  local deleted, deleted_err = run({ "git", "show", event.parent .. ":" .. path }, root)
  if not deleted then
    return nil, nil, deleted_err
  end
  local deleted_lines = vim.split(deleted, "\n", { plain = true })
  local deleted_highlights = {}
  for index = 1, #deleted_lines do
    deleted_highlights[#deleted_highlights + 1] = { line = index, kind = "delete" }
  end
  return deleted_lines, deleted_highlights
end

function M.blame(root, ref, relative_path)
  local output, err = run({ "git", "blame", "--line-porcelain", ref, "--", relative_path }, root)
  if not output then
    return nil, err
  end

  local hashes = {}
  for line in output:gmatch("[^\n]+") do
    local hash, final_line = line:match("^(%x+) %d+ (%d+)")
    if hash and final_line then
      hashes[tonumber(final_line)] = hash
    end
  end
  return hashes
end

return M
