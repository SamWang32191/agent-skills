# Codex Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first Codex Distribution for Agent Skills using a nested Codex Plugin Bundle plus explicit sync for Codex prompts and agent roles.

**Architecture:** The repository root remains the distribution root. `plugins/agent-skills/` becomes the self-contained Codex Plugin Bundle with regular-file Bundle Mirrors for `skills/` and `hooks/`, while `codex/prompts/` and `codex/agents/` hold committed Generated Codex Artifacts installed by `scripts/sync-codex-assets.sh`.

**Tech Stack:** Node.js 20 built-ins (`node:test`, `node:fs`, `node:path`, `node:assert`) for generation and validation; Bash 3.2-compatible shell for local asset sync; existing Markdown, JSON, and TOML file formats.

---

## File Structure

### New Files

- `scripts/codex-distribution.mjs`
  - Single deterministic generator/checker for Codex-facing artifacts.
  - Reads Source Assets from `.claude/commands/*.md`, `agents/*.md`, `skills/`, and `hooks/`.
  - Writes committed Generated Codex Artifacts under `codex/` and Bundle Mirrors under `plugins/agent-skills/`.
  - Exposes small pure functions for tests: frontmatter parsing, prompt rendering, agent rendering, TOML subset parsing, expected artifact collection.

- `scripts/codex-distribution-test.mjs`
  - Node built-in test suite for prompt conversion, agent conversion, manifest/marketplace output, Bundle Mirror output, and checker drift detection.

- `scripts/sync-codex-assets.sh`
  - Installs committed `codex/prompts/*.md` and `codex/agents/*.toml` into `${CODEX_HOME:-~/.codex}`.
  - Refuses conflicting overwrites by default.
  - Supports `--dry-run` and `--force`; force backs up conflicts under Codex home before overwrite.
  - Writes human status to stderr and JSON summary to stdout.

- `scripts/sync-codex-assets-test.sh`
  - Bash integration tests for dry-run, conflict refusal, force backup, and generated artifact presence checks.

- `.agents/plugins/marketplace.json`
  - Repo-local Codex marketplace named `agent-skills`.
  - Points plugin entry `agent-skills` at `./plugins/agent-skills`.

- `plugins/agent-skills/.codex-plugin/plugin.json`
  - Minimal Codex Plugin Bundle manifest with `name = agent-skills`, version `0.1.0`, bundle-local `skills`, and bundle-local `hooks`.

- `plugins/agent-skills/skills/**`
  - Generated Bundle Mirror of root `skills/`.

- `plugins/agent-skills/hooks/**`
  - Generated Bundle Mirror of root `hooks/`.

- `codex/prompts/agent-skills-build.md`
- `codex/prompts/agent-skills-code-simplify.md`
- `codex/prompts/agent-skills-plan.md`
- `codex/prompts/agent-skills-review.md`
- `codex/prompts/agent-skills-ship.md`
- `codex/prompts/agent-skills-spec.md`
- `codex/prompts/agent-skills-test.md`
  - Generated Codex prompts derived from `.claude/commands/*.md`.
  - Use the Prompt Namespace `agent-skills-`.

- `codex/agents/code-reviewer.toml`
- `codex/agents/security-auditor.toml`
- `codex/agents/test-engineer.toml`
  - Generated Codex agent roles derived from `agents/*.md`, excluding `agents/README.md`.

- `docs/codex-setup.md`
  - Codex-specific Distribution Install instructions: add local marketplace, install plugin, sync Synced Local Assets, verify prompts/agents.

### Modified Files

- `hooks/hooks.json:1`
  - Change command path resolution to prefer `CODEX_PLUGIN_ROOT` and fall back to `CLAUDE_PLUGIN_ROOT`.

- `hooks/session-start-test.sh:1`
  - Add JSON-level assertion that `hooks/hooks.json` uses the exact dual-host fallback command.

- `.github/workflows/test-plugin-install.yml:1`
  - Add Codex Distribution test/check steps without weakening the existing Claude plugin validation.

- `README.md:25`
  - Add Codex Quick Start details and link to `docs/codex-setup.md`.

### Generated Directories Owned by the Generator

The generator owns these directories. It may delete and recreate them in generation mode to remove stale generated files:

- `codex/prompts/`
- `codex/agents/`
- `plugins/agent-skills/skills/`
- `plugins/agent-skills/hooks/`

No other directory is generator-owned.

---

### Task 1: Add Codex Generator Tests

**Files:**
- Create: `scripts/codex-distribution-test.mjs`
- Later implementation target: `scripts/codex-distribution.mjs`

- [ ] **Step 1: Write the failing generator test suite**

Create `scripts/codex-distribution-test.mjs` with this complete content:

