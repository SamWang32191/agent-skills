---
description: "Run the pre-launch checklist via parallel fan-out to specialist personas, then synthesize a go/no-go decision"
argument-hint: "release scope or diff target"
---

Invoke the agent-skills:shipping-and-launch skill.

`agent-skills-ship` is a fan-out orchestrator. It runs three specialist Codex agent roles in parallel against the current change, then merges their reports into a single go/no-go decision with a rollback plan. The personas operate independently: no shared mutable state, no ordering, and no persona-to-persona delegation.

## Phase A — Parallel fan-out

Start all three `spawn_agent` calls before waiting for results:

1. `code-reviewer` — Run a five-axis review (correctness, readability, architecture, security, performance) on the staged changes or recent commits. Output the standard review template.
2. `security-auditor` — Run a vulnerability and threat-model pass. Check OWASP Top 10, secrets handling, auth/authz, dependency CVEs. Output the standard audit report.
3. `test-engineer` — Analyze test coverage for the change. Identify gaps in happy path, edge cases, error paths, and concurrency scenarios. Output the standard coverage analysis.

Each spawned task prompt must include the relevant diff or scope, the persona role name, and the required output format. Keep the fan-out flat: personas do not call other personas.

## Phase B — Wait loop

After spawning, use `wait_agent` to watch mailbox updates. A `wait_agent` call only reports that some mailbox activity occurred; it does not prove the target agent finished.

Continue waiting until all three target agents return final-status notifications. If the update is from another live agent, handle it only if useful, then keep waiting for these three reports. Do not synthesize a ship decision from partial reports unless the user explicitly approves proceeding without the missing report after being told the exact elapsed wait time.

## Phase C — Merge in main context

Once all three reports are available, the main agent synthesizes them:

1. **Code Quality** — Aggregate Critical/Important findings from `code-reviewer` and any failing tests, lint, or build output. Resolve duplicates between reviewers.
2. **Security** — Promote any Critical/High `security-auditor` findings to launch blockers. Cross-reference with `code-reviewer`'s security axis.
3. **Performance** — Pull from `code-reviewer`'s performance axis; cross-check Core Web Vitals if applicable.
4. **Accessibility** — Verify keyboard navigation, screen reader support, and contrast directly when the change has UI impact.
5. **Infrastructure** — Verify environment variables, migrations, monitoring, and feature flags directly.
6. **Documentation** — Verify README, ADRs, changelog, and setup docs directly.

## Phase D — Decision and rollback

Produce a single output:

```markdown
## Ship Decision: GO | NO-GO

### Blockers (must fix before ship)
- [Source persona: Critical finding + file:line]

### Recommended fixes (should fix before ship)
- [Source persona: Important finding + file:line]

### Acknowledged risks (shipping anyway)
- [Risk + mitigation]

### Rollback plan
- Trigger conditions: [what signals would prompt rollback]
- Rollback procedure: [exact steps]
- Recovery time objective: [target]

### Specialist reports (full)
- [code-reviewer report]
- [security-auditor report]
- [test-engineer report]
```

## Rules

1. Start the three Phase A agents before the first wait.
2. Personas do not call each other. The main agent merges in Phase C.
3. The rollback plan is mandatory before any GO decision.
4. If any persona returns a Critical finding, the default verdict is NO-GO unless the user explicitly accepts the risk.
5. Skip fan-out only if all of these are true: the change touches 2 files or fewer, the diff is under 50 lines, and it does not touch auth, payments, data access, or config/env. Otherwise, default to fan-out.
