# Using agent-skills with Codex

This repository is a Codex plugin. Codex reads the root-level `skills/` directory directly through `.codex-plugin/plugin.json`, while optional Codex App agent personas can be copied into the user's Codex home.

## Requirements

- Node.js is required on macOS, Linux, and Windows.
- Codex CLI v0.122 or later is required for `codex plugin marketplace add`.
- Codex plugin installation does not automatically execute repository scripts.

## Install

From this GitHub fork:

```bash
codex plugin marketplace add SamWang32191/agent-skills
codex plugin add agent-skills@agent-skills
```

The first command configures this repository as a marketplace source. The second command installs the `agent-skills` plugin from that marketplace snapshot.

To test a branch before merging it into the default branch:

```bash
codex plugin marketplace add SamWang32191/agent-skills --ref <branch-name>
codex plugin add agent-skills@agent-skills
```

To use a local checkout during development:

```bash
codex plugin marketplace add .
codex plugin add agent-skills@agent-skills
```

After updating a configured Git marketplace snapshot:

```bash
codex plugin marketplace upgrade agent-skills
codex plugin add agent-skills@agent-skills
```

Restart Codex App or open a new thread after plugin installation.

## Usage

After install, invoke a skill in Codex chat with `@` (for example, `@spec-driven-development`) or describe the task and let Codex pick the matching skill.

## Install Global Codex Assets

Use the `install-codex-assets` skill after the plugin is installed. In Codex, ask:

```text
Use the install-codex-assets skill to install Agent Skills Codex assets.
```

The skill runs its bundled copy-only installer. It copies:

- `agents/*.toml` into `~/.codex/agents/`

On Windows, the target is `%USERPROFILE%\.codex\agents`.

## Manual Install From a Checkout

From the repository root:

```bash
node skills/install-codex-assets/scripts/install-codex-assets.js --dry-run
node skills/install-codex-assets/scripts/install-codex-assets.js
```

If existing target files differ and you intentionally want to replace them:

```bash
node skills/install-codex-assets/scripts/install-codex-assets.js --force
```

If the script cannot infer the repository root, pass it explicitly:

```bash
node skills/install-codex-assets/scripts/install-codex-assets.js --source-root /path/to/agent-skills
```

## Verify

On macOS or Linux:

```bash
test -f ~/.codex/agents/code-reviewer.toml && test ! -L ~/.codex/agents/code-reviewer.toml
```

On Windows PowerShell:

```powershell
Test-Path "$HOME\.codex\agents\code-reviewer.toml"
```

Then restart Codex App or open a new thread so the app refreshes agents.

## How It Works

- `.codex-plugin/plugin.json` points `skills` at `./skills/` and declares an empty Codex hook config so Codex does not auto-load Claude-oriented hooks from `hooks/hooks.json`.
- `.agents/plugins/marketplace.json` declares the repository root (`./`) as the plugin source.
- `skills/<name>/SKILL.md` is shared by Codex and Claude Code.
