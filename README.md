# Kessel Run

> *"She may not look like much, but she's got it where it counts, kid."*

The fastest hunk of junk in the galaxy. A dead-simple bash loop that feeds your PRD to Claude, one item per cycle, with backpressure to keep quality high. Fresh context every parsec. No frameworks, no dependencies, no nonsense.

## Quick Start

```bash
# From your project root
bash /path/to/kessel-run/scripts/init.sh

# Write your specs and populate PRD.json, then:
./scripts/kessel-run/loop.sh        # full run (default 12 parsecs)
./scripts/kessel-run/loop.sh 5      # run 5 parsecs
./scripts/kessel-run/loop.sh watch  # single parsec in TUI mode
```

## How It Works

```
┌─────────────────────────────────────────┐
│  loop.sh                                │
│                                         │
│  for each parsec:                       │
│    1. Feed PROMPT.md to Claude          │
│    2. Claude reads PROGRESS.md          │
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

Each iteration gets a **fresh context window** — no accumulated confusion, no degraded performance. PROGRESS.md carries forward what matters. Backpressure (types, lint, tests, build) catches regressions immediately.

## File Reference

| File | Purpose |
|------|---------|
| `scripts/kessel-run/loop.sh` | The hyperdrive — outer bash loop |
| `scripts/kessel-run/PROMPT.md` | Navigation computer — agent instructions |
| `scripts/kessel-run/backpressure.sh` | Deflector shields — quality gate |
| `PRD.json` | Star chart — items with `passes` booleans |
| `PROGRESS.md` | Ship's log — append-only memory across parsecs |
| `specs/*.md` | Ground truth requirements (one per topic) |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KESSEL_MODEL` | `claude-opus-4-6` | Claude model to use |
| `KESSEL_MAX_PARSECS` | `12` | Max iterations (0 = unlimited) |
| `KESSEL_DIR` | `scripts/kessel-run` | Path to kessel-run files in your project |

## Battle-Tested

Built from experience running 74/97 PRD items across 12+ autonomous cycles. The patterns that survive:

- **One item per parsec.** Focused work beats multitasking.
- **Fresh context is your greatest weapon.** Don't accumulate — reset.
- **Backpressure catches what you miss.** Types + tests + build = confidence.
- **Stream, don't capture.** `claude -p --verbose 2>&1` — variable capture loses output on crash.
- **Bail after 3 attempts.** Fresh context on the next parsec often solves what this one couldn't.

## Credits

- **Geoffrey Huntley** — [The Ralph pattern](https://ghuntley.com/ralph/) that started it all
- **Anthropic** — [Effective Harnesses for Long-Running Agents](docs/reference/anthropic-effective-harnesses.md), [Agent Teams](docs/reference/anthropic-agent-teams.md)

## License

MIT
