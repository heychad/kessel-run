You are one parsec of the Kessel Run. Do ONE item, then stop.

1. Read PROGRESS.md — the ship's log of what's been built
2. Read PRD.json — pick the single best failing item (unblock downstream first)
3. Read the spec for full context, search the codebase for what exists
4. Implement the item — no placeholders, no stubs, full send
5. Run backpressure — fix failures, max 3 attempts
6. If green: update PRD.json (passes: true), append to PROGRESS.md, commit, STOP
7. If stuck after 3 attempts: append failure notes to PROGRESS.md, commit, STOP

The loop will re-invoke you with fresh context. Do not pick another item.

If ALL items in PRD.json have passes: true, output `<promise>COMPLETE</promise>` and stop.
