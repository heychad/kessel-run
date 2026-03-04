#!/usr/bin/env bash
# Kessel Run — autonomous loop for Claude Code.
# Fresh context every parsec. Stream everything. Never capture into variables.
#
# Usage:
#   ./scripts/kessel-run/loop.sh              # run max parsecs (default 12)
#   ./scripts/kessel-run/loop.sh 5            # run 5 parsecs
#   ./scripts/kessel-run/loop.sh 0            # unlimited parsecs
#   ./scripts/kessel-run/loop.sh watch        # single parsec in TUI mode
#
# Multi-runner mode (parallel runners in separate terminals):
#   RUNNER_ID=1 ./scripts/kessel-run/loop.sh  # runner 1
#   RUNNER_ID=2 ./scripts/kessel-run/loop.sh  # runner 2
#
# Each runner picks items via atomic locking, works in a git worktree,
# and merges back to main. Without RUNNER_ID, behaves exactly as before.
set -euo pipefail

KESSEL_MODEL="${KESSEL_MODEL:-claude-sonnet-4-6}"
KESSEL_DIR="${KESSEL_DIR:-scripts/kessel-run}"

# ── Multi-runner mode ─────────────────────────────────────────────
RUNNER_ID="${RUNNER_ID:-}"
MULTI_RUNNER=false
[ -n "$RUNNER_ID" ] && MULTI_RUNNER=true
PROJECT_ROOT="$(pwd)"
CURRENT_ITEM_ID=""
CURRENT_WORKTREE=""
CURRENT_BRANCH=""

# ── ANSI Colors (Star Wars palette) ─────────────────────────────
YELLOW='\033[38;5;220m'
WHITE='\033[1;37m'
DIM='\033[38;5;240m'
GREEN='\033[38;5;114m'
RED='\033[38;5;203m'
RESET='\033[0m'
BOLD='\033[1m'

# ── Cleanup ──────────────────────────────────────────────────────
cleanup() {
    [ -n "${TIMER_PID:-}" ] && kill "$TIMER_PID" 2>/dev/null
    printf '\033]0;\007'
    # Multi-runner: release lock and remove worktree on exit
    if [ "$MULTI_RUNNER" = true ]; then
        cd "$PROJECT_ROOT" 2>/dev/null || true
        if [ -n "$CURRENT_ITEM_ID" ]; then
            rm -rf ".kessel-locks/item-${CURRENT_ITEM_ID}" 2>/dev/null || true
        fi
        if [ -n "$CURRENT_WORKTREE" ] && [ -d "$CURRENT_WORKTREE" ]; then
            git worktree remove "$CURRENT_WORKTREE" --force 2>/dev/null || true
        fi
        if [ -n "$CURRENT_BRANCH" ]; then
            git branch -D "$CURRENT_BRANCH" 2>/dev/null || true
        fi
    fi
}
trap cleanup EXIT

# ── Helpers ──────────────────────────────────────────────────────
format_duration() {
    local secs=$1
    if [ "$secs" -lt 60 ]; then
        echo "${secs}s"
    elif [ "$secs" -lt 3600 ]; then
        echo "$((secs / 60))m $((secs % 60))s"
    else
        echo "$((secs / 3600))h $((secs % 3600 / 60))m"
    fi
}

count_prd_progress() {
    python3 -c "
import json, sys
with open('docs/specs/PRD.json') as f:
    data = json.load(f)
items = data.get('items', [])
total = len(items)
passing = sum(1 for i in items if i.get('passes'))
print(f'{passing} {total}')
" 2>/dev/null || echo "0 0"
}

# Output failing item IDs and progress — let the model pick the best one
failing_items() {
    python3 2>/dev/null << 'PYEOF' || echo "## FAILING ITEMS — error reading PRD.json"
import json, sys
with open('docs/specs/PRD.json') as f:
    data = json.load(f)
items = data.get('items', [])
total = len(items)
passing = sum(1 for i in items if i.get('passes'))
failing = [i['id'] for i in items if not i.get('passes')]
if not failing:
    print('ALL ITEMS PASSING.')
    sys.exit(0)
print(f'Progress: {passing}/{total} passing')
print(f'Failing: {", ".join(str(x) for x in failing)}')
PYEOF
}

