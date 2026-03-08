#!/usr/bin/env bats
# Tests for read_prd_progress — PRD.json parsing

load test_helpers

setup() {
    setup_temp_project
    source_loop_functions
}

teardown() {
    teardown_temp_project
}

@test "read_prd_progress: parses passing/total/failing from standard PRD" {
    read_prd_progress
    [ "$PRD_PASSING" -eq 1 ]
    [ "$PRD_TOTAL" -eq 3 ]
    # failing IDs should be 1 and 3
    [[ "$PRD_FAILING_CSV" == *"1"* ]]
    [[ "$PRD_FAILING_CSV" == *"3"* ]]
}

@test "read_prd_progress: all passing" {
    cat > docs/specs/PRD.json << 'EOF'
{"items": [
    {"id": 1, "passes": true},
    {"id": 2, "passes": true}
]}
EOF
    read_prd_progress
    [ "$PRD_PASSING" -eq 2 ]
    [ "$PRD_TOTAL" -eq 2 ]
    [ -z "$PRD_FAILING_CSV" ]
}

@test "read_prd_progress: none passing" {
    cat > docs/specs/PRD.json << 'EOF'
{"items": [
    {"id": 1, "passes": false},
    {"id": 2, "passes": false}
]}
EOF
    read_prd_progress
    [ "$PRD_PASSING" -eq 0 ]
    [ "$PRD_TOTAL" -eq 2 ]
}

@test "read_prd_progress: empty items array" {
    echo '{"items": []}' > docs/specs/PRD.json
    read_prd_progress
    [ "$PRD_PASSING" -eq 0 ]
    [ "$PRD_TOTAL" -eq 0 ]
}

@test "read_prd_progress: bare array format (no wrapper object)" {
    cat > docs/specs/PRD.json << 'EOF'
[
    {"id": 1, "passes": true},
    {"id": 2, "passes": false}
]
EOF
    read_prd_progress
    [ "$PRD_PASSING" -eq 1 ]
    [ "$PRD_TOTAL" -eq 2 ]
}

@test "read_prd_progress: items without id field use index" {
    cat > docs/specs/PRD.json << 'EOF'
{"items": [
    {"description": "no id", "passes": false},
    {"description": "also no id", "passes": false}
]}
EOF
    read_prd_progress
    [ "$PRD_TOTAL" -eq 2 ]
    [ "$PRD_PASSING" -eq 0 ]
    # Should use indices 0, 1 as fallback IDs
    [[ "$PRD_FAILING_CSV" == *"0"* ]]
    [[ "$PRD_FAILING_CSV" == *"1"* ]]
}

@test "read_prd_progress: missing file returns zeros" {
    rm docs/specs/PRD.json
    read_prd_progress
    [ "$PRD_PASSING" -eq 0 ]
    [ "$PRD_TOTAL" -eq 0 ]
}

@test "read_prd_progress: large PRD (50 items)" {
    python3 -c "
import json
items = [{'id': i, 'passes': i % 3 == 0} for i in range(50)]
json.dump({'items': items}, open('docs/specs/PRD.json', 'w'))
"
    read_prd_progress
    [ "$PRD_TOTAL" -eq 50 ]
    # items 0, 3, 6, ..., 48 pass (every 3rd, starting at 0) = 17
    [ "$PRD_PASSING" -eq 17 ]
}
