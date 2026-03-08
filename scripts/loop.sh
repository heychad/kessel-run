#!/usr/bin/env bash
# Kessel Run — autonomous loop for Claude Code.
# Fresh context every parsec. Stream everything. Never capture into variables.
#
# Usage:
#   ./scripts/kessel-run/loop.sh              # run max parsecs (auto-scaled)
#   ./scripts/kessel-run/loop.sh 5            # run 5 parsecs
#   ./scripts/kessel-run/loop.sh 0            # unlimited parsecs
#   ./scripts/kessel-run/loop.sh watch        # single parsec in TUI mode
set -euo pipefail

KESSEL_MODEL="${KESSEL_MODEL:-claude-sonnet-4-6}"
KESSEL_DIR="${KESSEL_DIR:-scripts/kessel-run}"

# ── ANSI Colors (Star Wars palette) ─────────────────────────────
YELLOW='\033[38;5;220m'
WHITE='\033[1;37m'
DIM='\033[38;5;240m'
GREEN='\033[38;5;114m'
RED='\033[38;5;203m'
RESET='\033[0m'
BOLD='\033[1m'
CYAN='\033[38;5;117m'
ORANGE='\033[38;5;208m'

# ── Temp / log paths ─────────────────────────────────────────────
STUCK_FILE=".kessel-run-stuck"      # persists across parsecs, gitignored
STATE_FILE=".kessel-run-state"      # crash-resume state
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/kessel-run.log"

# ── Cleanup ──────────────────────────────────────────────────────
cleanup() {
    [ -n "${TIMER_PID:-}" ] && kill "$TIMER_PID" 2>/dev/null
    printf '\033]0;\007'
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
items = data if isinstance(data, list) else data.get('items', [])
total = len(items)
passing = sum(1 for i in items if i.get('passes'))
failing_ids = [str(i.get('id', idx)) for idx, i in enumerate(items) if not i.get('passes')]
print(f'{passing} {total} {chr(44).join(failing_ids)}')
" 2>/dev/null || echo "0 0 "
}

# Update .kessel-run-stuck with current failing IDs.
# File format: one "ID COUNT" per line.
update_stuck_file() {
    local failing_csv="$1"   # comma-separated currently-failing IDs (may be empty)

    # Read existing counts into associative array
    declare -A counts
    if [ -f "$STUCK_FILE" ]; then
        while read -r id cnt; do
            counts["$id"]=$cnt
        done < "$STUCK_FILE"
    fi

    # Parse currently failing IDs
    declare -A currently_failing
    if [ -n "$failing_csv" ]; then
        IFS=',' read -ra fids <<< "$failing_csv"
        for fid in "${fids[@]}"; do
            [ -n "$fid" ] && currently_failing["$fid"]=1
        done
    fi

    # Increment failing, reset passing
    declare -A new_counts
    # Carry forward all known IDs that are still failing
    for id in "${!counts[@]}"; do
        if [ -n "${currently_failing[$id]:-}" ]; then
            new_counts["$id"]=$(( counts[$id] + 1 ))
        fi
        # IDs that are now passing just drop out (not written back)
    done
    # Add new failing IDs not seen before
    for id in "${!currently_failing[@]}"; do
        if [ -z "${counts[$id]:-}" ]; then
            new_counts["$id"]=1
        fi
    done

    # Write back
    : > "$STUCK_FILE"
    for id in "${!new_counts[@]}"; do
        echo "$id ${new_counts[$id]}" >> "$STUCK_FILE"
    done
}

# Returns warning line if any item has failed 3+ consecutive parsecs.
get_stuck_warning() {
    [ -f "$STUCK_FILE" ] || return 0
    local stuck_ids=()
    while read -r id cnt; do
        if [ "$cnt" -ge 3 ]; then
            stuck_ids+=("#${id}(${cnt}x)")
        fi
    done < "$STUCK_FILE"
    if [ "${#stuck_ids[@]}" -gt 0 ]; then
        local joined
        joined=$(IFS=', '; echo "${stuck_ids[*]}")
        printf "${ORANGE}⚠ %d stuck item(s): %s (failed 3+ cycles)${RESET}" \
            "${#stuck_ids[@]}" "$joined"
    fi
}

# Returns comma-separated IDs of stuck items (3+ failures) for prompt injection.
get_stuck_ids_for_prompt() {
    [ -f "$STUCK_FILE" ] || return 0
    local ids=()
    while read -r id cnt; do
        [ "$cnt" -ge 3 ] && ids+=("$id")
    done < "$STUCK_FILE"
    (IFS=','; echo "${ids[*]}")
}

