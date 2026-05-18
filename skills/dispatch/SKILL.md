---
name: dispatch
description: Orchestrates parallel implementation of `ready-for-agent` issues across a dependency graph (typically the issue set produced by /to-issues from a PRD). Spawns isolated subagents in git worktrees, each running /tdd against one issue, then `/self-review --posture auto` on the branch before PR-open (enabled by default — pass `--no-self-review` to disable). Merges in dependency order, handles failures explicitly, surfaces HITL slices and conflicts for human action. Use when the user wants to ship a PRD's worth of work, run a sweep of ready-for-agent issues, or implement multiple slices in parallel. Does NOT auto-merge by default — opens PRs and stops at the merge gate unless explicitly told otherwise. NOT for single-issue work — use /tdd directly for that.
argument-hint: "[PRD ref | issue list | filter expression | none] [--concurrency N] [--auto-merge] [--no-self-review] [--max-loops N]"
requires-skills: []
requires-config: []
---

# Dispatch

Coordinated PRD-to-merged execution across the issue dependency graph.

## Where this enters the workflow

```
grill-me → to-prd → to-issues → triage → tdd → diagnose
                                          ↑
                            /dispatch orchestrates many /tdd runs
                            across the dependency graph in parallel
```

Where `/tdd` is **surgical** (one issue at a time, brief-as-contract), `/dispatch` is **operational** — it picks up *every* `ready-for-agent` issue in a target set, builds the dependency graph, and runs parallel `/tdd` instances in git-worktree isolation, merging in correct dependency order.

**North star:** *coordinated PRD-to-merged execution* — every `ready-for-agent` issue in the graph gets implemented, tested, and merged in correct dependency order, with bounded parallelism for unblocked work and explicit failure semantics. Dependency-graph correctness > throughput. Bounded parallelism is a constraint, not a goal.

## Input shapes

`/dispatch` accepts any of:

- **PRD reference** — issue number / URL of a PRD; reads PRD body, finds child issues that reference it, treats those as the target set.
- **Issue list** — explicit numbers (`#42 #43 #44`) or comma-separated.
- **Filter expression** — passed through to the tracker's query (`label:ready-for-agent milestone:v2`).
- **No argument** — defaults to "all `ready-for-agent` issues in this repo," with a confirmation prompt before dispatching anything destructive.

