"use strict";

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const { readFileSync } = require("node:fs");
const test = require("node:test");

const manifestPaths = [
  "plugin.json",
  ".codex-plugin/plugin.json",
  ".claude-plugin/plugin.json",
  ".claude-plugin/marketplace.json",
  ".agents/plugins/marketplace.json",
];

function readManifestVersion(manifestPath) {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  return manifest.version ?? manifest.plugins?.[0]?.version;
}

function releaseBase(version) {
  return typeof version === "string" ? version.split("+", 1)[0] : version;
}

test("all plugin manifests use the latest release tag as their base version", () => {
  const expectedVersion = execFileSync(
    "git",
    ["describe", "--tags", "--abbrev=0"],
    { encoding: "utf8" },
  ).trim();

  for (const manifestPath of manifestPaths) {
    assert.equal(
      releaseBase(readManifestVersion(manifestPath)),
      expectedVersion,
      `${manifestPath} must use release base ${expectedVersion}`,
    );
  }
});
