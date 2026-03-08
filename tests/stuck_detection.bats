#!/usr/bin/env bats
# Tests for stuck detection: update_stuck_file, get_stuck_warning, get_stuck_ids_for_prompt

load test_helpers

setup() {
    setup_temp_project
    source_loop_functions
}

teardown() {
    teardown_temp_project
}

# ── update_stuck_file ──────────────────────────────────────────────

@test "update_stuck_file: first failure creates file with count 1" {
    update_stuck_file "1,3"
    [ -f "$STUCK_FILE" ]
    run grep "^1 " "$STUCK_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == "1 1" ]]
}

@test "update_stuck_file: consecutive failures increment counter" {
    update_stuck_file "1"
    update_stuck_file "1"
    update_stuck_file "1"
    run grep "^1 " "$STUCK_FILE"
    [[ "$output" == "1 3" ]]
}

@test "update_stuck_file: passing item is removed from stuck file" {
    # Item 1 fails twice
    update_stuck_file "1"
    update_stuck_file "1"
    # Item 1 passes (not in failing list)
    update_stuck_file ""
    # Should be empty or not contain item 1
    if [ -f "$STUCK_FILE" ]; then
        run grep "^1 " "$STUCK_FILE"
        [ "$status" -ne 0 ]
    fi
}

@test "update_stuck_file: multiple items tracked independently" {
    update_stuck_file "1,2"
    update_stuck_file "1,2"
    update_stuck_file "1"    # item 2 passes, item 1 still failing
    run grep "^1 " "$STUCK_FILE"
    [[ "$output" == "1 3" ]]
    run grep "^2 " "$STUCK_FILE"
    [ "$status" -ne 0 ]   # item 2 should be gone
}

@test "update_stuck_file: empty failing CSV clears all" {
    update_stuck_file "1,2,3"
    update_stuck_file ""
    # File should exist but be empty
    [ ! -s "$STUCK_FILE" ]
}

# ── get_stuck_warning ──────────────────────────────────────────────

@test "get_stuck_warning: no warning below threshold" {
    update_stuck_file "1"
    update_stuck_file "1"
    result=$(get_stuck_warning)
    [ -z "$result" ]
}

@test "get_stuck_warning: warning at threshold" {
    update_stuck_file "1"
    update_stuck_file "1"
    update_stuck_file "1"
    result=$(get_stuck_warning)
    [[ "$result" == *"stuck"* ]]
    [[ "$result" == *"#1"* ]]
}

@test "get_stuck_warning: no file returns empty" {
    rm -f "$STUCK_FILE"
    result=$(get_stuck_warning)
    [ -z "$result" ]
}

# ── get_stuck_ids_for_prompt ───────────────────────────────────────

@test "get_stuck_ids_for_prompt: returns IDs at threshold" {
    update_stuck_file "5"
    update_stuck_file "5"
    update_stuck_file "5"
    result=$(get_stuck_ids_for_prompt 3)
    [[ "$result" == *"5"* ]]
}

@test "get_stuck_ids_for_prompt: returns empty below threshold" {
    update_stuck_file "5"
    result=$(get_stuck_ids_for_prompt 3)
    [ -z "$result" ]
}

@test "get_stuck_ids_for_prompt: multiple stuck items" {
    for i in 1 2 3; do update_stuck_file "10,20"; done
    result=$(get_stuck_ids_for_prompt 3)
    [[ "$result" == *"10"* ]]
    [[ "$result" == *"20"* ]]
}

@test "get_stuck_ids_for_prompt: custom threshold" {
    update_stuck_file "7"
    update_stuck_file "7"
    update_stuck_file "7"
    update_stuck_file "7"
    update_stuck_file "7"
    result=$(get_stuck_ids_for_prompt 5)
    [[ "$result" == *"7"* ]]
    result=$(get_stuck_ids_for_prompt 6)
    [ -z "$result" ]
}
