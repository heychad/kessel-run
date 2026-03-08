#!/usr/bin/env bash
# Kessel Run — autonomous loop for Claude Code.
# Fresh context every parsec. Stream everything. Never capture into variables.
#
# Usage:
#   ./scripts/kessel-run/loop.sh              # run max parsecs (auto-scaled)
#   ./scripts/kessel-run/loop.sh 5            # run 5 parsecs
#   ./scripts/kessel-run/loop.sh 0            # unlimited parsecs
#   ./scripts/kessel-run/loop.sh watch        # single parsec in TUI mode
#   ./scripts/kessel-run/loop.sh --skip-stuck 5  # exclude items stuck 5+ cycles
#   KESSEL_SKIP_STUCK=5 ./scripts/kessel-run/loop.sh  # same via env
set -euo pipefail

KESSEL_MODEL="${KESSEL_MODEL:-claude-sonnet-4-6}"
KESSEL_DIR="${KESSEL_DIR:-scripts/kessel-run}"

# ── Parse flags ────────────────────────────────────────────────
SKIP_STUCK_THRESHOLD="${KESSEL_SKIP_STUCK:-0}"  # 0 = disabled
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-stuck)
            SKIP_STUCK_THRESHOLD="${2:-5}"
            shift 2
            ;;
        --skip-stuck=*)
            SKIP_STUCK_THRESHOLD="${1#*=}"
            shift
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

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

# ── Constants ──────────────────────────────────────────────────
STUCK_WARN_THRESHOLD="${KESSEL_STUCK_THRESHOLD:-3}"  # warn after N consecutive failures
STUCK_FILE=".kessel-run-stuck"         # persists across parsecs, gitignored
STATE_FILE=".kessel-run-state"         # crash-resume state
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/kessel-run.log"

# ── Cleanup ──────────────────────────────────────────────────────
cleanup() {
    [ -n "${TIMER_PID:-}" ] && kill "$TIMER_PID" 2>/dev/null
    TIMER_PID=""
    printf '\033]0;\007'
}

# Graceful Ctrl+C — show status snapshot before exiting
handle_interrupt() {
    cleanup

    local now elapsed progress passing total gained
    now=$(date +%s)
    elapsed=$((now - ${TOTAL_START:-$now}))
    progress=$(count_prd_progress 2>/dev/null || echo "? ? ")
    passing=${progress%% *}
    total=$(echo "$progress" | cut -d' ' -f2)
    gained=$(( ${passing:-0} - ${TOTAL_ITEMS_PASSED_START:-0} ))
    [ "$gained" -lt 0 ] && gained=0

    echo ""
    printf "\n  ${YELLOW}━━━ INTERRUPTED ━━━${RESET}\n"
    printf "  ${DIM}Parsec:${RESET} ${WHITE}%s${RESET}  ${DIM}Time:${RESET} ${WHITE}%s${RESET}  ${DIM}Items gained:${RESET} ${WHITE}+%d${RESET}  ${DIM}Progress:${RESET} ${WHITE}%s/%s${RESET}\n" \
        "${PARSEC:-?}" "$(format_duration $elapsed)" "$gained" "$passing" "$total"
    if [ -n "${_vel_str:-}" ] && [ "${_vel_str:-0.0}" != "0.0" ]; then
        printf "  ${DIM}Velocity:${RESET} ${CYAN}%s items/parsec${RESET}  ${DIM}State saved — resume with same command${RESET}\n" "$_vel_str"
    else
        printf "  ${DIM}State saved — resume with same command${RESET}\n"
    fi
    printf "  ${YELLOW}━━━━━━━━━━━━━━━━━━━${RESET}\n\n"
    exit 130
}

trap cleanup EXIT
trap handle_interrupt INT

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

