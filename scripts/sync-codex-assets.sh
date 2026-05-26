#!/bin/bash
# Install committed Codex prompts and agent roles into CODEX_HOME.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
PROMPT_SRC="$ROOT/codex/prompts"
AGENT_SRC="$ROOT/codex/agents"

DRY_RUN=0
FORCE=0
BACKUP_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="$CODEX_HOME_DIR/backups/agent-skills/$BACKUP_STAMP"

copied=()
skipped=()
conflicts=()
backups=()

usage() {
  cat <<'USAGE'
Usage: scripts/sync-codex-assets.sh [--dry-run] [--force]

Copies committed Codex prompts and agent roles into ${CODEX_HOME:-~/.codex}.

Options:
  --dry-run  Report planned writes without changing files.
  --force    Back up conflicting destination files before overwriting them.
  --help     Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'error: unknown argument: %s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

emit_error() {
  local type="$1"
  local message="$2"
  local path="$3"
  printf 'error: %s\n' "$message" >&2
  printf '{"status":"error","type":"%s","message":"%s","path":"%s","hint":"Run: node scripts/codex-distribution.mjs generate"}\n' \
    "$(json_escape "$type")" \
    "$(json_escape "$message")" \
    "$(json_escape "$path")"
  exit 1
}

require_dir() {
  local dir="$1"
  local label="$2"
  local pattern="$3"
  local match
  if [ ! -d "$dir" ]; then
    emit_error "missing_source_dir" "missing ${label} at ${dir}. Run: node scripts/codex-distribution.mjs generate" "$dir"
  fi
  match="$(find "$dir" -maxdepth 1 -type f -name "$pattern" -print -quit 2>/dev/null)"
  if [ -z "$match" ]; then
    emit_error "missing_matching_artifacts" "no ${label} files matching ${pattern} at ${dir}. Run: node scripts/codex-distribution.mjs generate" "$dir"
  fi
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

json_array() {
  local first=1 item
  printf '['
  for item in "$@"; do
    if [ "$first" -eq 0 ]; then printf ','; fi
    first=0
    printf '"%s"' "$(json_escape "$item")"
  done
  printf ']'
}

record_copy() {
  copied+=("$1")
}

record_skip() {
  skipped+=("$1")
}

record_conflict() {
  conflicts+=("$1")
}

record_backup() {
  backups+=("$1")
}

install_one() {
  local src="$1" dest="$2" rel="$3"

  if [ ! -f "$src" ]; then
    emit_error "missing_source_artifact" "missing source artifact ${src}. Run: node scripts/codex-distribution.mjs generate" "$src"
  fi

  if [ -L "$dest" ]; then
    printf 'conflict %s (destination is symlink)\n' "$rel" >&2
    record_conflict "$rel"
    return 0
  fi

  if [ -d "$dest" ]; then
    printf 'conflict %s (destination is directory)\n' "$rel" >&2
    record_conflict "$rel"
    return 0
  fi

  if [ ! -e "$dest" ]; then
    printf 'copy %s\n' "$rel" >&2
    record_copy "$rel"
    if [ "$DRY_RUN" -eq 0 ]; then
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
    fi
    return 0
  fi

  if cmp -s "$src" "$dest"; then
    printf 'skip unchanged %s\n' "$rel" >&2
    record_skip "$rel"
    return 0
  fi

  if [ "$FORCE" -eq 0 ]; then
    printf 'conflict %s\n' "$rel" >&2
    record_conflict "$rel"
    return 0
  fi

  local backup="$BACKUP_ROOT/$rel"
  printf 'backup %s -> %s\n' "$rel" "$backup" >&2
  record_backup "$backup"
  record_copy "$rel"
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$(dirname "$backup")" "$(dirname "$dest")"
    cp "$dest" "$backup"
    cp "$src" "$dest"
  fi
}

sync_dir() {
  local src_dir="$1" dest_dir="$2" rel_prefix="$3" pattern="$4" file base rel
  if [ -L "$dest_dir" ]; then
    printf 'conflict %s (destination directory is symlink)\n' "$rel_prefix" >&2
    record_conflict "$rel_prefix"
    return 0
  fi
  if [ -e "$dest_dir" ] && [ ! -d "$dest_dir" ]; then
    printf 'conflict %s (destination path is not a directory)\n' "$rel_prefix" >&2
    record_conflict "$rel_prefix"
    return 0
  fi
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$dest_dir"
  fi
  for file in "$src_dir"/$pattern; do
    [ -f "$file" ] || continue
    base="$(basename "$file")"
    rel="$rel_prefix/$base"
    install_one "$file" "$dest_dir/$base" "$rel"
  done
}

require_dir "$PROMPT_SRC" "generated Codex prompts" "*.md"
require_dir "$AGENT_SRC" "generated Codex agents" "*.toml"

sync_dir "$PROMPT_SRC" "$CODEX_HOME_DIR/prompts" "prompts" "*.md"
sync_dir "$AGENT_SRC" "$CODEX_HOME_DIR/agents" "agents" "*.toml"

status="ok"
exit_code=0
if [ "${#conflicts[@]}" -gt 0 ]; then
  status="conflict"
  exit_code=2
fi

printf '{'
printf '"status":"%s",' "$status"
printf '"codexHome":"%s",' "$(json_escape "$CODEX_HOME_DIR")"
printf '"dryRun":%s,' "$([ "$DRY_RUN" -eq 1 ] && printf true || printf false)"
printf '"force":%s,' "$([ "$FORCE" -eq 1 ] && printf true || printf false)"
printf '"copied":'; json_array "${copied[@]+"${copied[@]}"}"; printf ','
printf '"skipped":'; json_array "${skipped[@]+"${skipped[@]}"}"; printf ','
printf '"conflicts":'; json_array "${conflicts[@]+"${conflicts[@]}"}"; printf ','
printf '"backups":'; json_array "${backups[@]+"${backups[@]}"}"
printf '}\n'

exit "$exit_code"
