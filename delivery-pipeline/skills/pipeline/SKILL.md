---
name: pipeline
description: Run the delivery pipeline for a coding task (context -> acceptance criteria -> implement -> independent review -> fix -> hands-on QA -> codify tests) with human gates and loop caps. INVOKE ONLY when the user explicitly types /pipeline or explicitly asks to run the delivery pipeline. Do NOT auto-trigger this skill from general coding, planning, or "build me X" requests - it performs many side effects and must be started deliberately.
argument-hint: [optional - describe the task, paste it, or point at a file; anything works]
---

# Delivery pipeline orchestrator

Everything after the command name is **context, not parameters**: `$ARGUMENTS`

Only run when explicitly asked (`/pipeline …` or a direct request to run the
delivery pipeline). If the user merely asked for a feature or a fix, do not
start the pipeline - ask whether they want it.

You are the ORCHESTRATOR. You delegate, gate, and manage state - you never
implement, review, QA, or write tests yourself. Keep your context lean:
subagents write full artifacts under the run directory; you consume only their
short return summaries and pass file paths forward, never file contents.

## Naming and locations - you derive these, never ask the user

- `RUN_DIR` = `.pipeline/<run-id>/` (if `$PIPELINE_ROOT` is set, use that
  instead of `.pipeline`).
- `<run-id>` = a short kebab-case name you derive from what the work delivers
  (`add-oauth-login`, `fix-csv-import`), 2–4 words. If that directory already
  exists, suffix `-2`, `-3`, … Announce the id you picked; do not ask for one.
- Branch = `pipeline/<run-id>`.

## Repo facts and the test gate

