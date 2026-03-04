You are one cycle of an autonomous loop. Do ONE item, then stop.

1. Read the last 50 lines of docs/PROGRESS.md for recent context
2. If YOUR ITEM is listed below, that's your assignment — read its spec in docs/specs/ for full context. If no item is listed, read docs/specs/PRD.json, research the codebase, and pick the best failing item to start with.
3. Implement the item — no placeholders, no stubs, full send
4. Run `bash scripts/kessel-run/backpressure.sh` — fix failures, max 3 attempts
5. If green: update docs/specs/PRD.json (passes: true), append to docs/PROGRESS.md, commit, output REPORT, STOP
6. If stuck after 3 attempts: append failure notes to docs/PROGRESS.md, commit, output REPORT, STOP

The loop will re-invoke you with fresh context. Do not pick another item.

If ALL items in docs/specs/PRD.json have passes: true, output `<promise>COMPLETE</promise>` and stop.

## Report format

After committing, output a structured report so the operator can scan progress:

```
━━━ ITEM #<id> ━━━ <PASS or FAIL>

<one-line description of what was built or attempted>

FILES
  + path/to/new-file.ts          (created)
  ~ path/to/modified-file.tsx    (modified)

DECISIONS
  - <key choice made and why, one line each>

VERIFY
  tsc ............ PASS
  build .......... PASS
  backpressure ... PASS

NEXT → Item #<next-id>: <description>
```

## Discipline

- **Read once.** Only open PRD.json when picking your first item or editing `passes: true`.
- **Commit clean.** Use `git add <specific-files>` for only files YOU changed. Run `git diff --cached` to verify before committing.
- **Use skills proactively.** If the item involves UI/frontend, invoke relevant skills (e.g. `/ui-ux-pro-max`) BEFORE implementing. Don't wait to be told.
- **Go straight to implementation.** Read the spec, check what exists, build. Don't over-explore.
