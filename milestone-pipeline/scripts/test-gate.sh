#!/usr/bin/env bash
# test-gate.sh — GLOBAL deterministic test gate.
#
# The test command is auto-detected ONCE by the orchestrator in Phase 0
# (`test-gate.sh --detect`), confirmed by the human at Gate 1, and persisted to
# `milestones/<slug>/test-cmd`. Every gate run in the rest of the pipeline then
# reuses that exact command, so the whole run is deterministic and the user is
# never asked to author a test command.
#
# Resolution order (for a gate run):
#   1. $TEST_CMD environment variable (optional override / escape hatch)
#   2. milestones/<slug>/test-cmd   (the Phase-0 detected command for this run)
#   3. auto-detection from repo marker files (fallback if #2 is missing)
#
# Usage:
#   test-gate.sh <slug>     run the gate; exits with the test suite's exit code
#   test-gate.sh --detect   print the command to persist, then exit
#                           (0 = resolved and printed on stdout, 2 = unresolved)

set -uo pipefail

# Best-effort detection from repo marker files. Prints the command, or nothing
# if it cannot tell. package.json only counts if it actually declares a test
# script — an undeclared `npm test` just errors and reads as a false RED.
auto_detect() {
  if [ -f package.json ]; then
    if grep -Eq '"test"[[:space:]]*:' package.json; then echo "npm test"; fi
    return
  fi
  if [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ]; then echo "pytest -x -q"; return; fi
  if [ -f go.mod ]; then echo "go test ./..."; return; fi
  if [ -f Cargo.toml ]; then echo "cargo test"; return; fi
  if [ -f Gemfile ]; then echo "bundle exec rspec"; return; fi
  if [ -f pom.xml ]; then echo "mvn -q test"; return; fi
  if [ -f build.gradle ] || [ -f build.gradle.kts ]; then echo "./gradlew test"; return; fi
  echo ""  # unresolved
}

# --detect: print the command the orchestrator should persist for this run.
# An explicit $TEST_CMD override wins; otherwise fall back to marker detection.
if [ "${1:-}" = "--detect" ]; then
  cmd="${TEST_CMD:-$(auto_detect)}"
  if [ -z "$cmd" ]; then
    echo "test-gate: could not auto-detect a test command from repo markers." >&2
    echo "Confirm one with the human and write it to milestones/<slug>/test-cmd." >&2
    exit 2
  fi
  echo "$cmd"
  exit 0
fi

SLUG="${1:?usage: test-gate.sh <slug>  |  test-gate.sh --detect}"
DIR="milestones/${SLUG}"
LOG="${DIR}/last-test-output.log"
CMD_FILE="${DIR}/test-cmd"

resolve_test_cmd() {
  # 1. explicit env override
  if [ -n "${TEST_CMD:-}" ]; then echo "$TEST_CMD"; return; fi
  # 2. command detected & persisted for this milestone in Phase 0 (verbatim line)
  if [ -f "$CMD_FILE" ]; then
    local persisted
    persisted="$(head -1 "$CMD_FILE")"
    if [ -n "$persisted" ]; then echo "$persisted"; return; fi
  fi
  # 3. auto-detect fallback (should be rare — Phase 0 normally seeds #2)
  auto_detect
}

TEST_CMD_RESOLVED="$(resolve_test_cmd)"

mkdir -p "$DIR"
if [ -z "$TEST_CMD_RESOLVED" ]; then
  echo "== test-gate: NO TEST COMMAND RESOLVED =="
  echo "Phase 0 should have detected and written ${CMD_FILE}. Re-run detection" \
       "(test-gate.sh --detect) or set TEST_CMD. Refusing to pass a gate with" \
       "no tests." | tee "$LOG"
  exit 2
fi

echo "== test-gate: ${TEST_CMD_RESOLVED} (milestone: ${SLUG}) =="
{
  echo "# test-gate run: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# command: ${TEST_CMD_RESOLVED}"
  echo
} > "$LOG"

# shellcheck disable=SC2086
$TEST_CMD_RESOLVED 2>&1 | tee -a "$LOG"
EXIT_CODE=${PIPESTATUS[0]}

echo >> "$LOG"; echo "# exit code: ${EXIT_CODE}" >> "$LOG"
[ "$EXIT_CODE" -eq 0 ] && echo "== test-gate: GREEN ==" \
  || echo "== test-gate: RED (exit ${EXIT_CODE}) — see ${LOG} =="
exit "$EXIT_CODE"
