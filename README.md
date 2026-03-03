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
│    2. Claude reads .claude/PROGRESS.md  │
│    3. Claude picks one failing PRD item │
│    4. Claude implements it              │
│    5. Claude runs backpressure.sh       │
│    6. If green → commit, log, stop      │
│    7. If stuck → log failure, stop      │
│    8. Loop gives Claude fresh context   │
│                                         │
│  until: all PRD items pass              │
└─────────────────────────────────────────┘
```

Each iteration gets a **fresh context window** — no accumulated confusion, no degraded performance. `.claude/PROGRESS.md` carries forward what matters. Backpressure (types, lint, tests, build) catches regressions immediately.

## File Reference

| File | Purpose |
|------|---------|
| `scripts/kessel-run/loop.sh` | Outer bash loop with progress tracking |
| `scripts/kessel-run/PROMPT.md` | Agent instructions (fed to Claude each cycle) |
| `scripts/kessel-run/backpressure.sh` | Quality gate (auto-detects your stack) |
| `docs/specs/PRD.json` | Items with `passes` booleans |
| `docs/specs/*.md` | Ground truth requirements (one per topic) |
| `.claude/PROGRESS.md` | Append-only memory across cycles |
| `.claude/CLAUDE.md` | Agent config (backpressure path) |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KESSEL_MODEL` | `claude-opus-4-6` | Claude model to use |
| `KESSEL_MAX_PARSECS` | `12` | Max iterations (0 = unlimited) |
| `KESSEL_DIR` | `scripts/kessel-run` | Path to kessel-run files in your project |

## Battle-Tested

Built from experience running 74/97 PRD items across 12+ autonomous cycles. The patterns that survive:

- **One item per cycle.** Focused work beats multitasking.
- **Fresh context is your greatest weapon.** Don't accumulate — reset.
- **Backpressure catches what you miss.** Types + tests + build = confidence.
- **Stream, don't capture.** `claude -p --verbose 2>&1` — variable capture loses output on crash.
- **Bail after 3 attempts.** Fresh context on the next cycle often solves what this one couldn't.

## Credits

- **Geoffrey Huntley** — [The Ralph pattern](https://ghuntley.com/ralph/) that started it all
- **Anthropic** — [Effective Harnesses for Long-Running Agents](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/effective-harnesses)

## License

MIT
