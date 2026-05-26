# Codex Distribution Setup

This guide installs the Agent Skills Codex Distribution from a local checkout.

The Codex Distribution has two parts:

- **Codex Plugin Bundle:** `plugins/agent-skills/`, loaded by Codex through the plugin system.
- **Synced Local Assets:** generated prompts and agent roles copied into `${CODEX_HOME:-~/.codex}`.

Adding the marketplace and plugin bundle alone does not install the local prompts or agent roles. Run the sync step after enabling the plugin bundle.

## Prerequisites

- A local checkout of this repository.
- Codex with local plugin marketplace support.
- Node.js 20 or newer if you need to refresh generated artifacts.

## Install

From the repository root:

```bash
codex plugin marketplace add .
codex plugin add agent-skills@agent-skills
bash scripts/sync-codex-assets.sh
```

The selector `agent-skills@agent-skills` means:

- first `agent-skills`: the plugin name
- second `agent-skills`: the repo-local marketplace name

## Dry Run

Preview local prompt and agent writes without changing Codex home:

```bash
bash scripts/sync-codex-assets.sh --dry-run
```

The script prints human-readable status to stderr and a JSON summary to stdout.

## Conflict Handling

The sync step refuses to overwrite a local Codex prompt or agent role when the destination file differs.

To overwrite conflicts intentionally:

```bash
bash scripts/sync-codex-assets.sh --force
```

When forced, the script backs up each conflicting destination under:

```text
${CODEX_HOME:-~/.codex}/backups/agent-skills/<timestamp>/
```

## Verify

After installation, verify the committed Codex artifacts are current:

```bash
node scripts/codex-distribution.mjs check
```

Verify synced files exist:

```bash
ls "${CODEX_HOME:-$HOME/.codex}/prompts"/agent-skills-*.md
ls "${CODEX_HOME:-$HOME/.codex}/agents"/*.toml
```

Expected prompt names include:

- `agent-skills-spec`
- `agent-skills-plan`
- `agent-skills-build`
- `agent-skills-test`
- `agent-skills-review`
- `agent-skills-code-simplify`
- `agent-skills-ship`

Expected agent role names include:

- `code-reviewer`
- `security-auditor`
- `test-engineer`

## Refresh Generated Artifacts

When `.claude/commands/`, `agents/`, `skills/`, or `hooks/` changes, refresh and check Codex artifacts:

```bash
node scripts/codex-distribution.mjs generate
node scripts/codex-distribution.mjs check
```

Commit the generated Codex artifacts with the Source Asset change.
