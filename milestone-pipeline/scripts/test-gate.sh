#!/usr/bin/env bash
# test-gate.sh — GLOBAL deterministic test gate.
#
# One copy serves every repo. It resolves the test command per-project, in
# priority order, so nothing repo-specific is baked into this file:
#   1. $TEST_CMD environment variable (highest priority)
#   2. .claude/milestone.config  (a line: TEST_CMD=...)  in the repo root
#   3. auto-detection from repo marker files (best-effort fallback)
#
# Usage: test-gate.sh <milestone-slug>
# Exits with the test suite's exit code. The orchestrator branches on it.

set -uo pipefail
SLUG="${1:?usage: test-gate.sh <milestone-slug>}"
DIR="milestones/${SLUG}"
LOG="${DIR}/last-test-output.log"
CONFIG=".claude/milestone.config"

resolve_test_cmd() {
  # 1. explicit env override
  if [ -n "${TEST_CMD:-}" ]; then echo "$TEST_CMD"; return; fi
  # 2. per-repo config file
  if [ -f "$CONFIG" ]; then
    local from_cfg
    from_cfg="$(grep -E '^TEST_CMD=' "$CONFIG" | head -1 | cut -d= -f2-)"
    if [ -n "$from_cfg" ]; then echo "$from_cfg"; return; fi
  fi
  # 3. auto-detect
  if [ -f package.json ]; then echo "npm test"; return; fi
  if [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ]; then echo "pytest -x -q"; return; fi
  if [ -f go.mod ]; then echo "go test ./..."; return; fi
  if [ -f Cargo.toml ]; then echo "cargo test"; return; fi
  if [ -f Gemfile ]; then echo "bundle exec rspec"; return; fi
  if [ -f pom.xml ]; then echo "mvn -q test"; return; fi
  if [ -f build.gradle ] || [ -f build.gradle.kts ]; then echo "./gradlew test"; return; fi
  echo ""  # unresolved
}

TEST_CMD_RESOLVED="$(resolve_test_cmd)"

mkdir -p "$DIR"
if [ -z "$TEST_CMD_RESOLVED" ]; then
  echo "== test-gate: NO TEST COMMAND RESOLVED =="
  echo "Set TEST_CMD, or add 'TEST_CMD=...' to ${CONFIG}, or add a known" \
       "marker file. Refusing to pass a gate with no tests." | tee "$LOG"
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