```js
#!/usr/bin/env node

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  buildExpectedArtifacts,
  parseFrontmatter,
  parseGeneratedAgentToml,
  renderAgentRole,
  renderPrompt,
  validateGeneratedArtifacts,
} from './codex-distribution.mjs';

const repoRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');

test('parseFrontmatter reads required scalar fields and body', () => {
  const source = [
    '---',
    'description: Example command',
    'name: example',
    '---',
    '',
    'Body text',
    '',
  ].join('\n');

  const parsed = parseFrontmatter(source, 'example.md');
  assert.deepEqual(parsed.frontmatter, {
    description: 'Example command',
    name: 'example',
  });
  assert.equal(parsed.body, 'Body text\n');
});

test('parseFrontmatter fails when the opening block is missing', () => {
  assert.throws(
    () => parseFrontmatter('description: missing delimiters\n', 'broken.md'),
    /broken\.md: missing YAML frontmatter/,
  );
});

test('renderPrompt creates a namespaced Codex prompt with a command-specific argument hint', () => {
  const source = [
    '---',
    'description: Break work into small verifiable tasks with acceptance criteria and dependency ordering',
    '---',
    '',
    'Invoke the agent-skills:planning-and-task-breakdown skill.',
    '',
    'Read the existing spec (SPEC.md or equivalent) and the relevant codebase sections. Then:',
    '',
    '1. Enter plan mode — read only, no code changes',
    '2. Identify the dependency graph between components',
    '',
  ].join('\n');

  const rendered = renderPrompt('.claude/commands/plan.md', source);
  assert.equal(rendered.relativePath, 'codex/prompts/agent-skills-plan.md');
  assert.match(rendered.content, /^---\ndescription: "Break work into small verifiable tasks/m);
  assert.match(rendered.content, /^argument-hint: "spec path"$/m);
  assert.match(rendered.content, /Invoke the agent-skills:planning-and-task-breakdown skill\./);
  assert.match(rendered.content, /Work read-only while planning/);
  assert.doesNotMatch(rendered.content, /Enter plan mode/);
});

test('renderPrompt rewrites ship orchestration to Codex spawn_agent and wait_agent semantics', () => {
  const source = fs.readFileSync(path.join(repoRoot, '.claude/commands/ship.md'), 'utf8');
  const rendered = renderPrompt('.claude/commands/ship.md', source);

  assert.equal(rendered.relativePath, 'codex/prompts/agent-skills-ship.md');
  assert.match(rendered.content, /spawn_agent/);
  assert.match(rendered.content, /wait_agent/);
  assert.match(rendered.content, /final-status/);
  assert.match(rendered.content, /code-reviewer/);
  assert.match(rendered.content, /security-auditor/);
  assert.match(rendered.content, /test-engineer/);
  assert.doesNotMatch(rendered.content, /Agent tool/);
  assert.doesNotMatch(rendered.content, /Claude Code/);
  assert.doesNotMatch(rendered.content, /\.claude\/agents/);
});

test('renderAgentRole converts persona markdown to Codex TOML and rewrites Composition', () => {
  const source = fs.readFileSync(path.join(repoRoot, 'agents/code-reviewer.md'), 'utf8');
  const rendered = renderAgentRole('agents/code-reviewer.md', source);

  assert.equal(rendered.relativePath, 'codex/agents/code-reviewer.toml');
  assert.match(rendered.content, /^name = "code-reviewer"$/m);
  assert.match(rendered.content, /^description = "Senior code reviewer/m);
  assert.match(rendered.content, /^developer_instructions = '''\n# Senior Code Reviewer/m);
  assert.match(rendered.content, /generated Codex prompt `agent-skills-review`/);
  assert.match(rendered.content, /generated Codex prompt `agent-skills-ship`/);
  assert.doesNotMatch(rendered.content, /Agent tool/);
  assert.doesNotMatch(rendered.content, /Claude Code/);

  const parsedToml = parseGeneratedAgentToml(rendered.content, rendered.relativePath);
  assert.equal(parsedToml.name, 'code-reviewer');
  assert.equal(parsedToml.developer_instructions.startsWith('# Senior Code Reviewer'), true);
});

test('buildExpectedArtifacts includes manifests, prompts, agent roles, and Bundle Mirrors', () => {
  const artifacts = buildExpectedArtifacts(repoRoot);

  assert.equal(
    JSON.parse(artifacts.get('plugins/agent-skills/.codex-plugin/plugin.json')).name,
    'agent-skills',
  );
  assert.equal(
    JSON.parse(artifacts.get('plugins/agent-skills/.codex-plugin/plugin.json')).version,
    '0.1.0',
  );
  assert.equal(
    JSON.parse(artifacts.get('.agents/plugins/marketplace.json')).name,
    'agent-skills',
  );
  assert.ok(artifacts.has('codex/prompts/agent-skills-spec.md'));
  assert.ok(artifacts.has('codex/agents/security-auditor.toml'));
  assert.ok(artifacts.has('plugins/agent-skills/skills/spec-driven-development/SKILL.md'));
  assert.ok(artifacts.has('plugins/agent-skills/hooks/hooks.json'));
});

test('validateGeneratedArtifacts reports missing and drifted generated files', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-dist-test-'));
  try {
    fs.mkdirSync(path.join(tmp, 'codex/prompts'), { recursive: true });
    fs.writeFileSync(path.join(tmp, 'codex/prompts/agent-skills-spec.md'), 'stale\n');

    const expected = new Map([
      ['codex/prompts/agent-skills-spec.md', 'fresh\n'],
      ['codex/agents/code-reviewer.toml', 'role\n'],
    ]);

    const result = validateGeneratedArtifacts(tmp, expected, ['codex/prompts', 'codex/agents']);
    assert.equal(result.ok, false);
    assert.deepEqual(result.drifted, ['codex/prompts/agent-skills-spec.md']);
    assert.deepEqual(result.missing, ['codex/agents/code-reviewer.toml']);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
```

- [ ] **Step 2: Run tests to verify they fail for the expected reason**

Run:

```bash
node --test scripts/codex-distribution-test.mjs
```

Expected: FAIL with a module resolution error for `scripts/codex-distribution.mjs`.

- [ ] **Step 3: Commit**

```bash
git add scripts/codex-distribution-test.mjs
git commit -m "test: add codex distribution generator coverage"
```

---

### Task 2: Implement the Codex Distribution Generator

**Files:**
- Create: `scripts/codex-distribution.mjs`
- Generate: `.agents/plugins/marketplace.json`
- Generate: `plugins/agent-skills/.codex-plugin/plugin.json`
- Generate: `codex/prompts/*.md`
- Generate: `codex/agents/*.toml`
- Generate: `plugins/agent-skills/skills/**`
- Generate: `plugins/agent-skills/hooks/**`

- [ ] **Step 1: Add the generator implementation**

Create `scripts/codex-distribution.mjs` with this complete content:

```js
#!/usr/bin/env node

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DEFAULT_ROOT = path.resolve(__dirname, '..');

const GENERATED_DIRS = [
  'codex/prompts',
  'codex/agents',
  'plugins/agent-skills/skills',
  'plugins/agent-skills/hooks',
];

const COMMAND_ARGUMENT_HINTS = {
  build: 'plan path or task name',
  'code-simplify': 'file, directory, or recent-change scope',
  plan: 'spec path',
  review: 'diff, commit, PR, or file path',
  ship: 'release scope or diff target',
  spec: 'feature request',
  test: 'feature, bug, or test target',
};

const PLUGIN_MANIFEST = {
  name: 'agent-skills',
  description: 'Production-grade engineering skills for AI coding agents, packaged as a Codex Plugin Bundle.',
  version: '0.1.0',
  author: {
    name: 'Addy Osmani',
  },
  homepage: 'https://github.com/addyosmani/agent-skills',
  repository: 'https://github.com/addyosmani/agent-skills',
  license: 'MIT',
  skills: './skills',
  hooks: './hooks/hooks.json',
};

const MARKETPLACE_MANIFEST = {
  name: 'agent-skills',
  owner: {
    name: 'Addy Osmani',
  },
  metadata: {
    description: 'Repo-local Codex Distribution marketplace for Agent Skills.',
  },
  plugins: [
    {
      name: 'agent-skills',
      source: {
        source: 'local',
        path: './plugins/agent-skills',
      },
      description: 'Production-grade engineering skills covering spec, plan, build, verify, review, and ship workflows.',
    },
  ],
};

const SHIP_PROMPT_BODY = `Invoke the agent-skills:shipping-and-launch skill.

