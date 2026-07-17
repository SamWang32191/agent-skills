---
name: archive-spec
description: Archives root SPEC.md and tasks/ under docs/spec/ using $ARGUMENTS as the folder name. Use after completing an agent-skills workflow.
disable-model-invocation: true
---

# Archive Spec Artifacts

## Overview

Perform an **archive transaction** that moves root `SPEC.md` and `tasks/` into
`docs/spec/<slug>/`, deriving the slug from `$ARGUMENTS`, preserving the
complete record, and repairing links.

## When to Use

- After an agent-skills workflow leaves both `SPEC.md` and `tasks/` at the repository root.
- When the user supplies the archive folder name through `$ARGUMENTS`.

This is a post-workflow archive. The `spec`, `plan`, and `build` wrappers keep
their existing output paths.

## Process

### 1. Resolve `$ARGUMENTS`

Use `$ARGUMENTS` as the archive folder name. Ask one focused question when it
is empty. Lowercase it, replace runs outside `[a-z0-9]` with `-`, and trim
separators; `issue #67` becomes `issue-67`. Set the destination to
`docs/spec/<slug>/` and show both mappings.

**Complete when:** the slug matches `^[a-z0-9]+(?:-[a-z0-9]+)*$` and both exact mappings are visible.

### 2. Preflight the archive transaction

Confirm root `SPEC.md` and root `tasks/` both exist, while the destination does
not. Inventory every file under `tasks/`, capture `git status --short`, then
identify every Markdown reference affected by the move. Classify matches so
generic documentation about the wrapper contract is not mistaken for a stale
archive reference.

Stop before mutation when a source is missing or the destination collides. Ask
for an unoccupied slug when the name is ambiguous or already used. Merge,
replacement, deletion, and partial archives are separate operations.

**Complete when:** both sources exist, the destination is free, and the initial inventory, Git state, and affected references are captured.

### 3. Move the complete record

Start a rollback ledger before mutation. Until Step 5 succeeds, record each
move and reference edit; any failed criterion reverses those entries, moves both
artifacts back, removes newly empty directories, and matches the preflight
inventory and Git state.

Create the destination, then move `SPEC.md` and the complete `tasks/` tree into
it. Use `git mv` for tracked sources and `mv` for untracked sources. Preserve
`tasks/evidence/` and every other task artifact.

**Complete when:** both root sources are absent and the destination inventory balances exactly against the preflight inventory.

### 4. Repair affected references

Repair relative Markdown links whose base directory changed and repository
references that point to this archive's old root paths. Resolve every local
Markdown target from the containing file; external URLs and fragment-only links
need no filesystem target check.

**Complete when:** every preflighted affected reference uses the new location and every local target in the moved Markdown resolves.

### 5. Verify and report

Show the final archive tree. Run `git diff --check`, plus
`git diff --cached --check` when the index changed, and
`git status --short --branch`. Report moved files, repaired references, and
verification limits. Leave commit, push, and PR actions for a separate request.

**Complete when:** all prior completion criteria hold and every changed path is accounted for in the report.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "The Issue #67 example deleted evidence." | That deletion was separately requested; an archive preserves the complete record by default. |
| "The destination already exists, so merging is harmless." | This skill only archives to an empty destination; choose another slug or handle the collision separately. |
| "The links look the same after the move." | Relative targets are resolved from a new directory and must be checked there. |

## Red Flags

- Either source moves before the whole archive passes preflight.
- Merge, replacement, deletion, or partial-archive behavior appears in this skill.
- The final inventory loses any task artifact.
- A failed transaction does not restore its preflight inventory and Git state.
- Commit, push, or PR changes appear in the archive operation.

## Verification

- [ ] Every **Complete when** criterion is satisfied.
- [ ] Applicable worktree and index diff checks pass, and Git status contains only accounted-for paths.
