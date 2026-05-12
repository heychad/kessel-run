# Test & verification anti-patterns

> The 2026-05-11 CareAtlas Drug Interactions sprint shipped a 72-item PRD at
> 100% test-pass rate and a post-merge review still surfaced **16 real
> production bugs**. PR #468 fixed all of them. This doc encodes the five
> classes of bug-hiding the test suite missed so the next kessel-run cycle
> catches them automatically.
>
> Source: `docs/run-2026-05-11-careatlas-drug-interactions.md` and
> [CareAtlas PR #468](https://github.com/care-atlas/care-atlas/pull/468).

`PROMPT.md` and `scripts/kessel-run/backpressure.sh` reference this file. Keep
it short and example-driven — agents read it, operators audit it.

---

## 1. Negative-only tests that miss the positive path

**What slipped through:** A view's auth check had a test
`test_user_without_provider_link_denied` proving a 403 fires when the link is
missing. The fix flipped the predicate to allow non-staff users. The test
caught nothing because **no test asserted "non-staff user with valid auth →
200."** Negative-only test = predicate can be inverted with no signal.

**Rule:** Every user story implements a positive AND a negative assertion.

- ✅ Positive: "non-staff CN with valid auth and patient link → **200**, body
  contains expected payload."
- ✅ Negative: "non-staff CN without patient link → **403**."

If your test file for a view has only `*_denied`, `*_forbidden`, `*_404`,
`*_invalid` test names, that's a smell. Add the success case.

**How kessel-run catches it:** the anti-pattern grep in `backpressure.sh`
warns when a test file's test names are >70% negative-shaped. PRD items
that touch auth/permission code must have verification entries naming BOTH
the positive and negative case.

---

## 2. Mock fixtures that don't match real-API contracts

**What slipped through:** `fixtures/gemini_mock_extractions.json` contained
fields (`drug_a_rxcui`, `class_id`, `class_source`) that the real Gemini
prompt schema in `prompts/extract_interactions.txt` never asks for. Tests
passed against the rich mocks; production left those fields `None`.

Separately, `/ask` treated `gemini_client.generate_text()`'s return as a
**string**, but the real client returns `{'text': ..., 'model': ...,
'usage': ...}`. Mock returned a string. Tests passed. Production broke.

**Rule:** Mock fixtures must mirror the shape of the documented real-API
contract. The contract lives in one of:
- the prompt template (for LLM calls)
- the upstream API's documented response schema
- an integration-test recording of one real call

**Discipline:**
- When you write a mock, **open the source-of-truth file in the same cycle**
  (prompt template, OpenAPI spec, vendor docs) and copy the field set
  verbatim. Don't invent fields.
- When the production client wraps a response, the mock returns the wrapped
  shape — never the inner payload.
- For any external API, include at least one assertion that exercises the
  mock against the real client wrapper (the same `response['text']`
  extraction path that production uses).

**How kessel-run catches it:** PRD verification for any item that introduces
a mock fixture must include a "schema parity" step naming the source-of-truth
file. The PROMPT-level discipline reminds the agent to read it before
writing the mock.

---

## 3. Single-call tests for stateful features

**What slipped through:** `test_cursor_resume` proved the cursor *value*
was written to the cache after 100 rows. **It never proved the cursor was
*read* on a second invocation.** Resume was completely non-functional —
on restart, ingestion always began at row 0.

**Rule:** Any feature with cursor / pagination / retry / state-machine /
idempotency semantics needs a **two-invocation test**:

1. Call the operation once. Capture / verify state was written.
2. Call it a second time. Assert the second call **respects the state from
   the first** (resumes from cursor, skips already-processed rows, hits the
   retry path, etc.).

Single-call tests can prove state was *recorded*. Only multi-call tests
prove state is *used*.

**Trigger phrases in a PRD item that demand this pattern:**
`resume`, `cursor`, `checkpoint`, `retry`, `idempotent`, `cache`, `dedupe`,
`pagination`, `next_page_token`, `state machine`, `transition`.

**How kessel-run catches it:** PRD verification for any stateful item must
include "test invokes the operation twice and asserts second call respects
first." The anti-pattern grep flags test files mentioning trigger words
but never calling the operation twice.

---

## 4. Unit tests that mock the unit under test

**What slipped through:** `test_audit_log_contains_no_medication_names`
mocked `run_check_pipeline` to return an empty result, then asserted the
audit log was free of PHI. **The mocked path never fired the actual
PHI-leaking warning.** The real failure-path codepath was never exercised.

**Rule:** Tests of the form "X never leaks Y" (PHI safety, secret redaction,
PII scrubbing, error sanitization) MUST exercise the codepath where Y is
*at risk* of being leaked — usually a real failure path with realistic data
flowing through the un-mocked unit.

Pattern: if your test mocks the function whose internal log statements
you're testing, you've mocked away the test.

**Discipline:**
- For audit / log / redaction tests, drive realistic data through the
  *real* function and assert on the resulting log lines or audit row.
- Use `caplog` (pytest), `assertLogs` (Django), or recording loggers
  rather than mocks.
- Only mock the **boundaries** (external API calls), never the unit
  whose internal behavior you're verifying.

**How kessel-run catches it:** PRD verification for any item with "no
PHI", "no secrets", "redact", or "audit log" wording must specify "test
drives realistic data through the un-mocked unit and asserts on captured
logs." The anti-pattern grep flags test files that import the function
under test AND import `mock` / `patch` for the same import path.

---

## 5. Framework-default surprises

**What slipped through:**
- DRF's `URL_FORMAT_OVERRIDE` defaults to `'format'` and 404s unknown values
  **before views run**, so `?format=fhir` was dead code.
- DRF's renderer chain rewrites `response['Content-Type']` during
  finalization, so setting it post-`Response()` was also dead.

These are well-known framework behaviors. The build didn't account for them
because nothing forced the agent to ask "does this framework actually do
what the spec assumes?"

**Rule:** Any non-trivial framework integration gets an explicit
**framework-quirks pass** before the item is marked done. Areas with a
strong history of surprise:

- **DRF format negotiation** (`URL_FORMAT_OVERRIDE`, `DEFAULT_RENDERER_CLASSES`,
  `Accept` header parsing)
- **DRF renderers** rewriting `Content-Type` / `Accept-Charset` during
  `finalize_response`
- **Django middleware ordering** (auth before throttling before view)
- **Django signal timing** (`pre_save` vs `post_save`, transaction commit)
- **Celery task serialization** (kwargs must be JSON-serializable; `datetime`
  needs explicit handling)
- **DRF authentication classes ordering** vs permission classes
- **Next.js route handlers** vs server actions vs middleware
- **React Server Components** boundary (props serialization, no hooks)
- **Convex query/mutation** transactional semantics

**Discipline:**
- Any PRD item touching one of the above must include a verification
  step naming the **specific framework default** the spec depends on
  *not* doing, and a test that asserts the integration actually works
  end-to-end (not just that the code was written).
- When in doubt, write a **black-box** integration test — assert the HTTP
  response, not the internal call chain.

**How kessel-run catches it:** PROMPT.md instructs the agent to run a
framework-quirks pass when an item's spec touches the listed integration
points. Anti-pattern grep warns when the agent ships code that sets
response headers or registers a format negotiator without a matching
black-box assertion.

---

## How to use this doc

**Scout / planning phase (`/plan-sprint`):** When writing PRD `verification`
entries, run this checklist against each item:

- [ ] If the item touches auth or permissions → does verification include
      BOTH a positive and a negative assertion?
- [ ] If the item introduces a mock fixture → does verification name the
      source-of-truth file the mock must mirror?
- [ ] If the item is stateful (cursor / retry / cache / pagination) →
      does verification include a two-invocation test?
- [ ] If the item is about not-leaking-something → does verification drive
      real data through the un-mocked unit?
- [ ] If the item touches DRF format negotiation, renderers, middleware
      ordering, Celery serialization, or a similarly opinionated framework
      surface → does verification include a black-box end-to-end test
      naming the framework default the spec depends on?

**Build phase (kessel-run loop):** PROMPT.md references this file directly
under "Anti-pattern guard." The agent reads it once per cycle and self-checks
before marking `passes: true`.

**Verifier phase (`backpressure.sh`):** The optional `anti-patterns` check
greps for the most mechanically detectable cases (>70% negative tests,
self-mocking imports, stateful keywords without two-invocation patterns).
Soft-fail by default — it warns, doesn't block — so noise doesn't kill the
loop. Promote to hard-fail per project once tuned.
