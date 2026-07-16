#!/usr/bin/env node

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "install-codex-assets-"));

try {
  const sourceRoot = path.join(tempRoot, "source");
  const codexHome = path.join(tempRoot, "codex");
  const agentSource = path.join(sourceRoot, "agents", "example.toml");
  const installer = path.join(__dirname, "install-codex-assets.js");
  fs.mkdirSync(path.dirname(agentSource), { recursive: true });
  fs.writeFileSync(agentSource, 'name = "example"\n');

  const result = spawnSync(
    process.execPath,
    [installer, "--source-root", sourceRoot, "--codex-home", codexHome],
    { encoding: "utf8" }
  );

  assert.strictEqual(result.status, 0, result.stderr);
  const report = JSON.parse(result.stdout);
  assert.strictEqual("prompts" in report, false);
  assert.strictEqual(fs.existsSync(path.join(codexHome, "prompts")), false);
  assert.strictEqual(fs.readFileSync(path.join(codexHome, "agents", "example.toml"), "utf8"), 'name = "example"\n');

  const customPrompt = path.join(codexHome, "prompts", "custom.md");
  fs.mkdirSync(path.dirname(customPrompt), { recursive: true });
  fs.writeFileSync(customPrompt, "keep me\n");
  const preserveResult = spawnSync(
    process.execPath,
    [installer, "--source-root", sourceRoot, "--codex-home", codexHome],
    { encoding: "utf8" }
  );

  assert.strictEqual(preserveResult.status, 0, preserveResult.stderr);
  assert.strictEqual(fs.readFileSync(customPrompt, "utf8"), "keep me\n");
} finally {
  fs.rmSync(tempRoot, { recursive: true, force: true });
}
