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
    "git", "log", "--reverse", "--date=format:%H:%M:%S",
    "--format=%H%x09%P%x09%ad%x09%s", ref,
  }, root)
  if not output then
    return nil, err
  end

  local events = {}
  for line in output:gmatch("[^\n]+") do
    local hash, parents, time, subject = line:match("^([^\t]+)\t([^\t]*)\t([^\t]+)\t(.*)$")
    if hash then
      local sequence = #events
      events[#events + 1] = {
        hash = hash,
        parent = parents:match("^[^ ]+") or "",
        time = time,
        subject = subject:gsub("^codex%-timeline:%s*", ""),
        sequence = sequence,
      }
    end
  end
  return events
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
