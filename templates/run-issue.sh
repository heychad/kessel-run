#!/usr/bin/env bash
# run-issue.sh — autonomous worker for one GitHub issue (or a batch).
# Creates a worktree, runs kessel-run against a filtered PRD, opens a ready PR.
#
# Usage:
#   ./scripts/kessel-run/run-issue.sh 42                 # one issue
#   ./scripts/kessel-run/run-issue.sh 42,47              # multiple issues as one batch
#   ./scripts/kessel-run/run-issue.sh --batch A          # all issues with github_batch == "A"
#   ./scripts/kessel-run/run-issue.sh 42 --keep-worktree # don't cleanup on success
#   ./scripts/kessel-run/run-issue.sh 42 --dry-run       # print plan, don't execute
#
# Exit codes:
#   0 — all items passed, PR opened
#   1 — prerequisite failure (no gh, dirty repo, missing PRD)
#   2 — loop ran but items stuck; stuck report posted to issue(s)
#   3 — loop crashed or unknown failure
set -euo pipefail

# ── Config ─────────────────────────────────────────────────────────
KESSEL_DIR="${KESSEL_DIR:-scripts/kessel-run}"
PRD_PATH="${PRD_PATH:-docs/specs/PRD.json}"
WORKTREE_BASE="${WORKTREE_BASE:-.claude/worktrees}"
BRANCH_PREFIX="${BRANCH_PREFIX:-feature/}"
PR_LABEL="${PR_LABEL:-agent-built}"
PR_BASE="${PR_BASE:-main}"
KESSEL_MODEL="${KESSEL_MODEL:-claude-sonnet-4-6}"
export KESSEL_MODEL

# ── ANSI ───────────────────────────────────────────────────────────
YELLOW='\033[38;5;220m'
CYAN='\033[38;5;117m'
GREEN='\033[38;5;114m'
RED='\033[38;5;203m'
DIM='\033[38;5;240m'
BOLD='\033[1m'
RESET='\033[0m'

log()  { printf "${CYAN}[run-issue]${RESET} %s\n" "$*"; }
ok()   { printf "${GREEN}[run-issue]${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}[run-issue]${RESET} %s\n" "$*"; }
die()  { printf "${RED}[run-issue]${RESET} %s\n" "$*" >&2; exit 1; }

# ── Args ──────────────────────────────────────────────────────────
ISSUES=""
BATCH_NAME=""
KEEP_WORKTREE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --batch)          BATCH_NAME="$2"; shift 2 ;;
        --batch=*)        BATCH_NAME="${1#*=}"; shift ;;
        --keep-worktree)  KEEP_WORKTREE=true; shift ;;
        --dry-run)        DRY_RUN=true; shift ;;
        -h|--help)        sed -n '2,12p' "$0"; exit 0 ;;
        *)                ISSUES="$1"; shift ;;
    esac
done

[ -z "$ISSUES" ] && [ -z "$BATCH_NAME" ] && die "Provide issue numbers (e.g. 42,47) or --batch <name>"

# ── Prerequisites ─────────────────────────────────────────────────
command -v gh >/dev/null || die "gh CLI not installed"
command -v jq >/dev/null || die "jq not installed"
gh auth status >/dev/null 2>&1 || die "gh not authenticated — run 'gh auth login'"
[ -f "$PRD_PATH" ] || die "PRD not found at $PRD_PATH"
[ -d "$KESSEL_DIR" ] || die "kessel-run not installed at $KESSEL_DIR — run init.sh"

# Require clean tree on main so we don't worktree off dirty state
if [ -n "$(git status --porcelain)" ]; then
    die "Working tree dirty — commit or stash before running"
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# ── Resolve issue list ────────────────────────────────────────────
if [ -n "$BATCH_NAME" ]; then
    ISSUES=$(jq -r --arg b "$BATCH_NAME" \
        '[.items[] | select(.github_batch == $b) | .github_issue] | unique | join(",")' \
        "$PRD_PATH")
    [ -z "$ISSUES" ] && die "No items with github_batch == \"$BATCH_NAME\" in $PRD_PATH"
    log "Batch ${BOLD}$BATCH_NAME${RESET} resolves to issues: $ISSUES"
fi

