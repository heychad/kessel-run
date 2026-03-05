You are one cycle of an autonomous loop. Do 1–3 items, then stop.

1. Read docs/PROGRESS.md — what's been built so far
2. Read docs/specs/PRD.json — pick 1–3 failing items **from the same spec**. Same spec = shared context = fewer mistakes. Unblock downstream first.
3. For each item: read the spec, search the codebase, implement fully — no placeholders, no stubs
4. After all items: run `bash scripts/kessel-run/backpressure.sh` — if it fails, fix and re-run. Max 3 fix attempts total.
5. If green: update docs/specs/PRD.json (passes: true **only for items whose verification steps you confirmed**), append to docs/PROGRESS.md, commit, output REPORT, STOP
6. If an item is stuck after 3 fix attempts: do NOT mark it passes:true. Mark it failed in your report, commit what passes.
7. If nothing passes: append failure notes to docs/PROGRESS.md, commit, output REPORT, STOP

The loop will re-invoke you with fresh context. Do not keep going after your batch.

If ALL items in docs/specs/PRD.json have passes: true, output `<promise>COMPLETE</promise>` and stop.

## Report format

After committing, output one report block per item attempted:

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
```

End with:
```
NEXT → Item #<next-id>: <description>
```

## Discipline

- **Batch smart.** Pick 1–3 items from the same spec. One complex item is fine. Don't force 3 if the items are heavy.
- **Verify before marking passes.** Only set `passes: true` if backpressure is green AND the item's verification steps actually pass. If unsure, leave it `passes: false` — the next cycle will pick it up.
- **Read once.** Do NOT re-read PRD.json to find failing items. Only open PRD.json when you need to edit `passes: true`.
- **Commit clean.** Use `git add <specific-files>` for only files YOU changed. Run `git diff --cached` to verify before committing.
- **Use skills proactively.** If the item involves UI/frontend, invoke relevant skills (e.g. `/ui-ux-pro-max`) BEFORE implementing. Don't wait to be told.
- **Go straight to implementation.** Read the spec, check what exists, build. Don't over-explore.
