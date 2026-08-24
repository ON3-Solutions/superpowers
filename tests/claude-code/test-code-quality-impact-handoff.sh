#!/usr/bin/env bash
# Tests the actual map handoff to the SDD code-quality review consumer.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONSUMER="$PLUGIN_DIR/skills/subagent-driven-development/code-quality-reviewer-prompt.md"
REVIEW_TEMPLATE="$PLUGIN_DIR/skills/requesting-code-review/code-reviewer.md"

MAP='| Impact | Evidence file:line | Assessment | Decision or required change | Test |
| Indirect consumer | src/operations/employee-audit.js:6 | Harmful | Migrate to status | Integration test |'
RENDERED=$(mktemp)
trap 'rm -f "$RENDERED"' EXIT

awk -v map="$MAP" '{ gsub(/\{CHANGE_IMPACT_MAP\}/, map); print }' "$CONSUMER" > "$RENDERED"

if grep -Fq '| Impact | Evidence file:line | Assessment | Decision or required change | Test |' "$RENDERED" \
    && grep -Fq '| Indirect consumer | src/operations/employee-audit.js:6 | Harmful | Migrate to status | Integration test |' "$RENDERED" \
    && ! grep -Fq '{CHANGE_IMPACT_MAP}' "$RENDERED"; then
    echo "[PASS] The SDD consumer receives the completed reconciled map"
else
    echo "[FAIL] The SDD consumer did not receive the map content"
    exit 1
fi

if grep -Fq '## Change Impact Map' "$REVIEW_TEMPLATE" \
    && grep -Fq '{CHANGE_IMPACT_MAP}' "$REVIEW_TEMPLATE"; then
    echo "[PASS] The review template consumes the received map"
else
    echo "[FAIL] The review template does not expose the map to the reviewer"
    exit 1
fi