# Compose the full prompt: PROMPT.md + progress tail + failing IDs + codebase snapshot
build_prompt() {
    cat "${KESSEL_DIR}/PROMPT.md"
    echo ""
    echo "## RECENT PROGRESS"
    echo ""
    tail -50 docs/PROGRESS.md 2>/dev/null || echo "(no progress yet)"
    echo ""
    echo "## CODEBASE"
    echo ""
    find . -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.py' -o -name '*.sh' -o -name '*.css' -o -name '*.html' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' -o -name '*.swift' -o -name '*.kt' -o -name '*.dart' \) \
        -not -path '*/node_modules/*' -not -path '*/.next/*' -not -path '*/dist/*' -not -path '*/.git/*' -not -path '*/build/*' -not -path '*/.claude/*' \
        2>/dev/null | head -200 | sort
    echo ""
    failing_items
}

show_progress() {
    local progress passing total pct filled empty i filled_str empty_str
    progress=$(count_prd_progress)
    passing=$(echo "$progress" | cut -d' ' -f1)
    total=$(echo "$progress" | cut -d' ' -f2)

    if [ "$total" -eq 0 ]; then
        printf "  ${DIM}No PRD items found${RESET}\n"
        return
    fi

    pct=$(( passing * 100 / total ))
    local bar_width=30
    filled=$(( passing * bar_width / total ))
    empty=$(( bar_width - filled ))

    filled_str="" ; empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="█"; done
    for ((i=0; i<empty; i++)); do empty_str+="░"; done

    printf "  ${YELLOW}%s${WHITE}▸${DIM}%s${RESET}  ${WHITE}%d${DIM}/${WHITE}%d${RESET} items  ${YELLOW}%d%%${RESET}\n" \
        "$filled_str" "$empty_str" "$passing" "$total" "$pct"
}

show_parsec_header() {
    local parsec=$1 prev_dur=$2 total_dur=$3
    local time_now runner_tag=""
    time_now=$(date '+%H:%M:%S')
    [ "$MULTI_RUNNER" = true ] && runner_tag="  ${DIM}[Runner ${RUNNER_ID}]${RESET}"

    echo ""
    if [ "$parsec" -gt 1 ]; then
        printf "  ${YELLOW}━━━ ${WHITE}${BOLD}PARSEC %d${RESET} ${YELLOW}━━━${RESET}%b  ${DIM}%s  last ${WHITE}%s${RESET}  ${DIM}total ${WHITE}%s${RESET}\n" \
            "$parsec" "$runner_tag" "$time_now" "$(format_duration $prev_dur)" "$(format_duration $total_dur)"
    else
        printf "  ${YELLOW}━━━ ${WHITE}${BOLD}PARSEC %d${RESET} ${YELLOW}━━━${RESET}%b  ${DIM}%s${RESET}\n" "$parsec" "$runner_tag" "$time_now"
    fi
    show_progress
    echo ""
}

start_timer() {
    local parsec=$1 start=$2
    local runner_tag=""
    [ "$MULTI_RUNNER" = true ] && runner_tag=" [R${RUNNER_ID}]"
    while true; do
        local now=$(date +%s)
        local elapsed=$((now - start))
        printf '\033]0;Kessel Run — Parsec %d%s — %s\007' "$parsec" "$runner_tag" "$(format_duration $elapsed)"
        sleep 1
    done
}

# ── Multi-runner functions ─────────────────────────────────────────
pick_next_item() {
    python3 -c "
import json, os, sys
with open('docs/specs/PRD.json') as f:
    data = json.load(f)
items = data.get('items', [])
passing_ids = {i['id'] for i in items if i.get('passes')}
locked = set()
lock_dir = '.kessel-locks'
if os.path.isdir(lock_dir):
    for entry in os.listdir(lock_dir):
        if entry.startswith('item-'):
            try:
                locked.add(int(entry.split('-', 1)[1]))
            except ValueError:
                pass
for i in sorted(items, key=lambda x: x['id']):
    if i.get('passes'):
        continue
    if i['id'] in locked:
        continue
    deps = set(i.get('depends_on', []))
    unmet = deps - passing_ids
    if unmet:
        continue
    print(i['id'])
    sys.exit(0)
" 2>/dev/null
}

claim_item() {
    local id=$1
    mkdir ".kessel-locks/item-${id}" 2>/dev/null || return 1
    echo "$$" > ".kessel-locks/item-${id}/pid"
    echo "$RUNNER_ID" > ".kessel-locks/item-${id}/runner"
}

release_item() {
    rm -rf ".kessel-locks/item-${1}"
}

clean_stale_locks() {
    local lock_dir=".kessel-locks"
    [ -d "$lock_dir" ] || return 0
    for lock in "$lock_dir"/item-*; do
        [ -d "$lock" ] || continue
        local pid_file="$lock/pid"
        if [ -f "$pid_file" ]; then
            local pid
            pid=$(cat "$pid_file" 2>/dev/null)
            if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
                rm -rf "$lock"
            fi
        else
            rm -rf "$lock"
        fi
    done
}