# Show spec-level progress table.
show_spec_progress() {
    python3 -c "
import json, sys

with open('docs/specs/PRD.json') as f:
    data = json.load(f)
items = data if isinstance(data, list) else data.get('items', [])

# Group by spec field
specs = {}
for item in items:
    spec = item.get('spec', 'unknown')
    if spec not in specs:
        specs[spec] = {'pass': 0, 'total': 0}
    specs[spec]['total'] += 1
    if item.get('passes'):
        specs[spec]['pass'] += 1

import os
bar_w = 16
# Use just the filename, not the full path
name_w = max(len(os.path.basename(s)) for s in specs) + 1
for spec, counts in sorted(specs.items()):
    name = os.path.basename(spec)
    p, t = counts['pass'], counts['total']
    pct = p / t if t else 0
    filled = round(pct * bar_w)
    empty = bar_w - filled - (1 if 0 < pct < 1 else 0)
    tip = '\u25b8' if 0 < pct < 1 else ''
    bar = '\u2588' * filled + tip + '\u2591' * empty
    if p == t:
        status = '\033[38;5;114m\u2713\033[0m'
    elif p == 0:
        status = '\033[38;5;240m\u2014\033[0m'
    else:
        status = f'{round(pct*100)}%'
    print(f'  {name:<{name_w}} {bar}  {p:>3}/{t:<3}  {status}')
" 2>/dev/null || printf "  ${DIM}(spec data unavailable)${RESET}\n"
}

# Write one structured log line per parsec.
write_log_line() {
    local parsec=$1 passing=$2 total=$3 duration=$4 vel_str=$5 \
          attempted=$6 passed_this=$7 stuck_ids=$8

    mkdir -p "$LOG_DIR"
    local ts
    ts=$(date -u '+%Y-%m-%dT%H:%M:%S')
    local stuck_field=""
    [ -n "$stuck_ids" ] && stuck_field=" stuck=#${stuck_ids//,/,#}"
    echo "${ts} parsec=${parsec} passed=${passing} total=${total} duration=${duration}s velocity=${vel_str} items_attempted=${attempted} items_passed=${passed_this}${stuck_field}" \
        >> "$LOG_FILE"
}

# Crash-resume state helpers.
write_state() {
    local parsec=$1 start=$2
    printf "parsec=%d\nstart=%d\n" "$parsec" "$start" > "$STATE_FILE"
}

read_state() {
    # Prints: PARSEC START (two integers on one line)
    if [ -f "$STATE_FILE" ]; then
        local p s
        p=$(grep '^parsec=' "$STATE_FILE" | cut -d= -f2)
        s=$(grep '^start=' "$STATE_FILE" | cut -d= -f2)
        echo "${p:-0} ${s:-0}"
    else
        echo "0 0"
    fi
}

cleanup_state() {
    rm -f "$STATE_FILE"
}

# Compose the full prompt, injecting stuck IDs if any.
build_prompt() {
    local stuck_ids
    stuck_ids=$(get_stuck_ids_for_prompt)
    if [ -n "$stuck_ids" ]; then
        printf "<!-- KESSEL-RUN: The following item IDs have failed 3+ consecutive parsecs. Deprioritize them this parsec and focus on other failing items: %s -->\n\n" "$stuck_ids"
    fi
    cat "${KESSEL_DIR}/PROMPT.md"
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
    local pct_label="${pct}%"
    # Show <1% when items are passing but integer division rounds to 0
    if [ "$passing" -gt 0 ] && [ "$pct" -eq 0 ]; then
        pct_label="<1%"
    fi
    local bar_width=30
    filled=$(( passing * bar_width / total ))
    empty=$(( bar_width - filled ))

    filled_str="" ; empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="█"; done
    for ((i=0; i<empty; i++)); do empty_str+="░"; done

    printf "  ${YELLOW}%s${WHITE}▸${DIM}%s${RESET}  ${WHITE}%d${DIM}/${WHITE}%d${RESET} items  ${YELLOW}%s${RESET}\n" \
        "$filled_str" "$empty_str" "$passing" "$total" "$pct_label"
}

