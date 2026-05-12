You are one cycle of an autonomous loop. Do 1–3 items, then stop.

1. Read docs/PROGRESS.md — what's been built so far
2. Read docs/specs/PRD.json — pick 1–3 failing items **from the same spec**. Same spec = shared context = fewer mistakes. Unblock downstream first.
3. For each item, in this order:
   a. **First**, print one line to stdout: `🛠  WORKING ON #<id>: <one-line description>` — this is operator-facing status, do it before any tool calls for the item
   b. Read the spec, search the codebase, implement fully — no placeholders, no stubs
4. After all items: run `bash scripts/kessel-run/backpressure.sh` — if it fails, fix and re-run. Max 3 fix attempts total.
5. If green: update docs/specs/PRD.json (passes: true **only for items whose verification steps you confirmed**), append to docs/PROGRESS.md, commit, output REPORT, STOP
6. If an item is stuck after 3 fix attempts: do NOT mark it passes:true. Mark it failed in your report, commit what passes.
7. If nothing passes: append failure notes to docs/PROGRESS.md, commit, output REPORT, STOP

The loop will re-invoke you with fresh context. Do not keep going after your batch.

If ALL items in docs/specs/PRD.json have passes: true, output `<promise>COMPLETE</promise>` and stop.

## Report format

After committing, output one report block per item attempted. The status (PASS or FAIL) at the top means all verification ran — only mark PASS if backpressure is green AND the item's verification steps confirmed.

```
━━━ ITEM #<id> ━━━ <PASS or FAIL>

<one-line description of what was built or attempted>

FILES
  + path/to/new-file.ts          (created)
  ~ path/to/modified-file.tsx    (modified)

DECISIONS
  - <key choice made and why, one line each>
```

If FAIL, add a one-line `WHY:` after DECISIONS explaining what blocked you.

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

## Anti-pattern guard (before marking passes: true)

If `docs/anti-patterns.md` exists in this repo, read it once per cycle. Each anti-pattern below maps to a self-check the agent runs before flipping any item to `passes: true`. These exist because the 2026-05-11 CareAtlas sprint shipped 16 real bugs under a 100% green test suite — every one of them traceable to one of these five patterns.

1. **Negative-only tests miss the positive path.** For any item touching auth, permissions, or a predicate, you MUST write **both** a positive assertion (the legitimate user gets `200` with the expected payload) AND a negative assertion (the unauthorized user gets `403`/`404`). If your test names are all `*_denied` / `*_forbidden` / `*_invalid`, you've proved the gate fires — not that the gate is in the right place. Add the success case.

2. **Mock fixtures must mirror real-API contracts.** Before writing a mock fixture or `MagicMock(return_value=...)`, open the source-of-truth file in the same cycle: the prompt template, vendor docs, OpenAPI schema, or a recorded real-call. Copy the field set verbatim. Do NOT invent fields the real API never returns. If production code calls `response['text']`, the mock returns `{'text': ...}`, not the bare string.

3. **Stateful features need two-invocation tests.** Any item involving `resume`, `cursor`, `checkpoint`, `retry`, `idempotent`, `cache`, `dedupe`, `pagination`, or a state machine MUST have a test that runs the operation **twice** with state preserved between calls and asserts the second call respects the first's state. A test that only checks state was *written* does not prove state is *read*.

4. **Don't mock the unit you're testing.** For "X never leaks Y" tests (no-PHI, no-secret-in-log, redaction, audit), drive **realistic data through the real un-mocked unit** and assert on captured logs (`caplog`, `assertLogs`). Mock only true external boundaries. If the test mocks the very function whose internal log statements are at risk, the test proves nothing.

5. **Framework defaults bite.** When an item touches DRF format negotiation (`URL_FORMAT_OVERRIDE`, renderer chain rewriting `Content-Type`), DRF/Django auth+permission ordering, Django middleware ordering, Celery task kwarg serialization, Next.js route handlers vs server actions, or RSC serialization boundaries — write a **black-box end-to-end test** (real HTTP request → real response) that proves the integration actually works as specified, not just that the code was written. Name the specific framework default the spec depends on.

If any item's verification steps don't cover the relevant guard above, do NOT mark it `passes: true`. Either add the missing test in this cycle or leave the item failing for the next cycle to pick up. Honest red beats false green.
