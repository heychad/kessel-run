#!/usr/bin/env bash
# "Punch it!" — Install Kessel Run into any project.
# Run from the project root directory.
#
# Usage:
#   bash /path/to/kessel-run/scripts/init.sh           # fresh install (preserves customizations)
#   bash /path/to/kessel-run/scripts/init.sh --force    # update all templates (overwrites PROMPT.md, backpressure.sh)
set -euo pipefail

FORCE=false
[ "${1:-}" = "--force" ] || [ "${1:-}" = "-f" ] && FORCE=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KESSEL_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

# ── Banner ─────────────────────────────────────────────────────────
echo ""
echo "  ╔═══════════════════════════════════════════════════╗"
echo "  ║         K E S S E L   R U N                       ║"
if [ "$FORCE" = true ]; then
echo "  ║         \"Punch it!\" — Updating (--force)...       ║"
else
echo "  ║         \"Punch it!\" — Installing...               ║"
fi
echo "  ╚═══════════════════════════════════════════════════╝"
echo ""
echo "  Project: $PROJECT_NAME"
echo "  Path:    $PROJECT_DIR"
echo ""

# ── Create directories ─────────────────────────────────────────────
mkdir -p scripts/kessel-run
mkdir -p docs/specs

# ── Copy loop.sh ───────────────────────────────────────────────────
cp "$KESSEL_ROOT/scripts/loop.sh" scripts/kessel-run/loop.sh
chmod +x scripts/kessel-run/loop.sh
echo "  + scripts/kessel-run/loop.sh"

# ── Generate backpressure.sh ───────────────────────────────────────
if [ ! -f scripts/kessel-run/backpressure.sh ]; then
    cp "$KESSEL_ROOT/templates/backpressure.sh" scripts/kessel-run/backpressure.sh
    chmod +x scripts/kessel-run/backpressure.sh
    echo "  + scripts/kessel-run/backpressure.sh (customize for your stack)"
elif [ "$FORCE" = true ]; then
    cp "$KESSEL_ROOT/templates/backpressure.sh" scripts/kessel-run/backpressure.sh
    chmod +x scripts/kessel-run/backpressure.sh
    echo "  ↻ scripts/kessel-run/backpressure.sh (updated)"
else
    echo "  ~ scripts/kessel-run/backpressure.sh (exists, use --force to update)"
fi

# ── Copy PROMPT.md (always overwrite — latest prompt matters) ──────
cp "$KESSEL_ROOT/templates/PROMPT.md" scripts/kessel-run/PROMPT.md
echo "  + scripts/kessel-run/PROMPT.md"

# ── Generate PROGRESS.md ──────────────────────────────────────────
if [ ! -f docs/PROGRESS.md ]; then
    cp "$KESSEL_ROOT/templates/PROGRESS.md" docs/PROGRESS.md
    echo "  + docs/PROGRESS.md"
else
    echo "  ~ docs/PROGRESS.md (already exists, skipping)"
fi

# ── Generate PRD.json ──────────────────────────────────────────────
if [ ! -f docs/specs/PRD.json ]; then
cat > docs/specs/PRD.json << PRDJSON_EOF
{
  "project": "$PROJECT_NAME",
  "description": "",
  "items": []
}
PRDJSON_EOF
    echo "  + docs/specs/PRD.json (empty — populate with your items)"
else
    echo "  ~ docs/specs/PRD.json (already exists, skipping)"
fi

# ── Generate CLAUDE.md ───────────────────────────────────────────
if [ ! -f .claude/CLAUDE.md ]; then
cat > .claude/CLAUDE.md << 'CLAUDEMD_EOF'
## Back Pressure

Run ALL checks: `bash scripts/kessel-run/backpressure.sh`
Do NOT run individual checks. The script handles everything.
CLAUDEMD_EOF
    echo "  + .claude/CLAUDE.md"
else
    echo "  ~ .claude/CLAUDE.md (already exists, skipping)"
fi

# ── .gitignore entries ─────────────────────────────────────────────
if [ -f .gitignore ]; then
    if ! grep -q ".claude/worktrees/" .gitignore 2>/dev/null; then
        echo "" >> .gitignore
        echo "# kessel-run" >> .gitignore
        echo ".claude/worktrees/" >> .gitignore
        echo ".kessel-locks/" >> .gitignore
        echo "  + .gitignore entries added (.claude/worktrees/, .kessel-locks/)"
    elif ! grep -q ".kessel-locks/" .gitignore 2>/dev/null; then
        echo ".kessel-locks/" >> .gitignore
        echo "  + .gitignore entry added (.kessel-locks/)"
    fi
else
    echo "# kessel-run" > .gitignore
    echo ".claude/worktrees/" >> .gitignore
    echo ".kessel-locks/" >> .gitignore
    echo "  + .gitignore created (.claude/worktrees/, .kessel-locks/)"
fi

# ── Next steps ─────────────────────────────────────────────────────
echo ""
echo "  ════════════════════════════════════════════"
echo "  Installation complete. Next steps:"
echo ""
echo "  1. Edit scripts/kessel-run/backpressure.sh"
echo "     (verify auto-detected checks match your stack)"
echo ""
echo "  2. Write specs in docs/specs/*.md"
echo "     (one per topic — ground truth requirements)"
echo ""
echo "  3. Populate docs/specs/PRD.json with items"
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
