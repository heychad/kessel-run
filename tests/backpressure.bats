#!/usr/bin/env bats
# Tests for backpressure.sh — quality gate auto-detection

KESSEL_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    cp "$KESSEL_ROOT/templates/backpressure.sh" backpressure.sh
    chmod +x backpressure.sh
}

teardown() {
    [ -n "${TEST_DIR:-}" ] && rm -rf "$TEST_DIR"
}

@test "backpressure: exits 0 with no config files (no checks to run)" {
    run bash backpressure.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALL GREEN"* ]]
}

@test "backpressure: detects tsconfig.json → would run tsc" {
    # Create tsconfig but ensure npx tsc fails (no node_modules)
    echo '{}' > tsconfig.json
    run bash backpressure.sh
    # Should fail because tsc isn't available / project isn't set up
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL: tsc"* ]]
}

@test "backpressure: detects pyproject.toml → would run pytest" {
    echo '[tool.pytest]' > pyproject.toml
    run bash backpressure.sh
    # pytest likely not available or no tests — should fail
    [ "$status" -eq 1 ]
}

@test "backpressure: detects Cargo.toml → would run cargo test" {
    echo '[package]' > Cargo.toml
    run bash backpressure.sh
    # cargo test should fail (not a real Rust project)
    [ "$status" -eq 1 ]
}

@test "backpressure: check function captures output on failure" {
    # Create a mini backpressure that always fails
    cat > test_bp.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
FAILURES="" ; EXIT_CODE=0
check() {
  local name="$1"; shift; local output
  if output=$("$@" 2>&1); then return 0; fi
  FAILURES+=$'\n'"--- FAIL: $name ---"$'\n'"$(echo "$output" | head -30)"$'\n'
  EXIT_CODE=1
}
check "false-test" false
if [ $EXIT_CODE -eq 0 ]; then echo "ALL GREEN"
else echo "$FAILURES" | head -100; fi
exit $EXIT_CODE
EOF
    chmod +x test_bp.sh
    run bash test_bp.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL: false-test"* ]]
}

@test "backpressure: check function passes on success" {
    cat > test_bp.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
FAILURES="" ; EXIT_CODE=0
check() {
  local name="$1"; shift; local output
  if output=$("$@" 2>&1); then return 0; fi
  FAILURES+=$'\n'"--- FAIL: $name ---"$'\n'"$(echo "$output" | head -30)"$'\n'
  EXIT_CODE=1
}
check "true-test" true
if [ $EXIT_CODE -eq 0 ]; then echo "ALL GREEN"
else echo "$FAILURES" | head -100; fi
exit $EXIT_CODE
EOF
    chmod +x test_bp.sh
    run bash test_bp.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALL GREEN"* ]]
}
