# Archive Spec implementation plan

Spec: [`SPEC.md`](../SPEC.md)

## Task 1: Add the wrapper surface

Create `skills/wrapper/archive-spec/SKILL.md` and `agents/openai.yaml` with the archive transaction, explicit invocation policy, and checkable completion criteria.

Acceptance:

- The skill resolves a safe slug from `$ARGUMENTS` and preflights both root artifacts before moving either.
- The complete `tasks/` tree is preserved without merge, replacement, deletion, or exclusion branches.
- Destination collisions and missing inputs stop before mutation.
- Any failure after mutation restores the preflight inventory and Git state.
- Commit, push, and PR actions stay outside the skill.

Verify: structural validators and eval-runner unit tests exit successfully.

## Task 2: Exercise the behavior

Add explicit-wrapper execution fixtures for success, collision, and rollback, then use the completed skill to archive this task's own `SPEC.md` and `tasks/` into `docs/spec/archive-spec/`.

Acceptance:

- Issue `#67` resolves to `issue-67` in the isolated success scenario.
- Evidence survives the move and local Markdown links resolve.
- A pre-existing destination leaves both root artifacts unchanged.
- A failed link-verification transaction restores the original inventory and Git state.
- The self-hosted archive leaves no root `SPEC.md` or `tasks/` and changes no unrelated path.

Verify: fixture schema, runner tests, dry-run, inventory comparisons, local-link checks, and Git diff/status checks.

## Checkpoint

Review the final diff only after both tasks pass. No commit or push is part of this plan.