show_parsec_header() {
    local parsec=$1 prev_dur=$2 total_dur=$3
    local time_now
    time_now=$(date '+%H:%M:%S')

    echo ""
    if [ "$parsec" -gt 1 ]; then
        printf "  ${YELLOW}━━━ ${WHITE}${BOLD}PARSEC %d${RESET} ${YELLOW}━━━${RESET}  ${DIM}%s  last ${WHITE}%s${RESET}  ${DIM}total ${WHITE}%s${RESET}\n" \
            "$parsec" "$time_now" "$(format_duration $prev_dur)" "$(format_duration $total_dur)"
    else
        printf "  ${YELLOW}━━━ ${WHITE}${BOLD}PARSEC %d${RESET} ${YELLOW}━━━${RESET}  ${DIM}%s${RESET}\n" "$parsec" "$time_now"
    fi
    show_progress
    echo ""
}

start_timer() {
    local parsec=$1 start=$2
    while true; do
        local now=$(date +%s)
        local elapsed=$((now - start))
        printf '\033]0;Kessel Run — Parsec %d — %s\007' "$parsec" "$(format_duration $elapsed)"
        sleep 1
    done
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

# ── Completion check ─────────────────────────────────────────────
check_all_complete() {
    python3 -c "
import json, sys
with open('docs/specs/PRD.json') as f:
    data = json.load(f)
items = data if isinstance(data, list) else data.get('items', [])
if not items:
    sys.exit(1)
sys.exit(0 if all(i.get('passes') for i in items) else 1)
" 2>/dev/null
}

# ── Crash-resume: detect existing state ──────────────────────────
_state=$(read_state)
_resume_parsec=$(echo "$_state" | cut -d' ' -f1)
_resume_start=$(echo "$_state" | cut -d' ' -f2)

if [ "$_resume_parsec" -gt 0 ]; then
    PARSEC=$_resume_parsec
    TOTAL_START=$_resume_start
    printf "  ${ORANGE}↺ Resuming from parsec %d${RESET}\n" "$PARSEC"
else
    PARSEC=0
    TOTAL_START=$(date +%s)
    # Fresh start: reset stuck file so stale data from prior run doesn't linger
    rm -f "$STUCK_FILE"
fi

PREV_DURATION=0
VELOCITY_SUM=0
VELOCITY_COUNT=0

# ── Auto-scale max parsecs ───────────────────────────────────────
_prd_total=$(count_prd_progress | cut -d' ' -f2)
_auto_max=$(python3 -c "import math; print(max(12, math.ceil(${_prd_total} * 1.5)))")
MAX_PARSECS="${1:-${KESSEL_MAX_PARSECS:-${_auto_max}}}"

printf "  ${DIM}Max parsecs:${RESET} ${WHITE}%s${RESET} ${DIM}(auto: ceil(%d × 1.5) = %d; 0 = unlimited)${RESET}\n" \
    "$MAX_PARSECS" "$_prd_total" "$_auto_max"

# Capture initial passing count for velocity baseline
_init_progress=$(count_prd_progress)
TOTAL_ITEMS_PASSED_START=$(echo "$_init_progress" | cut -d' ' -f1)
PREV_PASSING=$TOTAL_ITEMS_PASSED_START

# On crash-resume: initialize checkpoint baseline from current PRD state
CHECKPOINT_PASSING_PREV=$PREV_PASSING

show_progress
echo ""

# Milestone tracking — space-separated list of already-sent percents
MILESTONES_SENT=""

# ── Main loop ────────────────────────────────────────────────────
while true; do
    PARSEC=$((PARSEC + 1))
    CYCLE_START=$(date +%s)

    # Write crash-resume state at start of each parsec
    write_state "$PARSEC" "$TOTAL_START"

    if [ "$MAX_PARSECS" -gt 0 ] && [ "$PARSEC" -gt "$MAX_PARSECS" ]; then
        TOTAL_END=$(date +%s)
        echo ""
        printf "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        printf "  ${WHITE}${BOLD}MAX PARSECS (%d) REACHED${RESET}  ${DIM}total ${WHITE}%s${RESET}\n" \
            "$MAX_PARSECS" "$(format_duration $((TOTAL_END - TOTAL_START)))"
        show_progress
        printf "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        cleanup_state
        break
    fi

    TOTAL_NOW=$(date +%s)
    show_parsec_header "$PARSEC" "$PREV_DURATION" "$((TOTAL_NOW - TOTAL_START))"

    # Show velocity/ETA in parsec header (available from parsec 2 onward)
    if [ "$VELOCITY_COUNT" -gt 0 ] && [ "$VELOCITY_SUM" -gt 0 ]; then
        _disp_progress=$(count_prd_progress)
        _disp_passing=$(echo "$_disp_progress" | cut -d' ' -f1)
        _disp_total=$(echo "$_disp_progress" | cut -d' ' -f2)
        _disp_remaining=$(( _disp_total - _disp_passing ))
        _disp_vel=$(python3 -c "print(f'{${VELOCITY_SUM}/${VELOCITY_COUNT}:.1f}')")
        _disp_avg_dur=$(( (TOTAL_NOW - TOTAL_START) / VELOCITY_COUNT ))
        _disp_parsecs_rem=$(python3 -c "
import math
v=${VELOCITY_SUM}/${VELOCITY_COUNT}
print(math.ceil(${_disp_remaining}/v) if v > 0 else 0)
")
        _disp_eta_secs=$(( _disp_parsecs_rem * _disp_avg_dur ))
        printf "  ${CYAN}⚡ %s items/parsec  ~%s remaining${RESET}\n\n" \
            "$_disp_vel" "$(format_duration $_disp_eta_secs)"
    fi

    # Show stuck warning if any
    _stuck_warn=$(get_stuck_warning)
    [ -n "$_stuck_warn" ] && printf "  %s\n" "$_stuck_warn"

    # Live timer in terminal title bar
    start_timer "$PARSEC" "$CYCLE_START" &
    TIMER_PID=$!

    # Capture passing count BEFORE this parsec
    _before_progress=$(count_prd_progress)
    _before_passing=$(echo "$_before_progress" | cut -d' ' -f1)

    # Clean git staging area — prevent committing stale staged files
    git reset --quiet HEAD -- . 2>/dev/null || true

    # Stream output directly
    build_prompt | claude -p \
        --model "$KESSEL_MODEL" \
        --dangerously-skip-permissions \
        --verbose 2>&1 || true

    # Stop timer
    kill "$TIMER_PID" 2>/dev/null || true
    wait "$TIMER_PID" 2>/dev/null || true
    TIMER_PID=""

    CYCLE_END=$(date +%s)
    PREV_DURATION=$((CYCLE_END - CYCLE_START))

    # ── Post-parsec metrics ───────────────────────────────────────
    _after_progress=$(count_prd_progress)
    _after_passing=$(echo "$_after_progress" | cut -d' ' -f1)
    _after_total=$(echo "$_after_progress" | cut -d' ' -f2)
    _after_failing=$(echo "$_after_progress" | cut -d' ' -f3)

    _items_passed_this=$(( _after_passing - _before_passing ))
    # Clamp to 0 in case of regression
    [ "$_items_passed_this" -lt 0 ] && _items_passed_this=0

    # Update stuck file
    update_stuck_file "$_after_failing"
    _stuck_ids_log=$(get_stuck_ids_for_prompt)

    # Compute velocity and ETA
    VELOCITY_SUM=$(( VELOCITY_SUM + _items_passed_this ))
    VELOCITY_COUNT=$(( VELOCITY_COUNT + 1 ))

    _vel_str="0.0"
    _eta_str="unknown"
    if [ "$VELOCITY_SUM" -gt 0 ] && [ "$VELOCITY_COUNT" -gt 0 ]; then
        _vel_str=$(python3 -c "print(f'{${VELOCITY_SUM}/${VELOCITY_COUNT}:.1f}')")
        _remaining=$(( _after_total - _after_passing ))
        _avg_dur=$(( (CYCLE_END - TOTAL_START) / VELOCITY_COUNT ))
        _parsecs_rem=$(python3 -c "
import math
v=${VELOCITY_SUM}/${VELOCITY_COUNT}
print(math.ceil(${_remaining}/v) if v > 0 else 0)
")
        _eta_secs=$(( _parsecs_rem * _avg_dur ))
        _eta_str=$(format_duration "$_eta_secs")
    fi

    echo ""
    if [ "$_items_passed_this" -gt 0 ]; then
        printf "  ${DIM}── parsec %d done ── %s ── ${GREEN}+%d item(s)${RESET}\n" \
            "$PARSEC" "$(format_duration $PREV_DURATION)" "$_items_passed_this"
    else
        printf "  ${DIM}── parsec %d done ── %s ── ${ORANGE}+0 items${RESET}\n" \
            "$PARSEC" "$(format_duration $PREV_DURATION)"
    fi

    # ── Write log line ────────────────────────────────────────────
    write_log_line "$PARSEC" "$_after_passing" "$_after_total" \
        "$PREV_DURATION" "$_vel_str" \
        "$(( _after_total - _after_passing + _items_passed_this ))" \
        "$_items_passed_this" \
        "$_stuck_ids_log"

    # ── Milestone notifications (25%, 50%, 75%) ───────────────────
    if command -v osascript &>/dev/null && [ "$_after_total" -gt 0 ]; then
        _pct_now=$(( _after_passing * 100 / _after_total ))
        for _ms in 25 50 75; do
            if [ "$_pct_now" -ge "$_ms" ] && [[ "$MILESTONES_SENT" != *"$_ms"* ]]; then
                osascript -e "display notification \"${_after_passing}/${_after_total} items passing (${_pct_now}%)\" with title \"Kessel Run — ${_ms}% milestone\"" 2>/dev/null || true
                MILESTONES_SENT="${MILESTONES_SENT} ${_ms}"
            fi
        done
    fi

    # ── Checkpoint every 10 parsecs ───────────────────────────────
    if [ $(( PARSEC % 10 )) -eq 0 ]; then
        _checkpoint_items_gained=$(( _after_passing - CHECKPOINT_PASSING_PREV ))
        _checkpoint_vel=$(python3 -c "print(f'{${_checkpoint_items_gained}/10:.1f}')" 2>/dev/null || echo "?")
        _remaining_parsecs="∞"
        [ "$MAX_PARSECS" -gt 0 ] && _remaining_parsecs=$(( MAX_PARSECS - PARSEC ))
        _stuck_summary=$([ -f "$STUCK_FILE" ] && awk '$2>=3{printf "#%s(%dx) ", $1, $2}' "$STUCK_FILE" || echo "none")
        _specs_done=$(python3 -c "
import json
with open('docs/specs/PRD.json') as f:
    data = json.load(f)
items = data if isinstance(data, list) else data.get('items', [])
specs = {}
for item in items:
    spec = item.get('spec', 'unknown')
    if spec not in specs:
        specs[spec] = {'pass': 0, 'total': 0}
    specs[spec]['total'] += 1
    if item.get('passes'):
        specs[spec]['pass'] += 1
import os
done = [os.path.basename(s) for s,c in specs.items() if c['pass']==c['total']]
print(', '.join(done) if done else 'none')
" 2>/dev/null || echo "?")

        echo ""
        printf "  ${YELLOW}━━━ CHECKPOINT (parsec %d) ━━━${RESET}\n" "$PARSEC"
        printf "  ${DIM}Last 10:${RESET} ${WHITE}+%d items${RESET}${DIM}, velocity ${WHITE}%s/parsec${RESET}\n" \
            "$_checkpoint_items_gained" "$_checkpoint_vel"
        printf "  ${DIM}Stuck:${RESET}   ${ORANGE}%s${RESET}\n" "$_stuck_summary"
        printf "  ${DIM}Specs done:${RESET} ${GREEN}%s${RESET}\n" "$_specs_done"
        if [ "$VELOCITY_SUM" -gt 0 ]; then
            printf "  ${DIM}ETA:${RESET}     ${CYAN}~%s (%s parsecs remaining)${RESET}\n" \
                "$_eta_str" "$_remaining_parsecs"
        fi
        echo ""
        show_spec_progress
        echo ""
        CHECKPOINT_PASSING_PREV=$_after_passing
    fi

    # ── Completion check ──────────────────────────────────────────
    if check_all_complete; then
        TOTAL_END=$(date +%s)
        echo ""
        printf "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        printf "  ${WHITE}${BOLD}  ✦  A L L   I T E M S   P A S S I N G  ✦${RESET}\n"
        printf "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        echo ""
        printf "  ${WHITE}Parsecs:${RESET} %d    ${WHITE}Time:${RESET} %s\n" \
            "$PARSEC" "$(format_duration $((TOTAL_END - TOTAL_START)))"
        show_progress
        echo ""
        printf "  ${DIM}\"Great shot kid, that was one in a million!\"${RESET}\n"
        echo ""
        if command -v osascript &>/dev/null; then
            osascript -e "display notification \"All PRD items passing after ${PARSEC} parsecs.\" with title \"Kessel Run Complete\" sound name \"Glass\""
        fi
        cleanup_state
        rm -f "$STUCK_FILE"
        break
    fi
done