build_assigned_prompt() {
    local item_id=$1
    echo "## MANDATORY ASSIGNMENT — ITEM #${item_id}"
    echo ""
    echo "You are assigned to work on item #${item_id} ONLY."
    echo "Do NOT pick a different item. Do NOT read PRD.json to find items."
    echo "Your item is pre-selected by the multi-runner coordinator."
    echo ""
    cat "${KESSEL_DIR}/PROMPT.md"
    echo ""
    failing_items
}

merge_worktree() {
    local worktree=$1 branch=$2 item_id=$3

    cd "$PROJECT_ROOT"

    # Attempt merge
    if ! git merge "$branch" --no-commit --no-ff 2>/dev/null; then
        # Check what's conflicted
        local conflicted
        conflicted=$(git diff --name-only --diff-filter=U 2>/dev/null || true)

        # Allow conflicts only in PRD.json and PROGRESS.md
        local code_conflicts=false
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            case "$file" in
                docs/specs/PRD.json|docs/PROGRESS.md) ;;
                *) code_conflicts=true ;;
            esac
        done <<< "$conflicted"

        if [ "$code_conflicts" = true ]; then
            git merge --abort 2>/dev/null || true
            return 1
        fi

        # Resolve PRD.json: keep ours, then set this item to passes:true
        if echo "$conflicted" | grep -q "docs/specs/PRD.json"; then
            git checkout --ours docs/specs/PRD.json 2>/dev/null || true
            git add docs/specs/PRD.json
        fi

        # Resolve PROGRESS.md: keep ours, append worktree's additions
        if echo "$conflicted" | grep -q "docs/PROGRESS.md"; then
            git checkout --ours docs/PROGRESS.md 2>/dev/null || true
            # Extract new content from worktree branch
            local base_commit
            base_commit=$(git merge-base HEAD "$branch" 2>/dev/null)
            if [ -n "$base_commit" ]; then
                local new_content
                new_content=$(git diff "$base_commit" "$branch" -- docs/PROGRESS.md | \
                    grep '^+' | grep -v '^+++' | sed 's/^+//' || true)
                if [ -n "$new_content" ]; then
                    echo "" >> docs/PROGRESS.md
                    echo "$new_content" >> docs/PROGRESS.md
                fi
            fi
            git add docs/PROGRESS.md
        fi
    fi

    # Set item passes:true in PRD.json (regardless of conflict)
    python3 -c "
import json
with open('docs/specs/PRD.json', 'r') as f:
    data = json.load(f)
for item in data.get('items', []):
    if item['id'] == ${item_id}:
        item['passes'] = True
        break
with open('docs/specs/PRD.json', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null
    git add docs/specs/PRD.json

    # Complete the merge
    git commit --no-edit -m "kessel: merge item #${item_id} from runner ${RUNNER_ID}" 2>/dev/null || true
    return 0
}

# ── Hero banner (Falcon + figlet starwars) ────────────────────────
print_hero() {
    echo ""
    while IFS= read -r line; do
        printf "  ${YELLOW}${BOLD}%s${RESET}\n" "$line"
    done << 'BANNER'
             _     _
            /_|   |_\
           //||   ||\\
          // ||   || \\
         //  ||___||  \\                 __  ___  _______     _______.     _______. _______  __
        /     |   |     \    _          |  |/  / |   ____|   /       |    /       ||   ____||  |
       /    __|   |__    \  /_\         |  '  /  |  |__     |   (----`   |   (----`|  |__   |  |
      / .--~  |   |  ~--. \|   |        |    <   |   __|     \   \        \   \    |   __|  |  |
     /.~ __\  |   |  /   ~.|   |        |  .  \  |  |____.----)   |   .----)   |   |  |____ |  `----.
    .~  `=='\ |   | /   _.-'.  |        |__|\__\ |_______|_______/    |_______/    |_______||_______|
   /  /      \|   |/ .-~    _.-'
  |           +---+  \  _.-~  |         .______       __    __  .__   __.
  `=----.____/  #  \____.----='         |   _  \     |  |  |  | |  \ |  |
   [::::::::|  (_)  |::::::::]          |  |_)  |    |  |  |  | |   \|  |
  .=----~~~~~\     /~~~~~----=.         |      /     |  |  |  | |  . `  |
  |          /`---'\          |         |  |\  \----.|  `--'  | |  |\   |
   \  \     /       \     /  /          | _| `._____| \______/  |__| \__|
    `.     /         \     .'
      `.  /._________.\  .'
        `--._________.--'
BANNER
    printf "  ${DIM}Autonomous loop for Claude Code${RESET}\n"
    echo ""
}

