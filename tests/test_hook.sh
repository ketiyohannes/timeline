#!/usr/bin/env bash
set -euo pipefail

project_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-timeline-hook-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

git -C "$test_root" init -q
git -C "$test_root" config user.name Test
git -C "$test_root" config user.email test@example.com
printf 'before\n' > "$test_root/hooked.txt"
git -C "$test_root" add hooked.txt
git -C "$test_root" commit -qm baseline
head_before="$(git -C "$test_root" rev-parse HEAD)"
index_before="$(git -C "$test_root" write-tree)"
printf 'before\npre-existing local work\n' > "$test_root/hooked.txt"
printf 'already here\n' > "$test_root/untracked.txt"

printf '{"session_id":"thr_test","cwd":"%s","hook_event_name":"SessionStart"}\n' "$test_root" |
  "$project_root/bin/codex-timeline-hook" SessionStart
printf '{"session_id":"thr_test","turn_id":"turn_1","tool_name":"apply_patch","tool_use_id":"call_1","tool_input":{"command":"*** Update File: hooked.txt"},"cwd":"%s"}\n' "$test_root" |
  "$project_root/bin/codex-timeline-hook" PreToolUse
printf 'before\npre-existing local work\nafter first task\n' > "$test_root/hooked.txt"
printf '{"session_id":"thr_test","turn_id":"turn_1","tool_name":"apply_patch","tool_use_id":"call_1","tool_input":{"command":"*** Update File: hooked.txt"},"cwd":"%s"}\n' "$test_root" |
  "$project_root/bin/codex-timeline-hook" PostToolUse

printf '{"session_id":"thr_second","turn_id":"turn_2","tool_name":"apply_patch","tool_use_id":"call_2","tool_input":{"command":"*** Add File: second.txt"},"cwd":"%s"}\n' "$test_root" |
  "$project_root/bin/codex-timeline-hook" PreToolUse
printf 'second task\n' > "$test_root/second.txt"
printf '{"session_id":"thr_second","turn_id":"turn_2","tool_name":"apply_patch","tool_use_id":"call_2","tool_input":{"command":"*** Add File: second.txt"},"cwd":"%s"}\n' "$test_root" |
  "$project_root/bin/codex-timeline-hook" PostToolUse

ref="refs/codex-timeline/session-project"
[[ "$(git -C "$test_root" rev-list --count "$ref")" == 3 ]]
baseline="$(git -C "$test_root" rev-list --reverse "$ref" | sed -n '1p')"
[[ "$(git -C "$test_root" show "$baseline:hooked.txt")" == $'before\npre-existing local work' ]]
[[ "$(git -C "$test_root" show "$baseline:untracked.txt")" == 'already here' ]]
message="$(git -C "$test_root" log -1 --format=%B "$ref")"
[[ "$message" == *"codex-timeline: add second.txt"* ]]
[[ "$message" == *"Codex-Timeline-Session: thr_second"* ]]
[[ "$message" == *"Codex-Timeline-Turn: turn_2"* ]]
[[ "$message" == *"Codex-Timeline-Tool-Use: call_2"* ]]
context_output="$("$project_root/bin/codex-timeline" context 2 --repo "$test_root" --session project)"
[[ "$context_output" == *"Codex-Timeline-Session: thr_second"* ]]
[[ "$context_output" == *"Codex-Timeline-Ref: session-project"* ]]
first_message="$(git -C "$test_root" log --reverse --format=%B "$ref" | sed -n '/codex-timeline: update hooked.txt/,+8p')"
[[ "$first_message" == *"Codex-Timeline-Session: thr_test"* ]]
[[ "$(git -C "$test_root" rev-parse HEAD)" == "$head_before" ]]
[[ "$(git -C "$test_root" write-tree)" == "$index_before" ]]

automatic_root="$test_root/automatic"
mkdir "$automatic_root"
git -C "$automatic_root" init -q
printf '{"session_id":"automatic","cwd":"%s","hook_event_name":"SessionStart"}\n' "$automatic_root" |
  "$project_root/bin/codex-timeline-hook" SessionStart
git -C "$automatic_root" show-ref --verify --quiet refs/codex-timeline/session-project || {
  printf 'hook did not automatically record an unconfigured repository\n' >&2
  exit 1
}

disabled_root="$test_root/disabled"
mkdir "$disabled_root"
git -C "$disabled_root" init -q
"$project_root/bin/codex-timeline" disable --repo "$disabled_root" >/dev/null
printf '{"session_id":"disabled","cwd":"%s","hook_event_name":"SessionStart"}\n' "$disabled_root" |
  "$project_root/bin/codex-timeline-hook" SessionStart
if git -C "$disabled_root" show-ref --quiet refs/codex-timeline/session-project; then
  printf 'hook recorded an explicitly disabled repository\n' >&2
  exit 1
fi

printf 'hook test passed\n'
