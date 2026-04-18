#!/usr/bin/env bash
# overnight.sh — orchestrate parallel autonomous builds across all batches.
# Reads PRD.json, groups items by github_batch, runs each batch in its own worktree,
# writes a morning digest log.
#
# Usage:
#   ./scripts/kessel-run/overnight.sh                   # all batches, parallel N=3
#   ./scripts/kessel-run/overnight.sh --parallel 5      # bump parallelism
#   ./scripts/kessel-run/overnight.sh --serial          # one at a time
#   ./scripts/kessel-run/overnight.sh --batches A,C     # only these batches
#   ./scripts/kessel-run/overnight.sh --dry-run         # print plan only
set -euo pipefail

KESSEL_DIR="${KESSEL_DIR:-scripts/kessel-run}"
PRD_PATH="${PRD_PATH:-docs/specs/PRD.json}"
PARALLEL="${KESSEL_PARALLEL:-3}"
ONLY_BATCHES=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --parallel)   PARALLEL="$2"; shift 2 ;;
        --parallel=*) PARALLEL="${1#*=}"; shift ;;
        --serial)     PARALLEL=1; shift ;;
        --batches)    ONLY_BATCHES="$2"; shift 2 ;;
        --batches=*)  ONLY_BATCHES="${1#*=}"; shift ;;
        --dry-run)    DRY_RUN=true; shift ;;
        -h|--help)    sed -n '2,12p' "$0"; exit 0 ;;
        *)            echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

# ── ANSI ───────────────────────────────────────────────────────────
YELLOW='\033[38;5;220m'
CYAN='\033[38;5;117m'
GREEN='\033[38;5;114m'
RED='\033[38;5;203m'
DIM='\033[38;5;240m'
BOLD='\033[1m'
RESET='\033[0m'

log() { printf "${CYAN}[overnight]${RESET} %s\n" "$*"; }
die() { printf "${RED}[overnight]${RESET} %s\n" "$*" >&2; exit 1; }

# ── Prerequisites ─────────────────────────────────────────────────
command -v jq >/dev/null || die "jq not installed"
[ -f "$PRD_PATH" ] || die "PRD not found at $PRD_PATH"
[ -x "$KESSEL_DIR/run-issue.sh" ] || die "$KESSEL_DIR/run-issue.sh not found or not executable"
[ -n "$(git status --porcelain)" ] && die "Working tree dirty — commit or stash before overnight run"

# ── Resolve batches ───────────────────────────────────────────────
ALL_BATCHES=$(jq -r '[.items[].github_batch // empty] | unique | .[]' "$PRD_PATH")
[ -z "$ALL_BATCHES" ] && die "No items have github_batch set — run plan-sprint --issues first"

if [ -n "$ONLY_BATCHES" ]; then
    IFS=',' read -ra WANTED <<< "$ONLY_BATCHES"
    BATCHES=""
    for want in "${WANTED[@]}"; do
        if echo "$ALL_BATCHES" | grep -qx "$want"; then
            BATCHES+="$want"$'\n'
        else
            die "Batch '$want' not found in PRD"
        fi
    done
    BATCHES=$(echo "$BATCHES" | sed '/^$/d')
else
    BATCHES="$ALL_BATCHES"
fi

BATCH_COUNT=$(echo "$BATCHES" | wc -l | tr -d ' ')
log "Planned: ${BOLD}$BATCH_COUNT${RESET} batch(es), parallelism=${BOLD}$PARALLEL${RESET}"
echo "$BATCHES" | while read -r b; do
    count=$(jq --arg b "$b" '[.items[] | select(.github_batch == $b)] | length' "$PRD_PATH")
    issues=$(jq -r --arg b "$b" '[.items[] | select(.github_batch == $b) | .github_issue] | unique | join(",")' "$PRD_PATH")
    printf "  ${DIM}batch${RESET} ${BOLD}%s${RESET}  items=%s  issues=%s\n" "$b" "$count" "$issues"
done

[ "$DRY_RUN" = true ] && { log "Dry run — exiting"; exit 0; }

# ── Setup digest log ──────────────────────────────────────────────
mkdir -p logs
DIGEST="logs/overnight-$(date +%Y-%m-%d-%H%M%S).md"
START_TS=$(date +%s)

cat > "$DIGEST" <<EOF
# Overnight run — $(date)

Batches: $BATCH_COUNT
Parallelism: $PARALLEL
Started: $(date)

