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

assert_not_exists() {
  local label="$1" path="$2"
  if [ ! -f "$path" ]; then
    pass=$((pass + 1))
    printf '  PASS: %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL: %s\n    should not exist: %s\n' "$label" "$path" >&2
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

printf '\nTest 5: ignore non-target source files\n'
home3="$TMPDIR/home3"
mkdir -p "$home3"
tmp_prompt_non_target="$ROOT/codex/prompts/not-a-prompt.txt"
tmp_agent_non_target="$ROOT/codex/agents/not-an-agent.md"
printf 'not a prompt file\n' > "$tmp_prompt_non_target"
printf 'not an agent file\n' > "$tmp_agent_non_target"
_ignore_output="$(CODEX_HOME="$home3" bash scripts/sync-codex-assets.sh --dry-run)"
assert_not_exists "prompt non-target is not copied" "$home3/prompts/not-a-prompt.txt"
assert_not_exists "agent non-target is not copied" "$home3/agents/not-an-agent.md"
rm -f "$tmp_prompt_non_target" "$tmp_agent_non_target"

printf '\nTest 6: missing source directories return error JSON\n'
tmp_missing_root="$TMPDIR/missing-source"
mkdir -p "$tmp_missing_root/scripts"
cp scripts/sync-codex-assets.sh "$tmp_missing_root/scripts/"
chmod +x "$tmp_missing_root/scripts/sync-codex-assets.sh"

set +e
missing_output="$(CODEX_HOME="$TMPDIR/missing-home" bash "$tmp_missing_root/scripts/sync-codex-assets.sh" 2>"$TMPDIR/missing.stderr")"
missing_status=$?
set -e
missing_stderr="$(cat "$TMPDIR/missing.stderr")"
assert_eq "missing source directory exits 1" "1" "$missing_status"
assert_contains "missing source directory JSON status" '"status":"error"' "$missing_output"
assert_contains "missing source directory JSON type" '"type":"missing_source_dir"' "$missing_output"
assert_contains "missing source directory human-readable error" 'error:' "$missing_stderr"

printf '\nTest 7: missing matching artifacts return error JSON\n'
tmp_nomatch_root="$TMPDIR/no-matching-source"
mkdir -p "$tmp_nomatch_root/scripts" "$tmp_nomatch_root/codex/prompts" "$tmp_nomatch_root/codex/agents"
cp scripts/sync-codex-assets.sh "$tmp_nomatch_root/scripts/"
printf 'placeholder\n' > "$tmp_nomatch_root/codex/prompts/readme.txt"
printf 'placeholder\n' > "$tmp_nomatch_root/codex/agents/readme.md"
chmod +x "$tmp_nomatch_root/scripts/sync-codex-assets.sh"

set +e
nomatch_output="$(CODEX_HOME="$TMPDIR/nomatch-home" bash "$tmp_nomatch_root/scripts/sync-codex-assets.sh" 2>"$TMPDIR/nomatch.stderr")"
nomatch_status=$?
set -e
nomatch_stderr="$(cat "$TMPDIR/nomatch.stderr")"
assert_eq "no matching artifacts exits 1" "1" "$nomatch_status"
assert_contains "no matching artifacts JSON status" '"status":"error"' "$nomatch_output"
assert_contains "no matching artifacts JSON type" '"type":"missing_matching_artifacts"' "$nomatch_output"
assert_contains "no matching artifacts path message" '/no-matching-source/codex/prompts' "$nomatch_output"
assert_contains "no matching artifacts human-readable error" 'error:' "$nomatch_stderr"

if [ "$fail" -gt 0 ]; then
  printf '\n%d assertion(s) failed\n' "$fail" >&2
  exit 1
fi

printf '\n%d assertion(s) passed\n' "$pass"
