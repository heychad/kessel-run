#!/usr/bin/env bats
# Tests for init.sh — project scaffolding

KESSEL_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    git init --quiet  # init.sh may need git context
}

teardown() {
    [ -n "${TEST_DIR:-}" ] && rm -rf "$TEST_DIR"
}

@test "init: creates required directory structure" {
    bash "$KESSEL_ROOT/scripts/init.sh"
    [ -d scripts/kessel-run ]
    [ -d docs/specs ]
}

@test "init: creates all required files" {
    bash "$KESSEL_ROOT/scripts/init.sh"
    [ -f scripts/kessel-run/loop.sh ]
    [ -f scripts/kessel-run/backpressure.sh ]
    [ -f scripts/kessel-run/PROMPT.md ]
    [ -f docs/PROGRESS.md ]
    [ -f docs/specs/PRD.json ]
}

@test "init: loop.sh is executable" {
    bash "$KESSEL_ROOT/scripts/init.sh"
    [ -x scripts/kessel-run/loop.sh ]
}

@test "init: backpressure.sh is executable" {
    bash "$KESSEL_ROOT/scripts/init.sh"
    [ -x scripts/kessel-run/backpressure.sh ]
}

@test "init: PRD.json is valid JSON" {
    bash "$KESSEL_ROOT/scripts/init.sh"
    python3 -c "import json; json.load(open('docs/specs/PRD.json'))"
}

@test "init: PRD.json has items array" {
    bash "$KESSEL_ROOT/scripts/init.sh"
    result=$(python3 -c "
import json
data = json.load(open('docs/specs/PRD.json'))
print(len(data.get('items', [])))
")
    [ "$result" -ge 1 ]
}

@test "init: preserves existing PROGRESS.md on re-run" {
    bash "$KESSEL_ROOT/scripts/init.sh"
    echo "## Cycle 1 — did stuff" >> docs/PROGRESS.md
    bash "$KESSEL_ROOT/scripts/init.sh"
    run grep "Cycle 1" docs/PROGRESS.md
    [ "$status" -eq 0 ]
}

@test "init: preserves existing PRD.json on re-run" {
    bash "$KESSEL_ROOT/scripts/init.sh"
    python3 -c "
import json
data = json.load(open('docs/specs/PRD.json'))
data['items'].append({'id': 99, 'passes': True})
json.dump(data, open('docs/specs/PRD.json', 'w'))
"
    bash "$KESSEL_ROOT/scripts/init.sh"
    result=$(python3 -c "
import json
data = json.load(open('docs/specs/PRD.json'))
print(any(i['id'] == 99 for i in data['items']))
")
    [ "$result" = "True" ]
}

@test "init: preserves existing backpressure.sh on re-run" {
    bash "$KESSEL_ROOT/scripts/init.sh"
    echo "# my custom check" >> scripts/kessel-run/backpressure.sh
    bash "$KESSEL_ROOT/scripts/init.sh"
    run grep "my custom check" scripts/kessel-run/backpressure.sh
    [ "$status" -eq 0 ]
}

@test "init --force: overwrites backpressure.sh" {
    bash "$KESSEL_ROOT/scripts/init.sh"
    echo "# my custom check" >> scripts/kessel-run/backpressure.sh
    bash "$KESSEL_ROOT/scripts/init.sh" --force
    run grep "my custom check" scripts/kessel-run/backpressure.sh
    [ "$status" -ne 0 ]
}

@test "init: always updates PROMPT.md" {
    bash "$KESSEL_ROOT/scripts/init.sh"
    echo "# old prompt" > scripts/kessel-run/PROMPT.md
    bash "$KESSEL_ROOT/scripts/init.sh"
    # Should have the template content, not our override
    run grep "old prompt" scripts/kessel-run/PROMPT.md
    [ "$status" -ne 0 ]
}

@test "init: creates .gitignore with kessel-run entries" {
    bash "$KESSEL_ROOT/scripts/init.sh"
    [ -f .gitignore ]
    run grep ".claude/worktrees/" .gitignore
    [ "$status" -eq 0 ]
    run grep ".kessel-locks/" .gitignore
    [ "$status" -eq 0 ]
}

@test "init: does not duplicate .gitignore entries on re-run" {
    bash "$KESSEL_ROOT/scripts/init.sh"
    bash "$KESSEL_ROOT/scripts/init.sh"
    count=$(grep -c ".claude/worktrees/" .gitignore)
    [ "$count" -eq 1 ]
}

@test "init: creates CLAUDE.md with backpressure instruction" {
    bash "$KESSEL_ROOT/scripts/init.sh"
    mkdir -p .claude
    # Re-run to test CLAUDE.md creation (might already exist from first run)
    [ -f .claude/CLAUDE.md ]
    run grep "backpressure" .claude/CLAUDE.md
    [ "$status" -eq 0 ]
}
