#!/usr/bin/env bash
# Behavioral test: the skill maps and reconciles impacts from a contract.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Test: analyzing-change-impact"
echo "========================================"

if ! command -v claude >/dev/null 2>&1; then
    echo "ERROR: Claude Code CLI not found"
    exit 1
fi

TEST_PROJECT=$(create_test_project)
trap "cleanup_test_project $TEST_PROJECT" EXIT
mkdir -p "$TEST_PROJECT/src/contracts" "$TEST_PROJECT/src/services" \
    "$TEST_PROJECT/src/operations" "$TEST_PROJECT/src/api" \
    "$TEST_PROJECT/src/notifications" "$TEST_PROJECT/docs"

cat > "$TEST_PROJECT/src/contracts/employee.js" <<'EOF'
export function toEmployeeProfile(record) {
  return {
    id: record.id,
    name: record.name,
    isActive: record.isActive,
  };
}
EOF

cat > "$TEST_PROJECT/src/services/employee-service.js" <<'EOF'
import { toEmployeeProfile } from "../contracts/employee.js";

export function findEmployee(id) {
  return toEmployeeProfile({ id, name: "Ana", isActive: true });
}
EOF

cat > "$TEST_PROJECT/src/operations/employee-audit.js" <<'EOF'
import { findEmployee } from "../services/employee-service.js";

export function buildAuditEvent(id) {
  const employee = findEmployee(id);
  return {
    type: employee.isActive ? "employee-enabled" : "employee-disabled",
    employeeId: employee.id,
  };
}
EOF

cat > "$TEST_PROJECT/src/api/employee-response.js" <<'EOF'
import { findEmployee } from "../services/employee-service.js";

export function getEmployeeResponse(id) {
  const employee = findEmployee(id);
  return { id: employee.id, name: employee.name, active: employee.isActive };
}
EOF

git init --quiet "$TEST_PROJECT"
git -C "$TEST_PROJECT" config user.email "test@example.com"
git -C "$TEST_PROJECT" config user.name "Test Runner"
git -C "$TEST_PROJECT" add src
git -C "$TEST_PROJECT" commit --quiet -m "feat: expose employee profile"
BASE_SHA=$(git -C "$TEST_PROJECT" rev-parse HEAD)

cat > "$TEST_PROJECT/src/contracts/employee.js" <<'EOF'
export function toEmployeeProfile(record) {
  return {
    id: record.id,
    name: record.name,
    status: record.status,
  };
}
EOF

cat > "$TEST_PROJECT/src/api/employee-response.js" <<'EOF'
import { findEmployee } from "../services/employee-service.js";

export function getEmployeeResponse(id) {
  const employee = findEmployee(id);
  return { id: employee.id, name: employee.name, status: employee.status };
}
EOF

cat > "$TEST_PROJECT/src/notifications/employee-notifier.js" <<'EOF'
import { findEmployee } from "../services/employee-service.js";

export function buildEmployeeNotification(id) {
  const employee = findEmployee(id);
  return {
    type: employee.status === "active" ? "employee-active" : "employee-inactive",
    employeeId: employee.id,
  };
}
EOF

cat > "$TEST_PROJECT/docs/release-note.md" <<'EOF'
# Employee profile

The contract now exposes status.
EOF

git -C "$TEST_PROJECT" add src docs
git -C "$TEST_PROJECT" commit --quiet -m "feat: migrate part of profile to status"
HEAD_SHA=$(git -C "$TEST_PROJECT" rev-parse HEAD)

OUTPUT_FILE="$TEST_PROJECT/claude-output.txt"
PROMPT="Repository: $TEST_PROJECT. Approved change: toEmployeeProfile will replace isActive with status, using the values active and inactive. Base state: $BASE_SHA. Current diff: $BASE_SHA..$HEAD_SHA. Before implementing, analyze the impact of the change and reconcile it with the diff. Do not modify files."

is_known_weekly_limit() {
    grep -qE "^You've hit your weekly limit · resets [A-Z][a-z]{2} [0-9]{1,2}, [0-9]+(am|pm) \\([^)]+\\)\$" "$1"
}

echo "Running Claude in the temporary project..."
cd "$TEST_PROJECT"
set +e
timeout 600 claude -p "$PROMPT" \
    --plugin-dir "$PLUGIN_DIR" \
    --permission-mode bypassPermissions 2>&1 | tee "$OUTPUT_FILE"
CLAUDE_EXIT=${PIPESTATUS[0]}
set -e

if [ "$CLAUDE_EXIT" -eq 124 ] \
    || { [ "$CLAUDE_EXIT" -ne 0 ] && is_known_weekly_limit "$OUTPUT_FILE"; }; then
    echo "STATUS: INFRASTRUCTURE (Claude did not run the scenario; exit $CLAUDE_EXIT)"
    exit 2
fi

if [ "$CLAUDE_EXIT" -ne 0 ]; then
    echo "STATUS: RUNNER_ERROR (Claude exited with status $CLAUDE_EXIT)"
    exit 3
fi