# Read PRD progress — sets global PRD_PASSING, PRD_TOTAL, PRD_FAILING_CSV.
# Call once and reuse, instead of spawning python3 + parsing JSON repeatedly.
read_prd_progress() {
    local progress
    progress=$(python3 -c "
import json
with open('docs/specs/PRD.json') as f:
    data = json.load(f)
items = data if isinstance(data, list) else data.get('items', [])
total = len(items)
passing = sum(1 for i in items if i.get('passes'))
failing_ids = [str(i.get('id', idx)) for idx, i in enumerate(items) if not i.get('passes')]
print(f'{passing} {total} {chr(44).join(failing_ids)}')
" 2>/dev/null || echo "0 0 ")
    PRD_PASSING=${progress%% *}
    PRD_TOTAL=$(echo "$progress" | cut -d' ' -f2)
    PRD_FAILING_CSV=$(echo "$progress" | cut -d' ' -f3)
}

# Update .kessel-run-stuck with current failing IDs.
# File format: one "ID COUNT" per line.
update_stuck_file() {
    local failing_csv="$1"   # comma-separated currently-failing IDs (may be empty)

    declare -A counts
    if [ -f "$STUCK_FILE" ]; then
        while read -r id cnt; do
            counts["$id"]=$cnt
        done < "$STUCK_FILE"
    fi

    declare -A currently_failing
    if [ -n "$failing_csv" ]; then
        IFS=',' read -ra fids <<< "$failing_csv"
        for fid in "${fids[@]}"; do
            [ -n "$fid" ] && currently_failing["$fid"]=1
        done
    fi

    declare -A new_counts
    for id in "${!counts[@]}"; do
        if [ -n "${currently_failing[$id]:-}" ]; then
            new_counts["$id"]=$(( counts[$id] + 1 ))
        fi
    done
    for id in "${!currently_failing[@]}"; do
        if [ -z "${counts[$id]:-}" ]; then
            new_counts["$id"]=1
        fi
    done

    : > "$STUCK_FILE"
    for id in "${!new_counts[@]}"; do
        echo "$id ${new_counts[$id]}" >> "$STUCK_FILE"
    done
}

# Returns warning line if any item has failed STUCK_WARN_THRESHOLD+ consecutive parsecs.
get_stuck_warning() {
    [ -f "$STUCK_FILE" ] || return 0
    local stuck_ids=()
    while read -r id cnt; do
        if [ "$cnt" -ge "$STUCK_WARN_THRESHOLD" ]; then
            stuck_ids+=("#${id}(${cnt}x)")
        fi
    done < "$STUCK_FILE"
    if [ "${#stuck_ids[@]}" -gt 0 ]; then
        local joined
        joined=$(IFS=', '; echo "${stuck_ids[*]}")
        printf "${ORANGE}⚠ %d stuck item(s): %s (failed %d+ cycles)${RESET}" \
            "${#stuck_ids[@]}" "$joined" "$STUCK_WARN_THRESHOLD"
    fi
}

# Returns comma-separated IDs of stuck items at given threshold.
get_stuck_ids_for_prompt() {
    [ -f "$STUCK_FILE" ] || return 0
    local threshold=${1:-$STUCK_WARN_THRESHOLD}
    local ids=()
    while read -r id cnt; do
        [ "$cnt" -ge "$threshold" ] && ids+=("$id")
    done < "$STUCK_FILE"
    (IFS=','; echo "${ids[*]}")
}

# Show spec-level progress table.
show_spec_progress() {
    python3 -c "
import json, os

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

bar_w = 16
name_w = max(len(os.path.basename(s)) for s in specs) + 1
for spec, counts in sorted(specs.items()):
    name = os.path.basename(spec)
    p, t = counts['pass'], counts['total']
    pct = p / t if t else 0
    filled = round(pct * bar_w)
    empty = bar_w - filled
    if 0 < p < t:
        empty = max(0, empty - 1)
        bar = '\u2588' * filled + '\u25b8' + '\u2591' * empty
    else:
        bar = '\u2588' * filled + '\u2591' * empty
    if p == t:
        status = '\033[38;5;114m\u2713\033[0m'
    elif p == 0:
        status = '\033[38;5;240m\u2014\033[0m'
    else:
        status = f'{round(pct*100)}%'
    print(f'  {name:<{name_w}} {bar}  {p:>3}/{t:<3}  {status}')
" 2>/dev/null || printf "  ${DIM}(spec data unavailable)${RESET}\n"
}

# End-of-run summary: hardest items and still-stuck items (single PRD read).
show_run_summary() {
    local run_outcome="$1"  # "complete" or "max"

    if [ "$run_outcome" != "complete" ]; then
        python3 -c "
import json
with open('docs/specs/PRD.json') as f:
    data = json.load(f)
items = data if isinstance(data, list) else data.get('items', [])
failing = [(i.get('id','?'), i.get('description','')[:60]) for i in items if not i.get('passes')]
if failing:
    print(f'\n  \033[1;37m\033[1mStill failing ({len(failing)}):\033[0m')
    for fid, desc in failing[:15]:
        print(f'    \033[38;5;203m#{fid}\033[0m {desc}')
    if len(failing) > 15:
        print(f'    \033[38;5;240m... and {len(failing)-15} more\033[0m')
" 2>/dev/null
    fi

    if [ -f "$STUCK_FILE" ] && [ -s "$STUCK_FILE" ]; then
        local hardest
        hardest=$(sort -t' ' -k2 -rn "$STUCK_FILE" | head -5)
        if [ -n "$hardest" ]; then
            printf "\n  ${WHITE}${BOLD}Hardest items (most attempts):${RESET}\n"
            while read -r id cnt; do
                printf "    ${ORANGE}#%s${RESET} ${DIM}— %d consecutive failures${RESET}\n" "$id" "$cnt"
            done <<< "$hardest"
        fi
    fi

    if [ -f "$LOG_FILE" ]; then
        local log_lines
        log_lines=$(wc -l < "$LOG_FILE" | tr -d ' ')
        printf "\n  ${DIM}Log: %s (%s entries)${RESET}\n" "$LOG_FILE" "$log_lines"
    fi
}

# Write one structured log line per parsec.
write_log_line() {
    local parsec=$1 passing=$2 total=$3 duration=$4 vel_str=$5 \
          attempted=$6 passed_this=$7 stuck_ids=$8

    local ts stuck_field=""
    ts=$(date -u '+%Y-%m-%dT%H:%M:%S')
    [ -n "$stuck_ids" ] && stuck_field=" stuck=#${stuck_ids//,/,#}"
    echo "${ts} parsec=${parsec} passed=${passing} total=${total} duration=${duration}s velocity=${vel_str} items_attempted=${attempted} items_passed=${passed_this}${stuck_field}" \
        >> "$LOG_FILE"
}

# Crash-resume state helpers.
write_state() {
    printf "parsec=%d\nstart=%d\n" "$1" "$2" > "$STATE_FILE"
}

read_state() {
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

# Trim PROGRESS.md to last N lines if it grows too large.
# Keeps the header (first 3 lines) and last KESSEL_PROGRESS_MAX_LINES lines.
KESSEL_PROGRESS_MAX_LINES="${KESSEL_PROGRESS_MAX_LINES:-500}"
trim_progress_log() {
    local file="docs/PROGRESS.md"
    [ -f "$file" ] || return 0
    local total_lines
    total_lines=$(wc -l < "$file" | tr -d ' ')
    if [ "$total_lines" -gt "$KESSEL_PROGRESS_MAX_LINES" ]; then
        local header tail_lines
        header=$(head -3 "$file")
        tail_lines=$(( KESSEL_PROGRESS_MAX_LINES - 5 ))
        {
            echo "$header"
            echo ""
            printf "<!-- Trimmed: older entries archived. %d lines kept of %d -->\n\n" "$tail_lines" "$total_lines"
            tail -"$tail_lines" "$file"
        } > "${file}.tmp" && mv "${file}.tmp" "$file"
    fi
}

# Compose the full prompt, injecting stuck IDs if any.
build_prompt() {
    if [ "$SKIP_STUCK_THRESHOLD" -gt 0 ]; then
        local skip_ids
        skip_ids=$(get_stuck_ids_for_prompt "$SKIP_STUCK_THRESHOLD")
        if [ -n "$skip_ids" ]; then
            printf "<!-- KESSEL-RUN: SKIP these item IDs entirely — they have failed %d+ consecutive parsecs and are excluded from this run: %s. Do NOT attempt them. -->\n\n" \
                "$SKIP_STUCK_THRESHOLD" "$skip_ids"
        fi
    fi
    local stuck_ids
    stuck_ids=$(get_stuck_ids_for_prompt "$STUCK_WARN_THRESHOLD")
    if [ -n "$stuck_ids" ]; then
        printf "<!-- KESSEL-RUN: The following item IDs have failed %d+ consecutive parsecs. Deprioritize them and focus on other failing items: %s -->\n\n" \
            "$STUCK_WARN_THRESHOLD" "$stuck_ids"
    fi
    cat "${KESSEL_DIR}/PROMPT.md"
}

# Render progress bar from PRD_PASSING/PRD_TOTAL globals (no extra reads).
show_progress_from_cache() {
    local passing=${PRD_PASSING:-0} total=${PRD_TOTAL:-0}
    if [ "$total" -eq 0 ]; then
        printf "  ${DIM}No PRD items found${RESET}\n"
        return
    fi

    local pct=$(( passing * 100 / total ))
    local pct_label="${pct}%"
    if [ "$passing" -gt 0 ] && [ "$pct" -eq 0 ]; then
        pct_label="<1%"
    fi
    local bar_width=30
    local filled=$(( passing * bar_width / total ))
    local empty=$(( bar_width - filled ))

    local filled_str empty_str
    printf -v filled_str '%*s' "$filled" '' ; filled_str="${filled_str// /█}"
    printf -v empty_str '%*s' "$empty" '' ; empty_str="${empty_str// /░}"

    if [ "$passing" -eq "$total" ]; then
        printf "  ${GREEN}%s${RESET}  ${WHITE}%d${DIM}/${WHITE}%d${RESET} items  ${GREEN}%s${RESET}\n" \
            "$filled_str" "$passing" "$total" "$pct_label"
    elif [ "$passing" -eq 0 ]; then
        printf "  ${DIM}%s${RESET}  ${WHITE}%d${DIM}/${WHITE}%d${RESET} items  ${YELLOW}%s${RESET}\n" \
            "$empty_str" "$passing" "$total" "$pct_label"
    else
        printf "  ${YELLOW}%s${WHITE}▸${DIM}%s${RESET}  ${WHITE}%d${DIM}/${WHITE}%d${RESET} items  ${YELLOW}%s${RESET}\n" \
            "$filled_str" "$empty_str" "$passing" "$total" "$pct_label"
    fi
}

# Read-then-display progress (for standalone calls outside the loop).
show_progress() {
    read_prd_progress
    show_progress_from_cache
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
    # Uses PRD_PASSING/PRD_TOTAL already set by caller
    show_progress_from_cache
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

# Check required commands
for cmd in python3 claude git; do
    if ! command -v "$cmd" &>/dev/null; then
        printf "  ${RED}✗${RESET} Command not found: ${WHITE}%s${RESET}\n" "$cmd"
        PREFLIGHT_OK=false
    fi
done

# Check required files
for f in "${KESSEL_DIR}/PROMPT.md" docs/specs/PRD.json "${KESSEL_DIR}/backpressure.sh" docs/PROGRESS.md; do
    if [ ! -f "$f" ]; then
        printf "  ${RED}✗${RESET} Missing: ${WHITE}%s${RESET}\n" "$f"
        PREFLIGHT_OK=false
    fi
done

# Check backpressure.sh is executable
if [ -f "${KESSEL_DIR}/backpressure.sh" ] && [ ! -x "${KESSEL_DIR}/backpressure.sh" ]; then
    printf "  ${ORANGE}⚠${RESET} ${WHITE}%s${RESET} is not executable, fixing...\n" "${KESSEL_DIR}/backpressure.sh"
    chmod +x "${KESSEL_DIR}/backpressure.sh"
fi

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
if [ "$SKIP_STUCK_THRESHOLD" -gt 0 ]; then
    printf "  ${GREEN}✓${RESET} ${DIM}Skip stuck${RESET}   ${WHITE}%d+ cycles${RESET}\n" "$SKIP_STUCK_THRESHOLD"
fi
printf "  ${DIM}Tip: tail -f %s for a quiet dashboard${RESET}\n" "$LOG_FILE"
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
    rm -f "$STUCK_FILE"
fi

PREV_DURATION=0
VELOCITY_SUM=0
VELOCITY_COUNT=0
_vel_str="0.0"
_eta_str="unknown"

# ── Auto-scale max parsecs ───────────────────────────────────────
read_prd_progress
_auto_max=$(( (PRD_TOTAL * 3 + 1) / 2 ))
[ "$_auto_max" -lt 12 ] && _auto_max=12
MAX_PARSECS="${1:-${KESSEL_MAX_PARSECS:-${_auto_max}}}"

printf "  ${DIM}Max parsecs:${RESET} ${WHITE}%s${RESET} ${DIM}(auto: ceil(%d × 1.5) = %d; 0 = unlimited)${RESET}\n" \
    "$MAX_PARSECS" "$PRD_TOTAL" "$_auto_max"

TOTAL_ITEMS_PASSED_START=$PRD_PASSING
PREV_PASSING=$PRD_PASSING
CHECKPOINT_PASSING_PREV=$PRD_PASSING

show_progress_from_cache
echo ""

# Create log dir once (not per iteration)
mkdir -p "$LOG_DIR"

# Milestone tracking — values 25/50/75 are safe for substring matching
MILESTONES_SENT=""

# ── Main loop ────────────────────────────────────────────────────
while true; do
    PARSEC=$((PARSEC + 1))
    CYCLE_START=$(date +%s)

    write_state "$PARSEC" "$TOTAL_START"

    if [ "$MAX_PARSECS" -gt 0 ] && [ "$PARSEC" -gt "$MAX_PARSECS" ]; then
        TOTAL_END=$(date +%s)
        read_prd_progress
        echo ""
        printf "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        printf "  ${WHITE}${BOLD}MAX PARSECS (%d) REACHED${RESET}  ${DIM}total ${WHITE}%s${RESET}\n" \
            "$MAX_PARSECS" "$(format_duration $((TOTAL_END - TOTAL_START)))"
        show_progress_from_cache
        show_run_summary "max"
        printf "\n  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        cleanup_state
        break
    fi

    # Trim PROGRESS.md if it's grown too large (prevents context bloat)
    trim_progress_log

    # Read PRD once for the header — reuse for before-snapshot too
    read_prd_progress
    _before_passing=$PRD_PASSING

    TOTAL_NOW=$(date +%s)
    show_parsec_header "$PARSEC" "$PREV_DURATION" "$((TOTAL_NOW - TOTAL_START))"

    # Show velocity/ETA from previous iteration's computation (data hasn't changed)
    if [ "$VELOCITY_COUNT" -gt 0 ] && [ "$_vel_str" != "0.0" ]; then
        printf "  ${CYAN}⚡ %s items/parsec  ~%s remaining${RESET}\n\n" \
            "$_vel_str" "$_eta_str"
    fi

    # Show stuck warning if any
    _stuck_warn=$(get_stuck_warning)
    [ -n "$_stuck_warn" ] && printf "  %s\n" "$_stuck_warn"

    # Live timer in terminal title bar
    start_timer "$PARSEC" "$CYCLE_START" &
    TIMER_PID=$!

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

    # ── Post-parsec metrics (single PRD read) ──────────────────────
    read_prd_progress
    _after_passing=$PRD_PASSING
    _after_total=$PRD_TOTAL

    _items_passed_this=$(( _after_passing - _before_passing ))
    [ "$_items_passed_this" -lt 0 ] && _items_passed_this=0

    update_stuck_file "$PRD_FAILING_CSV"
    _stuck_ids_log=$(get_stuck_ids_for_prompt)

    # Compute velocity and ETA (awk instead of python3 for simple math)
    VELOCITY_SUM=$(( VELOCITY_SUM + _items_passed_this ))
    VELOCITY_COUNT=$(( VELOCITY_COUNT + 1 ))

    _vel_str="0.0"
    _eta_str="unknown"
    if [ "$VELOCITY_SUM" -gt 0 ]; then
        _remaining=$(( _after_total - _after_passing ))
        _avg_dur=$(( (CYCLE_END - TOTAL_START) / VELOCITY_COUNT ))
        _vel_str=$(awk "BEGIN{printf \"%.1f\", ${VELOCITY_SUM}/${VELOCITY_COUNT}}")
        _parsecs_rem=$(awk "BEGIN{v=${VELOCITY_SUM}/${VELOCITY_COUNT}; print (v>0) ? int(${_remaining}/v + 0.999) : 0}")
        _eta_secs=$(( _parsecs_rem * _avg_dur ))
        _eta_str=$(format_duration "$_eta_secs")
    fi

    _remaining_items=$(( _after_total - _after_passing ))
    echo ""
    if [ "$_items_passed_this" -gt 0 ]; then
        printf "  ${DIM}── parsec %d done ── %s ── ${GREEN}+%d item(s)${DIM} ── %d remaining ──${RESET}\n" \
            "$PARSEC" "$(format_duration $PREV_DURATION)" "$_items_passed_this" "$_remaining_items"
    else
        printf "  ${DIM}── parsec %d done ── %s ── ${ORANGE}+0 items${DIM} ── %d remaining ──${RESET}\n" \
            "$PARSEC" "$(format_duration $PREV_DURATION)" "$_remaining_items"
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
            if [ "$_pct_now" -ge "$_ms" ] && [[ "$MILESTONES_SENT" != *" $_ms "* ]]; then
                osascript -e "display notification \"${_after_passing}/${_after_total} items passing (${_pct_now}%)\" with title \"Kessel Run — ${_ms}% milestone\"" 2>/dev/null || true
                MILESTONES_SENT="${MILESTONES_SENT} ${_ms} "
            fi
        done
    fi

    # ── Checkpoint every 10 parsecs ───────────────────────────────
    if [ $(( PARSEC % 10 )) -eq 0 ]; then
        _checkpoint_items_gained=$(( _after_passing - CHECKPOINT_PASSING_PREV ))
        _checkpoint_vel=$(awk "BEGIN{printf \"%.1f\", ${_checkpoint_items_gained}/10}")
        _remaining_parsecs="∞"
        [ "$MAX_PARSECS" -gt 0 ] && _remaining_parsecs=$(( MAX_PARSECS - PARSEC ))
        _stuck_summary=$([ -f "$STUCK_FILE" ] && awk -v t="$STUCK_WARN_THRESHOLD" '$2>=t{printf "#%s(%dx) ", $1, $2}' "$STUCK_FILE" || echo "none")
        _specs_done=$(python3 -c "
import json, os
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

    # ── Completion check (inline — no extra PRD read) ──────────────
    if [ "$_after_passing" -eq "$_after_total" ] && [ "$_after_total" -gt 0 ]; then
        TOTAL_END=$(date +%s)
        echo ""
        printf "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        printf "  ${WHITE}${BOLD}  ✦  A L L   I T E M S   P A S S I N G  ✦${RESET}\n"
        printf "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
        echo ""
        printf "  ${WHITE}Parsecs:${RESET} %d    ${WHITE}Time:${RESET} %s\n" \
            "$PARSEC" "$(format_duration $((TOTAL_END - TOTAL_START)))"
        show_progress_from_cache
        show_run_summary "complete"
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
