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
    value = value.replace(/^[']|[']$/g, '').replace(/^["]|["]$/g, '');
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
