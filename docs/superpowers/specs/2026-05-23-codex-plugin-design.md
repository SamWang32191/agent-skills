# Codex Plugin Design

Date: 2026-05-23

## Context

This repository already contains the source materials for an agent-skills distribution:

- `.claude/commands/*.md` defines the user-facing command prompts.
- `agents/*.md` defines persona-style subagents for review, security, and testing.
- `hooks/hooks.json` and `hooks/*.sh` define the existing hook behavior.
- `skills/*/SKILL.md` defines the workflows that the prompts invoke.

The target is a Codex plugin that makes these capabilities available to Codex without patching Codex core. The approved direction is `Plugin + Sync`: the repository root becomes the plugin root, and a sync script installs generated Codex-only assets into the Codex locations that are currently loaded at runtime.

## Codex Facts

The current Codex source supports plugin manifests at `.codex-plugin/plugin.json`. Plugin manifests support `skills`, `mcpServers`, `apps`, `hooks`, and `interface`. Hook discovery also loads the default `hooks/hooks.json` file when no manifest hook path overrides it.

Codex agent roles are TOML configurations. A role file can contain `name`, `description`, `nickname_candidates`, and config values such as `developer_instructions`, `model`, `model_reasoning_effort`, `service_tier`, or `sandbox_mode`. The minimum useful generated role for this repo is `name`, `description`, and `developer_instructions`.

Codex local prompts are known to work from `~/.codex/prompts/*.md` with YAML frontmatter such as `description` and optional `argument-hint`, followed by the prompt body. The plugin manifest `interface.defaultPrompt` is not a replacement for these files because it is capped at three short starter prompts.

Codex slash commands remain core/TUI behavior. This design does not try to register new native slash commands through the plugin manifest. The command-like UX comes from synced local prompts.

## Goals

- Make this repository installable as a Codex plugin using a `.codex-plugin/plugin.json` manifest at the repository root.
- Generate Codex prompt files from `.claude/commands/*.md` using the working `~/.codex/prompts` format.
- Generate Codex agent TOML files from `agents/*.md` while preserving each persona's role, description, and instructions.
- Adapt existing hooks so the same hook package works from Codex plugin execution as well as the existing Claude-oriented layout.
- Provide a repo-local sync script that installs prompts and agents into the Codex home directory without requiring Codex source changes.

## Non-Goals

- Do not patch `~/code/github.com/openai/codex`.
- Do not add native Codex slash-command variants.
- Do not replace or rewrite the existing Claude command, agent, skill, or hook sources.
- Do not add a personal marketplace entry unless requested separately.
- Do not make the sync script silently overwrite user-modified Codex files.

## Architecture

The repository root is the plugin root. This avoids duplicating `skills/` and `hooks/`, which are already in Codex plugin loader conventions.

The plugin package adds four Codex-facing pieces:

- `.codex-plugin/plugin.json`: identifies the plugin, declares metadata, and relies on default plugin paths for `skills/` and `hooks/hooks.json`.
- `prompts/*.md`: generated Codex prompt files derived from `.claude/commands/*.md`.
- `.codex-plugin/agents/*.toml`: generated Codex agent role files derived from `agents/*.md`.
- `scripts/sync-codex-plugin.sh`: installs generated prompts to `${CODEX_HOME:-~/.codex}/prompts` and generated agents to `${CODEX_HOME:-~/.codex}/agents`.

The sync script is part of the supported install path because current Codex plugin manifests do not provide a native prompt or agent-role contribution point equivalent to `~/.codex/prompts` and `~/.codex/agents`.

## Prompt Conversion

Each `.claude/commands/<name>.md` file becomes `prompts/agent-skills-<name>.md`.

The generated file keeps the source `description` frontmatter and adds a conservative `argument-hint: optional arguments` when no better command-specific hint is available. The body is copied from the source command and lightly normalized only where wording is Claude-specific and would confuse Codex.

The `agent-skills-` filename prefix avoids collisions with Codex built-ins and with other user prompts. In Codex prompt UX this gives a stable namespace for this package instead of claiming short global names such as `spec`, `plan`, or `ship`.

## Agent Conversion

Each `agents/<name>.md` source file becomes `.codex-plugin/agents/<name>.toml`.

The generated TOML includes:

```toml
name = "<source frontmatter name>"
description = "<source frontmatter description>"
developer_instructions = """
<source markdown body>
"""
```

The converter ignores Claude-only or platform-specific frontmatter fields that Codex agent roles do not use. If future agent files add compatible fields such as reasoning effort, the converter can map them explicitly, but the first version should preserve Codex defaults for model and service tier.

## Hook Adaptation

The existing `hooks/hooks.json` uses `CLAUDE_PLUGIN_ROOT` in command strings. For Codex plugin execution, hook commands should resolve the plugin root from `CODEX_PLUGIN_ROOT` first and fall back to `CLAUDE_PLUGIN_ROOT`.

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
- Support a dry-run mode so users can inspect the destination changes.
- Print human-readable status to stderr and a small JSON summary to stdout for automation.

## Error Handling

The converter should fail fast when a source command or agent has invalid frontmatter, missing required fields, or a derived output name collision.

The sync script should treat missing generated assets as an actionable error and tell the user to run the generation step first. It should not create partial or empty placeholder files.

The plugin manifest should stay minimal and avoid referencing non-existent paths. Optional interface starter prompts may be included only if they fit Codex's three-prompt, 128-character constraints.

## Testing

Verification should cover:

- Generated prompt frontmatter parses and every `.claude/commands/*.md` source has one generated prompt.
- Generated agent TOML parses and every `agents/*.md` source, excluding `README.md`, has one generated role file.
- Hook JSON parses after the environment-variable fallback change.
- The plugin manifest validates against the current plugin-creator validator where applicable, with Codex source behavior used as the final authority for hook support.
- The sync script dry-run reports the expected prompts and agents without writing files.

## Success Criteria

- The repository has a valid `.codex-plugin/plugin.json`.
- Codex prompts generated from `.claude/commands/` can be installed into `~/.codex/prompts`.
- Codex agent TOML generated from `agents/` can be installed into `~/.codex/agents`.
- Existing hook behavior is preserved while becoming usable from Codex plugin execution.
- No Codex source patch is required.
- No implementation depends on undocumented native plugin support for prompt or agent-role registration.
