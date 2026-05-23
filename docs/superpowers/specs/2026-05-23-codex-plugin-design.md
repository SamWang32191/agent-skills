# Codex Distribution Design

Date: 2026-05-23

## Context

This repository already contains the source materials for an agent-skills distribution:

- `.claude/commands/*.md` defines the user-facing command prompts.
- `agents/*.md` defines persona-style subagents for review, security, and testing.
- `hooks/hooks.json` and `hooks/*.sh` define the existing hook behavior.
- `skills/*/SKILL.md` defines the workflows that the prompts invoke.

The target is a Codex Distribution that makes these capabilities available to Codex without patching Codex core. The approved direction is `Nested Plugin Bundle + Sync`: the repository root is the distribution root, `plugins/agent-skills/` is the Codex Plugin Bundle, and a sync script installs generated Codex-only Synced Local Assets into the Codex locations that are currently loaded at runtime.

## Codex Facts

The current Codex source supports plugin manifests at `.codex-plugin/plugin.json`. Plugin manifests support `skills`, `mcpServers`, `apps`, `hooks`, and `interface`. Hook discovery also loads the default `hooks/hooks.json` file when no manifest hook path overrides it, but this distribution should explicitly declare plugin-native paths in the manifest.

Codex plugin skills are referenced with the plugin name as a prefix, for example `agent-skills:spec-driven-development`. The Codex Plugin Bundle must therefore use `agent-skills` as its manifest `name` so generated prompts can invoke the existing skills without rewriting their namespace.

Codex agent roles are TOML configurations. A role file can contain `name`, `description`, `nickname_candidates`, and config values such as `developer_instructions`, `model`, `model_reasoning_effort`, `service_tier`, or `sandbox_mode`. The minimum useful generated role for this repo is `name`, `description`, and `developer_instructions`.

Codex local prompts are known to work from `~/.codex/prompts/*.md` with YAML frontmatter such as `description` and optional `argument-hint`, followed by the prompt body. The plugin manifest `interface.defaultPrompt` is not a replacement for these files because it is capped at three short starter prompts.

Codex slash commands remain core/TUI behavior. This design does not try to register new native slash commands through the plugin manifest. The command-like UX comes from synced local prompts.

## Goals

- Make this repository installable as a Codex Distribution with a nested `plugins/agent-skills/.codex-plugin/plugin.json` manifest for the Codex Plugin Bundle.
- Generate and commit Codex prompt files from `.claude/commands/*.md` using the working `~/.codex/prompts` format.
- Generate and commit Codex agent TOML files from `agents/*.md` while preserving each persona's role, description, and instructions.
- Adapt existing hooks so the same hook package works from Codex plugin execution as well as the existing Claude-oriented layout.
- Provide a repo-local sync script that installs prompts and agents into the Codex home directory without requiring Codex source changes.

## Non-Goals

- Do not patch `~/code/github.com/openai/codex`.
- Do not add native Codex slash-command variants.
- Do not replace or rewrite the existing Claude command, agent, skill, or hook sources.
- Do not add a personal marketplace entry unless requested separately.
- Do not claim marketplace or plugin installation alone fully enables prompts and agent roles in the first version.
- Do not make the sync script silently overwrite user-modified Codex files.

## Architecture

The repository root is the distribution root. The Codex Plugin Bundle lives under `plugins/agent-skills/` so a repo-local marketplace can reference it with a valid non-root local source path. Codex local marketplace paths cannot point at the marketplace root itself.

The distribution adds four Codex-facing pieces:

- `plugins/agent-skills/.codex-plugin/plugin.json`: identifies the Codex Plugin Bundle with `name: "agent-skills"` and `version: "0.1.0"`, declares metadata, and explicitly points to bundle-local `./skills` and `./hooks/hooks.json`.
- `plugins/agent-skills/skills/` and `plugins/agent-skills/hooks/`: committed Bundle Mirrors of plugin-native Source Assets.
- `.agents/plugins/marketplace.json`: repo-local marketplace named `agent-skills` with an `agent-skills` plugin entry that points to `./plugins/agent-skills`.
- `codex/prompts/*.md`: committed Generated Codex Artifacts derived from `.claude/commands/*.md`.
- `codex/agents/*.toml`: committed Generated Codex Artifacts derived from `agents/*.md`.
- `scripts/sync-codex-assets.sh`: installs generated prompts to `${CODEX_HOME:-~/.codex}/prompts` and generated agents to `${CODEX_HOME:-~/.codex}/agents`.
- `docs/codex-setup.md`: Codex-specific Distribution Install instructions, linked from the README Codex section.