\`agent-skills-ship\` is a fan-out orchestrator. It runs three specialist Codex agent roles in parallel against the current change, then merges their reports into a single go/no-go decision with a rollback plan. The personas operate independently: no shared mutable state, no ordering, and no persona-to-persona delegation.

## Phase A — Parallel fan-out

Start all three \`spawn_agent\` calls before waiting for results:

1. \`code-reviewer\` — Run a five-axis review (correctness, readability, architecture, security, performance) on the staged changes or recent commits. Output the standard review template.
2. \`security-auditor\` — Run a vulnerability and threat-model pass. Check OWASP Top 10, secrets handling, auth/authz, dependency CVEs. Output the standard audit report.
3. \`test-engineer\` — Analyze test coverage for the change. Identify gaps in happy path, edge cases, error paths, and concurrency scenarios. Output the standard coverage analysis.

Each spawned task prompt must include the relevant diff or scope, the persona role name, and the required output format. Keep the fan-out flat: personas do not call other personas.

## Phase B — Wait loop

After spawning, use \`wait_agent\` to watch mailbox updates. A \`wait_agent\` call only reports that some mailbox activity occurred; it does not prove the target agent finished.

Continue waiting until all three target agents return final-status notifications. If the update is from another live agent, handle it only if useful, then keep waiting for these three reports. Do not synthesize a ship decision from partial reports unless the user explicitly approves proceeding without the missing report after being told the exact elapsed wait time.

## Phase C — Merge in main context

Once all three reports are available, the main agent synthesizes them:

1. **Code Quality** — Aggregate Critical/Important findings from \`code-reviewer\` and any failing tests, lint, or build output. Resolve duplicates between reviewers.
2. **Security** — Promote any Critical/High \`security-auditor\` findings to launch blockers. Cross-reference with \`code-reviewer\`'s security axis.
3. **Performance** — Pull from \`code-reviewer\`'s performance axis; cross-check Core Web Vitals if applicable.
4. **Accessibility** — Verify keyboard navigation, screen reader support, and contrast directly when the change has UI impact.
5. **Infrastructure** — Verify environment variables, migrations, monitoring, and feature flags directly.
6. **Documentation** — Verify README, ADRs, changelog, and setup docs directly.

## Phase D — Decision and rollback

Produce a single output:

\`\`\`markdown
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
\`\`\`

## Rules

1. Start the three Phase A agents before the first wait.
2. Personas do not call each other. The main agent merges in Phase C.
3. The rollback plan is mandatory before any GO decision.
4. If any persona returns a Critical finding, the default verdict is NO-GO unless the user explicitly accepts the risk.
5. Skip fan-out only if all of these are true: the change touches 2 files or fewer, the diff is under 50 lines, and it does not touch auth, payments, data access, or config/env. Otherwise, default to fan-out.`;

const COMPOSITION_REWRITES = {
  'code-reviewer': `## Composition

- **Invoke directly when:** the user asks for a review of a specific change, file, or PR.
- **Invoke via:** generated Codex prompt \`agent-skills-review\` for single-perspective review, or generated Codex prompt \`agent-skills-ship\` for parallel fan-out alongside \`security-auditor\` and \`test-engineer\`.
- **Do not invoke from another persona.** If you find yourself wanting a security audit or test analysis, surface that as a recommendation in your report. Orchestration belongs to the user or the main Codex session.`,
  'security-auditor': `## Composition

- **Invoke directly when:** the user wants a security-focused pass on a specific change, file, or system component.
- **Invoke via:** generated Codex prompt \`agent-skills-ship\` for parallel fan-out alongside \`code-reviewer\` and \`test-engineer\`.
- **Do not invoke from another persona.** If another persona flags a deeper security concern, the user or the main Codex session initiates that pass.`,
  'test-engineer': `## Composition

- **Invoke directly when:** the user asks for test design, coverage analysis, or a Prove-It test for a specific bug.
- **Invoke via:** generated Codex prompt \`agent-skills-test\` for TDD workflow, or generated Codex prompt \`agent-skills-ship\` for parallel fan-out alongside \`code-reviewer\` and \`security-auditor\`.
- **Do not invoke from another persona.** Recommendations to add tests belong in your report; the user or the main Codex session decides when to act on them.`,
};

