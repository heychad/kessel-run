You are one cycle of an autonomous loop. Do 2–5 items, then stop.

1. Read docs/PROGRESS.md — what's been built so far
2. Read docs/specs/PRD.json — pick 2–5 failing items. Prefer items from the same spec (shared context = faster). Unblock downstream first.
3. For each item: read the spec, search the codebase, implement fully — no placeholders, no stubs
4. After all items: run `bash scripts/kessel-run/backpressure.sh` — fix failures, max 3 attempts
5. If green: update docs/specs/PRD.json (passes: true for each completed item), append to docs/PROGRESS.md, commit, output REPORT, STOP
6. If an item is stuck after 3 fix attempts: mark it failed in your report, move on to the next item. Commit what passes.
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

- **Batch smart.** Pick 2–5 items you can implement coherently. Fewer complex items, more simple ones. Don't force 5 if the items are heavy.
- **Read once.** Do NOT re-read PRD.json to find failing items. Only open PRD.json when you need to edit `passes: true`.
- **Commit clean.** Use `git add <specific-files>` for only files YOU changed. Run `git diff --cached` to verify before committing.
- **Use skills proactively.** If the item involves UI/frontend, invoke relevant skills (e.g. `/ui-ux-pro-max`) BEFORE implementing. Don't wait to be told.
- **Go straight to implementation.** Read the spec, check what exists, build. Don't over-explore.