Before Phase 0, read the repo's `CLAUDE.md` for how to launch the app/CLI for
QA, and any convention notes. The test gate script is bundled with this skill;
invoke it as:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-gate.sh" <run-id>
```

If `${CLAUDE_PLUGIN_ROOT}` is unset (skill installed at user scope rather than
as a plugin), fall back to `bash ~/.claude/scripts/test-gate.sh <run-id>`.

## Non-negotiable rules

- Only YOU edit `<RUN_DIR>/status.json` (status, counters, `run_id`,
  `base_branch`, updated_at, append to history at every transition). Subagents
  never touch it.
- Diffs use the recorded `base_branch`, never a hardcoded `main`. Pass
  `base_branch` and `RUN_DIR` to every subagent that diffs (both reviewers,
  fixer, test-writer) so they run `git diff <base_branch>...HEAD` against the
  branch this run was actually forked from.
- Test gates are the script above - branch on its exit code. A subagent's claim
  of green is never a substitute.
- Verify prose, not just green: a suite can pass while a subagent's factual
  claim about the repo is false. Before any repo-state fact a subagent
  reported becomes **load-bearing** - an acceptance criterion, a gate/scope/
  config decision, an assertion you make to the human at a gate, or a line in
  SUMMARY - run the one cheap command (grep/ls/glob/read) that confirms it
  yourself. Claims that never become load-bearing need no check.
- At human gates (🧑) STOP and wait for explicit approval. Never proceed on
  silence; never answer a gate question on the human's behalf.
- Respect loop caps. On a cap or any unresolvable state: set `BLOCKED`,
  summarize, stop.
- If interrupted, resume rather than restart: scan `.pipeline/*/status.json`
  for runs whose status is neither `DONE` nor `BLOCKED`; if one matches what the
  user is asking about, read it and resume from its current status.

## Phase 0 - Setup & planning

### 0.1 Collect the context

Gather everything the user has given you about this task, in whatever form it
came: text after the command, file paths, pasted content, the preceding
conversation, or any mix of these at different levels of authority. Any shape
is valid; never ask the user to classify, reformat, or supplement it. Only if
you have **no** signal at all - nothing in the arguments and nothing in the
conversation - ask exactly one open question ("what should this run deliver?")
and accept whatever form the answer takes.

Never infer requirements the context does not contain. Thin context is allowed:
it becomes open questions at Gate 1, never invented detail.

### 0.2 Create the working area and branch

- Record the base branch BEFORE branching:
  `base_branch=$(git rev-parse --abbrev-ref HEAD)`.
- Derive `<run-id>` and create `<RUN_DIR>/context/`.
- **Normalize the context** into `<RUN_DIR>/context/` so every subagent has
  stable paths regardless of where it came from: copy each pointed-at file, and
  save pasted or conversational content as its own file. Keep original
  filenames where they exist; prefix with `01-`, `02-`, … to preserve order.
  Copy verbatim - never rewrite, summarize, or restructure.
- Write `<RUN_DIR>/context/INDEX.md`: one entry per item recording its
  provenance (file path / pasted / this conversation / the user's words at
  invocation) and, **verbatim**, how the user framed it. Do not label items
  "requirement" vs "background" unless the user's own framing says so; if it is
  genuinely unclear which item is the ask, that is a Gate 1 question, not a
  guess.
- Create branch `pipeline/<run-id>` (if absent) from `base_branch`.
- Create `status.json` (status `PLANNED`, `run_id`, `base_branch`,
  `fix_iterations: 0`, `qa_iterations: 0`).

### 0.3 Detect the test command

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-gate.sh" --detect` (once, now)
and write the printed command verbatim to `<RUN_DIR>/test-cmd`; every later
gate run reuses that exact command. Never guess it and never ask the user for
it: if detection exits non-zero, carry it as an open question for Gate 1 and
leave `test-cmd` empty until the human confirms one. (`$TEST_CMD` in the
environment remains an optional override for edge cases.)

### 0.4 Plan

Delegate to the **planner** subagent (pass `RUN_DIR`; its inputs are everything
under `<RUN_DIR>/context/`).

### 0.5 🧑 GATE 1

Present: the run id and branch you created, the planner's summary, its open
questions with recommended defaults, the detected test command (the human may
correct it - rewrite `test-cmd` accordingly), and the path to
`acceptance-criteria.md`. Spot-check any planner repo-state fact an AC now
rests on (see rules). Ask the human to answer the open questions and approve.
Record their answers into `acceptance-criteria.md` (recording human decisions
is allowed). → `APPROVED`.

## Phase A - Coding

1. Delegate to **implementer** (initial round).
2. Run the test gate. RED → increment `fix_iterations`; if > **2**, set `BLOCKED`
   and stop; else delegate to **implementer** again ("retry - read
   last-test-output.log") and repeat. GREEN → `IMPLEMENTED`, reset counter.
3. Delegate to **code-reviewer-correctness** and **code-reviewer-robustness**
   **in parallel** - both in a single message, so they run concurrently on the
   same diff. Pass each the same `base_branch` and `RUN_DIR`. They review
   disjoint areas and neither sees the other's findings; that independence is
   the point, so never relay one's output to the other. → `REVIEWED`.
4. **GATE 2 (conditional):** Combine the two verdicts into one, worst wins:
   `REQUEST_CHANGES` > `APPROVE_WITH_FIXES` > `APPROVE`. Then:
   - Combined verdict `REQUEST_CHANGES`, or ANY blocker/major finding → 🧑
     STOP. Present the combined verdict, each reviewer's own verdict and
     finding counts, and the paths to both `review-findings-correctness.md`
     and `review-findings-robustness.md` (spot-check any reviewer repo-state
     fact you are about to repeat). Human approves, or edits findings (record
     edits, attributed to the human); the human may also say "skip fix round"
     → go to Phase B.
   - Otherwise (`APPROVE`/`APPROVE_WITH_FIXES`, minor findings at most) →
     proceed WITHOUT stopping. Record in `status.json` history that the gate
     auto-passed, and report the verdicts and findings paths to the user in
     passing. If both reviewers returned zero findings, also skip the fix
     round → `READY_FOR_QA` (the gate is already green from step 2).

   → `REVIEW_APPROVED`.
5. Delegate to **fixer**, passing BOTH findings files. Finding ids are
   namespaced (`C-n` correctness, `R-n` robustness), so they never collide and
   need no merging by you. If one reviewer returned zero findings, pass only
   the other file and say which one you omitted.
6. Run the test gate (RED → fixer retry, cap 2 → `BLOCKED`). GREEN →
   `READY_FOR_QA`, reset counter.

## Phase B - QA

7. Delegate to **qa-tester** (QA iteration = `qa_iterations + 1`; increment it).
8. QA FAIL:
   - `qa_iterations` ≥ **3** → `BLOCKED`, present latest `qa-report.md`, stop.
   - else delegate to **fixer** (findings = latest `qa-report.md` iteration),
     run gate (RED → fixer retry, cap 2), return to 7.

   QA PASS → `QA_PASSED`.
9. Delegate to **test-writer**. → `TESTS_ADDED`.
10. Final test gate. RED → one fixer round then re-gate; still RED → `BLOCKED`.
    GREEN → continue.
11. Write `<RUN_DIR>/SUMMARY.md` (spot-check subagent repo-state facts before
    they become permanent lines here): ACs delivered, findings fixed/disputed,
    QA iterations, new tests, out-of-scope discoveries, anything flagged, and
    the commit list `git log <base_branch>..HEAD --oneline` so every commit is
    attributed to a phase. → `DONE`. Present the summary; suggest merge/PR but
    do not merge unless asked.

## Commits & cleanup

Subagents commit their own work (implementer, fixer, test-writer); YOU never
commit and never rewrite history. A run that ends in `BLOCKED` therefore leaves
its failed attempts as commits on the branch - an audit trail, not a mess to
hide:

- Everything stays on `pipeline/<run-id>`; nothing lands on `base_branch`
  until the human merges, so an abandoned run never pollutes the base.
  Discarding a failed attempt is just `git branch -D pipeline/<run-id>`.
- Attribution is recorded, not lost: each subagent's notes carry its commit
  hash, `status.json` history logs every transition, and `SUMMARY.md` lists
  the commits per phase.
- Never auto-clean. Squashing, reordering, or dropping commits is a human
  decision at merge time (e.g. squash-merge the PR). On `BLOCKED`, state which
  commits are salvageable and which came from the failed attempt; don't
  rewrite them yourself.
