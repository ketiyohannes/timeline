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
printf '{"session_id":"thr_test","turn_id":"turn_1","tool_name":"apply_patch","tool_use_id":"call_1","cwd":"%s"}\n' "$test_root" |
  "$project_root/bin/codex-timeline-hook" PreToolUse
printf 'before\nafter\n' > "$test_root/hooked.txt"
printf '{"session_id":"thr_test","turn_id":"turn_1","tool_name":"apply_patch","tool_use_id":"call_1","cwd":"%s"}\n' "$test_root" |
  "$project_root/bin/codex-timeline-hook" PostToolUse

ref="refs/codex-timeline/session-thr_test"
[[ "$(git -C "$test_root" rev-list --count "$ref")" == 2 ]]
message="$(git -C "$test_root" log -1 --format=%B "$ref")"
[[ "$message" == *"codex-timeline: apply_patch"* ]]
[[ "$message" == *"Codex-Timeline-Turn: turn_1"* ]]
[[ "$message" == *"Codex-Timeline-Tool-Use: call_1"* ]]

automatic_root="$test_root/automatic"
mkdir "$automatic_root"
git -C "$automatic_root" init -q
printf '{"session_id":"automatic","cwd":"%s","hook_event_name":"SessionStart"}\n' "$automatic_root" |
  "$project_root/bin/codex-timeline-hook" SessionStart
git -C "$automatic_root" show-ref --verify --quiet refs/codex-timeline/session-automatic || {
  printf 'hook did not automatically record an unconfigured repository\n' >&2
  exit 1
}

disabled_root="$test_root/disabled"
mkdir "$disabled_root"
git -C "$disabled_root" init -q
"$project_root/bin/codex-timeline" disable --repo "$disabled_root" >/dev/null
printf '{"session_id":"disabled","cwd":"%s","hook_event_name":"SessionStart"}\n' "$disabled_root" |
  "$project_root/bin/codex-timeline-hook" SessionStart
if git -C "$disabled_root" show-ref --quiet refs/codex-timeline/session-disabled; then
  printf 'hook recorded an explicitly disabled repository\n' >&2
  exit 1
fi

printf 'hook test passed\n'
