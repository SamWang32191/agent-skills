# Agent Skills Distribution

This context defines the language for distributing Agent Skills across coding-agent hosts. It keeps packaging terms precise so documentation does not overstate what a host loads natively.

## Language

**Codex Distribution**:
The complete Agent Skills package for Codex, including the plugin bundle and any assets that must be installed into Codex-managed locations. A Codex Distribution may combine native plugin capabilities with synced assets when Codex does not expose a native contribution point.
_Avoid_: Codex plugin, adapter, integration

**Codex Plugin Bundle**:
The nested subset of a Codex Distribution that Codex loads through its plugin system. It is not the right term for prompts or agent roles when those are installed through Codex local configuration instead of loaded from the plugin manifest.
_Avoid_: full plugin, command plugin, prompt plugin

**Synced Local Asset**:
A generated asset that belongs to the Codex Distribution but must be copied into a Codex-managed local location to be discovered. It remains part of the distribution even though Codex does not load it from the plugin bundle.
_Avoid_: plugin asset, native plugin feature

**Source Asset**:
The repository-owned canonical material that generated Codex artifacts are derived from, such as command prompts, personas, skills, or hooks. Source Assets are preserved in their original host-oriented format and are not rewritten in place for Codex.
_Avoid_: template, generated asset

**Generated Codex Artifact**:
A committed Codex-facing file derived from Source Assets. Generated Codex Artifacts are reviewable distribution contents, but their source of truth remains the Source Assets plus the generator rules.
_Avoid_: source file, hand-maintained Codex file, temporary output

**Bundle Mirror**:
A committed copy of plugin-native Source Assets inside the nested Codex Plugin Bundle. Bundle Mirrors exist because Codex installs plugin bundles from a self-contained directory and does not copy symlinked files.
_Avoid_: source directory, symlinked bundle, manual copy

**Prompt Namespace**:
The package-owned prefix used for Codex prompt filenames so generated prompts do not claim short command names owned by a host or user. Prompt Namespaces make the source distribution visible at the invocation point.
_Avoid_: slash command alias, short command, global command name

**Skill Namespace**:
The Codex plugin name prefix used when referencing skills contributed by the Codex Plugin Bundle. For this distribution, the Skill Namespace is `agent-skills` so prompts can refer to skills as `agent-skills:<skill-name>`.
_Avoid_: repo name, marketplace name, display name

**Persona Role Name**:
The stable role identifier shared by a source persona and its generated Codex agent role. Persona Role Names stay unprefixed so orchestration prompts can refer to the same role names across hosts.
_Avoid_: namespaced agent name, generated role alias

**Dual-Host Hook**:
A single hook definition that is valid for both Claude-oriented plugin execution and Codex plugin execution. Dual-Host Hooks use host-specific environment fallbacks instead of maintaining separate hook configuration files.
_Avoid_: Codex-only hook copy, duplicated hook config

**Host-Specific Rewrite**:
A deterministic conversion rule that changes host-only instructions while preserving the Source Asset's workflow intent. Host-Specific Rewrites are part of generation rules, not manual edits to Generated Codex Artifacts.
_Avoid_: manual fork, ad hoc edit, copy rewrite

**Distribution Install**:
The complete setup procedure for a Codex Distribution. In the first Codex version, Distribution Install means enabling the Codex Plugin Bundle and running the explicit sync step for Synced Local Assets.
_Avoid_: plugin install, marketplace install, one-click install

## Example Dialogue

Dev: "Does this Codex plugin provide slash commands?"

Domain expert: "The Codex Distribution provides command-like prompts, but those prompts are Synced Local Assets. The Codex Plugin Bundle does not register native slash commands."

Dev: "So the plugin bundle contains everything?"

Domain expert: "No. The Codex Plugin Bundle contains what Codex can load as a plugin. The Codex Distribution also includes Synced Local Assets generated from Source Assets."

Dev: "Should the sync step generate the Codex prompt files?"

Domain expert: "No. The Codex prompt files are Generated Codex Artifacts committed with the distribution. The sync step installs them and validation prevents them from drifting from the Source Assets."

Dev: "Can the nested plugin bundle symlink to root `skills/`?"

Domain expert: "No. The Codex Plugin Bundle uses Bundle Mirrors so standard plugin installation receives regular files."

Dev: "Can we install `/spec` directly for Codex?"

Domain expert: "No. The Codex Distribution uses a Prompt Namespace so it does not claim host-level short command names."

Dev: "Can the Codex plugin name change per fork?"

Domain expert: "No. The Skill Namespace is part of the prompt-to-skill contract, so the Codex Plugin Bundle keeps the plugin name `agent-skills`."

Dev: "Should Codex rename `code-reviewer` to avoid collisions?"

Domain expert: "No. `code-reviewer` is a Persona Role Name. The sync step protects existing local roles instead of inventing a different role name."

Dev: "Should Codex get its own copy of the hook config?"

Domain expert: "No. This distribution uses Dual-Host Hooks so the behavior stays in one Source Asset."

Dev: "Does installing the plugin complete setup?"

Domain expert: "No. Distribution Install includes both enabling the Codex Plugin Bundle and syncing local assets."

Dev: "Can the generated `/ship` prompt keep Claude Code Agent tool instructions?"

Domain expert: "No. That requires a Host-Specific Rewrite so Codex receives instructions for Codex's agent model while preserving the source workflow."
