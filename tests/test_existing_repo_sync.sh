#!/usr/bin/env bash
set -euo pipefail

project_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-timeline-existing.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

git -C "$test_root" init -q
git -C "$test_root" config user.name Test
git -C "$test_root" config user.email test@example.com
printf 'committed\n' > "$test_root/existing.txt"
git -C "$test_root" add existing.txt
git -C "$test_root" commit -qm "create existing project"
printf 'dark_mode=true\n' > "$test_root/settings.txt"
git -C "$test_root" add settings.txt
git -C "$test_root" commit -qm "add project settings"
printf 'committed\nsecond committed line\n' > "$test_root/existing.txt"
git -C "$test_root" add existing.txt
git -C "$test_root" commit -qm "extend existing feature"
# Simulate the previous plugin format, which stored the whole existing project
# as one synthetic root snapshot. Synchronization must migrate it in place.
"$project_root/bin/timeline" start --repo "$test_root" --session old-project-format >/dev/null
git -C "$test_root" update-ref \
  refs/codex-timeline/session-project \
  refs/codex-timeline/session-old-project-format
# Simulate a repository recorded by an older plugin version. The continuous
# project timeline must still be created and selected instead of reusing this.
git -C "$test_root" update-ref refs/codex-timeline/session-legacy HEAD
head_before="$(git -C "$test_root" rev-parse HEAD)"
index_before="$(git -C "$test_root" write-tree)"
printf 'committed\nsecond committed line\nlocal work before sync\n' > "$test_root/existing.txt"
printf 'untracked before sync\n' > "$test_root/new.txt"

TIMELINE_PROJECT="$project_root" TIMELINE_TEST_REPO="$test_root" \
  nvim --headless -u NONE -i NONE -l "$project_root/tests/test_existing_repo_sync.lua"

ref="refs/codex-timeline/session-project"
[[ "$(git -C "$test_root" rev-list --count "$ref")" == 4 ]]
history="$(git -C "$test_root" log --reverse --format=%s "$ref")"
[[ "$history" == *"create existing project"* ]]
[[ "$history" == *"add project settings"* ]]
[[ "$history" == *"extend existing feature"* ]]
[[ "$history" == *"timeline: existing project baseline"* ]]
[[ "$(git -C "$test_root" show "$ref:existing.txt")" == $'committed\nsecond committed line\nlocal work before sync' ]]
[[ "$(git -C "$test_root" show "$ref:new.txt")" == 'untracked before sync' ]]
[[ "$(git -C "$test_root" rev-parse HEAD)" == "$head_before" ]]
[[ "$(git -C "$test_root" write-tree)" == "$index_before" ]]

printf 'existing repository sync test passed\n'