SESSION_DIR="$HOME/.claude/projects/$(pwd -P | sed 's|[^a-zA-Z0-9]|-|g')"
SESSION_FILE=$(ls -t "$SESSION_DIR"/*.jsonl 2>/dev/null | head -1 || true)
MAP_OUTPUT="$TEST_PROJECT/impact-map.txt"
INFERENCE_OUTPUT="$TEST_PROJECT/pending-inferences.txt"
RECONCILIATION_OUTPUT="$TEST_PROJECT/diff-reconciliation.txt"
awk '/^##[[:space:]]+Impact Map/{inside=1; next} /^##[[:space:]]+Pending Inferences/{exit} inside{print}' "$OUTPUT_FILE" > "$MAP_OUTPUT"
awk '/^##[[:space:]]+Pending Inferences/{inside=1; next} /^##[[:space:]]+Post-Diff Reconciliation/{exit} inside{print}' "$OUTPUT_FILE" > "$INFERENCE_OUTPUT"
awk '/^##[[:space:]]+Post-Diff Reconciliation/{inside=1; next} inside{print}' "$OUTPUT_FILE" > "$RECONCILIATION_OUTPUT"
FAILED=0

assert_map_entry() {
    local file_line="$1"
    local name="$2"

    if awk -F '|' -v evidence="$file_line" '
        function trim(value) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); return value }
        /^\|/ && NF == 7 && index(trim($3), evidence) > 0 && trim($2) != "" && trim($4) != "" && trim($5) != "" && trim($6) != "" { found = 1 }
        END { exit !found }
    ' "$MAP_OUTPUT"; then
        echo "  [PASS] $name has evidence, an assessment, a decision, and a test"
    else
        echo "  [FAIL] $name does not fill the complete map interface"
        FAILED=$((FAILED + 1))
    fi
}

assert_reconciliation() {
    local file_line="$1"
    local status_pattern="$2"
    local name="$3"

    if awk -F '|' -v evidence="$file_line" -v status_pattern="$status_pattern" '
        function trim(value) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); return value }
        /^\|/ && NF == 7 && index(trim($4), evidence) > 0 && tolower(trim($3)) ~ status_pattern && trim($5) != "" && trim($6) != "" { found = 1 }
        END { exit !found }
    ' "$RECONCILIATION_OUTPUT"; then
        echo "  [PASS] $name was reconciled"
    else
        echo "  [FAIL] $name was not reconciled with the diff"
        FAILED=$((FAILED + 1))
    fi
}

assert_not_applicable() {
    if awk -F '|' '
        function trim(value) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); return value }
        /^\|/ && NF == 7 && index(trim($4), "docs/release-note.md:1") > 0 \
            && tolower(trim($3)) ~ /not applicable/ \
            && tolower(trim($6)) ~ /(documentation|release note|does not change|unrelated)/ { found = 1 }
        END { exit !found }
    ' "$RECONCILIATION_OUTPUT"; then
        echo "  [PASS] The not-applicable file has a justification"
    else
        echo "  [FAIL] The not-applicable file has no justification"
        FAILED=$((FAILED + 1))
    fi
}

echo "Checking the analysis..."
if [ -z "$SESSION_FILE" ] || ! grep -q '"skill":"superpowers:analyzing-change-impact"' "$SESSION_FILE"; then
    echo "  [FAIL] The analyzing-change-impact skill was not invoked"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] The analyzing-change-impact skill was invoked"
fi

assert_map_entry 'src/contracts/employee.js:5' "The local contract"
assert_map_entry 'src/services/employee-service.js:4' "The direct consumer"
assert_map_entry 'src/operations/employee-audit.js:6' "The indirect consumer"
assert_map_entry 'src/api/employee-response.js:5' "The API adapter"

if grep -qiE '^##[[:space:]]+Pending Inferences' "$OUTPUT_FILE" \
    && awk -F '|' '
        function trim(value) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); return value }
        /^\|/ && NF == 5 && tolower(trim($2)) ~ /historical data|persisted data/ \
            && tolower(trim($3)) ~ /not found|no evidence|pending/ && trim($4) != "" { found = 1 }
        END { exit !found }
    ' "$INFERENCE_OUTPUT"; then
    echo "  [PASS] The historical-data inference is separate from evidence"
else
    echo "  [FAIL] The historical-data inference was not separated from evidence"
    FAILED=$((FAILED + 1))
fi

if grep -qiE '^##[[:space:]]+Post-Diff Reconciliation' "$OUTPUT_FILE"; then
    echo "  [PASS] The post-diff reconciliation section was produced"
else
    echo "  [FAIL] The post-diff reconciliation section was omitted"
    FAILED=$((FAILED + 1))
fi

assert_reconciliation 'src/contracts/employee.js:5' 'covered|implemented' "The changed contract"
assert_reconciliation 'src/api/employee-response.js:5' 'covered|implemented' "The changed adapter"
assert_reconciliation 'src/services/employee-service.js:4' 'omitted|not covered|pending' "The unchanged direct consumer"
assert_reconciliation 'src/operations/employee-audit.js:6' 'omitted|not covered|pending' "The unchanged indirect consumer"
assert_reconciliation 'src/notifications/employee-notifier.js:6' 'discovered|new' "The consumer introduced by the diff"
assert_not_applicable

if [ "$FAILED" -gt 0 ]; then
    echo "STATUS: FAILED ($FAILED checks)"
    exit 1
fi

echo "STATUS: PASSED"
