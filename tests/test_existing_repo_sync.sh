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
git -C "$test_root" commit -qm "existing history"
# Simulate a repository recorded by an older plugin version. The continuous
# project timeline must still be created and selected instead of reusing this.
git -C "$test_root" update-ref refs/codex-timeline/session-legacy HEAD
head_before="$(git -C "$test_root" rev-parse HEAD)"
index_before="$(git -C "$test_root" write-tree)"
printf 'committed\nlocal work before sync\n' > "$test_root/existing.txt"
printf 'untracked before sync\n' > "$test_root/new.txt"

CODEX_TIMELINE_PROJECT="$project_root" CODEX_TIMELINE_TEST_REPO="$test_root" \
  nvim --headless -u NONE -i NONE -l "$project_root/tests/test_existing_repo_sync.lua"

ref="refs/codex-timeline/session-project"
[[ "$(git -C "$test_root" rev-list --count "$ref")" == 1 ]]
[[ "$(git -C "$test_root" show "$ref:existing.txt")" == $'committed\nlocal work before sync' ]]
[[ "$(git -C "$test_root" show "$ref:new.txt")" == 'untracked before sync' ]]
[[ "$(git -C "$test_root" rev-parse HEAD)" == "$head_before" ]]
[[ "$(git -C "$test_root" write-tree)" == "$index_before" ]]

printf 'existing repository sync test passed\n'
