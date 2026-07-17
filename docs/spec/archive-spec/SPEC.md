# Spec: Archive agent-skills artifacts by argument

## Status

- Phase: Complete
- Wrapper skill: `archive-spec`

## Objective

Add an explicitly invoked wrapper skill that performs an atomic archive of the root artifacts left by an agent-skills workflow. `$ARGUMENTS` supplies the archive folder name and is normalized to `<slug>`:

```text
SPEC.md                         docs/spec/<slug>/SPEC.md
tasks/            ->           docs/spec/<slug>/tasks/
```

The archive is complete only when both artifacts have moved, affected links resolve, and the resulting Git diff is inspectable. It is a post-workflow action; `/spec`, `/plan`, and `/build` keep their current output paths.

## Tech Stack

- Markdown skill instructions and YAML frontmatter.
- Existing agent-skills structural and behavioral eval infrastructure.
- Git and standard filesystem commands already available to coding agents.
- No new runtime dependency or helper script.

## Commands

```bash
git status --short --branch
git diff --check
git diff --cached --check
node scripts/validate-skills.js
node scripts/validate-commands.js
node scripts/run-evals-test.js
node scripts/run-evals.js --behavioral archive-spec --dry-run
```

Manual QA uses this change's own root `SPEC.md` and `tasks/`, archiving them to `docs/spec/archive-spec/`.

## Project Structure

```text
skills/wrapper/archive-spec/
├── SKILL.md
└── agents/openai.yaml

evals/cases/archive-spec.json
evals/fixtures/archive-spec-*/
scripts/run-evals.js
scripts/run-evals-test.js

SPEC.md                   # Temporary source artifact during development
tasks/                    # Temporary planning artifacts after approval
docs/spec/archive-spec/   # Final self-hosted QA destination
```

The requested surface is a skill, so this change adds no slash-command files.
The new-skill pre-flight follows [`CONTRIBUTING.md`](../../../CONTRIBUTING.md).

## Code Style

Use a human-facing, single-branch description because the skill is user-invoked:

```yaml
---
name: archive-spec
description: Archives root SPEC.md and tasks/ under docs/spec/ using $ARGUMENTS as the folder name. Use after completing an agent-skills workflow.
disable-model-invocation: true
---
```

The body uses **archive transaction** as its leading concept and follows these rules:

- Put the five ordered steps in `SKILL.md`; each ends with a checkable **Complete when** criterion.
- Co-locate collision, missing-source, and deletion handling with the step that detects each condition.
- State each behavioral rule once. Verification refers to the step criteria instead of restating the workflow.
- Keep the workflow in one file and under 100 lines; this linear skill has no branch large enough to justify progressive disclosure.
- Write repository content in English and use lowercase kebab-case names.

## Core Process

### 1. Resolve the archive

- Read `$ARGUMENTS` as the archive folder-name input.
- Without `$ARGUMENTS`, stop and ask for it instead of inferring a second input concept.
- Normalize the name to a safe kebab-case slug. Issue `#67` becomes `issue-67`.
- Set the destination to `docs/spec/<slug>/` and show the resolved source and destination.

**Complete when:** one slug matching `^[a-z0-9]+(?:-[a-z0-9]+)*$` and the exact two source/destination pairs are visible.

### 2. Preflight the whole move

- Confirm root `SPEC.md` and root `tasks/` both exist.
- Confirm the destination does not exist.
- Capture the complete task inventory, Git state, and every repository reference affected by the move.
- Ask for an unoccupied slug when the slug is ambiguous or the destination collides.

**Complete when:** both sources exist, the destination is free, and every source file and affected reference is accounted for.

### 3. Move the artifacts

- Create only the destination parent directories.
- Start a rollback ledger; any later failed completion criterion restores the preflight inventory and Git state.
- Move `SPEC.md` and the complete `tasks/` tree, preserving `tasks/evidence/` and all other contents.

**Complete when:** both root sources are absent, both destination artifacts exist, and the post-move inventory accounts for every preflighted file.

### 4. Repair references

- Repair relative Markdown links changed by the new directory depth.
- Update repository references that still name the old archive artifact paths.
- Check every local Markdown target in the moved artifacts.

**Complete when:** every preflighted reference points to the new location and every local Markdown target resolves.

### 5. Verify and report

- Show the final tree under `docs/spec/<slug>/`.
- Run `git diff --check` and `git status --short`.
- Report moved files, repaired references, and any verification limit.
- Leave commit, push, PR, and unrelated files outside this skill's change set.

**Complete when:** the final tree matches the contract, validation exits successfully, and the report accounts for every changed path.

## Testing Strategy

- `node scripts/validate-skills.js` accepts the skill without a new lint exemption.
- `node scripts/validate-commands.js` remains green because the command surface is unchanged.
- The eval runner accepts `invocation: "explicit"` cases for nested user-invoked wrappers without adding them to the routing corpus.
- The direct-skill eval baseline still has one unrelated failure: `install-codex-assets` has no eval case file.
- Fixture-backed cases cover complete moves, evidence preservation, destination collision, link repair, rollback, and the external Git boundary.
- Self-hosted manual QA applies the skill to this task's own artifacts and verifies the resulting paths and links.

## Boundaries

### Always

- Treat the archive as one atomic operation whose inventory must balance.
- Preserve the complete `tasks/` tree by default.
- Restore the preflight inventory and Git state after any failed transaction.
- Stop at empty or invalid `$ARGUMENTS`, a missing source, or a destination collision and request a valid unoccupied value.
- Limit edits to the moved artifacts and references made stale by their relocation.

### Ask first

- Supply `$ARGUMENTS` when it is empty or choose another value after a destination collision.
- Perform any operation other than a complete archive to an empty destination.

### Never

- Overwrite a destination implicitly.
- Merge, replace, delete, or exclude source artifacts within this skill.
- Commit, push, or open a PR without a separate request.

## Success Criteria

- `skills/wrapper/archive-spec/SKILL.md` and `agents/openai.yaml` are discoverable and valid.
- The skill remains a post-workflow archive, distinct from open proposals that change `/spec` and `/plan` output locations.
- Structural, command, eval-runner, and explicit-wrapper dry-run gates pass; the unrelated direct-skill baseline failure is recorded separately.
- Self-hosted manual QA archives this task to `docs/spec/archive-spec/`, balances the inventory, repairs every affected link, and changes no unrelated path.

## Open Questions

None. The user's request to create the skill approves this contract.
