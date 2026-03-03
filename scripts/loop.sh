#!/usr/bin/env bash
# Kessel Run — autonomous loop for Claude Code.
# Fresh context every cycle. Stream everything. Never capture into variables.
#
# Usage:
#   ./scripts/kessel-run/loop.sh              # run max cycles (default 12)
#   ./scripts/kessel-run/loop.sh 5            # run 5 cycles
#   ./scripts/kessel-run/loop.sh 0            # unlimited cycles
#   ./scripts/kessel-run/loop.sh watch        # single cycle in TUI mode
set -euo pipefail

KESSEL_MODEL="${KESSEL_MODEL:-claude-opus-4-6}"
KESSEL_DIR="${KESSEL_DIR:-scripts/kessel-run}"

# ── ANSI Colors (blue/purple space palette) ──────────────────────
BLUE='\033[38;5;69m'
PURPLE='\033[38;5;141m'
CYAN='\033[38;5;117m'
DIM='\033[38;5;240m'
WHITE='\033[1;37m'
GREEN='\033[38;5;114m'
RED='\033[38;5;203m'
RESET='\033[0m'
BOLD='\033[1m'

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

    printf "  ${PURPLE}%s${CYAN}▸${DIM}%s${RESET}  ${WHITE}%d${DIM}/${WHITE}%d${RESET} items  ${CYAN}%d%%${RESET}\n" \
        "$filled_str" "$empty_str" "$passing" "$total" "$pct"
}

show_cycle_header() {
    local cycle=$1 prev_dur=$2 total_dur=$3
    local time_now
    time_now=$(date '+%H:%M:%S')

    echo ""
    if [ "$cycle" -gt 1 ]; then
        printf "  ${BLUE}━━━ ${CYAN}${BOLD}CYCLE %d${RESET} ${BLUE}━━━${RESET}  ${DIM}%s  last ${WHITE}%s${RESET}  ${DIM}total ${WHITE}%s${RESET}\n" \
            "$cycle" "$time_now" "$(format_duration $prev_dur)" "$(format_duration $total_dur)"
    else
        printf "  ${BLUE}━━━ ${CYAN}${BOLD}CYCLE %d${RESET} ${BLUE}━━━${RESET}  ${DIM}%s${RESET}\n" "$cycle" "$time_now"
    fi
    show_progress
    echo ""
}

# ── Hero banner ──────────────────────────────────────────────────
printf "${BLUE}"
cat << 'HERO'

                 _     _
                /_|   |_\
               //||   ||\\
              // ||   || \\
             //  ||___||  \\
            /     |   |     \    _
           /    __|   |__    \  /_\
          / .--~  |   |  ~--. \|   |
         /.~ __\  |   |  /   ~.|   |
        .~  `=='\ |   | /   _.-'.  |
       /  /      \|   |/ .-~    _.-'
      |           +---+  \  _.-~  |
      `=----.____/  #  \____.----='
       [::::::::|  (_)  |::::::::]
      .=----~~~~~\     /~~~~~----=.
      |          /`---'\          |
       \  \     /       \     /  /
        `.     /         \     .'
          `.  /._________.\  .'
            `--._________.--'
HERO
printf "${RESET}\n"
printf "  ${CYAN}${BOLD}K E S S E L   R U N${RESET}\n"
printf "  ${DIM}Autonomous loop for Claude Code${RESET}\n\n"

# ── Pre-flight checks ───────────────────────────────────────────
PREFLIGHT_OK=true

for f in "${KESSEL_DIR}/PROMPT.md" docs/specs/PRD.json "${KESSEL_DIR}/backpressure.sh" .claude/PROGRESS.md; do
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
printf "  ${GREEN}✓${RESET} ${DIM}Progress${RESET}     ${WHITE}.claude/PROGRESS.md${RESET}\n"
printf "  ${GREEN}✓${RESET} ${DIM}Model${RESET}        ${WHITE}${KESSEL_MODEL}${RESET}\n"
echo ""

# ── Watch mode ───────────────────────────────────────────────────
if [ "${1:-}" = "watch" ]; then
    printf "  ${CYAN}━━━ WATCH MODE ━━━ single cycle in TUI${RESET}\n\n"
    cat "${KESSEL_DIR}/PROMPT.md" | claude \
        --model "$KESSEL_MODEL" \
        --dangerously-skip-permissions \
        --verbose
    echo ""
    printf "  ${CYAN}━━━ WATCH COMPLETE ━━━${RESET}\n"
    exit 0
fi

# ── Timing ───────────────────────────────────────────────────────
MAX_CYCLES="${1:-${KESSEL_MAX_PARSECS:-12}}"
CYCLE=0
TOTAL_START=$(date +%s)
PREV_DURATION=0

printf "  ${DIM}Max cycles:${RESET} ${WHITE}%s${RESET} ${DIM}(0 = unlimited)${RESET}\n" "$MAX_CYCLES"
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
    CYCLE=$((CYCLE + 1))
    CYCLE_START=$(date +%s)

    if [ "$MAX_CYCLES" -gt 0 ] && [ "$CYCLE" -gt "$MAX_CYCLES" ]; then
        TOTAL_END=$(date +%s)
        echo ""
        printf "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        printf "  ${CYAN}${BOLD}MAX CYCLES (%d) REACHED${RESET}  ${DIM}total ${WHITE}%s${RESET}\n" "$MAX_CYCLES" "$(format_duration $((TOTAL_END - TOTAL_START)))"
        show_progress
        printf "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        break
    fi

    TOTAL_NOW=$(date +%s)
    show_cycle_header "$CYCLE" "$PREV_DURATION" "$((TOTAL_NOW - TOTAL_START))"

    # Stream output directly — never capture into variables
    cat "${KESSEL_DIR}/PROMPT.md" | claude -p \
        --model "$KESSEL_MODEL" \
        --dangerously-skip-permissions \
        --output-format=text \
        --verbose 2>&1 || true

    CYCLE_END=$(date +%s)
    PREV_DURATION=$((CYCLE_END - CYCLE_START))

    echo ""
    printf "  ${DIM}── cycle %d done ── %s ──${RESET}\n" "$CYCLE" "$(format_duration $PREV_DURATION)"

    # Check if all PRD items pass
    if check_all_complete; then
        TOTAL_END=$(date +%s)
        echo ""
        printf "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        printf "  ${CYAN}${BOLD}  ✦  A L L   I T E M S   P A S S I N G  ✦${RESET}\n"
        printf "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        echo ""
        printf "  ${WHITE}Cycles:${RESET} %d    ${WHITE}Time:${RESET} %s\n" "$CYCLE" "$(format_duration $((TOTAL_END - TOTAL_START)))"
        show_progress
        echo ""
        printf "  ${DIM}\"Great shot kid, that was one in a million!\"${RESET}\n"
        echo ""

        # macOS notification
        if command -v osascript &>/dev/null; then
            osascript -e "display notification \"All PRD items passing after ${CYCLE} cycles.\" with title \"Kessel Run Complete\" sound name \"Glass\""
        fi
        break
    fi
done