IFS=',' read -ra ISSUE_ARR <<< "$ISSUES"
[ ${#ISSUE_ARR[@]} -eq 0 ] && die "No issues to process"

# ── Filter PRD to matching items ──────────────────────────────────
# jq produces a PRD.json containing only items whose github_issue is in the list,
# with IDs renumbered starting at 1 so loop.sh works cleanly.
FILTERED_PRD=$(jq --argjson issues "$(printf '%s\n' "${ISSUE_ARR[@]}" | jq -R 'tonumber' | jq -s .)" '
    .items |= ([.[] | select(.github_issue != null and (.github_issue | IN($issues[])))] |
        to_entries | map(.value + {id: (.key + 1)}))
' "$PRD_PATH")

ITEM_COUNT=$(echo "$FILTERED_PRD" | jq '.items | length')
[ "$ITEM_COUNT" -eq 0 ] && die "No PRD items reference issue(s) $ISSUES"
log "Filtered PRD: $ITEM_COUNT items for issues $ISSUES"

# ── Branch + worktree naming ──────────────────────────────────────
# Always fetch the first issue's title — used for PR title and
# (in non-batch mode) the slug. Default to "issue" if gh lookup fails.
FIRST_ISSUE="${ISSUE_ARR[0]}"
TITLE=$(gh issue view "$FIRST_ISSUE" --json title -q .title 2>/dev/null || echo "issue")

if [ -n "$BATCH_NAME" ]; then
    SLUG="batch-$(echo "$BATCH_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g')"
else
    title_slug=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g' | cut -c1-40)
    if [ ${#ISSUE_ARR[@]} -gt 1 ]; then
        SLUG="issues-$(IFS=-; echo "${ISSUE_ARR[*]}")-${title_slug}"
    else
        SLUG="issue-${FIRST_ISSUE}-${title_slug}"
    fi
fi

BRANCH="${BRANCH_PREFIX}${SLUG}"
WORKTREE="${WORKTREE_BASE}/${SLUG}"

log "Branch:   ${BOLD}$BRANCH${RESET}"
log "Worktree: ${BOLD}$WORKTREE${RESET}"

if [ "$DRY_RUN" = true ]; then
    ok "Dry run — would create worktree and run loop with $ITEM_COUNT items"
    echo "$FILTERED_PRD" | jq '.items[] | {id, github_issue, description}'
    exit 0
fi

# ── Create worktree ───────────────────────────────────────────────
[ -d "$WORKTREE" ] && die "Worktree already exists: $WORKTREE (remove with 'git worktree remove $WORKTREE')"
mkdir -p "$(dirname "$WORKTREE")"
git worktree add -b "$BRANCH" "$WORKTREE" "$PR_BASE" >/dev/null
ok "Worktree created at $WORKTREE"

# Preflight: the worktree checkout must have the kessel-run scripts committed,
# otherwise loop.sh won't be found. This catches the common "I scaffolded but
# didn't commit yet" footgun with a clear message.
if [ ! -x "$WORKTREE/$KESSEL_DIR/loop.sh" ]; then
    git worktree remove "$WORKTREE" --force 2>/dev/null || true
    die "$KESSEL_DIR/loop.sh missing in worktree — commit kessel-run scripts on $PR_BASE first"
fi

# ── Write filtered PRD inside worktree ────────────────────────────
mkdir -p "$(dirname "$WORKTREE/$PRD_PATH")"
echo "$FILTERED_PRD" > "$WORKTREE/$PRD_PATH"
log "Wrote filtered PRD to $WORKTREE/$PRD_PATH"

# ── Run loop inside worktree ──────────────────────────────────────
MAX_PARSECS=$((ITEM_COUNT * 2 + 4))
log "Starting loop with KESSEL_MAX_PARSECS=$MAX_PARSECS"

LOOP_EXIT=0
(
    cd "$WORKTREE"
    KESSEL_MAX_PARSECS="$MAX_PARSECS" bash "$KESSEL_DIR/loop.sh"
) || LOOP_EXIT=$?

# ── Evaluate outcome ──────────────────────────────────────────────
PASSING=$(jq '[.items[] | select(.passes == true)] | length' "$WORKTREE/$PRD_PATH")
TOTAL=$(jq '.items | length' "$WORKTREE/$PRD_PATH")
log "Loop exited ($LOOP_EXIT). Items passing: $PASSING/$TOTAL"

# ── Build PR/comment body ─────────────────────────────────────────
ISSUES_CLOSES=$(printf 'Closes #%s\n' "${ISSUE_ARR[@]}")
ITEMS_SUMMARY=$(jq -r '.items[] | "- [" + (if .passes then "x" else " " end) + "] #" + (.github_issue|tostring) + ": " + .description' "$WORKTREE/$PRD_PATH")
PROGRESS_TAIL=$(tail -60 "$WORKTREE/docs/PROGRESS.md" 2>/dev/null || echo "(no progress log)")

# Manual verification plan (investigate skill Step 6 format) — give reviewers
# a concrete checklist instead of just a diff to eyeball. One "Test" per item,
# derived from the item's user-visible description + spec reference.
MANUAL_VERIFY=$(jq -r '
  .items
  | to_entries
  | map(
      "### Test " + ([.key + 65] | implode) + ": " + .value.description + "\n" +
      "1. (Exercise the change — see spec: `" + .value.spec + "`)\n" +
      "2. **Expected:** " + .value.description + " — works end-to-end for the flow described in issue #" + (.value.github_issue|tostring) + ".\n"
    )
  | join("\n")
' "$WORKTREE/$PRD_PATH")

if [ "$PASSING" -eq "$TOTAL" ] && [ "$LOOP_EXIT" -eq 0 ]; then
    # ── Success: push + open PR ─────────────────────────────────
    (cd "$WORKTREE" && git push -u origin "$BRANCH")

    PR_BODY=$(cat <<EOF
> ⚠️ **Autonomous build** — human review required before merge.

## Summary

$ITEMS_SUMMARY

$ISSUES_CLOSES

## Automated verification

All PRD items passed backpressure: types, lint, tests, build.
Generated by kessel-run in worktree \`$WORKTREE\`.

## Manual verification checklist

_Format borrowed from the \`/investigate\` skill (Step 6). Walk through before approving._

$MANUAL_VERIFY

## Recent progress log

\`\`\`
$PROGRESS_TAIL
\`\`\`
EOF
)

    if [ -n "$BATCH_NAME" ]; then
        PR_TITLE="batch $BATCH_NAME: ${#ISSUE_ARR[@]} issue(s), $ITEM_COUNT items"
    elif [ ${#ISSUE_ARR[@]} -eq 1 ]; then
        PR_TITLE="#${ISSUE_ARR[0]}: $(echo "$TITLE" | head -c 70)"
    else
        PR_TITLE="#${ISSUE_ARR[0]} + ${#ISSUE_ARR[@]}-issue batch: $ITEM_COUNT items"
    fi

    PR_URL=$(cd "$WORKTREE" && gh pr create \
        --title "$PR_TITLE" \
        --body "$PR_BODY" \
        --base "$PR_BASE" \
        --label "$PR_LABEL" 2>&1 | tail -1)

    ok "PR opened: $PR_URL"

    # Comment on each issue
    for issue in "${ISSUE_ARR[@]}"; do
        gh issue comment "$issue" --body "Autonomous build complete — see $PR_URL" >/dev/null || warn "Could not comment on #$issue"
    done

    # Cleanup worktree unless --keep-worktree
    if [ "$KEEP_WORKTREE" = false ]; then
        git worktree remove "$WORKTREE" --force
        ok "Worktree cleaned up"
    else
        log "Worktree kept at $WORKTREE"
    fi
    exit 0
else
    # ── Stuck or failed ─────────────────────────────────────────
    STUCK_BODY=$(cat <<EOF
## Autonomous build stuck

Progress: **$PASSING/$TOTAL** items passed.

$ITEMS_SUMMARY

Worktree left in place for manual pickup: \`$WORKTREE\` on branch \`$BRANCH\`.

## Recent progress log

\`\`\`
$PROGRESS_TAIL
\`\`\`
EOF
)
    for issue in "${ISSUE_ARR[@]}"; do
        gh issue comment "$issue" --body "$STUCK_BODY" >/dev/null || warn "Could not comment on #$issue"
    done
    warn "Loop stuck — comments posted to issues, worktree preserved at $WORKTREE"
    exit 2
fi