print_hero

# ── Pre-flight checks ───────────────────────────────────────────
PREFLIGHT_OK=true

for f in "${KESSEL_DIR}/PROMPT.md" docs/specs/PRD.json "${KESSEL_DIR}/backpressure.sh" docs/PROGRESS.md; do
    if [ ! -f "$f" ]; then
        printf "  ${RED}✗${RESET} Missing: ${WHITE}%s${RESET}\n" "$f"
        PREFLIGHT_OK=false
    fi
done

if [ "$PREFLIGHT_OK" = false ]; then
    echo ""
    printf "  ${RED}Pre-flight failed.${RESET} Run ${WHITE}init.sh${RESET} first.\n"
    exit 1
fi

printf "  ${GREEN}✓${RESET} ${DIM}Prompt${RESET}       ${WHITE}${KESSEL_DIR}/PROMPT.md${RESET}\n"
printf "  ${GREEN}✓${RESET} ${DIM}PRD${RESET}          ${WHITE}docs/specs/PRD.json${RESET}\n"
printf "  ${GREEN}✓${RESET} ${DIM}Backpressure${RESET} ${WHITE}${KESSEL_DIR}/backpressure.sh${RESET}\n"
printf "  ${GREEN}✓${RESET} ${DIM}Progress${RESET}     ${WHITE}docs/PROGRESS.md${RESET}\n"
printf "  ${GREEN}✓${RESET} ${DIM}Model${RESET}        ${WHITE}${KESSEL_MODEL}${RESET}\n"
if [ "$MULTI_RUNNER" = true ]; then
    printf "  ${GREEN}✓${RESET} ${DIM}Runner${RESET}       ${WHITE}#${RUNNER_ID}${RESET} ${DIM}(multi-runner mode)${RESET}\n"
    mkdir -p .kessel-locks
fi
echo ""

# ── Watch mode ───────────────────────────────────────────────────
if [ "${1:-}" = "watch" ]; then
    printf "  ${YELLOW}━━━ WATCH MODE ━━━${RESET} ${DIM}single parsec in TUI${RESET}\n\n"
    build_prompt | claude \
        --model "$KESSEL_MODEL" \
        --dangerously-skip-permissions \
        --verbose
    echo ""
    printf "  ${YELLOW}━━━ WATCH COMPLETE ━━━${RESET}\n"
    exit 0
fi

# ── Timing ───────────────────────────────────────────────────────
MAX_PARSECS="${1:-${KESSEL_MAX_PARSECS:-12}}"
PARSEC=0
TOTAL_START=$(date +%s)
PREV_DURATION=0

printf "  ${DIM}Max parsecs:${RESET} ${WHITE}%s${RESET} ${DIM}(0 = unlimited)${RESET}\n" "$MAX_PARSECS"
show_progress
echo ""

# ── Completion check ─────────────────────────────────────────────
check_all_complete() {
    python3 -c "
import json, sys
with open('docs/specs/PRD.json') as f:
    data = json.load(f)
items = data.get('items', [])
if not items:
    sys.exit(1)
sys.exit(0 if all(i.get('passes') for i in items) else 1)
" 2>/dev/null
}

