#!/bin/bash
# session-start-codex-test.sh - Tests for the Codex SessionStart hook JSON payload

set -euo pipefail

tmp_payload="$(mktemp)"
trap 'rm -f "$tmp_payload"' EXIT

payload="$(bash hooks/session-start-codex.sh)"
printf '%s' "$payload" > "$tmp_payload"

PAYLOAD_PATH="$tmp_payload" node <<'NODE'
const fs = require('fs');

const payload = JSON.parse(fs.readFileSync(process.env.PAYLOAD_PATH, 'utf8'));
const hookSpecificOutput = payload.hookSpecificOutput;

if (!hookSpecificOutput || typeof hookSpecificOutput !== 'object') {
  throw new Error('missing hookSpecificOutput object');
}

if (hookSpecificOutput.hookEventName !== 'SessionStart') {
  throw new Error(`expected SessionStart hookEventName, got ${hookSpecificOutput.hookEventName}`);
}

if (typeof hookSpecificOutput.additionalContext !== 'string') {
  throw new Error('missing additionalContext string');
}

if (!hookSpecificOutput.additionalContext.includes('agent-skills loaded.')) {
  throw new Error('additionalContext is missing startup preface');
}

if (!hookSpecificOutput.additionalContext.includes('# Using Agent Skills')) {
  throw new Error('additionalContext is missing using-agent-skills content');
}

console.log('session-start Codex JSON payload OK');
NODE
