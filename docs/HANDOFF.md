# Kessel Run — Session Handoff

**Updated:** 2026-03-03

## Current State
Kessel Run is feature-complete with a modernized terminal UI (Star Wars yellow palette, progress bar, live timer, parsec naming). Published as v0.1.0 on GitHub at `heychad/kessel-run`. **Not yet tested against a real PRD.json** — that's the immediate next step. User has a project with ~5 PRD items ready to test.

## What Exists
```
kessel-run/
├── scripts/
│   ├── init.sh              # Scaffolds into any project (re-run for updates)
│   └── loop.sh              # Core loop — yellow/white/dim colors, progress bar, terminal title timer
├── templates/
│   ├── PROMPT.md            # 11-line agent prompt (generic, no Star Wars in prompt)
│   ├── backpressure.sh      # Auto-detecting quality gate (tsc/eslint/vitest/jest/next/pytest/cargo/convex)
│   └── PROGRESS.md          # Empty append-only log template
├── README.md                # Quick start, file reference, env vars, credits
├── LICENSE                  # MIT
└── .gitignore               # .DS_Store, editor swap files
```

## What Was Decided
- **Solo Opus per cycle, no teams/subagents** — battle-tested from chad-brain (74/97 items, 12+ cycles)
- **Stream via `claude -p --verbose 2>&1`** — never capture into variables (crash = lost output)
- **File layout**: `docs/specs/PRD.json` + `docs/specs/*.md` for specs, `docs/PROGRESS.md` for log, `.claude/CLAUDE.md` for agent config
- **Star Wars yellow palette** (`38;5;220`) + white + dim gray — chosen over blue/purple
- **"Parsec" naming** for iterations — PARSEC 1, PARSEC 2, etc.
- **Falcon left, stacked KESSEL/RUN right** for hero banner
- **Progress bar** with `█▸░` showing PRD item completion per parsec
- **Live timer** in terminal title bar during each parsec (background process)
- **init.sh is the update mechanism** — re-run it to get latest loop.sh; skips customized files (backpressure, prompt)
- **Prompt stays generic** — no Star Wars flavor in PROMPT.md (confuses Claude), theming is only in loop.sh UI

## What Was Done This Session
- Removed `/ralph` skill from `~/.claude/skills/`
- Added `.gitignore` to kessel-run repo
- Stripped Star Wars theming from `PROMPT.md` (kept it focused for Claude)
- Moved `PROGRESS.md` → `docs/PROGRESS.md`
- Moved `PRD.json` → `docs/specs/PRD.json`
- Moved `specs/` → `docs/specs/`
- Removed `docs/reference/` (research docs, not part of tool)
- Rewrote `loop.sh` — ANSI colors, progress bar, timing per parsec, total duration
- Changed palette from blue/purple to Star Wars yellow/white
- Changed "Cycle" → "Parsec" throughout
- Rebuilt hero banner: Falcon left + stacked title right (heredoc reader with `%-42s` padding)
- Added live timer updating terminal title bar during each parsec
- Added trap cleanup to reset terminal title on exit
- `init.sh` now creates `.claude/CLAUDE.md` with backpressure config
- Fixed `mkdir -p docs/specs` (was still `specs`)
- Fixed stray `PROGRESS.md` path in PROMPT.md
- Updated README with correct paths, removed dead links
- Created GitHub repo `heychad/kessel-run` (public)
- Published v0.1.0 release
- Pushed all changes

## What To Do Next
1. **Test against a real project** — user has a project with ~5 PRD items. Run `bash ~/vibes/tools/kessel-run/scripts/init.sh` from project root, populate PRD, run `./scripts/kessel-run/loop.sh 1`
2. **Verify hero banner alignment** — the `%-42s` padding for side-by-side Falcon + title needs visual confirmation in a real terminal
3. **Verify timer cleanup** — the background `start_timer` process (updates terminal title) needs testing for clean kill/wait behavior, no orphan processes or "Terminated" messages
4. **Distribution strategy** — currently "clone + init.sh". Could become brew tap, npm package, or stay simple

## Gotchas
- **`loop.sh` can't run inside Claude Code** — nested sessions error. Must be run from a regular terminal
- **init.sh copies loop.sh fresh each time** but skips backpressure.sh and PROMPT.md if they exist (user customizations preserved). If you change the template prompt, users need to delete their copy and re-run init
- **Timer uses background process** — `start_timer &` with `kill`/`wait` cleanup. Untested in production. Trap on EXIT should handle Ctrl+C but verify
- **python3 required** — `count_prd_progress` and `check_all_complete` use python3 for JSON parsing
- **Hero banner uses `%-42s` printf padding** — if falcon art lines exceed 42 chars, title text shifts right

## Human Context
- Kessel-run is feature-complete but completely untested against a real PRD.json. The scaffolding and UI are done, but the actual Claude invocation cycle hasn't been validated in kessel-run form (it was validated as ralph-loop on chad-brain). First real test is the immediate priority.
- The timer background process is the biggest uncertainty — it updates the terminal title bar every second during each parsec. Haven't verified clean process lifecycle (start, kill, wait, no orphans).
- Star Wars theming is intentional and important — it's not just decoration. The goal is a memorable, fun, shareable tool. Yellow palette was a deliberate choice (Star Wars crawl vibe). Keep it approachable. But the PROMPT.md stays generic so Claude doesn't get confused by flavor text.