In all cases, `/dispatch` only ever operates on issues that are currently **`ready-for-agent`** (the canonical role; check `docs/agents/triage-labels.md` for your repo's actual label string). Issues in other states are surfaced in the report but not dispatched.

## Process

### 1. Pre-flight

Before dispatching anything, validate:

- [ ] `docs/agents/issue-tracker.md` exists (run `/setup-workflow` if not)
- [ ] `docs/agents/triage-labels.md` exists
- [ ] Every target issue has an agent brief (per `triage/AGENT-BRIEF.md` format)
- [ ] Dependency graph is acyclic (parse "Blocked by" fields; reject cycles)
- [ ] User has push + PR permissions in the target repo
- [ ] **Concurrency cap is set by the user** (see below — always ask, never assume)

If any check fails, **stop and surface** — don't half-dispatch.

#### Asking for concurrency

The right concurrency cap depends on the user's repo: shared test database serialises everything; isolated CI runners parallelise freely; rate-limited external APIs cap concurrency at 1 or 2. **There is no safe default.** If the user passed `--concurrency N` as an argument, use that and skip the prompt. Otherwise ask:

> "How many `/tdd` subagents should I run in parallel? (Concurrency depends on your test infra: shared DB or fixed ports = 1; isolated test runners = 3–5; well-isolated repos with fast CI = higher.)"

Wait for the answer. Don't proceed with an assumed number.

#### Unattended runs (CI / no user present)

When `/dispatch` runs without a user in the loop (e.g., GitHub Actions, cron worker, scheduled agent), the prompt has no one to answer. In that case `/dispatch` requires concurrency to be set explicitly via **either**:

- The `--concurrency N` argument, or
- A `concurrency: N` line in the repo's optional `docs/agents/dispatch.md` config file.

If neither is set and no user is present, **`/dispatch` refuses to run with a clear error** pointing to both paths. Do **not** fall back to a hardcoded default — the whole point of asking is that the right value depends on facts the model doesn't have. Forcing the maintainer to set this once per repo (or once per CI invocation) preserves the contract.

### 2. Build the dependency graph

For each target issue:

- Fetch the issue (using `docs/agents/issue-tracker.md` conventions)
- Parse the "Blocked by" field (per `to-issues/SKILL.md` issue template)
- Build a directed graph: edge from blocker → dependent

Identify **leaves** (issues with no unmet blockers — ready to start now). These are the first batch.

If the graph contains:

- **Cycles** — abort and surface; cycles are a triage failure, not a dispatch failure. Send the cyclic issues back to `/triage`.
- **HITL issues** (`ready-for-human`, not `ready-for-agent`) blocking AFK issues — halt that subgraph, surface "blocked by HITL #N" for human resolution; continue independent subgraphs.

### 3. Dispatch loop

While there are unprocessed issues:

1. **Pick the next batch**: leaves of the remaining graph, capped at `concurrency` minus currently-running subagents.
2. **Spawn one subagent per batch leaf**, each:
   - In an isolated git worktree (`Agent` tool's `isolation: "worktree"` parameter)
   - With its own branch, named `dispatch/<issue-number>-<slug>`
   - Running this three-phase flow:
     - **(a) `/tdd #<issue-number>`** through step 4 (refactor) — red-green-refactor implementation, but **stop short of step 5 (close-the-loop)**. Don't push or open the PR yet.
     - **(b) `/self-review --posture auto`** on this branch — multi-persona pre-PR review. Applies agree-and-fix findings as new commits, writes `REVIEW-NOTES.md` for deliberate disagreements, surfaces unsure cases. *Skip this phase entirely if `/dispatch` was invoked with `--no-self-review`.*
     - **(c) `/tdd` step 5 (close the loop)** — push the branch, open PR, comment on issue, apply post-implementation label. PR description should include `REVIEW-NOTES.md` content if the file was created in (b).
3. **Wait for any subagent to complete** (don't wait for the whole batch — pipeline new dispatches as soon as a slot frees).
4. **On subagent completion**:
   - **Success** — subagent has pushed its branch and opened a PR. Mark issue with the post-implementation label (`in-review` per `docs/agents/triage-labels.md`, or your tracker's equivalent). Recompute leaves; dispatch newly-unblocked issues into freed concurrency slots.
   - **Failure** — subagent reports back with reason (test failed, brief ambiguous, conflict with main, out-of-scope bug, etc.). Mark issue back to `needs-triage` with a comment from `/dispatch` explaining the failure and pointing to the worktree's branch for debugging. **Continue the rest of the loop; do not abort the whole dispatch.**
5. **Repeat** until no more issues are dispatchable.

### 4. Merge gate (PR-only by default)

`/dispatch` opens PRs in dependency order but **does not auto-merge by default**.

*Why:* merging is a high-stakes operation. Branch protection rules, code review, CI signals, and merge-order semantics depend on the user's repo conventions. Auto-merging from a model is irreversibly the wrong default.

If the user has explicitly opted in (`--auto-merge` flag, or a `dispatch.auto_merge: true` line in their repo's `docs/agents/dispatch.md` if you choose to add one), `/dispatch` will:

- Wait for required CI checks to pass on each PR
- Merge in **dependency order** (blocker before dependent — never reorder)
- On merge conflict, **surface for human resolution; do not force-merge**
- On CI failure, treat as a subagent failure — mark `needs-triage` and continue

### 5. Report

When the dispatch loop ends (all targets dispatched, completed, or failed), emit a final summary:

- **Completed** — issue numbers, PR links, branch names
- **Failed** — issue numbers, reason for failure, branch link for debugging
- **HITL-blocked** — issue numbers blocked on human action, with the dependency context
- **Skipped** — issues in the target set that weren't `ready-for-agent`
- **Cycles** — if found in pre-flight (and the run aborted before the loop)

Suggest next actions: review PRs, resolve HITL slices, re-triage failed issues, re-run `/dispatch` once unblocking work is done.

## State persistence and resumability

`/dispatch` writes progress to `.scratch/dispatch-<run-id>/state.json` after each batch transition. Schema:

- Run ID, started-at timestamp, target set
- Per-issue state (`queued` / `running` / `completed` / `failed` / `hitl-blocked`)
- Worktree paths and branch names
- Subagent IDs (so an interrupted run can resume from these)

If `/dispatch` is invoked in a directory with an in-progress `state.json`, **offer to resume rather than starting fresh**. Resume re-fetches each running subagent's status and re-attaches; recomputes leaves from the live graph.

## Edge cases

- **Subagent spawns but never reports back** — timeout (default 30 min per issue, configurable via `--timeout`). Mark as failed; suggest the user inspect the worktree to recover any partial work.
- **Subagent crashes with an unclean exit** — distinct from timeout. Mark the issue `needs-triage` with a comment noting the crash, retain the worktree at its last state for inspection, and continue the dispatch loop. Don't try to re-spawn — the crash might be deterministic, and a hung retry loop is worse than a clear failure.
- **Two leaves touch the same file** — `/dispatch` doesn't try to predict conflicts; let them race. Behavior diverges by mode:
   - **PR-only mode (default)** — both subagents push their branches and open PRs cleanly; the conflict surfaces on the second PR for the human reviewer to resolve. `/dispatch`'s job is done once both PRs exist.
   - **Auto-merge mode** (`--auto-merge`) — the second-merging PR hits a merge conflict; `/dispatch` marks that issue `needs-triage`, surfaces the conflict, and continues with the rest of the graph. Never force-merges.
- **Shared CI infrastructure** (one test database, fixed ports) — concurrency cap is your safety knob. If your test infra serialises, run `--concurrency 1`.
- **Subagent runs into out-of-scope bug** — same as `/tdd`'s edge case: subagent stops, comments on the issue, escalates to `/diagnose`. `/dispatch` marks the issue failed and continues.
- **Dependency graph drift mid-run** — issues can be retriaged or relabeled while `/dispatch` is running. Re-fetch each target's state on every batch transition; if a target has been moved out of `ready-for-agent`, drop it from the queue and note in the report.
- **Brief found stale during implementation** — subagent surfaces it (per `/tdd`'s "brief contradicts existing code" edge case). `/dispatch` marks `needs-triage`; doesn't try to update the brief.
- **`/self-review` finds an issue that fails to fix cleanly** — same as `/self-review`'s edge case: that specific fix is aborted (test failed after applying it), surfaced; remaining `/self-review` findings continue. If `/self-review` can't reach a clean state, the subagent still proceeds to PR-open with whatever fixes did apply, and `REVIEW-NOTES.md` records the un-applied finding for the human reviewer. Subagent reports back as success (PR is open, partial review state noted in PR description).
- **`--no-self-review` was passed** — subagents skip phase (b) entirely; flow is just `/tdd` → push → PR. PR descriptions don't include `REVIEW-NOTES.md` (since none was generated).

## Anti-patterns

- **Don't dispatch without `/setup-workflow` and `/triage` having run.** Without an agent brief, `/tdd` has no contract. Pre-flight catches this.
- **Don't use `/dispatch` for single-issue work.** `/tdd #42` is the right tool. Orchestration overhead is wasted.
- **Don't auto-merge unless the user has explicitly opted in AND has branch protection + CI.** PR-open is the safe default. Never override silently.
- **Don't treat HITL slices as failures.** They're surfaced for humans, not retried by the dispatcher.
- **Don't try to predict file conflicts before dispatch.** Let them race; recover reactively. Predicting conflict probability from diffs is speculative complexity that earns very little.

## Worked example

> **User:** `/dispatch milestone:v2`
>
> **Pre-flight passes.** Target set: 8 issues with `ready-for-agent` and `milestone:v2`. Dependency graph: #42 blocks #43 and #44; #45 is independent; #46 blocks #47 (also blocked by #43); #48 blocks #49.
>
> **Claude:** "How many `/tdd` subagents should I run in parallel? (Depends on your test infra...)"
> **User:** "3 — we have isolated test runners but a shared staging DB."
>
> **Initial leaves:** #42, #45, #46, #48. Concurrency 3, so dispatch #42, #45, #46. #48 queued.
>
> **#45 completes first** (smallest slice). PR opened. Dispatch #48 from queue.
> **#42 completes.** Recompute leaves: #43 and #44 now unblocked. Dispatch #43; #44 queued.
> **#46 completes.** Recompute: #47 still blocked by #43. Dispatch #44 from queue.
> **#48 times out** at 30 min with no report. Mark #48 `needs-triage` with `/dispatch`'s comment ("subagent timed out — branch `dispatch/48-...` retained at `<worktree-path>` for inspection"). #49 was blocked only by #48; surface as blocked-on-failed-blocker.
> **#43 fails** (test couldn't be made to fail in RED phase — brief ambiguous about expected behavior). Mark #43 `needs-triage`. Recompute: #47 already blocked by #43, surface as HITL-blocked.
> **#44 completes.** No more leaves.
>
> **Final report:**
> - **Completed:** #42, #44, #45, #46 — 4 PRs open in dependency order
> - **Failed:** #43 (brief ambiguous; back to `/triage`), #48 (timed out; inspect worktree)
> - **HITL-blocked:** #47 (blocked on #43 re-triage), #49 (blocked on #48 re-triage)
> - **Suggested next actions:** review the 4 open PRs; re-triage #43 and #48; once their replacements ship, re-run `/dispatch` on the unblocked dependents.
