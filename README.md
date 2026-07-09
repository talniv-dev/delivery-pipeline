# Milestone Pipeline

A [Claude Code](https://claude.com/claude-code) plugin that runs milestone
delivery as a disciplined, gated assembly line instead of one long free-form
coding session:

```
plan → acceptance criteria → implement → independent review → fix
     → hands-on QA → codify QA scenarios as tests
```

One orchestrator skill (`/milestone`) drives six single-purpose subagents, a
deterministic test gate, two human approval gates, and loop caps — with all
run state tracked on disk so an interrupted run can resume.

## Why it's built this way

- **Fresh-context subagents.** The reviewer has no memory of how the code was
  built and defaults to skepticism; the fixer "defends the codebase, not the
  implementation's ego." Each role starts cold so it can't rationalize the
  previous role's mistakes.
- **A deterministic gate is the source of truth.** Pass/fail is the exit code
  of a bundled script — never a subagent's *claim* that tests are green.
- **QA runs the software, then that work becomes permanent.** The QA role
  actually exercises each acceptance criterion; the test-writer then converts
  those exercised scenarios into automated tests, deduplicating against the
  existing suite by explicit inventory.
- **The acceptance-criteria file is the contract.** Everything downstream —
  implementation, review, QA, tests — is checked against it, and scope
  discipline ("record out-of-scope work, don't silently do it") hangs off it.
- **Lean orchestrator context.** Subagents write full artifacts under
  `milestones/<slug>/`; the orchestrator passes file *paths* forward and
  consumes only short return summaries, so a long multi-phase run doesn't blow
  its context.

## Install

Add the marketplace, then install the plugin:

```
/plugin marketplace add <this-repo-url>
/plugin install milestone-pipeline
```

The bundled test gate resolves itself via `${CLAUDE_PLUGIN_ROOT}`, so no manual
script setup is needed.

## Usage

```
/milestone <slug>
```

…and provide the **milestone plan** (a file path or pasted content). A broader
**master plan** is optional context. The plugin does not require any fixed
project layout — it normalizes whatever you provide into its own
pipeline-owned working directory.

### What happens

| Phase | Steps |
|-------|-------|
| **0 — Setup & planning** | Collect the plan(s); create the milestone branch off the branch you're on; auto-detect the test command; derive testable acceptance criteria. **🧑 Gate 1:** approve criteria + confirm the detected test command. |
| **A — Coding** | Implement against the criteria (tests written alongside) → test gate → independent code review. **🧑 Gate 2:** approve/edit review findings → fix round → test gate. |
| **B — QA** | Hands-on QA of every criterion → fix loop on failures → codify exercised scenarios as automated tests → final gate → `SUMMARY.md`. |

Two human gates (🧑) block the pipeline until you explicitly approve. Fix and QA
loops have caps; on a cap or any unresolvable state the run sets `BLOCKED`,
summarizes, and stops.

## The test command

Auto-detected **once** in Phase 0 (from repo markers — `package.json` with a
real `test` script, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`,
`pom.xml`, Gradle) and persisted to `milestones/<slug>/test-cmd`. You confirm
or correct it at Gate 1, and every later gate run reuses that exact command.
You're never asked to author a config file. `TEST_CMD` in the environment is an
optional override for edge cases.

## The base branch

The milestone branch is forked from whatever branch you're on, and that base is
recorded in `status.json`. Reviews and diffs run against the recorded base —
not a hardcoded `main` — so the pipeline works on `master`, `develop`, or a
feature branch you're stacking on.

## Commits & cleanup

Subagents commit their own work; the orchestrator never commits or rewrites
history. Everything stays on `milestone/<slug>` until *you* merge, so an
abandoned run never touches the base branch (discard a failed attempt with
`git branch -D milestone/<slug>`). Commit attribution is preserved in each
subagent's notes, in `status.json` history, and in the per-phase commit list in
`SUMMARY.md`. Squashing or reordering before a merge is always your call.

## Layout

```
milestone-pipeline/
├── .claude-plugin/plugin.json
├── skills/milestone/SKILL.md      # the /milestone orchestrator
├── agents/                        # six role subagents
│   ├── milestone-planner.md       # plans → testable acceptance criteria
│   ├── implementer.md             # builds to the criteria, tests alongside
│   ├── code-reviewer.md           # independent, read-only diff review
│   ├── fixer.md                   # applies review/QA findings, minimal diffs
│   ├── qa-tester.md               # runs the software, verifies each criterion
│   └── test-writer.md             # codifies QA scenarios as automated tests
└── scripts/test-gate.sh           # deterministic test gate
```

Per run, the pipeline writes its artifacts under `milestones/<slug>/`
(`status.json`, `acceptance-criteria.md`, `review-findings.md`, `qa-report.md`,
`SUMMARY.md`, …) — created automatically; you don't author this structure.

## License

[MIT](LICENSE) © Tal Niv
