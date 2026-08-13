#!/usr/bin/env bash
set -euo pipefail

project_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-timeline-nvim-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

git -C "$test_root" init -q
git -C "$test_root" config user.name Test
git -C "$test_root" config user.email test@example.com
printf 'alpha\n' > "$test_root/example.txt"
printf 'stable\n' > "$test_root/unchanged.txt"
git -C "$test_root" add example.txt
git -C "$test_root" add unchanged.txt
git -C "$test_root" commit -qm baseline
"$project_root/bin/codex-timeline" start --repo "$test_root" --session nvim >/dev/null
printf 'alpha\nbeta\n' > "$test_root/example.txt"
"$project_root/bin/codex-timeline" checkpoint --repo "$test_root" --session nvim --label apply_patch >/dev/null
printf 'alpha\ngamma\n' > "$test_root/example.txt"
printf 'new\n' > "$test_root/added.txt"
rm "$test_root/unchanged.txt"
"$project_root/bin/codex-timeline" checkpoint --repo "$test_root" --session nvim --label refactor >/dev/null

CODEX_TIMELINE_PROJECT="$project_root" \
CODEX_TIMELINE_TEST_REPO="$test_root" \
  nvim --headless -u NONE -l "$project_root/tests/test_nvim_integration.lua"