---

EOF

log "Digest: $DIGEST"

# ── Run each batch, tracking pids ─────────────────────────────────
# Arrays live in parent shell — the driver loop uses process substitution
# (not a pipe) so PIDS+=() mutations persist across iterations.
declare -a PIDS=()
declare -a BATCH_LOGS=()  # this-run logs only, used for digest assembly

wait_for_slot() {
    while [ "${#PIDS[@]}" -ge "$PARALLEL" ]; do
        for i in "${!PIDS[@]}"; do
            if ! kill -0 "${PIDS[$i]}" 2>/dev/null; then
                wait "${PIDS[$i]}" 2>/dev/null || true
                unset 'PIDS[i]'
            fi
        done
        PIDS=("${PIDS[@]+"${PIDS[@]}"}")
        if [ "${#PIDS[@]}" -ge "$PARALLEL" ]; then
            sleep 2
        fi
    done
    return 0
}

while read -r batch; do
    [ -z "$batch" ] && continue
    wait_for_slot
    log "▶ Launching batch ${BOLD}$batch${RESET}"
    batch_log="logs/batch-${batch}-$(date +%Y%m%d-%H%M%S).log"
    BATCH_LOGS+=("$batch_log")
    ( bash "$KESSEL_DIR/run-issue.sh" --batch "$batch" > "$batch_log" 2>&1; echo $? > "$batch_log.exit" ) &
    PIDS+=($!)
done < <(echo "$BATCHES")

# ── Wait for all remaining ────────────────────────────────────────
log "Waiting for all batches to complete..."
wait

END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))

# ── Assemble digest from exit codes + batch logs ──────────────────
GREEN_COUNT=0
STUCK_COUNT=0
FAIL_COUNT=0

for batch_log in "${BATCH_LOGS[@]}"; do
    [ -f "$batch_log" ] || continue
    [ -f "$batch_log.exit" ] || continue
    exit_code=$(cat "$batch_log.exit")
    batch_name=$(basename "$batch_log" | sed -E 's/^batch-([^-]+)-.*/\1/')

    # Find PR URL or stuck indicator in log
    pr_url=$(grep -oE 'https://github.com/[^ ]+/pull/[0-9]+' "$batch_log" | tail -1 || true)

    case "$exit_code" in
        0)  status="✅ GREEN"; GREEN_COUNT=$((GREEN_COUNT + 1)) ;;
        2)  status="⚠️ STUCK"; STUCK_COUNT=$((STUCK_COUNT + 1)) ;;
        *)  status="❌ FAIL ($exit_code)"; FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    esac

    {
        echo "## Batch $batch_name — $status"
        echo ""
        [ -n "$pr_url" ] && echo "PR: $pr_url"
        echo ""
        echo "Log: \`$batch_log\`"
        echo ""
        echo "<details><summary>Tail</summary>"
        echo ""
        echo '```'
        tail -30 "$batch_log" | sed 's/\x1b\[[0-9;]*m//g'
        echo '```'
        echo ""
        echo "</details>"
        echo ""
        echo "---"
        echo ""
    } >> "$DIGEST"

    rm -f "$batch_log.exit"
done

# ── Summary header ────────────────────────────────────────────────
{
    echo ""
    echo "## Summary"
    echo ""
    echo "- Green:  **$GREEN_COUNT**"
    echo "- Stuck:  **$STUCK_COUNT**"
    echo "- Failed: **$FAIL_COUNT**"
    echo "- Elapsed: $((ELAPSED / 60))m $((ELAPSED % 60))s"
    echo ""
} >> "$DIGEST"

# Print digest path big
printf "\n${GREEN}━━━ OVERNIGHT COMPLETE ━━━${RESET}\n"
printf "  Green: ${BOLD}%d${RESET}  Stuck: ${BOLD}%d${RESET}  Failed: ${BOLD}%d${RESET}\n" "$GREEN_COUNT" "$STUCK_COUNT" "$FAIL_COUNT"
printf "  Elapsed: ${BOLD}%dm %ds${RESET}\n" $((ELAPSED / 60)) $((ELAPSED % 60))
printf "  Digest:  ${BOLD}%s${RESET}\n\n" "$DIGEST"
printf "  Read with: ${CYAN}bash %s/morning-digest.sh${RESET}\n\n" "$KESSEL_DIR"

[ "$FAIL_COUNT" -gt 0 ] && exit 3
exit 0
