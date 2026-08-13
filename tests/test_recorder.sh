#!/usr/bin/env bash
set -euo pipefail

project_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-timeline-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

git -C "$test_root" init -q
git -C "$test_root" config user.name Test
git -C "$test_root" config user.email test@example.com
printf 'alpha\n' > "$test_root/example.txt"
git -C "$test_root" add example.txt
git -C "$test_root" commit -qm baseline
[[ "$("$project_root/bin/codex-timeline" status --repo "$test_root")" == "enabled" ]] || {
  printf 'unconfigured Git repository should be enabled by default\n' >&2
  exit 1
}
"$project_root/bin/codex-timeline" sync --repo "$test_root" >/dev/null
git -C "$test_root" show-ref --verify --quiet refs/codex-timeline/session-project

head_before="$(git -C "$test_root" rev-parse HEAD)"
index_before="$(git -C "$test_root" write-tree)"

"$project_root/bin/codex-timeline" start --repo "$test_root" --session test >/dev/null
printf 'alpha\nbeta\n' > "$test_root/example.txt"
"$project_root/bin/codex-timeline" checkpoint --repo "$test_root" --session test --label apply_patch --tool apply_patch >/dev/null
printf 'alpha\nbeta\ngamma\n' > "$test_root/example.txt"
"$project_root/bin/codex-timeline" checkpoint --repo "$test_root" --session test --label exec_command --tool exec_command >/dev/null
"$project_root/bin/codex-timeline" checkpoint --repo "$test_root" --session test --label no-op >/dev/null

ref="refs/codex-timeline/session-test"
count="$(git -C "$test_root" rev-list --count "$ref")"
[[ "$count" == 3 ]] || { printf 'expected 3 snapshots, got %s\n' "$count" >&2; exit 1; }
[[ "$(git -C "$test_root" rev-parse HEAD)" == "$head_before" ]] || { printf 'HEAD changed\n' >&2; exit 1; }
[[ "$(git -C "$test_root" write-tree)" == "$index_before" ]] || { printf 'index changed\n' >&2; exit 1; }

list_output="$("$project_root/bin/codex-timeline" list --repo "$test_root" --session test)"
[[ "$list_output" == *"codex-timeline: apply_patch"* ]] || { printf 'missing first event\n' >&2; exit 1; }
[[ "$list_output" == *"codex-timeline: exec_command"* ]] || { printf 'missing second event\n' >&2; exit 1; }
"$project_root/bin/codex-timeline" diff 1 --repo "$test_root" --session test | grep -q '^+beta$'
"$project_root/bin/codex-timeline" diff 2 --repo "$test_root" --session test | grep -q '^+gamma$'

printf 'untracked\n' > "$test_root/new file.txt"
"$project_root/bin/codex-timeline" checkpoint --repo "$test_root" --session test --label add-file >/dev/null
rm "$test_root/new file.txt"
"$project_root/bin/codex-timeline" checkpoint --repo "$test_root" --session test --label delete-file >/dev/null
"$project_root/bin/codex-timeline" files 3 --repo "$test_root" --session test | grep -q '^new file.txt$'
"$project_root/bin/codex-timeline" diff 4 --repo "$test_root" --session test | grep -q '^deleted file mode'

printf 'alpha\nbeta\ngamma\ndelta\n' > "$test_root/example.txt"
"$project_root/bin/codex-timeline" checkpoint --repo "$test_root" --session race --label first >/dev/null &
first_pid=$!
"$project_root/bin/codex-timeline" checkpoint --repo "$test_root" --session race --label second >/dev/null &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
[[ "$(git -C "$test_root" rev-list --count refs/codex-timeline/session-race)" == 1 ]]

printf 'recorder test passed\n'
