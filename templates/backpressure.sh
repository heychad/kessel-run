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

if [ $EXIT_CODE -eq 0 ]; then echo "ALL GREEN"
else echo "$FAILURES" | head -100; fi
exit $EXIT_CODE
