#!/usr/bin/env bats
# Tests for loop.sh pre-flight checks (run loop.sh and expect early exit on missing files)

KESSEL_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    mkdir -p scripts/kessel-run docs/specs logs
}

teardown() {
    [ -n "${TEST_DIR:-}" ] && rm -rf "$TEST_DIR"
}

@test "preflight: fails when PROMPT.md missing" {
    echo '{"items":[]}' > docs/specs/PRD.json
    echo "# bp" > scripts/kessel-run/backpressure.sh
    echo "# progress" > docs/PROGRESS.md
    # No PROMPT.md
    run bash "$KESSEL_ROOT/scripts/loop.sh" 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing"* ]]
}

@test "preflight: fails when PRD.json missing" {
    echo "prompt" > scripts/kessel-run/PROMPT.md
    echo "# bp" > scripts/kessel-run/backpressure.sh
    echo "# progress" > docs/PROGRESS.md
    # No PRD.json
    run bash "$KESSEL_ROOT/scripts/loop.sh" 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing"* ]]
}

@test "preflight: fails when backpressure.sh missing" {
    echo "prompt" > scripts/kessel-run/PROMPT.md
    echo '{"items":[]}' > docs/specs/PRD.json
    echo "# progress" > docs/PROGRESS.md
    # No backpressure.sh
    run bash "$KESSEL_ROOT/scripts/loop.sh" 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing"* ]]
}

@test "preflight: fails when PROGRESS.md missing" {
    echo "prompt" > scripts/kessel-run/PROMPT.md
    echo '{"items":[]}' > docs/specs/PRD.json
    echo "# bp" > scripts/kessel-run/backpressure.sh
    # No PROGRESS.md
    run bash "$KESSEL_ROOT/scripts/loop.sh" 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing"* ]]
}

@test "preflight: passes when all files present" {
    echo "prompt" > scripts/kessel-run/PROMPT.md
    echo '{"items":[]}' > docs/specs/PRD.json
    echo "# bp" > scripts/kessel-run/backpressure.sh
    echo "# progress" > docs/PROGRESS.md
    # Run loop.sh but kill after 3 seconds — we just check preflight output
    run bash -c "bash '$KESSEL_ROOT/scripts/loop.sh' 1 2>&1 & PID=\$!; sleep 3; kill \$PID 2>/dev/null; wait \$PID 2>/dev/null; exit 0"
    # Should NOT contain "Missing" or "Pre-flight failed"
    [[ "$output" != *"Pre-flight failed"* ]]
}
