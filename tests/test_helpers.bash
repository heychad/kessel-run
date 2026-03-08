#!/usr/bin/env bash
# Shared test helpers — source this in each .bats file.
# Sets up isolated temp dirs and sources loop.sh functions without running the main loop.

KESSEL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup_temp_project() {
    TEST_DIR="$(mktemp -d)"
    mkdir -p "$TEST_DIR/scripts/kessel-run"
    mkdir -p "$TEST_DIR/docs/specs"
    mkdir -p "$TEST_DIR/logs"
    cd "$TEST_DIR"

    # Minimal PRD.json
    cat > docs/specs/PRD.json << 'EOF'
{
  "items": [
    {"id": 1, "description": "Task one", "spec": "docs/specs/foo.md", "passes": false},
    {"id": 2, "description": "Task two", "spec": "docs/specs/foo.md", "passes": true},
    {"id": 3, "description": "Task three", "spec": "docs/specs/bar.md", "passes": false}
  ]
}
EOF

    # Minimal required files
    echo "prompt" > scripts/kessel-run/PROMPT.md
    echo '#!/usr/bin/env bash' > scripts/kessel-run/backpressure.sh
    chmod +x scripts/kessel-run/backpressure.sh
    echo "# Progress" > docs/PROGRESS.md
}

teardown_temp_project() {
    [ -n "${TEST_DIR:-}" ] && rm -rf "$TEST_DIR"
}

# Source only the function definitions from loop.sh (skip execution).
source_loop_functions() {
    # Set required globals that loop.sh expects
    export KESSEL_DIR="scripts/kessel-run"
    export KESSEL_MODEL="claude-sonnet-4-6"
    export SKIP_STUCK_THRESHOLD=0
    export STUCK_WARN_THRESHOLD=3
    export STUCK_FILE=".kessel-run-stuck"
    export STATE_FILE=".kessel-run-state"
    export LOG_DIR="logs"
    export LOG_FILE="logs/kessel-run.log"

    # ANSI colors (no-op for tests — strip in assertions)
    YELLOW='' WHITE='' DIM='' GREEN='' RED='' RESET='' BOLD='' CYAN='' ORANGE=''

    # Source functions by extracting them
    eval "$(sed -n '/^format_duration()/,/^$/p' "$KESSEL_ROOT/scripts/loop.sh")"
    eval "$(sed -n '/^read_prd_progress()/,/^}/p' "$KESSEL_ROOT/scripts/loop.sh")"
    eval "$(sed -n '/^get_stuck_warning()/,/^}/p' "$KESSEL_ROOT/scripts/loop.sh")"
    eval "$(sed -n '/^get_stuck_ids_for_prompt()/,/^}/p' "$KESSEL_ROOT/scripts/loop.sh")"
    eval "$(sed -n '/^write_state()/,/^}/p' "$KESSEL_ROOT/scripts/loop.sh")"
    eval "$(sed -n '/^read_state()/,/^}/p' "$KESSEL_ROOT/scripts/loop.sh")"
    eval "$(sed -n '/^cleanup_state()/,/^}/p' "$KESSEL_ROOT/scripts/loop.sh")"
    eval "$(sed -n '/^build_prompt()/,/^}/p' "$KESSEL_ROOT/scripts/loop.sh")"
    eval "$(sed -n '/^write_log_line()/,/^}/p' "$KESSEL_ROOT/scripts/loop.sh")"
    eval "$(sed -n '/^show_progress_from_cache()/,/^}/p' "$KESSEL_ROOT/scripts/loop.sh")"
}

# Wrapper for update_stuck_file — needs bash 4+ for declare -A.
# macOS ships bash 3.2; use homebrew bash 5 if available.
_BASH4="$({ command -v /opt/homebrew/bin/bash || command -v /usr/local/bin/bash || echo /bin/bash; } 2>/dev/null)"
update_stuck_file() {
    local failing_csv="$1"
    "$_BASH4" -c "
        set -euo pipefail
        STUCK_FILE='$STUCK_FILE'
        STUCK_WARN_THRESHOLD=$STUCK_WARN_THRESHOLD
        $(sed -n '/^update_stuck_file()/,/^}/p' "$KESSEL_ROOT/scripts/loop.sh")
        update_stuck_file '$failing_csv'
    "
}
