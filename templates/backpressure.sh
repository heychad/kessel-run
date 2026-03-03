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

# Auto-detect checks based on config files
[ -f tsconfig.json ]     && check "tsc" npx tsc --noEmit
[ -f eslint.config.mjs ] || [ -f .eslintrc.json ] && check "eslint" npx eslint . --max-warnings 0
[ -f vitest.config.ts ]  || [ -f vitest.config.mts ] && check "vitest" npx vitest run
[ -f jest.config.js ]    || [ -f jest.config.ts ] && check "jest" npx jest
[ -f next.config.ts ]    || [ -f next.config.mjs ] && check "next-build" npx next build
[ -f pyproject.toml ]    && check "pytest" python -m pytest
[ -f Cargo.toml ]        && check "cargo" cargo test
[ -d convex ]            && check "convex" npx convex typecheck

if [ $EXIT_CODE -eq 0 ]; then echo "ALL GREEN"
else echo "$FAILURES" | head -100; fi
exit $EXIT_CODE
