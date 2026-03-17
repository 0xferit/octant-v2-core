#!/usr/bin/env bash
# Verifies that every contract declaring a VERSION constant, among the files
# changed in this PR, has it set to today's date (DDMMYY).
# Intended for CI enforcement on PRs targeting main.
#
# Usage: bash scripts/check-version-date.sh [EXPECTED_DATE]
#   EXPECTED_DATE: optional override in DDMMYY format (defaults to system date)
#
# Environment:
#   CHANGED_FILES: newline-separated list of changed .sol file paths (optional).
#                  If not set, checks all src/**/*.sol files.

set -euo pipefail

EXPECTED="${1:-$(date +%d%m%y)}"
FAILED=0
CHECKED=0

echo "Expected VERSION date: $EXPECTED"
echo ""

if [ -n "${CHANGED_FILES:-}" ]; then
  FILES="$CHANGED_FILES"
else
  # Fallback: all Solidity files under src/
  FILES=$(find src/ -name '*.sol' -type f 2>/dev/null || true)
fi

while IFS= read -r file; do
  [ -z "$file" ] && continue
  [ ! -f "$file" ] && continue

  # Check if this file declares a VERSION constant
  match=$(grep -n 'string.*constant.*VERSION.*=.*"[0-9]\{6\}"' "$file" || true)
  [ -z "$match" ] && continue

  line_num=$(echo "$match" | head -1 | cut -d: -f1)
  actual=$(echo "$match" | head -1 | sed 's/.*"\([0-9]\{6\}\)".*/\1/')

  CHECKED=$((CHECKED + 1))

  if [ "$actual" != "$EXPECTED" ]; then
    echo "FAIL: $file:$line_num has VERSION=\"$actual\" (expected \"$EXPECTED\")"
    FAILED=1
  else
    echo "  OK: $file:$line_num VERSION=\"$actual\""
  fi
done <<< "$FILES"

echo ""

if [ "$CHECKED" -eq 0 ]; then
  echo "No contracts with VERSION constant found in changed files. Nothing to check."
  exit 0
fi

echo "Checked $CHECKED contract(s)."

if [ "$FAILED" -eq 1 ]; then
  echo ""
  echo "VERSION date mismatch detected. Update the VERSION constant to today's date before merging."
  exit 1
fi

echo "All VERSION constants match the expected date."
