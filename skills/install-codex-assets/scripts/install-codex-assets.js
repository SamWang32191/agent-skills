#!/usr/bin/env node

const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");

const args = process.argv.slice(2);
const options = {
  dryRun: false,
  force: false,
  codexHome: process.env.CODEX_HOME || path.join(os.homedir(), ".codex"),
  sourceRoot: null,
};

function usage() {
  process.stderr.write(`Usage: install-codex-assets.js [options]

Copy this repository's Codex assets into a Codex home directory.

Options:
  --dry-run              Report planned changes without writing files.
  --force                Replace conflicting targets.
  --codex-home PATH      Target Codex home. Defaults to CODEX_HOME or ~/.codex.
  --source-root PATH     Repository or plugin root. Inferred from this script when omitted.
  -h, --help             Show this help.

Installs:
  agents/*.toml              -> $CODEX_HOME/agents/ (copy)
  .claude/commands/*.md      -> $CODEX_HOME/prompts/ (copy)
`);
}

for (let index = 0; index < args.length; index += 1) {
  const arg = args[index];
  switch (arg) {
    case "--dry-run":
      options.dryRun = true;
      break;
    case "--force":
      options.force = true;
      break;
    case "--codex-home":
      index += 1;
      if (index >= args.length) {
        process.stderr.write("Missing value for --codex-home\n");
        process.exit(2);
      }
      options.codexHome = args[index];
      break;
    case "--source-root":
      index += 1;
      if (index >= args.length) {
        process.stderr.write("Missing value for --source-root\n");
        process.exit(2);
      }
      options.sourceRoot = args[index];
      break;
    case "-h":
    case "--help":
      usage();
      process.exit(0);
      break;
    default:
      process.stderr.write(`Unknown option: ${arg}\n`);
      usage();
      process.exit(2);
  }
}

function hasAssetSources(candidateRoot) {
  return (
    fs.existsSync(path.join(candidateRoot, "agents")) &&
    fs.existsSync(path.join(candidateRoot, ".claude", "commands"))
  );
}

function inferSourceRoot(startDir) {
  let current = path.resolve(startDir);

  while (true) {
    if (hasAssetSources(current)) {
      return current;
    }

    const parent = path.dirname(current);
    if (parent === current) {
      return null;
    }
    current = parent;
  }
}

options.codexHome = path.resolve(options.codexHome);
options.sourceRoot = options.sourceRoot
  ? path.resolve(options.sourceRoot)
  : inferSourceRoot(__dirname);

if (!options.sourceRoot) {
  process.stderr.write("Could not infer source root. Re-run with --source-root /path/to/agent-skills\n");
  process.exit(2);
}

if (!hasAssetSources(options.sourceRoot)) {
  process.stderr.write(`Source root is missing agents/ or .claude/commands/: ${options.sourceRoot}\n`);
  process.exit(2);
}

const agentsTargetDir = path.join(options.codexHome, "agents");
const promptsTargetDir = path.join(options.codexHome, "prompts");
const agentRecords = [];
const promptRecords = [];
const conflicts = [];

function addRecord(group, source, target, action) {
  const record = { source, target, action };
  if (group === "agents") {
    agentRecords.push(record);
  } else {
    promptRecords.push(record);
  }
}

function addConflict(source, target, reason) {
  conflicts.push({ source, target, reason });
}

function lstatOrNull(filePath) {
  try {
    return fs.lstatSync(filePath);
  } catch (error) {
    if (error && error.code === "ENOENT") {
      return null;
    }
    throw error;
  }
}

function fileHash(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function sameContentFile(source, target, stats) {
  if (!stats || stats.isDirectory()) {
    return false;
  }

  try {
    const targetStats = fs.statSync(target);
    if (!targetStats.isFile()) {
      return false;
    }
    return fileHash(source) === fileHash(target);
  } catch (error) {
    if (error && error.code === "ENOENT") {
      return false;
    }
    throw error;
  }
}

function installOne(group, source, target) {
  const stats = lstatOrNull(target);
  let replacing = false;

  if (stats) {
    const targetAlreadyMatches = sameContentFile(source, target, stats);
    const symlinkNeedsCopy = stats.isSymbolicLink() && targetAlreadyMatches;

    if (targetAlreadyMatches && !symlinkNeedsCopy) {
      addRecord(group, source, target, "unchanged");
      return;
    }

    if (stats.isDirectory() && !stats.isSymbolicLink()) {
      addConflict(source, target, "target directory exists");
      return;
    }

    if (!options.force && (!symlinkNeedsCopy || !targetAlreadyMatches)) {
      addConflict(source, target, "target exists");
      return;
    }

    replacing = true;
  }

  if (options.dryRun) {
    addRecord(group, source, target, replacing ? "would-overwrite-copy" : "would-copy");
    return;
  }

  if (replacing) {
    fs.rmSync(target, { force: true });
  }

  fs.copyFileSync(source, target);
  addRecord(group, source, target, replacing ? "overwritten-copy" : "copied");
}

function listFiles(directory, extension) {
  try {
    return fs
      .readdirSync(directory, { withFileTypes: true })
      .filter((entry) => entry.isFile() && entry.name.endsWith(extension))
      .map((entry) => path.join(directory, entry.name))
      .sort((left, right) => path.basename(left).localeCompare(path.basename(right)));
  } catch (error) {
    if (error && error.code === "ENOENT") {
      return [];
    }
    throw error;
  }
}

process.stderr.write(`Installing Codex assets from ${options.sourceRoot}\n`);
process.stderr.write(`Target Codex home: ${options.codexHome}\n`);
process.stderr.write("Mode: copy\n");

if (!options.dryRun) {
  fs.mkdirSync(agentsTargetDir, { recursive: true });
  fs.mkdirSync(promptsTargetDir, { recursive: true });
}

const agentSourceDir = path.join(options.sourceRoot, "agents");
const promptSourceDir = path.join(options.sourceRoot, ".claude", "commands");
const agentSources = listFiles(agentSourceDir, ".toml");
const promptSources = listFiles(promptSourceDir, ".md");

if (agentSources.length === 0) {
  addConflict(path.join(agentSourceDir, "*.toml"), agentsTargetDir, "no agent toml files found");
}

if (promptSources.length === 0) {
  addConflict(path.join(promptSourceDir, "*.md"), promptsTargetDir, "no prompt markdown files found");
}

for (const source of agentSources) {
  installOne("agents", source, path.join(agentsTargetDir, path.basename(source)));
}

for (const source of promptSources) {
  installOne("prompts", source, path.join(promptsTargetDir, path.basename(source)));
}

if (conflicts.length > 0) {
  process.stderr.write("Conflicts found. Re-run with --force only if replacing these targets is intended.\n");
}

const status = conflicts.length > 0 ? "failed" : "success";
process.stdout.write(
  `${JSON.stringify({
    status,
    mode: "copy",
    dryRun: options.dryRun,
    force: options.force,
    sourceRoot: options.sourceRoot,
    codexHome: options.codexHome,
    agents: agentRecords,
    prompts: promptRecords,
    conflicts,
  })}\n`
);

if (conflicts.length > 0) {
  process.exit(1);
}
