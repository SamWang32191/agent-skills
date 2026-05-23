#!/bin/bash
# Tests for scripts/sync-codex-assets.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_file_exists() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then
    pass=$((pass + 1))
    printf '  PASS: %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL: %s\n    missing: %s\n' "$label" "$path" >&2
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -Fq "$needle"; then
    pass=$((pass + 1))
    printf '  PASS: %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL: %s\n    expected substring: %s\n    actual: %s\n' "$label" "$needle" "$haystack" >&2
  fi
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1))
    printf '  PASS: %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL: %s\n    expected: %s\n    actual: %s\n' "$label" "$expected" "$actual" >&2
  fi
}

assert_no_files() {
  local label="$1" path="$2"
  local file_count
  file_count="$(find "$path" -type f | wc -l | tr -d ' ')"
  if [ "$file_count" -eq 0 ]; then
    pass=$((pass + 1))
    printf '  PASS: %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL: %s\n    expected no files under %s\n    found: %s\n' "$label" "$path" "$file_count" >&2
  fi
}

assert_files_are_equal() {
  local label="$1" expected="$2" actual="$3"
  if cmp -s "$expected" "$actual"; then
    pass=$((pass + 1))
    printf '  PASS: %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL: %s\n    expected file: %s\n    actual file: %s\n' "$label" "$expected" "$actual" >&2
  fi
}

if [ ! -d codex/prompts ] || [ ! -d codex/agents ]; then
  printf 'Generated codex assets are missing. Run: node scripts/codex-distribution.mjs generate\n' >&2
  exit 1
fi

printf 'Test 1: dry-run reports copies without writing\n'
home1="$TMPDIR/home1"
mkdir -p "$home1"
dry_output="$(CODEX_HOME="$home1" bash scripts/sync-codex-assets.sh --dry-run)"
assert_contains "dry-run JSON status" '"status":"ok"' "$dry_output"
assert_contains "dry-run records prompt copy" 'prompts/agent-skills-spec.md' "$dry_output"
assert_no_files "dry-run did not write any files" "$home1"

printf '\nTest 2: normal sync copies prompts and agents\n'
sync_output="$(CODEX_HOME="$home1" bash scripts/sync-codex-assets.sh)"
assert_contains "sync JSON status" '"status":"ok"' "$sync_output"
assert_file_exists "prompt copied" "$home1/prompts/agent-skills-spec.md"
assert_file_exists "agent copied" "$home1/agents/code-reviewer.toml"

printf '\nTest 3: conflict refuses overwrite by default\n'
home2="$TMPDIR/home2"
mkdir -p "$home2/prompts"
printf 'local edit\n' > "$home2/prompts/agent-skills-spec.md"
local_edit_tmp="$TMPDIR/local-edit-before-force.txt"
cp "$home2/prompts/agent-skills-spec.md" "$local_edit_tmp"
set +e
conflict_output="$(CODEX_HOME="$home2" bash scripts/sync-codex-assets.sh 2>"$TMPDIR/conflict.err")"
conflict_status=$?
set -e
assert_eq "conflict exits 2" "2" "$conflict_status"
assert_contains "conflict JSON status" '"status":"conflict"' "$conflict_output"
assert_contains "conflict path included" 'prompts/agent-skills-spec.md' "$conflict_output"
assert_eq "local file preserved" "local edit" "$(cat "$home2/prompts/agent-skills-spec.md")"

printf '\nTest 4: force backs up conflict before overwrite\n'
force_output="$(CODEX_HOME="$home2" bash scripts/sync-codex-assets.sh --force)"
assert_contains "force JSON status" '"status":"ok"' "$force_output"
assert_contains "backup path included" 'backups/agent-skills/' "$force_output"
backup_count="$(find "$home2/backups/agent-skills" -type f | wc -l | tr -d ' ')"
assert_eq "one backup written" "1" "$backup_count"
backup_file="$(find "$home2/backups/agent-skills" -type f | head -n 1)"
assert_file_exists "backup file exists" "$backup_file"
assert_files_are_equal "backup preserved original content" "$local_edit_tmp" "$backup_file"
assert_files_are_equal "destination overwritten from generated prompt" "codex/prompts/agent-skills-spec.md" "$home2/prompts/agent-skills-spec.md"

if [ "$fail" -gt 0 ]; then
  printf '\n%d assertion(s) failed\n' "$fail" >&2
  exit 1
fi

printf '\n%d assertion(s) passed\n' "$pass"
