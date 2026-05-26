#!/usr/bin/env node

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

import {
  buildExpectedArtifacts,
  parseFrontmatter,
  parseGeneratedAgentToml,
  renderAgentRole,
  renderPrompt,
  validateGeneratedArtifacts,
} from './codex-distribution.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

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

test('renderPrompt throws for unknown command names', () => {
  const source = [
    '---',
    'description: Unknown command',
    '---',
    '',
    'Unknown command prompt.',
    '',
  ].join('\n');

  assert.throws(
    () => renderPrompt('.claude/commands/unknown.md', source),
    /unknown\.md: missing command argument hint mapping for unknown/,
  );
});

test('renderPrompt throws for prototype-key command names', () => {
  const source = [
    '---',
    'description: Prototype key command',
    '---',
    '',
    'Should not be allowed.',
    '',
  ].join('\n');

  assert.throws(
    () => renderPrompt('.claude/commands/toString.md', source),
    /toString\.md: missing command argument hint mapping for toString/,
  );

  assert.throws(
    () => renderPrompt('.claude/commands/constructor.md', source),
    /constructor\.md: missing command argument hint mapping for constructor/,
  );
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
    fs.mkdirSync(path.join(tmp, 'codex/agents'), { recursive: true });
    fs.writeFileSync(path.join(tmp, 'codex/prompts/agent-skills-spec.md'), 'stale\n');
    fs.writeFileSync(path.join(tmp, 'codex/agents/extra.toml'), 'ignore me\n');

    const expected = new Map([
      ['codex/prompts/agent-skills-spec.md', 'fresh\n'],
      ['codex/agents/code-reviewer.toml', 'role\n'],
    ]);

    const result = validateGeneratedArtifacts(tmp, expected, ['codex/prompts', 'codex/agents']);
    assert.equal(result.ok, false);
    assert.deepEqual(result.drifted, ['codex/prompts/agent-skills-spec.md']);
    assert.deepEqual(result.missing, ['codex/agents/code-reviewer.toml']);
    assert.deepEqual(result.extra, ['codex/agents/extra.toml']);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
