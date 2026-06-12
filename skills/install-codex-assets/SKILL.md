---
name: install-codex-assets
description: Install Agent Skills assets for Codex App. Use when installing the Agent Skills plugin for the first time or updating the plugin in Codex.
---

# Install Codex Assets

## Overview

Install this repository's Codex assets into the user's Codex home directory. The bundled installer copies files only; it does not create symlinks because Codex App does not load symlinked prompt files reliably.

## When to Use

Use this skill when:

- The user installed the Agent Skills Codex plugin and wants Codex App commands or agent personas to appear.
- `agents/*.toml` must be copied into `~/.codex/agents`.
- `.claude/commands/*.md` must be copied into `~/.codex/prompts`.
- The user wants a macOS, Linux, or Windows-compatible Codex asset install flow.

## Workflow

1. Resolve the bundled script path relative to this `SKILL.md`:

   ```bash
   node skills/install-codex-assets/scripts/install-codex-assets.js --dry-run
   ```

   If running from an installed plugin cache, run the same script from that installed skill directory.

2. Confirm Node.js is available:

   ```bash
   node --version
   ```

3. Run a dry run first:

   ```bash
   node skills/install-codex-assets/scripts/install-codex-assets.js --dry-run
   ```

4. If the dry run reports no conflicts, run the installer:

   ```bash
   node skills/install-codex-assets/scripts/install-codex-assets.js
   ```

5. If existing targets differ and the user agrees to replace them, run:

   ```bash
   node skills/install-codex-assets/scripts/install-codex-assets.js --force
   ```

6. If the repository root cannot be inferred, pass it explicitly:

   ```bash
   node skills/install-codex-assets/scripts/install-codex-assets.js --source-root /path/to/agent-skills
   ```

7. Request shell escalation before writing to the user's Codex home. Targets are:
   - macOS/Linux: `~/.codex/agents` and `~/.codex/prompts`
   - Windows: `%USERPROFILE%\.codex\agents` and `%USERPROFILE%\.codex\prompts`

8. Report the JSON result and ask the user to restart Codex App or open a new thread.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Symlinks are simpler." | Codex App prompt discovery does not reliably load symlinked prompt files. Copy files. |
| "Plugin installation should run this automatically." | Codex plugin installation does not execute repository scripts. The asset install is an explicit follow-up step. |
| "Conflicts can be overwritten silently." | Existing user files may be intentional. Use `--force` only after user approval. |

## Red Flags

- The installer creates symlinks.
- The installer reads prompts from `commands/` instead of `.claude/commands/`.
- The installer overwrites different existing files without `--force`.
- The response says commands are installed before checking `~/.codex/prompts`.

## Verification

After installation:

```bash
node skills/install-codex-assets/scripts/install-codex-assets.js --dry-run
```

The dry run should report `status: "success"` and `action: "unchanged"` for all installed assets.

Also verify the targets are real files, not symlinks:

```bash
test -f ~/.codex/agents/code-reviewer.toml && test ! -L ~/.codex/agents/code-reviewer.toml
test -f ~/.codex/prompts/spec.md && test ! -L ~/.codex/prompts/spec.md
```
