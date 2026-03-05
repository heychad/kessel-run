# Kessel Run

> *"She may not look like much, but she's got it where it counts, kid."*

A dead-simple bash loop that feeds your PRD to Claude, one item per cycle, with backpressure to keep quality high. Fresh context every cycle. No frameworks, no dependencies, no nonsense.

## Quick Start

```bash
# From your project root
bash /path/to/kessel-run/scripts/init.sh

# Write your specs and populate docs/specs/PRD.json, then:
./scripts/kessel-run/loop.sh        # full run (default 12 cycles)
./scripts/kessel-run/loop.sh 5      # run 5 cycles
./scripts/kessel-run/loop.sh watch  # single cycle in TUI mode
```

## How It Works

```
┌─────────────────────────────────────────┐
│  loop.sh                                │
│                                         │
│  for each cycle:                        │
│    1. Feed PROMPT.md to Claude          │
│    2. Claude reads docs/PROGRESS.md  │
│    3. Claude picks 1-3 failing PRD items│
│    4. Claude implements them            │
│    5. Claude runs backpressure.sh       │
│    6. If green → commit, log, stop      │
│    7. If stuck → log failure, stop      │
│    8. Loop gives Claude fresh context   │
│                                         │
│  until: all PRD items pass              │
└─────────────────────────────────────────┘
```

Each iteration gets a **fresh context window** — no accumulated confusion, no degraded performance. `docs/PROGRESS.md` carries forward what matters. Backpressure (types, lint, tests, build) catches regressions immediately.

## File Reference

| File | Purpose |
|------|---------|
| `scripts/kessel-run/loop.sh` | Outer bash loop with progress tracking |
| `scripts/kessel-run/PROMPT.md` | Agent instructions (fed to Claude each cycle) |
| `scripts/kessel-run/backpressure.sh` | Quality gate (auto-detects your stack including E2E) |
| `docs/specs/PRD.json` | Work items with steps, verification, and `passes` tracking |
| `docs/specs/*.md` | Ground truth requirements (one per topic) |
| `docs/PROGRESS.md` | Append-only memory across cycles |
| `.claude/CLAUDE.md` | Agent config (backpressure path) |

## PRD Schema

`docs/specs/PRD.json` drives the loop. Each item is a self-contained work unit with explicit steps and machine-checkable verification:

```json
{
  "project": "my-app",
  "goal": "What this sprint/batch achieves",
  "categories": ["auth", "ui", "api"],
  "items": [
    {
      "id": 1,
      "category": "auth",
      "description": "Add JWT refresh token rotation",
      "spec": "docs/specs/auth.md",
      "steps": [
        "Add refreshToken field to session table in schema.ts",
        "Create rotateToken mutation that invalidates old token and issues new one",
        "Wire refresh logic into the auth middleware"
      ],
      "passes": false,
      "notes": "Currently tokens expire with no refresh path",
      "depends_on": [],
      "verification": [
        "Grep: schema.ts contains refreshToken field",
        "Grep: auth middleware calls rotateToken",
        "npx tsc --noEmit passes"
      ]
    }
  ]
}
```

| Field | Type | Purpose |
|-------|------|---------|
| `id` | number | Unique item ID, referenced by `depends_on` |
| `category` | string | Groups items — Claude batches from the same category |
| `description` | string | One-line summary of what to build |
| `spec` | string | File path to the spec doc (Claude reads this for context) |
| `steps` | string[] | Explicit implementation steps — no ambiguity |
| `passes` | boolean | Flipped to `true` by Claude after verification |
| `notes` | string | Current state context that helps Claude understand what exists |
| `depends_on` | number[] | Item IDs that must pass first (unblocks downstream) |
| `verification` | string[] | Concrete checks Claude runs before marking done |

**Tips:**
- `steps` are the secret sauce — explicit instructions beat vague descriptions
- `verification` gives Claude a machine-checkable "done" definition (greps, type checks, build commands)
- `depends_on` lets Claude prioritize unblocking work
- `spec` points to a markdown file with full requirements — keep PRD items lean, specs rich

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KESSEL_MODEL` | `claude-opus-4-6` | Claude model to use |
| `KESSEL_MAX_PARSECS` | `12` | Max iterations (0 = unlimited) |
| `KESSEL_DIR` | `scripts/kessel-run` | Path to kessel-run files in your project |

## Battle-Tested

Built from experience running 74/97 PRD items across 12+ autonomous cycles. The patterns that survive:

- **1–3 items per cycle, same spec.** Shared context = fewer mistakes.
- **Fresh context is your greatest weapon.** Don't accumulate — reset.
- **Backpressure catches what you miss.** Types + lint + build + E2E = confidence.
- **Stream, don't capture.** `claude -p --verbose 2>&1` — variable capture loses output on crash.
- **Bail after 3 attempts.** Fresh context on the next cycle often solves what this one couldn't.

## Credits

- **Geoffrey Huntley** — [The Ralph pattern](https://ghuntley.com/ralph/) that started it all
- **Anthropic** — [Effective Harnesses for Long-Running Agents](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/effective-harnesses)

## License

MIT