# ── Main loop ────────────────────────────────────────────────────
while true; do
    PARSEC=$((PARSEC + 1))
    CYCLE_START=$(date +%s)

    if [ "$MAX_PARSECS" -gt 0 ] && [ "$PARSEC" -gt "$MAX_PARSECS" ]; then
        TOTAL_END=$(date +%s)
        echo ""
        printf "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        printf "  ${WHITE}${BOLD}MAX PARSECS (%d) REACHED${RESET}  ${DIM}total ${WHITE}%s${RESET}\n" "$MAX_PARSECS" "$(format_duration $((TOTAL_END - TOTAL_START)))"
        show_progress
        printf "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        break
    fi

    TOTAL_NOW=$(date +%s)
    show_parsec_header "$PARSEC" "$PREV_DURATION" "$((TOTAL_NOW - TOTAL_START))"

    # Live timer in terminal title bar
    start_timer "$PARSEC" "$CYCLE_START" &
    TIMER_PID=$!

    if [ "$MULTI_RUNNER" = true ]; then
        # ── Multi-runner: pick, claim, worktree, merge ──
        clean_stale_locks
        ITEM_ID=$(pick_next_item)
        if [ -z "$ITEM_ID" ]; then
            NO_ITEM_COUNT=$((${NO_ITEM_COUNT:-0} + 1))
            kill "$TIMER_PID" 2>/dev/null || true; wait "$TIMER_PID" 2>/dev/null || true; TIMER_PID=""
            if [ "$NO_ITEM_COUNT" -ge 5 ]; then
                printf "  ${RED}No items available after 5 retries. Exiting.${RESET}\n"
                break
            fi
            printf "  ${DIM}No unclaimed items available, waiting 10s...${RESET}\n"
            sleep 10
            PARSEC=$((PARSEC - 1))
            continue
        fi
        NO_ITEM_COUNT=0

        if ! claim_item "$ITEM_ID"; then
            kill "$TIMER_PID" 2>/dev/null || true; wait "$TIMER_PID" 2>/dev/null || true; TIMER_PID=""
            PARSEC=$((PARSEC - 1))
            continue
        fi

        CURRENT_ITEM_ID="$ITEM_ID"
        CURRENT_BRANCH="kessel/runner-${RUNNER_ID}/parsec-${PARSEC}"
        CURRENT_WORKTREE=".claude/worktrees/runner-${RUNNER_ID}"

        # Clean up any leftover worktree at this path
        git worktree remove "$CURRENT_WORKTREE" --force 2>/dev/null || true
        git worktree prune 2>/dev/null || true
        git worktree add "$CURRENT_WORKTREE" -b "$CURRENT_BRANCH" HEAD

        printf "  ${DIM}Item #%d claimed → %s${RESET}\n" "$ITEM_ID" "$CURRENT_BRANCH"

        # Build prompt from project root (where docs/specs/PRD.json lives)
        PROMPT_FILE=$(mktemp)
        build_assigned_prompt "$ITEM_ID" > "$PROMPT_FILE"
        printf "  ${DIM}Prompt: %d bytes → %s${RESET}\n" "$(wc -c < "$PROMPT_FILE")" "$PROMPT_FILE"

        # Run Claude in worktree with assigned item
        cd "$CURRENT_WORKTREE"
        claude -p \
            --model "$KESSEL_MODEL" \
            --dangerously-skip-permissions \
            --verbose < "$PROMPT_FILE" 2>&1 || true
        cd "$PROJECT_ROOT"
        rm -f "$PROMPT_FILE"

        # Merge worktree back to main
        if merge_worktree "$CURRENT_WORKTREE" "$CURRENT_BRANCH" "$ITEM_ID"; then
            printf "  ${GREEN}✓${RESET} Item #%d merged successfully\n" "$ITEM_ID"
        else
            printf "  ${RED}✗${RESET} Item #%d merge failed — returning to pool\n" "$ITEM_ID"
        fi

        # Cleanup worktree and lock
        git worktree remove "$CURRENT_WORKTREE" --force 2>/dev/null || true
        git branch -D "$CURRENT_BRANCH" 2>/dev/null || true
        release_item "$ITEM_ID"
        CURRENT_ITEM_ID=""
        CURRENT_WORKTREE=""
        CURRENT_BRANCH=""
    else
        # ── Single-runner: original behavior ──
        # Clean git staging area — prevent committing stale staged files
        git reset --quiet HEAD -- . 2>/dev/null || true

        # Stream output directly — never capture into variables
        # build_prompt injects PROMPT.md + dynamic PRD status
        build_prompt | claude -p \
            --model "$KESSEL_MODEL" \
            --dangerously-skip-permissions \
            --verbose 2>&1 || true
    fi

    # Stop timer
    kill "$TIMER_PID" 2>/dev/null || true
    wait "$TIMER_PID" 2>/dev/null || true
    TIMER_PID=""

    CYCLE_END=$(date +%s)
    PREV_DURATION=$((CYCLE_END - CYCLE_START))

    echo ""
    printf "  ${DIM}── parsec %d done ── %s ──${RESET}\n" "$PARSEC" "$(format_duration $PREV_DURATION)"

    # Check if all PRD items pass
    if check_all_complete; then
        TOTAL_END=$(date +%s)
        echo ""
        printf "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        printf "  ${WHITE}${BOLD}  ✦  A L L   I T E M S   P A S S I N G  ✦${RESET}\n"
        printf "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        echo ""
        printf "  ${WHITE}Parsecs:${RESET} %d    ${WHITE}Time:${RESET} %s\n" "$PARSEC" "$(format_duration $((TOTAL_END - TOTAL_START)))"
        show_progress
        echo ""
        printf "  ${DIM}\"Great shot kid, that was one in a million!\"${RESET}\n"
        echo ""

        # macOS notification
        if command -v osascript &>/dev/null; then
            osascript -e "display notification \"All PRD items passing after ${PARSEC} parsecs.\" with title \"Kessel Run Complete\" sound name \"Glass\""
        fi
        break
    fi
done
