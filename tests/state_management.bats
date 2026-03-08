#!/usr/bin/env bats
# Tests for crash-resume state, logging, and build_prompt

load test_helpers

setup() {
    setup_temp_project
    source_loop_functions
}

teardown() {
    teardown_temp_project
}

# ── write_state / read_state ───────────────────────────────────────

@test "write_state: creates state file" {
    write_state 5 1700000000
    [ -f "$STATE_FILE" ]
    run cat "$STATE_FILE"
    [[ "$output" == *"parsec=5"* ]]
    [[ "$output" == *"start=1700000000"* ]]
}

@test "read_state: returns parsec and start time" {
    write_state 12 1700000500
    result=$(read_state)
    [ "$result" = "12 1700000500" ]
}

@test "read_state: returns zeros when no state file" {
    rm -f "$STATE_FILE"
    result=$(read_state)
    [ "$result" = "0 0" ]
}

@test "cleanup_state: removes state file" {
    write_state 5 1700000000
    [ -f "$STATE_FILE" ]
    cleanup_state
    [ ! -f "$STATE_FILE" ]
}

@test "write_state: overwrites existing state" {
    write_state 5 1700000000
    write_state 10 1700001000
    result=$(read_state)
    [ "$result" = "10 1700001000" ]
}

# ── write_log_line ─────────────────────────────────────────────────

@test "write_log_line: appends structured line" {
    write_log_line 1 5 10 120 "0.5" 8 2 ""
    [ -f "$LOG_FILE" ]
    run cat "$LOG_FILE"
    [[ "$output" == *"parsec=1"* ]]
    [[ "$output" == *"passed=5"* ]]
    [[ "$output" == *"total=10"* ]]
    [[ "$output" == *"duration=120s"* ]]
    [[ "$output" == *"velocity=0.5"* ]]
}

@test "write_log_line: includes stuck IDs when present" {
    write_log_line 3 5 10 90 "1.0" 6 1 "7,8"
    run cat "$LOG_FILE"
    [[ "$output" == *"stuck=#7,#8"* ]]
}

@test "write_log_line: no stuck field when empty" {
    write_log_line 1 5 10 60 "1.0" 6 1 ""
    run cat "$LOG_FILE"
    [[ "$output" != *"stuck="* ]]
}

@test "write_log_line: multiple lines accumulate" {
    write_log_line 1 1 10 60 "1.0" 10 1 ""
    write_log_line 2 3 10 55 "1.5" 8 2 ""
    write_log_line 3 5 10 50 "1.7" 6 2 ""
    line_count=$(wc -l < "$LOG_FILE" | tr -d ' ')
    [ "$line_count" -eq 3 ]
}

# ── build_prompt ───────────────────────────────────────────────────

@test "build_prompt: outputs PROMPT.md content" {
    echo "Test prompt content" > scripts/kessel-run/PROMPT.md
    result=$(build_prompt)
    [[ "$result" == *"Test prompt content"* ]]
}

@test "build_prompt: injects stuck IDs when present" {
    for i in 1 2 3; do update_stuck_file "42"; done
    result=$(build_prompt)
    [[ "$result" == *"42"* ]]
    [[ "$result" == *"Deprioritize"* ]]
}

@test "build_prompt: injects skip comment for high-stuck items" {
    SKIP_STUCK_THRESHOLD=2
    update_stuck_file "99"
    update_stuck_file "99"
    result=$(build_prompt)
    [[ "$result" == *"SKIP"* ]]
    [[ "$result" == *"99"* ]]
}

@test "build_prompt: no injection when nothing is stuck" {
    rm -f "$STUCK_FILE"
    result=$(build_prompt)
    [[ "$result" != *"KESSEL-RUN"* ]]
}

# ── show_progress_from_cache ───────────────────────────────────────

@test "show_progress_from_cache: shows item counts" {
    PRD_PASSING=5
    PRD_TOTAL=10
    result=$(show_progress_from_cache)
    [[ "$result" == *"5"* ]]
    [[ "$result" == *"10"* ]]
}

@test "show_progress_from_cache: handles zero total" {
    PRD_PASSING=0
    PRD_TOTAL=0
    result=$(show_progress_from_cache)
    [[ "$result" == *"No PRD items"* ]]
}

@test "show_progress_from_cache: shows <1% for small progress" {
    PRD_PASSING=1
    PRD_TOTAL=200
    result=$(show_progress_from_cache)
    [[ "$result" == *"<1%"* ]]
}

@test "show_progress_from_cache: all passing shows 100%" {
    PRD_PASSING=10
    PRD_TOTAL=10
    result=$(show_progress_from_cache)
    [[ "$result" == *"100%"* ]]
}
