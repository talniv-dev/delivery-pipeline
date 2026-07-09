---
name: milestone
description: Run the milestone delivery pipeline (plan -> acceptance criteria -> implement -> review -> fix -> QA -> codify tests) with human gates and loop caps. INVOKE ONLY when the user explicitly types /milestone or explicitly asks to run the milestone pipeline. Do NOT auto-trigger this skill from general coding or planning requests — it performs many side effects and must be started deliberately.
argument-hint: <milestone-slug> (then provide the milestone plan — path or pasted; master plan optional)
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
Before Phase 0, read the repo's `CLAUDE.md` for: how to launch the app/CLI for
QA, and any convention notes. The test gate script is bundled with this skill;
invoke it as:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-gate.sh" $ARGUMENTS
```

If `${CLAUDE_PLUGIN_ROOT}` is unset (skill installed at user scope rather than as
a plugin), fall back to `bash ~/.claude/scripts/test-gate.sh $ARGUMENTS`.

The test command is **auto-detected once in Phase 0** (never supplied by the
user) and persisted to `milestones/$ARGUMENTS/test-cmd`; every later gate run
reuses that exact command. You do not hardcode the command and you do not ask
the user for it — you detect, confirm at Gate 1, and persist. (`$TEST_CMD` in
the environment remains an optional override for edge cases.)

## Non-negotiable rules
- Only YOU edit `milestones/$ARGUMENTS/status.json` (status, counters,
  `base_branch`, updated_at, append to history at every transition). Subagents
  never touch it.
- Diffs use the recorded `base_branch`, never a hardcoded `main`. Pass
  `base_branch` to every subagent that diffs (reviewer, fixer, test-writer) so
  they run `git diff <base_branch>...HEAD` against the branch this milestone was
  actually forked from.
- Test gates are the script above — branch on its exit code. A subagent's claim
  of green is never a substitute.
- At human gates (🧑) STOP and wait for explicit approval. Never proceed on
  silence; never answer a gate question on the human's behalf.
- Respect loop caps. On a cap or any unresolvable state: set `BLOCKED`,
  summarize, stop.
- If interrupted, read `status.json` first and resume from the current status.

## Phase 0 — Setup & planning
1. **Collect the plan inputs** from what the user provided — do NOT assume a
   fixed project location. The **milestone plan** is required (a path the user
   pointed at, or pasted content). The **master plan** is recommended context
   but optional. If no milestone plan was provided, STOP and ask for it.
2. **Create the pipeline's working area and branch.** The pipeline owns this
   directory and creates it itself — the user is not expected to author any
   structure.
   - Record the base branch BEFORE branching:
     `base_branch=$(git rev-parse --abbrev-ref HEAD)`.
   - Create `milestones/$ARGUMENTS/` and normalize the inputs into it so every
     subagent has stable paths regardless of where the user kept them: write the
     milestone plan to `milestones/$ARGUMENTS/milestone-plan.md` and, if
     provided, the master plan to `milestones/$ARGUMENTS/master-plan.md` (copy
     the pointed-at file, or save the pasted content).
   - Create branch `milestone/$ARGUMENTS` (if absent) from `base_branch`.
   - Create `status.json` (status `PLANNED`, `base_branch`, `fix_iterations: 0`,
     `qa_iterations: 0`).
3. **Detect the test command** (once, now): run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-gate.sh" --detect`. Write the
   printed command verbatim to `milestones/$ARGUMENTS/test-cmd`. If detection
   exits non-zero (no recognizable markers), do NOT guess — carry it as an open
   question for Gate 1 and leave `test-cmd` empty until the human confirms one.
4. Delegate to the **milestone-planner** subagent (pass the slug and the
   normalized plan paths).
5. 🧑 **GATE 1:** Present the planner's summary, its open questions with
   recommended defaults, the **detected test command** (for confirmation — the
   human may correct it, and you rewrite `test-cmd` accordingly), and the path to
   `acceptance-criteria.md`. Ask the human to answer the open questions and
   approve. Record their answers into `acceptance-criteria.md` (recording human
   decisions is allowed). → `APPROVED`.

## Phase A — Coding
6. Delegate to **implementer** (initial round).
7. Run the test gate. RED → increment `fix_iterations`; if > **2**, set `BLOCKED`
   and stop; else delegate to **implementer** again ("retry — read
   last-test-output.log") and repeat. GREEN → `IMPLEMENTED`, reset counter.
8. Delegate to **code-reviewer**. → `REVIEWED`.
9. 🧑 **GATE 2:** Present the verdict + finding counts and the path to
   `review-findings.md`. Human approves, or edits findings (record edits,
   attributed to the human). → `REVIEW_APPROVED`. If verdict was `APPROVE` with
   zero blocker/major findings, the human may say "skip fix round" → go to 12.
10. Delegate to **fixer** (findings file = `review-findings.md`).
11. Run the test gate (RED → fixer retry, cap 2 → `BLOCKED`). GREEN →
    `READY_FOR_QA`, reset counter.

## Phase B — QA
12. Delegate to **qa-tester** (QA iteration = `qa_iterations + 1`; increment it).
13. QA FAIL:
    - `qa_iterations` ≥ **3** → `BLOCKED`, present latest `qa-report.md`, stop.
    - else delegate to **fixer** (findings = latest `qa-report.md` iteration),
      run gate (RED → fixer retry, cap 2), return to 12.
    QA PASS → `QA_PASSED`.
14. Delegate to **test-writer**. → `TESTS_ADDED`.
15. Final test gate. RED → one fixer round then re-gate; still RED → `BLOCKED`.
    GREEN → continue.
16. Write `milestones/$ARGUMENTS/SUMMARY.md` (ACs delivered, findings
    fixed/disputed, QA iterations, new tests, out-of-scope discoveries, anything
    flagged, and the **commit list** `git log <base_branch>..HEAD --oneline` so
    every commit is attributed to a phase). → `DONE`. Present the summary;
    suggest merge/PR but do not merge unless asked.

## Commits & cleanup
Subagents commit their own work (implementer, fixer, test-writer); YOU never
commit and never rewrite history. This keeps ownership clear, but it means a
run that ends in `BLOCKED` leaves the failed/partial attempts as commits on the
branch. That is by design — an audit trail, not a mess to hide. The cleanup
contract:

- **Everything stays on `milestone/$ARGUMENTS`.** Nothing lands on
  `base_branch` until the human merges, so an abandoned run never pollutes the
  base. Discarding a whole failed attempt is just
  `git branch -D milestone/$ARGUMENTS` (base untouched).
- **Attribution is recorded, not lost.** Each subagent's return summary and
  notes file carry its commit hash, `status.json` history logs every transition,
  and `SUMMARY.md` lists the commits per phase — so a human can see exactly which
  commit belongs to which implement/fix/QA round and decide what to keep.
- **You never auto-clean.** Squashing, reordering, or dropping commits before a
  merge is a human decision made at merge time (e.g. squash-merge the PR, or an
  interactive rebase they run themselves). On `BLOCKED`, state plainly which
  commits are the salvageable ones and which came from the failed attempt;
  don't rewrite them yourself.