The sync script is part of the supported install path because current Codex plugin manifests do not provide a native prompt or agent-role contribution point equivalent to `~/.codex/prompts` and `~/.codex/agents`.

The first version supports a local/development Distribution Install: add this repository as a local marketplace, install the `agent-skills` plugin from that marketplace, then run the explicit sync step for Synced Local Assets. Marketplace installation alone must not be described as a one-step complete setup while prompts and agent roles still require syncing.

The local install selector is `agent-skills@agent-skills`: the first `agent-skills` is the plugin name, and the second `agent-skills` is the repo-local marketplace name.

The generation and validation tooling should follow the repository's existing lightweight script style. Use Node.js built-ins for deterministic generation/checking of Generated Codex Artifacts, and use Bash for the sync/install script. Do not introduce a package manager or third-party parser dependency in the first version.

The nested Codex Plugin Bundle must be self-contained with regular files. Do not use symlinks from `plugins/agent-skills/` back to root `skills/` or `hooks/`, because Codex plugin installation copies regular files/directories and does not preserve symlinked bundle contents. Bundle Mirrors should be generated or refreshed by the same deterministic tooling and committed to the repository.

## Prompt Conversion

Each `.claude/commands/<name>.md` file becomes `codex/prompts/agent-skills-<name>.md`.

The generated file keeps the source `description` frontmatter and adds a command-specific `argument-hint` from generator rules when the command naturally accepts a target, scope, task, or spec path. Do not emit a generic `optional arguments` hint. The body is derived from the source command with deterministic Host-Specific Rewrites where Claude-only wording, tools, or platform constraints would confuse Codex.

The `agent-skills-` filename prefix is the Prompt Namespace. It avoids collisions with Codex built-ins and with other user prompts. In Codex prompt UX this gives a stable namespace for this package instead of claiming short global names such as `spec`, `plan`, or `ship`. The distribution should not generate short-name prompt aliases in the first version.

The generated prompt body may keep skill references such as `agent-skills:spec-driven-development` because the Codex Plugin Bundle's Skill Namespace is fixed to `agent-skills`.

`ship.md` needs explicit rewrite coverage in the first version because its source command contains Claude Code Agent tool and Agent Teams instructions. The generated Codex prompt should preserve the fan-out and merge workflow while describing Codex's `spawn_agent`/`wait_agent` execution model instead of Claude-only agent mechanics.

Generated prompt files are committed to the repository. A validation step should fail when the committed prompt output no longer matches the source command plus the generator rules.

## Agent Conversion

Each `agents/<name>.md` source file becomes `codex/agents/<name>.toml`.

The generated TOML includes:

```toml
name = "<source frontmatter name>"
description = "<source frontmatter description>"
developer_instructions = """
<source markdown body>
"""
```

The converter ignores Claude-only or platform-specific frontmatter fields that Codex agent roles do not use. If future agent files add compatible fields such as reasoning effort, the converter can map them explicitly, but the first version should preserve Codex defaults for model and service tier.

Generated agent TOML files are committed to the repository. A validation step should fail when the committed role output no longer matches the source persona plus the generator rules.

Generated agent roles preserve the source Persona Role Name, such as `code-reviewer`, `security-auditor`, and `test-engineer`. They are not prefixed in the first version. Sync conflict protection is responsible for preventing accidental overwrite of user-defined local roles with the same names.

Agent body conversion should preserve each persona's role, rules, output format, and "personas do not invoke other personas" boundary. The Composition block should receive a Host-Specific Rewrite so Codex agent roles reference the Codex Distribution's namespaced prompts and Codex orchestration model rather than Claude-facing slash commands or Agent tool wording.

## Hook Adaptation

The existing `hooks/hooks.json` uses `CLAUDE_PLUGIN_ROOT` in command strings. For Codex plugin execution, hook commands should resolve the plugin root from `CODEX_PLUGIN_ROOT` first and fall back to `CLAUDE_PLUGIN_ROOT`.

