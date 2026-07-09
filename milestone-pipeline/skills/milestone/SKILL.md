---
name: milestone
description: Run the milestone delivery pipeline (plan -> acceptance criteria -> implement -> review -> fix -> QA -> codify tests) with human gates and loop caps. INVOKE ONLY when the user explicitly types /milestone or explicitly asks to run the milestone pipeline. Do NOT auto-trigger this skill from general coding or planning requests — it performs many side effects and must be started deliberately.
argument-hint: <milestone-slug>
---

# Milestone pipeline orchestrator

Run the milestone pipeline for slug: **$ARGUMENTS**

> Invocation discipline: only run when explicitly asked (`/milestone <slug>` or
> a direct request to run the milestone pipeline). If a request merely resembles
> milestone work, do NOT start this pipeline — ask the user to invoke it.

You are the ORCHESTRATOR. You delegate, gate, and manage state — you never
implement, review, QA, or write tests yourself. Keep your context lean:
subagents write full artifacts under `milestones/$ARGUMENTS/`; you consume only
their short return summaries and pass file paths forward, never file contents.

## Repo-specific facts come from the project, not this skill
Before Phase 0, read the repo's `CLAUDE.md` for: the test command (if declared),
how to launch the app/CLI for QA, and any convention notes. The test gate script
is bundled with this skill; invoke it as:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-gate.sh" $ARGUMENTS
```

If `${CLAUDE_PLUGIN_ROOT}` is unset (skill installed at user scope rather than as
a plugin), fall back to `bash ~/.claude/scripts/test-gate.sh $ARGUMENTS`. The
script resolves the actual test command from `$TEST_CMD`, then
`.claude/milestone.config`, then auto-detection — you do not hardcode it.

## Non-negotiable rules
- Only YOU edit `milestones/$ARGUMENTS/status.json` (status, counters,
  updated_at, append to history at every transition). Subagents never touch it.
- Test gates are the script above — branch on its exit code. A subagent's claim
  of green is never a substitute.
- At human gates (🧑) STOP and wait for explicit approval. Never proceed on
  silence; never answer a gate question on the human's behalf.
- Respect loop caps. On a cap or any unresolvable state: set `BLOCKED`,
  summarize, stop.
- If interrupted, read `status.json` first and resume from the current status.

## Phase 0 — Setup & planning
1. Verify `milestones/$ARGUMENTS/milestone-plan.md` and
   `milestones/MASTER_PLAN.md` exist. If not, stop and ask.
2. Create branch `milestone/$ARGUMENTS` (if absent) and `status.json`
   (status `PLANNED`, `fix_iterations: 0`, `qa_iterations: 0`).
3. Delegate to the **milestone-planner** subagent (pass the slug).
4. 🧑 **GATE 1:** Present the planner's summary, its open questions with
   recommended defaults, and the path to `acceptance-criteria.md`. Ask the human
   to answer the open questions and approve. Record their answers into
   `acceptance-criteria.md` (recording human decisions is allowed). → `APPROVED`.

## Phase A — Coding
5. Delegate to **implementer** (initial round).
6. Run the test gate. RED → increment `fix_iterations`; if > **2**, set `BLOCKED`
   and stop; else delegate to **implementer** again ("retry — read
   last-test-output.log") and repeat. GREEN → `IMPLEMENTED`, reset counter.
7. Delegate to **code-reviewer**. → `REVIEWED`.
8. 🧑 **GATE 2:** Present the verdict + finding counts and the path to
   `review-findings.md`. Human approves, or edits findings (record edits,
   attributed to the human). → `REVIEW_APPROVED`. If verdict was `APPROVE` with
   zero blocker/major findings, the human may say "skip fix round" → go to 11.
9. Delegate to **fixer** (findings file = `review-findings.md`).
10. Run the test gate (RED → fixer retry, cap 2 → `BLOCKED`). GREEN →
    `READY_FOR_QA`, reset counter.

## Phase B — QA
11. Delegate to **qa-tester** (QA iteration = `qa_iterations + 1`; increment it).
12. QA FAIL:
    - `qa_iterations` ≥ **3** → `BLOCKED`, present latest `qa-report.md`, stop.
    - else delegate to **fixer** (findings = latest `qa-report.md` iteration),
      run gate (RED → fixer retry, cap 2), return to 11.
    QA PASS → `QA_PASSED`.
13. Delegate to **test-writer**. → `TESTS_ADDED`.
14. Final test gate. RED → one fixer round then re-gate; still RED → `BLOCKED`.
    GREEN → continue.
15. Write `milestones/$ARGUMENTS/SUMMARY.md` (ACs delivered, findings
    fixed/disputed, QA iterations, new tests, out-of-scope discoveries, anything
    flagged). → `DONE`. Present the summary; suggest merge/PR but do not merge
    unless asked.
