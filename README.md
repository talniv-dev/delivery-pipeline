# Delivery Pipeline

A [Claude Code](https://claude.com/claude-code) plugin that runs a coding task
as a disciplined, gated assembly line instead of one long free-form coding
session:

```
your context -> acceptance criteria -> implement -> independent review -> fix
             -> hands-on QA -> codify QA scenarios as tests
```

One orchestrator skill (`/pipeline`) drives seven single-purpose subagents, a
deterministic test gate, two human approval gates, and loop caps, with all run
state tracked on disk so an interrupted run can resume.

## It enforces the workflow, nothing else

The plugin takes **whatever context you have, in whatever shape you have it**,
and imposes no vocabulary, template, or task size on you:

- free text after the command, long or short;
- one or more file paths (plan, ticket, PRD, design doc, notes, a directory);
- pasted content of any kind (spec, bug report, transcript, error output);
- nothing at all, when the task is already described in the conversation;
- any mix of the above.

There are **no parameters**. You don't name a slug, pick a branch, classify
your documents, or write a config file. The pipeline derives the run id, copies
your context verbatim into its own working directory, and records where each
piece came from. What it enforces is the process: a written contract you
approve before any code is written, fresh-context roles, a deterministic gate,
loop caps, and an audit trail.

## Why it's built this way

- **Fresh-context subagents.** The reviewers have no memory of how the code
  was built and default to skepticism; the fixer "defends the codebase, not the
  implementation's ego." Each role starts cold so it can't rationalize the
  previous role's mistakes.
- **Review is split in two and runs in parallel.** One reviewer judges contract
  fidelity, correctness, test quality, scope and conventions; the other judges
  security and efficiency/scalability. Each gets a full context window for a
  narrow question, so a long performance checklist can't crowd out "does this
  actually satisfy the criteria". They never see each other's findings, and
  their finding ids are namespaced (`C-n`, `R-n`) so the fixer works one
  combined list.
- **A deterministic gate is the source of truth.** Pass/fail is the exit code
  of a bundled script, never a subagent's *claim* that tests are green.
- **QA runs the software, then that work becomes permanent.** The QA role
  actually exercises each acceptance criterion; the test-writer then converts
  those exercised scenarios into automated tests, deduplicating against the
  existing suite by explicit inventory.
- **The acceptance-criteria file is the contract.** Your raw context is input
  to it, not a substitute for it. Everything downstream (implementation,
  review, QA, tests) is checked against the criteria you approved, and scope
  discipline ("record out-of-scope work, don't silently do it") hangs off it.
  Thin context doesn't become invented requirements; it becomes open questions
  at Gate 1.
- **Lean orchestrator context.** Subagents write full artifacts under
  `.pipeline/<run-id>/`; the orchestrator passes file *paths* forward and
  consumes only short return summaries, so a long multi-phase run doesn't blow
  its context.

## Install

Add the marketplace, then install the plugin:

```
/plugin marketplace add <this-repo-url>
/plugin install delivery-pipeline
```

The bundled test gate resolves itself via `${CLAUDE_PLUGIN_ROOT}`, so no manual
script setup is needed.

## Usage

```
/pipeline
```

...optionally followed by anything at all: a description, a file path, a pasted
spec. If you've already described the task in the conversation, the bare
command is enough.

### What happens

| Phase | Steps |
|-------|-------|
| **0 - Setup & planning** | Collect your context in whatever form it came; normalize it into the run directory; create the run branch off the branch you're on; auto-detect the test command; derive testable acceptance criteria. **Gate 1:** approve criteria, answer open questions, confirm the detected test command. |
| **A - Coding** | Implement against the criteria (tests written alongside) -> test gate -> two independent code reviews in parallel (correctness, robustness). **Gate 2:** approve/edit review findings -> fix round -> test gate. |
| **B - QA** | Hands-on QA of every criterion -> fix loop on failures -> codify exercised scenarios as automated tests -> final gate -> `SUMMARY.md`. |

Two human gates block the pipeline until you explicitly approve. Fix and QA
loops have caps; on a cap or any unresolvable state the run sets `BLOCKED`,
summarizes, and stops.

## The run directory

Each run lives in `.pipeline/<run-id>/`, created automatically (set
`PIPELINE_ROOT` to put it elsewhere). The run id is derived from what the work
delivers, and the branch is `pipeline/<run-id>`. Inside:

```
.pipeline/<run-id>/
├── context/               # your context, copied verbatim, plus INDEX.md (provenance)
├── status.json            # status, counters, base branch, transition history
├── test-cmd               # the detected + confirmed test command
├── acceptance-criteria.md # the contract
├── implementation-notes.md
├── review-findings-correctness.md
├── review-findings-robustness.md
├── qa-report.md
├── test-coverage-notes.md
└── SUMMARY.md
```

Resuming is automatic: an interrupted run is found by scanning
`.pipeline/*/status.json` for a status that isn't `DONE` or `BLOCKED`.

## The test command

Auto-detected **once** in Phase 0 (from repo markers: `package.json` with a
real `test` script, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`,
`pom.xml`, Gradle) and persisted to `.pipeline/<run-id>/test-cmd`. You confirm
or correct it at Gate 1, and every later gate run reuses that exact command.
You're never asked to author a config file. `TEST_CMD` in the environment is an
optional override for edge cases.

## The base branch

The run branch is forked from whatever branch you're on, and that base is
recorded in `status.json`. Reviews and diffs run against the recorded base, not
a hardcoded `main`, so the pipeline works on `master`, `develop`, or a feature
branch you're stacking on.

## Commits & cleanup

Subagents commit their own work; the orchestrator never commits or rewrites
history. Everything stays on `pipeline/<run-id>` until *you* merge, so an
abandoned run never touches the base branch (discard a failed attempt with
`git branch -D pipeline/<run-id>`). Commit attribution is preserved in each
subagent's notes, in `status.json` history, and in the per-phase commit list in
`SUMMARY.md`. Squashing or reordering before a merge is always your call.

## Layout

```
delivery-pipeline/
├── .claude-plugin/plugin.json
├── skills/pipeline/SKILL.md        # the /pipeline orchestrator
├── agents/                         # seven role subagents
│   ├── planner.md                  # any context -> testable acceptance criteria
│   ├── implementer.md              # builds to the criteria, tests alongside
│   ├── code-reviewer-correctness.md # read-only review: contract, bugs, tests, scope
│   ├── code-reviewer-robustness.md  # read-only review: security, efficiency, scale
│   ├── fixer.md                    # applies review/QA findings, minimal diffs
│   ├── qa-tester.md                # runs the software, verifies each criterion
│   └── test-writer.md              # codifies QA scenarios as automated tests
└── scripts/test-gate.sh            # deterministic test gate
```

## License

[MIT](LICENSE) © Tal Niv