`hooks/hooks.json` remains the single hook Source Asset. The distribution should not create a Codex-only duplicate hook config in the first version.

The intended command shape is:

```json
"command": "bash ${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/hooks/session-start.sh"
```

The shell scripts remain in `hooks/` and should keep their current behavior. If a hook script needs to emit Codex-specific structured output later, that should be a focused follow-up change with hook-runtime tests.

## Sync Behavior

The sync script should:

- Resolve the repository root from the script location.
- Use `${CODEX_HOME}` when set, otherwise default to `~/.codex`.
- Create `prompts/` and `agents/` inside Codex home when missing.
- Copy generated prompt files and generated agent TOML files.
- Refuse to overwrite a destination file if it differs, unless the user passes an explicit force flag.
- Treat an existing different local agent role as a conflict rather than silently replacing a user's custom persona.
- When force is explicitly requested, back up each conflicting destination file before overwriting it. The default backup location should be under the Codex home in a distribution-specific backup directory, preserving enough relative path information to restore prompts and agents.
- Support a dry-run mode so users can inspect the destination changes.
- Print human-readable status to stderr and a small JSON summary to stdout for automation, including conflicts and backup paths when present.

## Error Handling

The converter should fail fast when a source command or agent has invalid frontmatter, missing required fields, or a derived output name collision.

The sync script should treat missing committed Generated Codex Artifacts as an actionable packaging error. It should not create partial or empty placeholder files.

The plugin manifest should stay minimal and avoid referencing non-existent paths. It should use `name: "agent-skills"` and initial `version: "0.1.0"`, and explicitly declare bundle-local `skills: "./skills"` and `hooks: "./hooks/hooks.json"`. The first version should not use `interface.defaultPrompt`; command-like entry points come only from synced local prompts.

## Testing

Verification should cover:

- Generated prompt frontmatter parses and every `.claude/commands/*.md` source has one generated prompt.
- Generated prompt `argument-hint` values are command-specific when present and never the generic `optional arguments` placeholder.
- Host-Specific Rewrites remove Claude-only execution instructions from generated Codex prompts where applicable.
- Generated agent TOML parses and every `agents/*.md` source, excluding `README.md`, has one generated role file.
- Committed Generated Codex Artifacts are up to date with their Source Assets and generator rules.
- Committed Bundle Mirrors are up to date with root `skills/` and `hooks/` Source Assets.
- Generation and validation scripts run with only built-in Node.js modules.
- Generated agent roles do not contain stale Claude-facing invocation instructions.
- Hook JSON parses after the environment-variable fallback change.
- Hook command path resolution works when only `CODEX_PLUGIN_ROOT` is set and when only `CLAUDE_PLUGIN_ROOT` is set.
- Codex source-backed checks are the blocking authority for manifest, hook, prompt, and agent compatibility.
- The plugin-creator validator may be run as an advisory check, but it must not block behavior that the checked Codex source supports.
- The sync script dry-run reports the expected prompts and agents without writing files.
- The sync script force path backs up conflicting files before overwriting them.
- Codex setup documentation describes marketplace add, plugin add, sync, and verification in the correct order.

## Success Criteria

- The repository has a valid `plugins/agent-skills/.codex-plugin/plugin.json` for the Codex Plugin Bundle.
- The repository has a valid repo-local `.agents/plugins/marketplace.json` pointing to `./plugins/agent-skills`.
- The repo-local marketplace name is `agent-skills`, so documented local install commands use `agent-skills@agent-skills`.
- The Codex Plugin Bundle manifest name is `agent-skills`.
- The Codex Plugin Bundle manifest version is `0.1.0`.
- Codex prompts generated from `.claude/commands/` can be installed into `~/.codex/prompts`.
- Codex agent TOML generated from `agents/` can be installed into `~/.codex/agents`.
- Existing hook behavior is preserved while becoming usable from Codex plugin execution.
- The documented install flow requires both plugin enablement and explicit local-asset sync.
- README links to `docs/codex-setup.md` from the Codex section.
- No Codex source patch is required.
- No implementation depends on undocumented native plugin support for prompt or agent-role registration.
