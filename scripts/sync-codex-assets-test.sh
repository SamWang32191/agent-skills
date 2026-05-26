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

assert_not_exists_path() {
  local label="$1" path="$2"
  if [ ! -e "$path" ]; then
    pass=$((pass + 1))
    printf '  PASS: %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL: %s\n    expected missing path: %s\n' "$label" "$path" >&2
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

assert_is_symlink() {
  local label="$1" path="$2"
  if [ -L "$path" ]; then
    pass=$((pass + 1))
    printf '  PASS: %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL: %s\n    expected symlink: %s\n' "$label" "$path" >&2
  fi
}

assert_is_dir() {
  local label="$1" path="$2"
  if [ -d "$path" ]; then
    pass=$((pass + 1))
    printf '  PASS: %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL: %s\n    expected directory: %s\n' "$label" "$path" >&2
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
tmp_non_target_root="$TMPDIR/non-target-source"
mkdir -p "$tmp_non_target_root/scripts"
cp -R codex "$tmp_non_target_root/"
cp scripts/sync-codex-assets.sh "$tmp_non_target_root/scripts/"
chmod +x "$tmp_non_target_root/scripts/sync-codex-assets.sh"
printf 'not a prompt file\n' > "$tmp_non_target_root/codex/prompts/not-a-prompt.txt"
printf 'not an agent file\n' > "$tmp_non_target_root/codex/agents/not-an-agent.md"
home3="$TMPDIR/home3"
mkdir -p "$home3"
_ignore_output="$(CODEX_HOME="$home3" bash "$tmp_non_target_root/scripts/sync-codex-assets.sh" --dry-run)"
assert_not_exists "prompt non-target is not copied" "$home3/prompts/not-a-prompt.txt"
assert_not_exists "agent non-target is not copied" "$home3/agents/not-an-agent.md"

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

printf '\nTest 8: dangling destination file symlink remains conflict even with --force\n'
tmp_symlink_root="$TMPDIR/symlink-dest"
mkdir -p "$tmp_symlink_root/scripts"
cp -R codex "$tmp_symlink_root/"
cp scripts/sync-codex-assets.sh "$tmp_symlink_root/scripts/"
chmod +x "$tmp_symlink_root/scripts/sync-codex-assets.sh"
home4="$TMPDIR/home4"
mkdir -p "$home4/prompts"
mkdir -p "$tmp_symlink_root/ext"
printf 'external target content\n' > "$tmp_symlink_root/ext/agent-skills-spec-target.txt"
ln -sf "$tmp_symlink_root/ext/agent-skills-spec-target.txt-missing" "$home4/prompts/agent-skills-spec.md"
set +e
symlink_output="$(CODEX_HOME="$home4" bash "$tmp_symlink_root/scripts/sync-codex-assets.sh" --force 2>"$TMPDIR/symlink.stderr")"
symlink_status=$?
set -e
symlink_stderr="$(cat "$TMPDIR/symlink.stderr")"
assert_eq "symlink destination exits 2" "2" "$symlink_status"
assert_contains "symlink destination conflict status" '"status":"conflict"' "$symlink_output"
assert_contains "symlink destination path included" 'prompts/agent-skills-spec.md' "$symlink_output"
assert_is_symlink "destination remains a symlink" "$home4/prompts/agent-skills-spec.md"
assert_eq "symlink dangling target remains missing" "agent-skills-spec-target.txt-missing" \
  "$(basename "$(readlink "$home4/prompts/agent-skills-spec.md")")"
assert_not_exists_path "symlink dangling external target still missing" \
  "$tmp_symlink_root/ext/agent-skills-spec-target.txt-missing"
assert_contains "symlink path does not write through on stderr" 'destination is symlink' "$symlink_stderr"

printf '\nTest 9: destination prompts directory is regular file (dry-run)\n'
home7="$TMPDIR/home7"
mkdir -p "$home7"
printf 'opaque file\n' > "$home7/prompts"
set +e
prompts_file_output="$(CODEX_HOME="$home7" bash scripts/sync-codex-assets.sh --dry-run 2>"$TMPDIR/prompts-dir-file.err")"
prompts_file_status=$?
set -e
assert_eq "destination prompts file (dry-run) exits 2" "2" "$prompts_file_status"
assert_contains "destination prompts file conflict JSON status" '"status":"conflict"' "$prompts_file_output"
assert_contains "destination prompts file conflict path included" '"prompts"' "$prompts_file_output"
assert_file_exists "destination prompts file remains untouched" "$home7/prompts"

printf '\nTest 10: destination agents directory is regular file (dry-run)\n'
home8="$TMPDIR/home8"
mkdir -p "$home8"
printf 'opaque file\n' > "$home8/agents"
set +e
agents_file_output="$(CODEX_HOME="$home8" bash scripts/sync-codex-assets.sh --dry-run 2>"$TMPDIR/agents-dir-file.err")"
agents_file_status=$?
set -e
assert_eq "destination agents file (dry-run) exits 2" "2" "$agents_file_status"
assert_contains "destination agents file conflict JSON status" '"status":"conflict"' "$agents_file_output"
assert_contains "destination agents file conflict path included" '"agents"' "$agents_file_output"
assert_file_exists "destination agents file remains untouched" "$home8/agents"

printf '\nTest 11: prompt artifact destination path as directory blocks sync even with force\n'
home9="$TMPDIR/home9/prompts"
mkdir -p "$home9"
mkdir -p "$home9/agent-skills-spec.md"
set +e
artifact_dir_output="$(CODEX_HOME="$TMPDIR/home9" bash scripts/sync-codex-assets.sh --force 2>"$TMPDIR/artifact-dir.err")"
artifact_dir_status=$?
set -e
assert_eq "prompt artifact path directory exits 2" "2" "$artifact_dir_status"
assert_contains "prompt artifact path directory conflict JSON status" '"status":"conflict"' "$artifact_dir_output"
assert_contains "prompt artifact directory path included" 'prompts/agent-skills-spec.md' "$artifact_dir_output"
assert_is_dir "prompt artifact destination still directory" "$TMPDIR/home9/prompts/agent-skills-spec.md"

printf '\nTest 12: agents artifact destination path as directory blocks sync even with force\n'
home10="$TMPDIR/home10/agents"
mkdir -p "$home10"
mkdir -p "$home10/code-reviewer.toml"
set +e
artifact_dir_agents_output="$(CODEX_HOME="$TMPDIR/home10" bash scripts/sync-codex-assets.sh --force 2>"$TMPDIR/artifact-dir-agents.err")"
artifact_dir_agents_status=$?
set -e
assert_eq "agents artifact path directory exits 2" "2" "$artifact_dir_agents_status"
assert_contains "agents artifact path directory conflict JSON status" '"status":"conflict"' "$artifact_dir_agents_output"
assert_contains "agents artifact directory path included" 'agents/code-reviewer.toml' "$artifact_dir_agents_output"
assert_is_dir "agents artifact destination still directory" "$TMPDIR/home10/agents/code-reviewer.toml"

printf '\nTest 13: symlinked prompts directory is reported as conflict\n'
tmp_dirsymlink_root="$TMPDIR/dirsymlink-prompts-root"
mkdir -p "$tmp_dirsymlink_root/scripts"
cp -R codex "$tmp_dirsymlink_root/"
cp scripts/sync-codex-assets.sh "$tmp_dirsymlink_root/scripts/"
chmod +x "$tmp_dirsymlink_root/scripts/sync-codex-assets.sh"
home5="$TMPDIR/home5"
mkdir -p "$home5"
ln -sfn "$tmp_dirsymlink_root/ext-prompts-missing" "$home5/prompts"
set +e
dirsymlink_output="$(CODEX_HOME="$home5" bash "$tmp_dirsymlink_root/scripts/sync-codex-assets.sh" --force 2>"$TMPDIR/dirsymlink-prompts.stderr")"
dirsymlink_status=$?
set -e
dirsymlink_stderr="$(cat "$TMPDIR/dirsymlink-prompts.stderr")"
assert_eq "symlinked prompts directory exits 2" "2" "$dirsymlink_status"
assert_contains "symlinked prompts directory conflict status" '"status":"conflict"' "$dirsymlink_output"
assert_contains "symlinked prompts conflict path included" '"prompts"' "$dirsymlink_output"
assert_is_symlink "prompts destination remains a symlink" "$home5/prompts"
assert_contains "symlinked prompts reports directory symlink" 'destination directory is symlink' "$dirsymlink_stderr"
assert_not_exists_path "external dangling prompts target remains missing" "$tmp_dirsymlink_root/ext-prompts-missing"

printf '\nTest 14: symlinked agents directory is reported as conflict\n'
tmp_dirsymlink_agents_root="$TMPDIR/dirsymlink-agents-root"
mkdir -p "$tmp_dirsymlink_agents_root/scripts"
cp -R codex "$tmp_dirsymlink_agents_root/"
cp scripts/sync-codex-assets.sh "$tmp_dirsymlink_agents_root/scripts/"
chmod +x "$tmp_dirsymlink_agents_root/scripts/sync-codex-assets.sh"
home6="$TMPDIR/home6"
mkdir -p "$home6"
ln -sfn "$tmp_dirsymlink_agents_root/ext-agents-missing" "$home6/agents"
set +e
dirsymlink_agents_output="$(CODEX_HOME="$home6" bash "$tmp_dirsymlink_agents_root/scripts/sync-codex-assets.sh" --force 2>"$TMPDIR/dirsymlink-agents.stderr")"
dirsymlink_agents_status=$?
set -e
dirsymlink_agents_stderr="$(cat "$TMPDIR/dirsymlink-agents.stderr")"
assert_eq "symlinked agents directory exits 2" "2" "$dirsymlink_agents_status"
assert_contains "symlinked agents directory conflict status" '"status":"conflict"' "$dirsymlink_agents_output"
assert_contains "symlinked agents conflict path included" '"agents"' "$dirsymlink_agents_output"
assert_is_symlink "agents destination remains a symlink" "$home6/agents"
assert_contains "symlinked agents reports directory symlink" 'destination directory is symlink' "$dirsymlink_agents_stderr"
assert_not_exists_path "external dangling agents target remains missing" "$tmp_dirsymlink_agents_root/ext-agents-missing"

if [ "$fail" -gt 0 ]; then
  printf '\n%d assertion(s) failed\n' "$fail" >&2
  exit 1
fi

printf '\n%d assertion(s) passed\n' "$pass"
