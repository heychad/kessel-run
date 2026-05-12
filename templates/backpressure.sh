#!/usr/bin/env bash
# Deflector shields — quality gate. Exit 0 = green, non-zero = red.
set -euo pipefail
FAILURES="" ; EXIT_CODE=0

check() {
  local name="$1"; shift; local output
  if output=$("$@" 2>&1); then return 0; fi
  FAILURES+=$'\n'"--- FAIL: $name ---"$'\n'"$(echo "$output" | head -30)"$'\n'
  EXIT_CODE=1
}

# ── Static checks (auto-detect based on config files) ───────────
[ -f tsconfig.json ]     && check "tsc" npx tsc --noEmit
[ -f eslint.config.mjs ] || [ -f .eslintrc.json ] && check "eslint" npx eslint . --max-warnings 0
[ -f vitest.config.ts ]  || [ -f vitest.config.mts ] && check "vitest" npx vitest run
[ -f jest.config.js ]    || [ -f jest.config.ts ] && check "jest" npx jest
[ -f next.config.ts ]    || [ -f next.config.mjs ] && check "next-build" npx next build
[ -f pyproject.toml ]    && check "pytest" python -m pytest
[ -f Cargo.toml ]        && check "cargo" cargo test
[ -d convex ]            && check "convex" npx convex typecheck

# ── E2E tests (auto-detect Playwright or Cypress) ───────────────
[ -f playwright.config.ts ] || [ -f playwright.config.js ] && \
  ls tests/*.spec.ts tests/*.spec.js e2e/*.spec.ts e2e/*.spec.js 2>/dev/null | head -1 >/dev/null && \
  check "playwright" npx playwright test
[ -f cypress.config.ts ] || [ -f cypress.config.js ] && check "cypress" npx cypress run

# ── Anti-pattern advisory (soft warnings, never fails the build) ──
# Catches the five patterns in docs/anti-patterns.md that ship bugs under
# green test suites. Each detector is heuristic — false positives are
# expected. The signal is "look here," not "block here."
#
# Scoped to test files changed by the agent vs origin/main (or HEAD~3
# fallback) so we don't flag legacy code. Silent when no test files changed.
check_anti_patterns() {
  command -v git >/dev/null 2>&1 || return 0
  local base
  base=$(git merge-base HEAD origin/main 2>/dev/null || git rev-parse HEAD~3 2>/dev/null || echo "")
  [ -z "$base" ] && return 0
  local changed_tests
  changed_tests=$(git diff --name-only "$base"...HEAD 2>/dev/null \
    | grep -E '(^|/)(tests?|__tests__|spec)/.*\.(py|ts|tsx|js|jsx)$|.*[._-](test|spec)\.(py|ts|tsx|js|jsx)$' \
    || true)
  [ -z "$changed_tests" ] && return 0
  local warnings=""
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    # 1. Negative-only test files (>= 3 tests, >=70% negative names).
    local total neg
    total=$(grep -cE '^\s*(def test_|test\(|it\()' "$f" 2>/dev/null || echo 0)
    neg=$(grep -cE '(denied|forbidden|unauthorized|not_allowed|rejects|invalid|returns_4[0-9]{2}|_404|_403|_401|_400)' "$f" 2>/dev/null || echo 0)
    if [ "$total" -ge 3 ] && [ "$neg" -gt 0 ] && [ $(( neg * 10 / total )) -ge 7 ]; then
      warnings+=$'\n  ⚠ '"$f"" — ${neg}/${total} tests look negative-only. Add a positive-path assertion (legitimate user → 200 with expected payload). See docs/anti-patterns.md #1."
    fi
    # 3. Stateful keywords without two-invocation pattern.
    if grep -qE '(cursor|resume|checkpoint|retry|idempotent|dedup|pagination|next_page)' "$f" 2>/dev/null; then
      if ! grep -qE '(twice|second_call|second invocation|call.*again|second_run|resumes_from|reads.*cursor)' "$f" 2>/dev/null; then
        warnings+=$'\n  ⚠ '"$f"" — stateful keyword present but no two-invocation pattern detected. Add a test that invokes twice and asserts the second call respects state from the first. See docs/anti-patterns.md #3."
      fi
    fi
    # 4a. No-leak / audit / redaction tests that patch the unit under test.
    if echo "$f" | grep -qiE '(no_phi|no_secret|redact|audit_log|sanitiz|leak)' && \
       grep -qE "patch\(" "$f" 2>/dev/null; then
      warnings+=$'\n  ⚠ '"$f"" — no-leak / audit test patches the unit under test. Drive real data through the un-mocked unit and assert on captured logs (caplog / assertLogs). See docs/anti-patterns.md #4."
    fi
    # 4b. Test imports a function AND also patches that same function path.
    local self_mocks
    self_mocks=$(grep -oE "patch\(['\"][a-zA-Z0-9_.]+['\"]" "$f" 2>/dev/null \
      | sed -E "s/patch\(['\"]([^'\"]+)['\"]/\\1/" \
      | while read -r patched; do
          [ -z "$patched" ] && continue
          local mod fn
          mod=$(echo "$patched" | sed -E 's/\.[^.]+$//')
          fn=$(echo "$patched" | sed -E 's/^.*\.//')
          if grep -qE "from $mod import .*$fn" "$f" 2>/dev/null; then
            echo "$patched"
          fi
        done | head -3)
    if [ -n "$self_mocks" ]; then
      warnings+=$'\n  ⚠ '"$f"" — patches a function it also imports. For no-leak / audit tests, drive real data through the un-mocked unit. See docs/anti-patterns.md #4."
    fi
  done <<< "$changed_tests"
  if [ -n "$warnings" ]; then
    echo ""
    echo "━━━ ANTI-PATTERN ADVISORIES (soft — not blocking) ━━━"
    echo "$warnings"
    echo ""
    echo "Review docs/anti-patterns.md before marking these items passes: true."
  fi
}
check_anti_patterns || true

if [ $EXIT_CODE -eq 0 ]; then echo "ALL GREEN"
else echo "$FAILURES" | head -100; fi
exit $EXIT_CODE
