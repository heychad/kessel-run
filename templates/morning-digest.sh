#!/usr/bin/env bash
# morning-digest.sh — pretty-print the most recent overnight digest.
#
# Usage:
#   ./scripts/kessel-run/morning-digest.sh                  # most recent
#   ./scripts/kessel-run/morning-digest.sh logs/overnight-2026-04-18-0300.md
#   ./scripts/kessel-run/morning-digest.sh --list           # list recent digests
set -euo pipefail

LOG_DIR="${LOG_DIR:-logs}"

YELLOW='\033[38;5;220m'
CYAN='\033[38;5;117m'
GREEN='\033[38;5;114m'
RED='\033[38;5;203m'
DIM='\033[38;5;240m'
BOLD='\033[1m'
RESET='\033[0m'

if [ "${1:-}" = "--list" ]; then
    printf "${BOLD}Recent overnight digests:${RESET}\n"
    ls -1t "$LOG_DIR"/overnight-*.md 2>/dev/null | head -10
    exit 0
fi

DIGEST="${1:-}"
if [ -z "$DIGEST" ]; then
    DIGEST=$(ls -1t "$LOG_DIR"/overnight-*.md 2>/dev/null | head -1 || true)
fi
[ -z "$DIGEST" ] && { echo "No overnight digests found in $LOG_DIR/"; exit 1; }
[ -f "$DIGEST" ] || { echo "Digest not found: $DIGEST" >&2; exit 1; }

# ── Header ────────────────────────────────────────────────────────
printf "\n${CYAN}━━━ MORNING DIGEST ━━━${RESET}\n"
printf "  ${DIM}%s${RESET}\n\n" "$DIGEST"

# ── Summary line (from bottom of digest) ─────────────────────────
GREEN_COUNT=$(grep -E '^- Green:' "$DIGEST" | head -1 | grep -oE '[0-9]+' || echo "0")
STUCK_COUNT=$(grep -E '^- Stuck:' "$DIGEST" | head -1 | grep -oE '[0-9]+' || echo "0")
FAIL_COUNT=$(grep -E '^- Failed:' "$DIGEST" | head -1 | grep -oE '[0-9]+' || echo "0")
ELAPSED=$(grep -E '^- Elapsed:' "$DIGEST" | head -1 | sed 's/^- Elapsed: //' || echo "?")

printf "  ${GREEN}✓ %s green${RESET}   ${YELLOW}⚠ %s stuck${RESET}   ${RED}✗ %s failed${RESET}   ${DIM}(%s)${RESET}\n\n" \
    "$GREEN_COUNT" "$STUCK_COUNT" "$FAIL_COUNT" "$ELAPSED"

# ── Per-batch results ────────────────────────────────────────────
# Parse "## Batch <name> — <status>" + "PR: <url>"
awk '
/^## Batch / {
    batch = $0
    sub(/^## Batch /, "", batch)
    pr = ""
    next
}
/^PR: / {
    pr = $2
    next
}
/^---$/ {
    if (batch != "") {
        print batch "|" pr
        batch = ""
    }
}
' "$DIGEST" | while IFS='|' read -r batch pr; do
    if echo "$batch" | grep -q "GREEN"; then
        icon="${GREEN}✓${RESET}"
    elif echo "$batch" | grep -q "STUCK"; then
        icon="${YELLOW}⚠${RESET}"
    else
        icon="${RED}✗${RESET}"
    fi
    name=$(echo "$batch" | sed -E 's/ — .*//')
    printf "  %b  ${BOLD}%s${RESET}\n" "$icon" "$name"
    [ -n "$pr" ] && printf "      ${CYAN}%s${RESET}\n" "$pr"
done

echo ""

# ── Next actions ─────────────────────────────────────────────────
printf "${BOLD}Next actions:${RESET}\n"
if [ "$GREEN_COUNT" -gt 0 ]; then
    printf "  ${DIM}•${RESET} Review green PRs:  ${CYAN}gh pr list --label agent-built --state open${RESET}\n"
fi
if [ "$STUCK_COUNT" -gt 0 ]; then
    printf "  ${DIM}•${RESET} Inspect stuck batches — see per-batch sections in digest\n"
    printf "  ${DIM}•${RESET} Resume manually:    ${CYAN}git worktree list${RESET}\n"
fi
if [ "$FAIL_COUNT" -gt 0 ]; then
    printf "  ${DIM}•${RESET} Check failed batch logs in ${CYAN}logs/batch-*.log${RESET}\n"
fi

# Surface the next-wave prompt if the digest has one
NEXT_WAVE_CMD=$(grep -oE '\./scripts/kessel-run/overnight\.sh --wave [0-9]+' "$DIGEST" | head -1 || true)
if [ -n "$NEXT_WAVE_CMD" ]; then
    printf "  ${DIM}•${RESET} ${YELLOW}After merging today's PRs,${RESET} launch next wave: ${CYAN}%s${RESET}\n" "$NEXT_WAVE_CMD"
fi

printf "  ${DIM}•${RESET} Full digest:        ${CYAN}less %s${RESET}\n\n" "$DIGEST"
