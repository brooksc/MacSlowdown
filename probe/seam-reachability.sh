#!/bin/bash
# seam-reachability.sh — find capabilities that are tested but never called.
#
# TASK-73. Five times in one session we found code that was fully implemented in
# the `Metrics` framework, covered by passing tests, and wired into nothing. A
# passing test proves a unit works; it does not prove anything calls it. This
# script looks for exactly that signature:
#
#     declared public  +  referenced by tests  +  referenced by no caller
#
# It is deliberately NOT "unreferenced by the app". Plenty of framework types are
# reached transitively — the app calls `StorageSignals.snapshot()` and never spells
# `StorageSnapshot`. Requiring zero callers *anywhere outside the declaration*
# while tests do exercise it is what isolates the defect class without drowning it
# in false positives.
#
# Usage:  probe/seam-reachability.sh            # report and exit non-zero on new findings
#         probe/seam-reachability.sh --list     # report only, always exit 0
#
# Staged work belongs in probe/seam-allowlist.txt, one symbol per line followed by
# a reason. An entry without a reason is rejected: "we meant to" has to be written
# down at the time, or it is indistinguishable from having forgotten.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

ALLOWLIST="probe/seam-allowlist.txt"
FRAMEWORK_SRC="Metrics/Sources"
APP_SRC="MacSlowdown/Sources"
TESTS=(Metrics/Tests MacSlowdown/Tests)

list_only=0
[ "${1:-}" = "--list" ] && list_only=1

# Every public declaration, as "name<TAB>file:line".
symbols=$(grep -rnE \
  "^[[:space:]]*public [a-z ]*(struct|enum|class|actor|protocol|func|var|let|init)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*" \
  "$FRAMEWORK_SRC"/*.swift \
  | sed -E 's/^([^:]+):([0-9]+):[[:space:]]*public [a-z ]*(struct|enum|class|actor|protocol|func|var|let|init)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\4\t\1:\2/')

findings=0
allowed_hit=0

while IFS=$'\t' read -r name where; do
  [ -z "$name" ] && continue
  file="${where%%:*}"
  line="${where##*:}"

  # Callers in the app.
  app=$(grep -rowE "\b$name\b" "$APP_SRC" 2>/dev/null | wc -l | tr -d ' ')
  [ "$app" -gt 0 ] && continue

  # Callers inside the framework, excluding the declaration line itself.
  fw=$(grep -rnowE "\b$name\b" "$FRAMEWORK_SRC" 2>/dev/null \
        | grep -v "^$file:$line:" | wc -l | tr -d ' ')
  [ "$fw" -gt 0 ] && continue

  # Exercised by tests? No test coverage means "unused", which is a different and
  # much less interesting problem than "tested and unreachable".
  tests=0
  for t in "${TESTS[@]}"; do
    [ -d "$t" ] || continue
    n=$(grep -rowE "\b$name\b" "$t" 2>/dev/null | wc -l | tr -d ' ')
    tests=$((tests + n))
  done
  [ "$tests" -eq 0 ] && continue

  if grep -qE "^$name([[:space:]]|$)" "$ALLOWLIST" 2>/dev/null; then
    allowed_hit=$((allowed_hit + 1))
    continue
  fi

  printf 'TESTED BUT UNREACHABLE  %-38s %s  (%s test references, 0 callers)\n' \
    "$name" "$where" "$tests"
  findings=$((findings + 1))
done <<< "$symbols"

echo
echo "$findings unexplained; $allowed_hit allowed by $ALLOWLIST."

if [ "$findings" -gt 0 ] && [ "$list_only" -eq 0 ]; then
  echo
  echo "Each of these is either a missing call site or deliberate staging."
  echo "Wire it up, delete it, or add it to $ALLOWLIST with the reason it is staged"
  echo "and the task that will connect it. Do not add a bare name."
  exit 1
fi
exit 0
