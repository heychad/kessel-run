#!/usr/bin/env bash
# "Punch it!" — Install Kessel Run into any project.
# Run from the project root directory.
#
# Usage:
#   bash /path/to/kessel-run/scripts/init.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KESSEL_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

# ── Banner ─────────────────────────────────────────────────────────
echo ""
echo "  ╔═══════════════════════════════════════════════════╗"
echo "  ║         K E S S E L   R U N                       ║"
echo "  ║         \"Punch it!\" — Installing...               ║"
echo "  ╚═══════════════════════════════════════════════════╝"
echo ""
echo "  Project: $PROJECT_NAME"
echo "  Path:    $PROJECT_DIR"
echo ""

# ── Create directories ─────────────────────────────────────────────
mkdir -p scripts/kessel-run
mkdir -p specs

# ── Copy loop.sh ───────────────────────────────────────────────────
cp "$KESSEL_ROOT/scripts/loop.sh" scripts/kessel-run/loop.sh
chmod +x scripts/kessel-run/loop.sh
echo "  + scripts/kessel-run/loop.sh"

# ── Generate backpressure.sh ───────────────────────────────────────
if [ ! -f scripts/kessel-run/backpressure.sh ]; then
    cp "$KESSEL_ROOT/templates/backpressure.sh" scripts/kessel-run/backpressure.sh
    chmod +x scripts/kessel-run/backpressure.sh
    echo "  + scripts/kessel-run/backpressure.sh (customize for your stack)"
else
    echo "  ~ scripts/kessel-run/backpressure.sh (already exists, skipping)"
fi

# ── Generate PROMPT.md ─────────────────────────────────────────────
if [ ! -f scripts/kessel-run/PROMPT.md ]; then
    cp "$KESSEL_ROOT/templates/PROMPT.md" scripts/kessel-run/PROMPT.md
    echo "  + scripts/kessel-run/PROMPT.md (customize if needed)"
else
    echo "  ~ scripts/kessel-run/PROMPT.md (already exists, skipping)"
fi

# ── Generate PROGRESS.md ──────────────────────────────────────────
mkdir -p .claude
if [ ! -f .claude/PROGRESS.md ]; then
    cp "$KESSEL_ROOT/templates/PROGRESS.md" .claude/PROGRESS.md
    echo "  + .claude/PROGRESS.md"
else
    echo "  ~ .claude/PROGRESS.md (already exists, skipping)"
fi

# ── Generate PRD.json ──────────────────────────────────────────────
if [ ! -f specs/PRD.json ]; then
cat > specs/PRD.json << PRDJSON_EOF
{
  "project": "$PROJECT_NAME",
  "description": "",
  "items": []
}
PRDJSON_EOF
    echo "  + specs/PRD.json (empty — populate with your items)"
else
    echo "  ~ specs/PRD.json (already exists, skipping)"
fi

# ── .gitignore entries ─────────────────────────────────────────────
if [ -f .gitignore ]; then
    if ! grep -q ".claude/worktrees/" .gitignore 2>/dev/null; then
        echo "" >> .gitignore
        echo "# kessel-run" >> .gitignore
        echo ".claude/worktrees/" >> .gitignore
        echo "  + .gitignore entry added (.claude/worktrees/)"
    fi
else
    echo "# kessel-run" > .gitignore
    echo ".claude/worktrees/" >> .gitignore
    echo "  + .gitignore created (.claude/worktrees/)"
fi

# ── CLAUDE.md backpressure note ────────────────────────────────────
if [ -f CLAUDE.md ]; then
    if ! grep -q "backpressure" CLAUDE.md 2>/dev/null; then
        echo "" >> CLAUDE.md
        echo "## Back Pressure" >> CLAUDE.md
        echo "Run ALL checks: \`bash scripts/kessel-run/backpressure.sh\`" >> CLAUDE.md
        echo "Do NOT run individual checks. The script handles everything." >> CLAUDE.md
        echo "  + CLAUDE.md — added backpressure path"
    fi
fi

# ── Next steps ─────────────────────────────────────────────────────
echo ""
echo "  ════════════════════════════════════════════"
echo "  Installation complete. Next steps:"
echo ""
echo "  1. Edit scripts/kessel-run/backpressure.sh"
echo "     (verify auto-detected checks match your stack)"
echo ""
echo "  2. Write specs in specs/*.md"
echo "     (one per topic — ground truth requirements)"
echo ""
echo "  3. Populate specs/PRD.json with items"
echo "     (each item: id, title, spec, passes: false)"
echo ""
echo "  4. Test one parsec:"
echo "     ./scripts/kessel-run/loop.sh 1"
echo ""
echo "  5. Make the Kessel Run:"
echo "     ./scripts/kessel-run/loop.sh"
echo ""
echo "  \"She may not look like much, but she's got it"
echo "   where it counts, kid.\""
echo ""
