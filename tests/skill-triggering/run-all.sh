#!/usr/bin/env bash
# Run all skill triggering tests
# Usage: ./run-all.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/prompts"

SKILLS=(
    "systematic-debugging"
    "test-driven-development"
    "writing-plans"
    "dispatching-parallel-agents"
    "executing-plans"
    "requesting-code-review"
    "analyzing-change-impact"
)

echo "=== Running Skill Triggering Tests ==="
echo ""

PASSED=0
FAILED=0
INFRASTRUCTURE=0
RUNNER_ERRORS=0
RESULTS=()

for skill in "${SKILLS[@]}"; do
    prompt_file="$PROMPTS_DIR/${skill}.txt"

    if [ ! -f "$prompt_file" ]; then
        echo "⚠️  SKIP: No prompt file for $skill"
        continue
    fi

    echo "Testing: $skill"

    set +e
    "$SCRIPT_DIR/run-test.sh" "$skill" "$prompt_file" 3 2>&1 | tee /tmp/skill-test-$skill.log
    test_exit=${PIPESTATUS[0]}
    set -e

    if [ "$test_exit" -eq 0 ]; then
        PASSED=$((PASSED + 1))
        RESULTS+=("✅ $skill")
    elif [ "$test_exit" -eq 2 ]; then
        INFRASTRUCTURE=$((INFRASTRUCTURE + 1))
        RESULTS+=("⚠️ $skill (infrastructure)")
    elif [ "$test_exit" -eq 3 ]; then
        RUNNER_ERRORS=$((RUNNER_ERRORS + 1))
        RESULTS+=("❌ $skill (runner error)")
    else
        FAILED=$((FAILED + 1))
        RESULTS+=("❌ $skill")
    fi

    echo ""
    echo "---"
    echo ""
done

echo ""
echo "=== Summary ==="
for result in "${RESULTS[@]}"; do
    echo "  $result"
done
echo ""
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "Infrastructure: $INFRASTRUCTURE"
echo "Runner errors: $RUNNER_ERRORS"

if [ $FAILED -gt 0 ] || [ $INFRASTRUCTURE -gt 0 ] || [ $RUNNER_ERRORS -gt 0 ]; then
    exit 1
fi
