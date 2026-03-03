#!/usr/bin/env bash
# The Hyperdrive — core Kessel Run loop.
# Fresh context every parsec. Stream everything. Never capture into variables.
#
# Usage:
#   ./scripts/kessel-run/loop.sh              # run KESSEL_MAX_PARSECS (default 12)
#   ./scripts/kessel-run/loop.sh 5            # run 5 parsecs
#   ./scripts/kessel-run/loop.sh 0            # unlimited parsecs
#   ./scripts/kessel-run/loop.sh watch        # single TUI iteration (no -p flag)
set -euo pipefail

KESSEL_MODEL="${KESSEL_MODEL:-claude-opus-4-6}"
KESSEL_DIR="${KESSEL_DIR:-scripts/kessel-run}"

# ── Star Wars banner ──────────────────────────────────────────────
echo ""
echo "  ╔═══════════════════════════════════════════════════╗"
echo "  ║         K E S S E L   R U N                       ║"
echo "  ║   The fastest hunk of junk in the galaxy          ║"
echo "  ╚═══════════════════════════════════════════════════╝"
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────
PREFLIGHT_OK=true

for f in "${KESSEL_DIR}/PROMPT.md" PRD.json "${KESSEL_DIR}/backpressure.sh" PROGRESS.md; do
    if [ ! -f "$f" ]; then
        echo "  [FAIL] Missing: $f"
        PREFLIGHT_OK=false
    fi
done

if [ "$PREFLIGHT_OK" = false ]; then
    echo ""
    echo "  Pre-flight check failed. Run init.sh first."
    echo "  \"She may not look like much, but she's got it where it counts.\""
    exit 1
fi

echo "  Pre-flight check ........... ALL GREEN"
echo "  Navigation computer ........ ${KESSEL_DIR}/PROMPT.md"
echo "  Star chart ................. PRD.json"
echo "  Deflector shields .......... ${KESSEL_DIR}/backpressure.sh"
echo "  Ship's log ................. PROGRESS.md"
echo "  Hyperdrive ................. ${KESSEL_MODEL}"
echo ""

# ── Watch mode (single TUI iteration) ─────────────────────────────
if [ "${1:-}" = "watch" ]; then
    echo "  ── WATCH MODE ── Single parsec in TUI ──"
    echo ""
    cat "${KESSEL_DIR}/PROMPT.md" | claude \
        --model "$KESSEL_MODEL" \
        --dangerously-skip-permissions \
        --verbose
    echo ""
    echo "  ── WATCH MODE COMPLETE ──"
    exit 0
fi

# ── Parse parsec count ─────────────────────────────────────────────
MAX_PARSECS="${1:-${KESSEL_MAX_PARSECS:-12}}"
PARSEC=0

echo "  Plotting course: ${MAX_PARSECS} parsecs (0 = unlimited)"
echo ""

# ── Completion check ───────────────────────────────────────────────
check_all_complete() {
    python3 -c "
import json, sys
with open('PRD.json') as f:
    data = json.load(f)
items = data.get('items', [])
if not items:
    sys.exit(1)
sys.exit(0 if all(i.get('passes') for i in items) else 1)
" 2>/dev/null
}

# ── The Kessel Run ─────────────────────────────────────────────────
while true; do
    PARSEC=$((PARSEC + 1))

    if [ "$MAX_PARSECS" -gt 0 ] && [ "$PARSEC" -gt "$MAX_PARSECS" ]; then
        echo ""
        echo "  ════════════════════════════════════════════"
        echo "  MAX PARSECS ($MAX_PARSECS) REACHED"
        echo "  \"Great shot kid, that was one in a million!\""
        echo "  ════════════════════════════════════════════"
        break
    fi

    echo ""
    echo "  ════════════════════════════════════════════"
    echo "  PARSEC #${PARSEC}  $(date '+%H:%M:%S')"
    echo "  ════════════════════════════════════════════"
    echo ""

    # Stream output directly — never capture into variables
    cat "${KESSEL_DIR}/PROMPT.md" | claude -p \
        --model "$KESSEL_MODEL" \
        --dangerously-skip-permissions \
        --output-format=text \
        --verbose 2>&1 || true

    echo ""
    echo "  ── END PARSEC #${PARSEC} ──"

    # Check if all PRD items pass
    if check_all_complete; then
        echo ""
        echo "  ╔═══════════════════════════════════════════════════╗"
        echo "  ║         H Y P E R S P A C E   C O M P L E T E    ║"
        echo "  ║                                                   ║"
        echo "  ║   All PRD items passing after ${PARSEC} parsecs.        ║"
        echo "  ║   \"It's not my fault!\" — It's nobody's fault.     ║"
        echo "  ║   The Kessel Run is done.                         ║"
        echo "  ╚═══════════════════════════════════════════════════╝"

        # macOS notification
        if command -v osascript &>/dev/null; then
            osascript -e "display notification \"All PRD items passing after ${PARSEC} parsecs.\" with title \"Kessel Run Complete\" sound name \"Glass\""
        fi
        break
    fi
done
