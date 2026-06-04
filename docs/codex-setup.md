# Codex Setup

This guide installs Agent Skills as a Codex plugin and then copies optional global assets that Codex App reads from the user's Codex home.

## Requirements

- Node.js is required on macOS, Linux, and Windows.
- Codex plugin installation does not automatically execute repository scripts.
- Codex App prompt files must be real files. Do not use symlinks for `~/.codex/prompts`.

## Install the Plugin

From this GitHub fork:

```bash
codex plugin marketplace add SamWang32191/agent-skills
codex plugin add agent-skills@agent-skills
```

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

## Install Global Codex Assets

Use the `install-codex-assets` skill after the plugin is installed. In Codex, ask:

```text
Use the install-codex-assets skill to install Agent Skills Codex assets.
```

The skill runs its bundled copy-only installer. It copies:

- `agents/*.toml` into `~/.codex/agents/`
- `.claude/commands/*.md` into `~/.codex/prompts/`

On Windows, the targets are under `%USERPROFILE%\.codex\agents` and `%USERPROFILE%\.codex\prompts`.

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
test -f ~/.codex/prompts/spec.md && test ! -L ~/.codex/prompts/spec.md
```

On Windows PowerShell:

```powershell
Test-Path "$HOME\.codex\agents\code-reviewer.toml"
Test-Path "$HOME\.codex\prompts\spec.md"
```

Then restart Codex App or open a new thread so the app refreshes prompts and agents.
