# Kessel Run

> *"She may not look like much, but she's got it where it counts, kid."*

A dead-simple bash loop that feeds a PRD to Claude Code, one batch per cycle, with backpressure to keep quality high. Fresh context every cycle. No frameworks, no dependencies beyond `bash`, `jq`, `gh`, and `claude`.

Pairs with the [`plan-sprint`](https://github.com/heychad/claude-dotfiles/tree/main/shared/skills/plan-sprint) skill for spec generation and with the [`/investigate`](https://github.com/heychad/claude-dotfiles/tree/main/shared/skills/investigate) skill's patterns for dependency-aware sequencing.

---

## Two modes

Kessel Run has one core (`loop.sh`) and two modes of operation. Same loop, same PRD schema, different wrappers depending on whether you're building against GitHub issues or against hand-written specs.

```
                 ┌──────────────────────────────────┐
                 │   loop.sh  +  PROMPT.md          │   ← unchanged core
                 │   backpressure.sh                │
                 │   PRD.json (items + specs)       │
                 └──────────────▲───────────────────┘
                                │
          ┌─────────────────────┼──────────────────────┐
          │                                            │
    SPEC-DRIVEN                                ISSUE-DRIVEN
    (personal projects)                        (GitHub-backed, overnight)

    plan-sprint writes:                        plan-sprint --issues writes:
    - docs/specs/*.md                          - docs/specs/*.md (seeded from issues)
    - PRD.json                                 - PRD.json (+ github_issue, batch, wave)

    run with:                                  run with:
    ./loop.sh                                  ./run-issue.sh 42
                                               ./overnight.sh --parallel 3
                                               ./morning-digest.sh
```

---

## Quick start

### Install into a project

```bash
# From the project root:
bash ~/vibes/tools/kessel-run/scripts/init.sh                 # spec mode
bash ~/vibes/tools/kessel-run/scripts/init.sh --issue-mode    # + run-issue, overnight, morning-digest
```

Or let [`plan-sprint`](https://github.com/heychad/claude-dotfiles/tree/main/shared/skills/plan-sprint) do it — it runs `init.sh` in Phase 6 and fills in project-specific context automatically.

### Spec-driven flow

```bash
# Plan the sprint (specs come from conversation)
/plan-sprint

# Test one cycle, then let it run
source .kessel-env
./scripts/kessel-run/loop.sh 1    # single parsec, smoke test
./scripts/kessel-run/loop.sh      # full run until PRD is green
```

### Issue-driven flow

```bash
# Plan from GitHub issues — clustering, dependency graph, wave sequencing
/plan-sprint --issues

# Commit scaffolded files so worktrees can find them
git add scripts/kessel-run/ docs/specs/ .claude/CLAUDE.md .kessel-env
git commit -m "scaffold kessel-run for sprint N"
git push

# Dry-run, then real
source .kessel-env
./scripts/kessel-run/overnight.sh --dry-run
./scripts/kessel-run/overnight.sh       # defaults to wave 1

# Morning
./scripts/kessel-run/morning-digest.sh
gh pr list --label agent-built --state open
```

---

## How it works

```
┌─────────────────────────────────────────┐
│  loop.sh                                │
│                                         │
│  for each parsec:                       │
│    1. Feed PROMPT.md to Claude Code     │
│    2. Claude reads docs/PROGRESS.md     │
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

Every cycle gets a **fresh context window** — no accumulated confusion, no degraded performance. `docs/PROGRESS.md` carries forward what matters across cycles. Backpressure (types + lint + tests + build) catches regressions immediately.

---

## File reference

### Core (both modes)

| File | Purpose |
|------|---------|
| `scripts/kessel-run/loop.sh` | Outer bash loop with progress tracking, crash-resume, skip-stuck |
| `scripts/kessel-run/PROMPT.md` | Agent instructions fed to Claude each cycle |
| `scripts/kessel-run/backpressure.sh` | Quality gate — types + lint + tests + build (+ E2E if configured) |
| `docs/specs/PRD.json` | Work items with steps, verification, `passes` tracking |
| `docs/specs/*.md` | Ground truth requirements, one per topic |
| `docs/PROGRESS.md` | Append-only memory across cycles |
| `.claude/CLAUDE.md` | Project constraints + backpressure hook |
| `.kessel-env` | Sized defaults — source before running |

### Issue-mode only

| File | Purpose |
|------|---------|
| `scripts/kessel-run/run-issue.sh` | Single-batch worker — worktree → loop → ready PR |
| `scripts/kessel-run/overnight.sh` | Parallel batch orchestrator with wave sequencing |
| `scripts/kessel-run/morning-digest.sh` | Terminal reader for overnight results |

### Tools in this repo

| File | Purpose |
|------|---------|
| `scripts/init.sh` | Project installer. `--force` updates templates. `--issue-mode` installs issue-mode runners. |
| `scripts/generate-backpressure.sh` | Scans stack, emits customized backpressure.sh (no runtime probing). Supports `--preset careatlas`. |
| `templates/*` | Source files copied into projects by init.sh |

---

## PRD schema

`docs/specs/PRD.json` is the contract. Every item is a self-contained work unit with explicit steps and machine-checkable verification.

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
      ],

      "github_issue": 42,
      "github_batch": "A",
      "batch_wave": 1
    }
  ]
}
```

### Core fields (always required)

| Field | Type | Purpose |
|-------|------|---------|
| `id` | number | Unique item ID, referenced by `depends_on` |
| `category` | string | Groups items — Claude batches from the same category |
| `description` | string | One-line summary |
| `spec` | string | File path to the spec doc (Claude reads it for context) |
| `steps` | string[] | Explicit implementation steps — no ambiguity |
| `passes` | boolean | Flipped to `true` by Claude after verification |
| `notes` | string | State context (can be empty) |
| `depends_on` | number[] | Item IDs that must pass first |
| `verification` | string[] | Machine-checkable "done" criteria |

### Issue-mode fields (required when present on any item)

| Field | Type | Purpose |
|-------|------|---------|
| `github_issue` | number | Source GitHub issue number |
| `github_batch` | string | Batch name from clustering (e.g., "A" or "billing"). One batch = one worktree = one PR. |
| `batch_wave` | number | Wave number from dependency sequencing (1, 2, 3...). All items in the same batch must share the same wave. |

Validate with:

```bash
python3 ~/.claude/skills/plan-sprint/scripts/validate_prd.py docs/specs/PRD.json
```

---

## The three runners (issue mode)

### `run-issue.sh` — single-batch worker

```bash
./scripts/kessel-run/run-issue.sh 42                 # one issue
./scripts/kessel-run/run-issue.sh 42,47              # ad-hoc batch
./scripts/kessel-run/run-issue.sh --batch A          # all items with github_batch == "A"
./scripts/kessel-run/run-issue.sh 42 --dry-run       # preview without executing
./scripts/kessel-run/run-issue.sh 42 --keep-worktree # don't cleanup on success
```

**What it does:**
1. Filters PRD.json to items matching the issue(s) or batch
2. Creates a git worktree at `.claude/worktrees/<slug>` on branch `feature/<slug>`
3. Writes the filtered PRD into the worktree
4. Runs `loop.sh` inside the worktree with `KESSEL_MAX_PARSECS = items*2+4`
5. On green: pushes branch, opens a ready PR labeled `agent-built`, comments on each issue, removes worktree
6. On stuck: comments stuck report on each issue, leaves worktree for manual pickup

**Exit codes:** `0` green, `1` prerequisite failure, `2` stuck, `3` crashed.

### `overnight.sh` — parallel orchestrator with wave sequencing

```bash
./scripts/kessel-run/overnight.sh                   # auto-selects lowest incomplete wave, N=3
./scripts/kessel-run/overnight.sh --wave 2          # explicit wave
./scripts/kessel-run/overnight.sh --all-waves       # every wave in one go (only safe if no cross-wave code deps)
./scripts/kessel-run/overnight.sh --parallel 5      # more concurrency
./scripts/kessel-run/overnight.sh --serial          # one at a time
./scripts/kessel-run/overnight.sh --batches A,C     # specific batches
./scripts/kessel-run/overnight.sh --dry-run         # preview
```

**What it does:**
1. Reads PRD.json, determines the wave to run (unless `--batches` or `--all-waves` override)
2. Launches each batch in parallel via `run-issue.sh`, capped at `--parallel N`
3. Writes `logs/overnight-<timestamp>.md` digest with per-batch outcomes + PR links
4. On completion, appends a "Next wave" section if more waves remain

**Wave defaults:** no flag ⇒ lowest wave that still has incomplete batches. When all items pass, exits cleanly with "All waves complete."

### `morning-digest.sh` — terminal reader

```bash
./scripts/kessel-run/morning-digest.sh              # most recent digest
./scripts/kessel-run/morning-digest.sh --list       # list recent digests
./scripts/kessel-run/morning-digest.sh logs/overnight-2026-04-18.md
```

Shows per-batch ✓/⚠/✗, PR links, and the next-wave prompt if applicable.

---

## Backpressure

`backpressure.sh` is the quality gate. Exit 0 = green, non-zero = red.

Two ways to generate one:

```bash
# Generic template (runtime-probing, falls back to npx)
bash ~/vibes/tools/kessel-run/scripts/init.sh

# Custom, stack-detected (preferred — emits locked-in checks, no probing)
bash ~/vibes/tools/kessel-run/scripts/generate-backpressure.sh
bash ~/vibes/tools/kessel-run/scripts/generate-backpressure.sh --preset careatlas
bash ~/vibes/tools/kessel-run/scripts/generate-backpressure.sh --stdout   # preview
```

Auto-detected: pnpm/npm/yarn/bun, TypeScript, ESLint, Vitest, Jest, Next.js, Convex, Playwright, Cypress, Python (pytest), Rust (cargo test + clippy), Go (build + test).

Add custom checks to the `# ── Custom` section of the generated file — regeneration preserves that section only if you re-edit post-generation; keep a copy if you want durable custom gates.

---

## Wave sequencing (issue mode)

Waves prevent the common "we started overnight but batch B needs types from batch A" failure.

During planning (`plan-sprint --issues` Phase 1c), investigators emit:

- `creates` — types/endpoints/tables this issue would introduce
- `references` — things it assumes exist
- `external_blockers` — `blocked` labels, "waiting on X" in body
- `related_issues` — `#N` references

The planner builds a dependency DAG, detects cycles/missing prereqs/blockers, and topo-sorts into **waves**. Within a wave, batches run in parallel overnight. Waves run serially across nights:

```
WAVE 1 (parallel, no deps within sprint)
  Batch A  #42, #47    [creates: invoice service]
  Batch D  #58         [creates: session sweeper]

WAVE 2 (needs wave 1 merged to main)
  Batch B  #51         [references: invoice service from A]
```

**Execution contract:** `overnight.sh` defaults to running the lowest incomplete wave only. After you merge that wave's PRs in the morning, next night picks up wave 2 automatically.

Override with `--all-waves` when there are no true code dependencies (i.e., the DAG is flat).

---

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KESSEL_MODEL` | `claude-sonnet-4-6` | Claude model. Switch to `claude-opus-4-6` for heavy items, `claude-haiku-4-5` for rote stuff. |
| `KESSEL_MAX_PARSECS` | `12` (or `2*items+4` via plan-sprint) | Max iterations. `0` = unlimited. |
| `KESSEL_DIR` | `scripts/kessel-run` | Path to kessel-run files in your project. |
| `KESSEL_SKIP_STUCK` | `0` (disabled) | Skip items stuck N+ cycles. |
| `KESSEL_STUCK_THRESHOLD` | `3` | Warn after N consecutive failures on an item. |
| `KESSEL_PARALLEL` | `3` | Default `--parallel` for overnight.sh. |
| `PR_LABEL` | `agent-built` | Label applied to autonomous PRs. |
| `PR_BASE` | `main` | Base branch for PRs. |
| `BRANCH_PREFIX` | `feature/` | Branch name prefix. |

Put durable defaults in `.kessel-env` and source it before running.

---

## Review workflow

Autonomous PRs are opened **ready for review** (not draft) with the `agent-built` label. A prominent header in the body says *"Autonomous build — human review required."* PRs also include a **manual verification checklist** (one test per PRD item, in `/investigate` Step 6 format) so review is "walk this checklist" not "squint at a diff."

**Morning flow (~15 min for ~5 PRs):**

1. `./scripts/kessel-run/morning-digest.sh` — 30-second scan of the overnight digest
2. `gh pr list --label agent-built --state open` — filtered view of kessel PRs
3. Per ✓ PR:
   - Skim the body (summary, verification passed, manual checklist)
   - Diff review
   - `gh pr checkout <#>` if you want to exercise locally
   - Approve + merge, or request changes
4. Per ⚠ stuck batch: read stuck comment on the issue, decide pickup/re-run/punt (worktree is preserved)
5. Per ✗ failed batch: check `logs/batch-*.log` — usually a prerequisite issue

**Safety:** don't enable auto-merge on PRs labeled `agent-built`. Require reviews if your org supports branch protection.

---

## Skills this pairs with

- [`/plan-sprint`](https://github.com/heychad/claude-dotfiles/tree/main/shared/skills/plan-sprint) — interactive sprint planning. Runs Phases 1–6 including investigation, clustering, dependency graph, spec writing, PRD generation, and Phase 6 auto-scaffolding of kessel-run into the project. Two modes: spec-driven and `--issues`.
- [`/investigate`](https://github.com/heychad/claude-dotfiles/tree/main/shared/skills/investigate) — deep codebase investigation. Plan-sprint's Phase 1b borrows Steps 1–3 (restate → trace code → verify data). Run-issue.sh's PR body borrows Step 6 (manual verification plan) format.
- [`/triage-issues`](https://github.com/heychad/claude-dotfiles/tree/main/shared/skills/triage-issues) — get the backlog ready before sprint planning. Label issues `ready` so `plan-sprint --issues --label ready` can pull them.
- [`/review-pr`](https://github.com/heychad/claude-dotfiles/tree/main/shared/skills/review-pr) — guided PR review for non-SWE reviewers. Walks through `agent-built` PRs in plain language.

---

## Troubleshooting

**"Worktree already exists"**
`git worktree remove .claude/worktrees/<slug> --force` — then retry. Or use `--keep-worktree` if you want to inspect a previous run.

**Loop reports FAIL but nothing was committed**
Check `docs/PROGRESS.md` for the last entry. If a PRD item is stuck 3 cycles in a row, `KESSEL_SKIP_STUCK=5` will route around it. Item stays `passes: false` and you can pick it up manually.

**"kessel-run/loop.sh missing in worktree"**
The scaffolded scripts aren't committed on the base branch yet. `git add scripts/kessel-run/` then commit, then retry.

**Overnight ran only wave 1 but I wanted everything**
Pass `--all-waves`. Only safe when you're sure there are no cross-wave code dependencies.

**Backpressure too loose — agent ships broken code**
Add a check to `scripts/kessel-run/backpressure.sh` under the `# ── Custom` section. E2E tests, schema validators, migration linters — whatever catches what slipped through.

**Backpressure too strict — agent can't get green**
Start wider, tighten later. If `pnpm lint` has 200 pre-existing warnings and you pass `--max-warnings 0`, every run fails. Exclude or fix the baseline first.

**PRD has `github_issue` on some items but not others**
Validator will reject this. Either fully in issue mode or fully out — no partial.

**Wave N is ready but `overnight.sh` says "all complete"**
Items in wave 1 still show `passes: false` even after you merged wave 1's PRs? Plan-sprint flips PRD item `passes` to `true` only inside the worktree. After merging, re-run `plan-sprint --refresh` (coming soon) or hand-flip the PRD items. Alternative: always run `--wave N` explicitly.

---

## Battle-tested

Built from experience running 74/97 PRD items across 12+ autonomous cycles. Patterns that survived:

- **1–3 items per cycle, same spec.** Shared context = fewer mistakes.
- **Fresh context is your greatest weapon.** Don't accumulate — reset.
- **Backpressure catches what you miss.** Types + lint + build + E2E = confidence.
- **Stream, don't capture.** `claude -p --verbose 2>&1` — variable capture loses output on crash.
- **Bail after 3 attempts.** Fresh context on the next cycle often solves what this one couldn't.
- **Waves, not lanes.** Cross-batch dependencies get sequenced at plan time, not patched at runtime.
- **Ready PRs with a human gate.** Don't auto-merge autonomous work. `agent-built` label + required reviews = safe speed.

---

## Credits

- **Geoffrey Huntley** — [The Ralph pattern](https://ghuntley.com/ralph/) that started it all
- **Anthropic** — [Effective Harnesses for Long-Running Agents](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/effective-harnesses)

## License

MIT