export function parseFrontmatter(content, sourcePath) {
  const match = content.match(/^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*\r?\n?/);
  if (!match) {
    throw new Error(`${sourcePath}: missing YAML frontmatter`);
  }

  const frontmatter = {};
  for (const rawLine of match[1].split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) continue;
    const colonIndex = line.indexOf(':');
    if (colonIndex === -1) {
      throw new Error(`${sourcePath}: invalid frontmatter line "${rawLine}"`);
    }
    const key = line.slice(0, colonIndex).trim();
    let value = line.slice(colonIndex + 1).trim();
    value = value.replace(/^['"]|['"]$/g, '');
    if (!key || !value) {
      throw new Error(`${sourcePath}: frontmatter key "${key}" has an empty value`);
    }
    frontmatter[key] = value;
  }

  let body = content.slice(match[0].length);
  if (body.startsWith('\n')) {
    body = body.slice(1);
  }

  return {
    frontmatter,
    body,
  };
}

function jsonBlock(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function yamlScalar(value) {
  return JSON.stringify(value);
}

function tomlBasicString(value) {
  return JSON.stringify(value);
}

function tomlLiteralString(value, sourcePath) {
  if (value.includes("'''")) {
    throw new Error(`${sourcePath}: body contains TOML literal string delimiter`);
  }
  return `'''\n${value.replace(/\s+$/, '')}\n'''`;
}

function listFilesRecursive(rootDir) {
  if (!fs.existsSync(rootDir)) return [];

  const result = [];
  const stack = [''];
  while (stack.length > 0) {
    const relDir = stack.pop();
    const absDir = path.join(rootDir, relDir);
    for (const entry of fs.readdirSync(absDir, { withFileTypes: true })) {
      const relPath = path.join(relDir, entry.name);
      if (entry.isDirectory()) {
        stack.push(relPath);
      } else if (entry.isFile()) {
        result.push(relPath.split(path.sep).join('/'));
      } else if (entry.isSymbolicLink()) {
        throw new Error(`${path.join(rootDir, relPath)}: Bundle Mirrors must use regular files, not symlinks`);
      }
    }
  }

  return result.sort();
}

function listMarkdownFiles(dir) {
  return fs.readdirSync(dir)
    .filter((name) => name.endsWith('.md'))
    .sort();
}

function promptNameFromSource(sourcePath) {
  return path.basename(sourcePath, '.md');
}

function renderPromptFrontmatter(description, hint) {
  const lines = ['---', `description: ${yamlScalar(description)}`];
  if (hint) {
    lines.push(`argument-hint: ${yamlScalar(hint)}`);
  }
  lines.push('---', '');
  return lines.join('\n');
}

function applyPromptRewrites(commandName, body) {
  if (commandName === 'ship') {
    return `${SHIP_PROMPT_BODY}\n`;
  }

  let rewritten = body.trimEnd();

  rewritten = rewritten.replace(
    '1. Enter plan mode — read only, no code changes',
    '1. Work read-only while planning — inspect files but do not edit code until the plan is accepted',
  );
  rewritten = rewritten.replaceAll('CLAUDE.md', 'AGENTS.md');

  return `${rewritten}\n`;
}

export function renderPrompt(sourcePath, content) {
  const commandName = promptNameFromSource(sourcePath);
  const parsed = parseFrontmatter(content, sourcePath);
  const description = parsed.frontmatter.description;
  if (!description) {
    throw new Error(`${sourcePath}: missing required description frontmatter`);
  }

  const hint = COMMAND_ARGUMENT_HINTS[commandName];
  const rendered = [
    renderPromptFrontmatter(description, hint),
    applyPromptRewrites(commandName, parsed.body),
  ].join('\n');

  const forbiddenGenericHint = `argument-hint: ${JSON.stringify('optional ' + 'arguments')}`;
  if (rendered.includes(forbiddenGenericHint)) {
    throw new Error(`${sourcePath}: generated a generic argument hint`);
  }

  return {
    relativePath: `codex/prompts/agent-skills-${commandName}.md`,
    content: rendered,
  };
}

function applyAgentRewrites(roleName, body) {
  const replacement = COMPOSITION_REWRITES[roleName];
  if (!replacement) return `${body.trimEnd()}\n`;

  if (!body.includes('## Composition')) {
    throw new Error(`agents/${roleName}.md: missing Composition section`);
  }

  return `${body.replace(/## Composition[\s\S]*$/m, replacement).trimEnd()}\n`;
}

export function renderAgentRole(sourcePath, content) {
  if (path.basename(sourcePath) === 'README.md') return null;

  const parsed = parseFrontmatter(content, sourcePath);
  const name = parsed.frontmatter.name;
  const description = parsed.frontmatter.description;
  if (!name) throw new Error(`${sourcePath}: missing required name frontmatter`);
  if (!description) throw new Error(`${sourcePath}: missing required description frontmatter`);

  const body = applyAgentRewrites(name, parsed.body);
  const contentToml = [
    `name = ${tomlBasicString(name)}`,
    `description = ${tomlBasicString(description)}`,
    `developer_instructions = ${tomlLiteralString(body, sourcePath)}`,
    '',
  ].join('\n');

  parseGeneratedAgentToml(contentToml, sourcePath);

  return {
    relativePath: `codex/agents/${name}.toml`,
    content: contentToml,
  };
}

export function parseGeneratedAgentToml(content, sourcePath = 'generated-agent.toml') {
  const match = content.match(/^name = ("(?:\\.|[^"\\])*")\ndescription = ("(?:\\.|[^"\\])*")\ndeveloper_instructions = '''\n([\s\S]*)\n'''\n?$/);
  if (!match) {
    throw new Error(`${sourcePath}: not in the generated Codex agent TOML subset`);
  }

  return {
    name: JSON.parse(match[1]),
    description: JSON.parse(match[2]),
    developer_instructions: match[3],
  };
}

function addPromptArtifacts(rootDir, artifacts) {
  const commandDir = path.join(rootDir, '.claude/commands');
  const seen = new Set();

  for (const fileName of listMarkdownFiles(commandDir)) {
    const sourcePath = path.join('.claude/commands', fileName).split(path.sep).join('/');
    const source = fs.readFileSync(path.join(rootDir, sourcePath), 'utf8');
    const rendered = renderPrompt(sourcePath, source);
    if (seen.has(rendered.relativePath)) {
      throw new Error(`duplicate generated prompt path: ${rendered.relativePath}`);
    }
    seen.add(rendered.relativePath);
    artifacts.set(rendered.relativePath, rendered.content);
  }
}

function addAgentArtifacts(rootDir, artifacts) {
  const agentDir = path.join(rootDir, 'agents');
  const seen = new Set();

  for (const fileName of listMarkdownFiles(agentDir)) {
    const sourcePath = path.join('agents', fileName).split(path.sep).join('/');
    const source = fs.readFileSync(path.join(rootDir, sourcePath), 'utf8');
    const rendered = renderAgentRole(sourcePath, source);
    if (!rendered) continue;
    if (seen.has(rendered.relativePath)) {
      throw new Error(`duplicate generated agent path: ${rendered.relativePath}`);
    }
    seen.add(rendered.relativePath);
    artifacts.set(rendered.relativePath, rendered.content);
  }
}

function addBundleMirrorArtifacts(rootDir, artifacts, sourceDir, destDir) {
  for (const relPath of listFilesRecursive(path.join(rootDir, sourceDir))) {
    const sourcePath = path.join(rootDir, sourceDir, relPath);
    const destPath = path.posix.join(destDir, relPath);
    artifacts.set(destPath, fs.readFileSync(sourcePath, 'utf8'));
  }
}

export function buildExpectedArtifacts(rootDir = DEFAULT_ROOT) {
  const artifacts = new Map();

  artifacts.set('plugins/agent-skills/.codex-plugin/plugin.json', jsonBlock(PLUGIN_MANIFEST));
  artifacts.set('.agents/plugins/marketplace.json', jsonBlock(MARKETPLACE_MANIFEST));
  addPromptArtifacts(rootDir, artifacts);
  addAgentArtifacts(rootDir, artifacts);
  addBundleMirrorArtifacts(rootDir, artifacts, 'skills', 'plugins/agent-skills/skills');
  addBundleMirrorArtifacts(rootDir, artifacts, 'hooks', 'plugins/agent-skills/hooks');

  return artifacts;
}

function ensureParent(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function writeArtifacts(rootDir, artifacts) {
  for (const relDir of GENERATED_DIRS) {
    fs.rmSync(path.join(rootDir, relDir), { recursive: true, force: true });
  }

  for (const [relativePath, content] of artifacts.entries()) {
    const absPath = path.join(rootDir, relativePath);
    ensureParent(absPath);
    fs.writeFileSync(absPath, content);
  }
}

function listFilesUnder(rootDir, relativeDir) {
  const absDir = path.join(rootDir, relativeDir);
  if (!fs.existsSync(absDir)) return [];
  return listFilesRecursive(absDir).map((relPath) => path.posix.join(relativeDir, relPath));
}

export function validateGeneratedArtifacts(rootDir, artifacts, generatedDirs = GENERATED_DIRS) {
  const missing = [];
  const drifted = [];
  const extra = [];

  for (const [relativePath, expected] of artifacts.entries()) {
    const absPath = path.join(rootDir, relativePath);
    if (!fs.existsSync(absPath)) {
      missing.push(relativePath);
      continue;
    }
    const actual = fs.readFileSync(absPath, 'utf8');
    if (actual !== expected) {
      drifted.push(relativePath);
    }
  }

  const expectedPaths = new Set(artifacts.keys());
  for (const relDir of generatedDirs) {
    for (const actualPath of listFilesUnder(rootDir, relDir)) {
      if (!expectedPaths.has(actualPath)) {
        extra.push(actualPath);
      }
    }
  }

  missing.sort();
  drifted.sort();
  extra.sort();

  return {
    ok: missing.length === 0 && drifted.length === 0 && extra.length === 0,
    missing,
    drifted,
    extra,
  };
}

function printCheckResult(result) {
  for (const file of result.missing) {
    console.error(`missing: ${file}`);
  }
  for (const file of result.drifted) {
    console.error(`drifted: ${file}`);
  }
  for (const file of result.extra) {
    console.error(`extra: ${file}`);
  }
}

function parseArgs(argv) {
  const args = [...argv];
  const command = args.shift();
  if (!command || command === '--help' || command === '-h') {
    return { command: 'help' };
  }
  if (command !== 'generate' && command !== 'check') {
    throw new Error(`unknown command: ${command}`);
  }
  if (args.length > 0) {
    throw new Error(`unexpected arguments: ${args.join(' ')}`);
  }
  return { command };
}

function usage() {
  return [
    'Usage:',
    '  node scripts/codex-distribution.mjs generate',
    '  node scripts/codex-distribution.mjs check',
    '',
    'generate  Refresh committed Codex Distribution artifacts.',
    'check     Fail if committed Codex Distribution artifacts drift from sources.',
    '',
  ].join(os.EOL);
}

export function main(argv = process.argv.slice(2), rootDir = DEFAULT_ROOT) {
  const parsed = parseArgs(argv);
  if (parsed.command === 'help') {
    process.stdout.write(usage());
    return 0;
  }

  const artifacts = buildExpectedArtifacts(rootDir);

  if (parsed.command === 'generate') {
    writeArtifacts(rootDir, artifacts);
    console.error(`wrote ${artifacts.size} Codex Distribution artifacts`);
    return 0;
  }

  const result = validateGeneratedArtifacts(rootDir, artifacts);
  if (!result.ok) {
    printCheckResult(result);
    console.error('Codex Distribution artifacts are not up to date. Run: node scripts/codex-distribution.mjs generate');
    return 1;
  }

  console.error(`checked ${artifacts.size} Codex Distribution artifacts`);
  return 0;
}

if (process.argv[1] === __filename) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
```

- [ ] **Step 2: Run the generator tests**

Run:

```bash
node --test scripts/codex-distribution-test.mjs
```

Expected: PASS.

- [ ] **Step 3: Generate committed Codex artifacts**

Run:

```bash
node scripts/codex-distribution.mjs generate
```

Expected: stderr includes `wrote` and mentions Codex Distribution artifacts.

- [ ] **Step 4: Verify generated artifacts are current**

Run:

```bash
node scripts/codex-distribution.mjs check
```

Expected: PASS with stderr similar to `checked 40 Codex Distribution artifacts`. The exact count may differ because it includes every mirrored skill and hook file.

- [ ] **Step 5: Inspect generated `ship` prompt for Codex-only orchestration**

Run:

```bash
rg -n "Agent tool|Claude Code|spawn_agent|wait_agent|final-status" codex/prompts/agent-skills-ship.md
```

Expected: output contains `spawn_agent`, `wait_agent`, and `final-status`; output does not contain `Agent tool` or `Claude Code`.

- [ ] **Step 6: Commit**

```bash
git add scripts/codex-distribution.mjs .agents/plugins/marketplace.json plugins/agent-skills codex scripts/codex-distribution-test.mjs
git commit -m "feat: generate codex distribution artifacts"
```

---

### Task 3: Make Hooks Dual-Host

**Files:**
- Modify: `hooks/hooks.json:1`
- Modify: `hooks/session-start-test.sh:1`
- Generate after source hook change: `plugins/agent-skills/hooks/hooks.json`

- [ ] **Step 1: Write the failing hook fallback assertion**

Append this Node assertion inside `hooks/session-start-test.sh`, after the existing `session-start JSON payload OK` assertion block and before the terminating `NODE` marker:

```js
const hookConfig = JSON.parse(fs.readFileSync('hooks/hooks.json', 'utf8'));
const sessionStartCommand = hookConfig.hooks.SessionStart[0].hooks[0].command;
const expectedCommand = 'bash ${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/hooks/session-start.sh';

if (sessionStartCommand !== expectedCommand) {
  throw new Error(`expected dual-host hook command ${expectedCommand}, got ${sessionStartCommand}`);
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash hooks/session-start-test.sh
```

Expected: FAIL with `expected dual-host hook command`.

- [ ] **Step 3: Update the hook command**

Replace `hooks/hooks.json` with this complete content:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/hooks/session-start.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: Run hook tests**

Run:

```bash
bash hooks/session-start-test.sh
```

Expected: PASS with `session-start JSON payload OK`.

- [ ] **Step 5: Refresh generated mirrors**

Run:

```bash
node scripts/codex-distribution.mjs generate
node scripts/codex-distribution.mjs check
```

Expected: PASS; `plugins/agent-skills/hooks/hooks.json` matches `hooks/hooks.json`.

- [ ] **Step 6: Commit**

```bash
git add hooks/hooks.json hooks/session-start-test.sh plugins/agent-skills/hooks/hooks.json
git commit -m "fix: support codex plugin root in hooks"
```

---

### Task 4: Add Sync Script Tests

**Files:**
- Create: `scripts/sync-codex-assets-test.sh`
- Later implementation target: `scripts/sync-codex-assets.sh`

- [ ] **Step 1: Write failing sync script tests**

Create `scripts/sync-codex-assets-test.sh` with this complete content:

```bash
#!/bin/bash
# Tests for scripts/sync-codex-assets.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_file_exists() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then
    pass=$((pass + 1))
    printf '  PASS: %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL: %s\n    missing: %s\n' "$label" "$path" >&2
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -Fq "$needle"; then
    pass=$((pass + 1))
    printf '  PASS: %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL: %s\n    expected substring: %s\n    actual: %s\n' "$label" "$needle" "$haystack" >&2
  fi
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1))
    printf '  PASS: %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL: %s\n    expected: %s\n    actual: %s\n' "$label" "$expected" "$actual" >&2
  fi
}

if [ ! -d codex/prompts ] || [ ! -d codex/agents ]; then
  printf 'Generated codex assets are missing. Run: node scripts/codex-distribution.mjs generate\n' >&2
  exit 1
fi

printf 'Test 1: dry-run reports copies without writing\n'
home1="$TMPDIR/home1"
mkdir -p "$home1"
dry_output="$(CODEX_HOME="$home1" bash scripts/sync-codex-assets.sh --dry-run)"
assert_contains "dry-run JSON status" '"status":"ok"' "$dry_output"
assert_contains "dry-run records prompt copy" 'prompts/agent-skills-spec.md' "$dry_output"
if [ ! -e "$home1/prompts/agent-skills-spec.md" ]; then
  pass=$((pass + 1))
  printf '  PASS: dry-run does not write prompt\n'
else
  fail=$((fail + 1))
  printf '  FAIL: dry-run wrote prompt\n' >&2
fi

printf '\nTest 2: normal sync copies prompts and agents\n'
sync_output="$(CODEX_HOME="$home1" bash scripts/sync-codex-assets.sh)"
assert_contains "sync JSON status" '"status":"ok"' "$sync_output"
assert_file_exists "prompt copied" "$home1/prompts/agent-skills-spec.md"
assert_file_exists "agent copied" "$home1/agents/code-reviewer.toml"

printf '\nTest 3: conflict refuses overwrite by default\n'
home2="$TMPDIR/home2"
mkdir -p "$home2/prompts"
printf 'local edit\n' > "$home2/prompts/agent-skills-spec.md"
set +e
conflict_output="$(CODEX_HOME="$home2" bash scripts/sync-codex-assets.sh 2>"$TMPDIR/conflict.err")"
conflict_status=$?
set -e
assert_eq "conflict exits 2" "2" "$conflict_status"
assert_contains "conflict JSON status" '"status":"conflict"' "$conflict_output"
assert_contains "conflict path included" 'prompts/agent-skills-spec.md' "$conflict_output"
assert_eq "local file preserved" "local edit" "$(cat "$home2/prompts/agent-skills-spec.md")"

printf '\nTest 4: force backs up conflict before overwrite\n'
force_output="$(CODEX_HOME="$home2" bash scripts/sync-codex-assets.sh --force)"
assert_contains "force JSON status" '"status":"ok"' "$force_output"
assert_contains "backup path included" 'backups/agent-skills/' "$force_output"
backup_count="$(find "$home2/backups/agent-skills" -type f | wc -l | tr -d ' ')"
assert_eq "one backup written" "1" "$backup_count"
assert_contains "destination overwritten" 'Start spec-driven development' "$(cat "$home2/prompts/agent-skills-spec.md")"

if [ "$fail" -gt 0 ]; then
  printf '\n%d assertion(s) failed\n' "$fail" >&2
  exit 1
fi

printf '\n%d assertion(s) passed\n' "$pass"
```

- [ ] **Step 2: Run tests to verify they fail for the expected reason**

Run:

```bash
bash scripts/sync-codex-assets-test.sh
```

Expected: FAIL with `scripts/sync-codex-assets.sh: No such file or directory`.

- [ ] **Step 3: Commit**

```bash
git add scripts/sync-codex-assets-test.sh
git commit -m "test: cover codex asset sync behavior"
```

---

### Task 5: Implement the Sync Script

**Files:**
- Create: `scripts/sync-codex-assets.sh`

- [ ] **Step 1: Add the sync script implementation**

Create `scripts/sync-codex-assets.sh` with this complete content:

```bash
#!/bin/bash
# Install committed Codex prompts and agent roles into CODEX_HOME.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
PROMPT_SRC="$ROOT/codex/prompts"
AGENT_SRC="$ROOT/codex/agents"

DRY_RUN=0
FORCE=0
BACKUP_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="$CODEX_HOME_DIR/backups/agent-skills/$BACKUP_STAMP"

copied=()
skipped=()
conflicts=()
backups=()

usage() {
  cat <<'USAGE'
Usage: scripts/sync-codex-assets.sh [--dry-run] [--force]

Copies committed Codex prompts and agent roles into ${CODEX_HOME:-~/.codex}.

Options:
  --dry-run  Report planned writes without changing files.
  --force    Back up conflicting destination files before overwriting them.
  --help     Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'error: unknown argument: %s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

require_dir() {
  local dir="$1" label="$2"
  if [ ! -d "$dir" ]; then
    printf 'error: missing %s at %s. Run: node scripts/codex-distribution.mjs generate\n' "$label" "$dir" >&2
    exit 1
  fi
  if ! find "$dir" -maxdepth 1 -type f 2>/dev/null | grep -q .; then
    printf 'error: %s has no files at %s. Run: node scripts/codex-distribution.mjs generate\n' "$label" "$dir" >&2
    exit 1
  fi
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

json_array() {
  local first=1 item
  printf '['
  for item in "$@"; do
    if [ "$first" -eq 0 ]; then printf ','; fi
    first=0
    printf '"%s"' "$(json_escape "$item")"
  done
  printf ']'
}

record_copy() {
  copied+=("$1")
}

record_skip() {
  skipped+=("$1")
}

record_conflict() {
  conflicts+=("$1")
}

record_backup() {
  backups+=("$1")
}

install_one() {
  local src="$1" dest="$2" rel="$3"

  if [ ! -f "$src" ]; then
    printf 'error: missing source artifact %s\n' "$src" >&2
    exit 1
  fi

  if [ ! -e "$dest" ]; then
    printf 'copy %s\n' "$rel" >&2
    record_copy "$rel"
    if [ "$DRY_RUN" -eq 0 ]; then
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
    fi
    return 0
  fi

  if cmp -s "$src" "$dest"; then
    printf 'skip unchanged %s\n' "$rel" >&2
    record_skip "$rel"
    return 0
  fi

  if [ "$FORCE" -eq 0 ]; then
    printf 'conflict %s\n' "$rel" >&2
    record_conflict "$rel"
    return 0
  fi

  local backup="$BACKUP_ROOT/$rel"
  printf 'backup %s -> %s\n' "$rel" "$backup" >&2
  record_backup "$backup"
  record_copy "$rel"
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$(dirname "$backup")" "$(dirname "$dest")"
    cp "$dest" "$backup"
    cp "$src" "$dest"
  fi
}

sync_dir() {
  local src_dir="$1" dest_dir="$2" rel_prefix="$3" file base rel
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$dest_dir"
  fi
  for file in "$src_dir"/*; do
    [ -f "$file" ] || continue
    base="$(basename "$file")"
    rel="$rel_prefix/$base"
    install_one "$file" "$dest_dir/$base" "$rel"
  done
}

require_dir "$PROMPT_SRC" "generated Codex prompts"
require_dir "$AGENT_SRC" "generated Codex agents"

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$CODEX_HOME_DIR/prompts" "$CODEX_HOME_DIR/agents"
fi

sync_dir "$PROMPT_SRC" "$CODEX_HOME_DIR/prompts" "prompts"
sync_dir "$AGENT_SRC" "$CODEX_HOME_DIR/agents" "agents"

status="ok"
exit_code=0
if [ "${#conflicts[@]}" -gt 0 ]; then
  status="conflict"
  exit_code=2
fi

printf '{'
printf '"status":"%s",' "$status"
printf '"codexHome":"%s",' "$(json_escape "$CODEX_HOME_DIR")"
printf '"dryRun":%s,' "$([ "$DRY_RUN" -eq 1 ] && printf true || printf false)"
printf '"force":%s,' "$([ "$FORCE" -eq 1 ] && printf true || printf false)"
printf '"copied":'; json_array "${copied[@]}"; printf ','
printf '"skipped":'; json_array "${skipped[@]}"; printf ','
printf '"conflicts":'; json_array "${conflicts[@]}"; printf ','
printf '"backups":'; json_array "${backups[@]}"
printf '}\n'

exit "$exit_code"
```

- [ ] **Step 2: Make the script executable**

Run:

```bash
chmod +x scripts/sync-codex-assets.sh scripts/sync-codex-assets-test.sh
```

Expected: no output.

- [ ] **Step 3: Run sync tests**

Run:

```bash
bash scripts/sync-codex-assets-test.sh
```

Expected: PASS with all assertions passed.

- [ ] **Step 4: Run a real dry-run against a temp Codex home**

Run:

```bash
tmp_codex_home="$(mktemp -d)"
CODEX_HOME="$tmp_codex_home" bash scripts/sync-codex-assets.sh --dry-run
find "$tmp_codex_home" -type f
rm -rf "$tmp_codex_home"
```

Expected: JSON status is `ok`; `find` prints no files because dry-run does not write.

- [ ] **Step 5: Commit**

```bash
git add scripts/sync-codex-assets.sh scripts/sync-codex-assets-test.sh
git commit -m "feat: sync codex prompts and agents"
```

---

### Task 6: Add Codex Setup Documentation

**Files:**
- Create: `docs/codex-setup.md`
- Modify: `README.md:25`

- [ ] **Step 1: Add Codex setup documentation**

Create `docs/codex-setup.md` with this complete content:

```markdown
# Codex Distribution Setup

This guide installs the Agent Skills Codex Distribution from a local checkout.

The Codex Distribution has two parts:

- **Codex Plugin Bundle:** `plugins/agent-skills/`, loaded by Codex through the plugin system.
- **Synced Local Assets:** generated prompts and agent roles copied into `${CODEX_HOME:-~/.codex}`.

Marketplace installation alone does not install the local prompts or agent roles. Run the sync step after enabling the plugin bundle.

## Prerequisites

- A local checkout of this repository.
- Codex with local plugin marketplace support.
- Node.js 20 or newer if you need to refresh generated artifacts.

## Install

From the repository root:

```bash
codex plugin marketplace add ./.agents/plugins/marketplace.json
codex plugin install agent-skills@agent-skills
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
```

- [ ] **Step 2: Replace the README Codex section**

Replace the existing Codex / Other Agents details block in `README.md` with:

```markdown
<details>
<summary><b>Codex</b></summary>

Codex uses a local Codex Distribution: a nested plugin bundle plus synced local prompts and agent roles.

```bash
codex plugin marketplace add ./.agents/plugins/marketplace.json
codex plugin install agent-skills@agent-skills
bash scripts/sync-codex-assets.sh
```

See [docs/codex-setup.md](docs/codex-setup.md).

</details>

<details>
<summary><b>Other Agents</b></summary>

Skills are plain Markdown - they work with any agent that accepts system prompts or instruction files. See [docs/getting-started.md](docs/getting-started.md).

</details>
```

- [ ] **Step 3: Verify documentation references the supported install order**

Run:

```bash
rg -n "codex plugin marketplace add|codex plugin install|sync-codex-assets|docs/codex-setup" README.md docs/codex-setup.md
```

Expected: README links to `docs/codex-setup.md`, and `docs/codex-setup.md` lists marketplace add, plugin install, then sync.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/codex-setup.md
git commit -m "docs: add codex distribution setup"
```

---

### Task 7: Wire Codex Checks into CI

**Files:**
- Modify: `.github/workflows/test-plugin-install.yml:1`

- [ ] **Step 1: Add failing CI expectation locally**

Before editing CI, run the commands that CI will run:

```bash
node --test scripts/codex-distribution-test.mjs
bash scripts/sync-codex-assets-test.sh
node scripts/codex-distribution.mjs check
```

Expected: PASS locally before CI wiring.

- [ ] **Step 2: Update workflow**

Edit `.github/workflows/test-plugin-install.yml` so the `validate-skills` job becomes:

```yaml
  validate-skills:
    name: Validate skill and Codex distribution content
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Validate all skills
        run: node scripts/validate-skills.js

      - name: Test Codex distribution generator
        run: node --test scripts/codex-distribution-test.mjs

      - name: Test Codex asset sync
        run: bash scripts/sync-codex-assets-test.sh

      - name: Check Codex generated artifacts
        run: node scripts/codex-distribution.mjs check
```

Leave the existing Claude plugin validation and install jobs in place.

- [ ] **Step 3: Run all local checks**

Run:

```bash
node scripts/validate-skills.js
node --test scripts/codex-distribution-test.mjs
bash scripts/sync-codex-assets-test.sh
bash hooks/session-start-test.sh
bash hooks/simplify-ignore-test.sh
node scripts/codex-distribution.mjs check
```

Expected: all commands PASS.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/test-plugin-install.yml
git commit -m "ci: validate codex distribution artifacts"
```

---

### Task 8: Final Verification and Release-Readiness Review

**Files:**
- Read: `docs/superpowers/specs/2026-05-23-codex-plugin-design.md`
- Read: `docs/adr/0001-codex-distribution-uses-nested-plugin-plus-sync.md`
- Read: `CONTEXT.md`
- Verify generated and modified files from Tasks 1-7.

- [ ] **Step 1: Run the full verification suite**

Run:

```bash
node scripts/validate-skills.js
node --test scripts/codex-distribution-test.mjs
bash scripts/sync-codex-assets-test.sh
bash hooks/session-start-test.sh
bash hooks/simplify-ignore-test.sh
node scripts/codex-distribution.mjs check
```

Expected: all commands PASS.

- [ ] **Step 2: Verify Codex distribution file inventory**

Run:

```bash
test -f plugins/agent-skills/.codex-plugin/plugin.json
test -f .agents/plugins/marketplace.json
test -f codex/prompts/agent-skills-spec.md
test -f codex/prompts/agent-skills-ship.md
test -f codex/agents/code-reviewer.toml
test -f plugins/agent-skills/skills/spec-driven-development/SKILL.md
test -f plugins/agent-skills/hooks/hooks.json
```

Expected: no output and exit code 0.

- [ ] **Step 3: Verify no symlinks exist inside the Codex Plugin Bundle**

Run:

```bash
find plugins/agent-skills -type l -print
```

Expected: no output.

- [ ] **Step 4: Verify install docs do not overstate marketplace installation**

Run:

```bash
rg -n "one-step|one step|marketplace installation alone|sync step|Synced Local Assets|Distribution Install" README.md docs/codex-setup.md docs/superpowers/specs/2026-05-23-codex-plugin-design.md CONTEXT.md
```

Expected: `docs/codex-setup.md` says marketplace installation alone does not install prompts or agent roles, and the install flow includes the sync step.

- [ ] **Step 5: Review final diff**

Run:

```bash
git diff --stat HEAD
git diff --check HEAD
```

Expected: diff only contains Codex Distribution implementation, tests, docs, generated artifacts, and the hook fallback change; `git diff --check HEAD` reports no whitespace errors.

- [ ] **Step 6: Commit any verification-only fixes**

If Step 5 reveals a concrete issue, fix that issue and run Step 1 again. Then commit the fix:

```bash
git add <fixed files>
git commit -m "fix: align codex distribution verification"
```

Expected: no commit is needed when Steps 1-5 already pass.

---

## Self-Review

### Spec Coverage

- Nested Codex Plugin Bundle: Task 2 generates `plugins/agent-skills/.codex-plugin/plugin.json`.
- Repo-local marketplace: Task 2 generates `.agents/plugins/marketplace.json` with marketplace name `agent-skills` and local source `./plugins/agent-skills`.
- Prompt generation: Task 2 converts all `.claude/commands/*.md` to `codex/prompts/agent-skills-*.md`.
- Prompt namespace: Task 2 hardcodes the `agent-skills-` filename prefix.
- `ship` Host-Specific Rewrite: Task 2 replaces Claude-only agent mechanics with Codex `spawn_agent` and `wait_agent` flow.
- Agent role generation: Task 2 converts `agents/*.md`, excluding `agents/README.md`, to `codex/agents/*.toml`.
- Persona Role Names: Task 2 keeps `code-reviewer`, `security-auditor`, and `test-engineer` unprefixed.
- Bundle Mirrors: Task 2 mirrors root `skills/` and `hooks/` into `plugins/agent-skills/` as regular files.
- Dual-Host Hook: Task 3 updates `hooks/hooks.json` to use `${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}`.
- Sync behavior: Tasks 4-5 implement dry-run, conflict refusal, force backup, stderr status, and stdout JSON summary.
- Docs: Task 6 adds `docs/codex-setup.md` and README link with install order.
- Validation: Tasks 1, 4, 7, and 8 cover generator, sync, hooks, generated artifact drift, and CI.
- Non-goals: No task patches Codex core, registers native Codex slash commands, rewrites Source Assets in place, or claims marketplace install alone is complete.

### Placeholder Scan

This plan avoids deferred work markers, generic argument hints, and instructions that require an engineer to invent missing behavior. Each code-creating step provides complete file content or an exact replacement block.

### Type and Name Consistency

- Generator function names used by tests match exported implementation names: `parseFrontmatter`, `parseGeneratedAgentToml`, `renderPrompt`, `renderAgentRole`, `buildExpectedArtifacts`, `validateGeneratedArtifacts`.
- Generated path names match the spec: `codex/prompts/agent-skills-<name>.md`, `codex/agents/<name>.toml`, `plugins/agent-skills/.codex-plugin/plugin.json`.
- Sync script flags used by tests match implementation: `--dry-run` and `--force`.
- Marketplace selector remains `agent-skills@agent-skills`.
