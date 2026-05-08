---
name: post-merge-cleanup
description: Run the post-merge cleanup checklist for a PR the user has just merged — close the originating issue, delete the merged branch (local + remote), strip "remove once #N merges" TODOs and temp instrumentation, draft a CHANGELOG entry, schedule any rollout/soak follow-ups, and surface the judgment-call cleanups (feature-flag removal, stakeholder notification, CONTEXT.md updates) for the human. Triggered when the user signals merge — "the PR merged", "I merged it", "we shipped #142" — or when the agent detects via the configured tracker (per `docs/agents/issue-tracker.md`) that a PR it has context for has flipped to merged. Reads posture from `docs/agents/post-merge-cleanup.md` (`auto` / `draft` / `comment-only`). NOT for cleanup that requires re-implementation (use `/tdd` on a follow-up issue), NOT for pre-merge review (use `/self-review`), and NOT for inbound review-comment resolution (use `/resolve-reviews`) — this skill assumes the merge has already happened.
argument-hint: "[optional: PR ref or URL, defaults to last-touched PR] [optional: --posture auto|draft|comment-only] [optional: --skip <task>]"
---

# Post-Merge Cleanup

Closes the loop on a PR after the human has merged it. Symmetric back-bookend to `/self-review` (front-bookend) — the work is small, mechanical, and easy to forget; that's exactly why an agent should own it.

## Where this enters the workflow

```
/tdd → /self-review → PR opens → /resolve-reviews → human merges → /post-merge-cleanup (NEW)
                                                                          ↓
                                                                  next feature: /grill-me
```

Sits **after** merge. Not in the upstream pipeline (`grill-me → to-prd → to-issues → triage → tdd`); applied per-PR after the merge button is pressed.

**North star:** *the agent that built the PR is the same agent that cleans up after it.* The user should never have to say "now clean up" — when they signal merge, cleanup runs. Anything that requires human judgment (feature-flag removal, stakeholder notification, CONTEXT.md updates) is surfaced cleanly, not silently skipped.

This is **load-bearing** — session memory is what lets the agent strip only its own debug logs, close only its own sub-issues, and find only its own TODOs. Run from a fresh session and tasks that depend on session memory (M4 instrumentation removal in particular) degrade to best-effort PR-metadata inference; the report flags this, but you should know going in. The skill is designed for the warm-context case; the cold-context case is a fallback, not a happy path.

*Why agent-owned, not human-owned:* the agent has the full implementation context — which TODOs were tagged "remove once #N merges," which temp `console.log`s were added during diagnose, which sub-issues were spawned, which acceptance criteria the PR closed. Reconstructing this from PR metadata alone is lossy. The human knows the strategic context (flag rollout pace, who to notify); the agent knows the mechanical trail. Split the work along that line.

## Process

### 1. Pre-flight

Before doing anything:

- [ ] **PR is actually merged.** Use `docs/agents/issue-tracker.md` conventions to confirm PR state (e.g. `gh pr view <ref> --json state,mergedAt` returning `MERGED` for GitHub; equivalent `glab mr view` flags for GitLab; per-tracker convention for "Other"). If not merged, refuse — this skill doesn't merge for you.
- [ ] **`docs/agents/issue-tracker.md` exists.** Need it to know how to close issues / delete remote branches in this repo's tracker. If absent, run `/setup-workflow` first.
- [ ] **Posture is set** — via `docs/agents/post-merge-cleanup.md` (`posture: auto|draft|comment-only`), `--posture <name>` argument, or asked at start.
- [ ] **The originating issue is identifiable.** Either from the PR body (`Closes #N`, `Fixes #N`) or from the agent's session context. If neither, ask the user once: "Which issue did this PR close?"

#### Asking for posture

Same three-way choice as `/self-review` and `/resolve-reviews`. If the junior dev has used either of those, this dialogue should feel identical.

> "How should I handle the cleanup tasks?
>
> - **auto** — run all mechanical tasks (close issue, delete branch, strip TODOs, remove temp instrumentation, draft CHANGELOG, schedule follow-ups), commit any code changes as a `chore: post-merge cleanup` commit on `main`. Surface judgment-call tasks for your decision after.
> - **draft** — show me the full proposed cleanup (issue close action, files to change, follow-ups to schedule, judgment calls to surface) before any of it executes. One confirmation for the whole batch.
> - **comment-only** — produce a checklist to stdout and `.scratch/post-merge-cleanup/<pr>.md`. Don't close anything, don't change any files, don't schedule anything."

Wait for the answer. Don't proceed with an assumed posture.

#### When to pick which posture

The same three-way model is shared by `/self-review` (pre-PR front-bookend) and `/resolve-reviews` (inbound review responses) — picking the same posture across all three skills gives you predictable behavior across the whole PR lifecycle. Not arbitrary listings; each fits a real situation:

- **`auto`** — when the action is reversible, the safety net is in place (branch protection, CI, or your own session memory of what was done), and you trust this agent to act without per-task confirmation. Right for routine cleanups where you've used the skill before, the PR is ordinary, and there's nothing surprising in the diff. *Why it's safe here:* the cleanup is small, the cleanup commit shows up in `main`'s history with a clear `chore: post-merge cleanup for #<PR>` message, and a bad cleanup is reverted in seconds.
- **`draft`** — when you're learning the skill, when the cleanup touches something high-blast-radius (CHANGELOG entries that ship in release notes, scheduled future agents that will run unattended, multiple sub-issue closes), or when you want a human eye on the full ledger before any of it commits. *The default for new users.* Cost: one round of confirmation per merged PR. Benefit: nothing surprising lands without your sign-off.
- **`comment-only`** — when you want the assessment but plan to action manually, when running unattended in an audit-trail context where commits aren't allowed, or when direct-push to `main` is blocked and you'd rather treat the cleanup as a checklist than a PR. *Why distinct from `draft`:* `draft` still commits on confirmation; `comment-only` never commits.

If you're undecided, pick `draft`. The cost of one confirmation prompt is much smaller than the cost of an unwanted commit on `main`.

#### Unattended runs

In CI / non-interactive contexts, posture must be set via `--posture` or `docs/agents/post-merge-cleanup.md`. If neither is set and no user is present, refuse to run.

### 2. Gather context

Read once, cache for the rest of the run:

- The PR diff (per `docs/agents/issue-tracker.md` conventions — `gh pr diff <ref>` for GitHub, `glab mr diff` for GitLab, equivalent for "Other")
- The PR body and commit log
- The originating issue's body and comments (gives the agent brief / acceptance criteria)
- The agent's own session memory if available (which `console.log`s did *I* add during diagnose? which sub-issues did *I* spawn?)
- `docs/agents/triage-labels.md` (need the label string for "done" / closed states)
- `CONTEXT.md` and recent ADRs (so we can detect new domain terms or decisions worth recording)
- `docs/agents/post-merge-cleanup.md` if it has skip-list / project-specific tasks
- `docs/agents/prior-rejected-suggestions.md` if it exists — the accumulated-rejection ledger shared with `/self-review` and `/resolve-reviews`. Judgment-column items the user has already declined upstream (e.g. a `CONTEXT.md` candidate they said no to during self-review, or a debug-instrumentation pattern the team chose to keep) should not be re-surfaced here.

### 3. Build the cleanup ledger

Two columns: **mechanical (agent-owned)** and **judgment (surface to human)**.

#### Mechanical — agent runs these

| # | Task | How to detect |
|---|------|--------------|
| M1 | Close the originating issue (or move to `done` per `triage-labels.md`) | Issue ref from PR body or session |
| M2 | Delete the merged branch (local + remote) | `git branch -d <branch>` + `git push origin --delete <branch>` |
| M3 | Strip TODO comments tagged `remove once #N merges` (or `TODO(#N)`) where `N` matches the merged PR or its closed issues | `grep -rn` for the issue/PR numbers in TODO/FIXME/XXX comments |
| M4 | Remove temp instrumentation added during this work | Compare diff vs `main` for `console.log`, `print()`, `pdb.set_trace()`, `.skip` / `.only`, debug-only branches — but only ones the agent's session memory confirms it added; don't strip pre-existing instrumentation |
| M5 | Draft a CHANGELOG entry (or release-notes equivalent) | PR title + body + closed issues; commit as part of the cleanup commit |
| M6 | Close sub-issues spawned during the work | Session memory or issue-tracker linked-issue queries |
| M7 | Schedule follow-up agents via `/schedule` | TODOs of the form "remove once X" / "soak window: check after N days" / "ramp flag in 2 weeks" — propose a routine, surface for confirmation if posture is `draft` |

#### Judgment — surface to human

| # | Task | Why human |
|---|------|----------|
| J1 | Feature-flag removal / ramping | Rollout pace is a strategic call (canary % → 10% → 100%). Agent shouldn't decide. |
| J2 | Stakeholder notification (Slack, email, comment "shipped") | Audience and tone vary by team and topic. Agent shouldn't post to chat without explicit per-message authorization. |
| J3 | `CONTEXT.md` updates if new domain terms entered the codebase during this work | Glossary entries are editorial — phrasing matters and the canonical form is the human's call. Agent surfaces *that* an entry should exist; human writes the entry (or confirms a draft). |
| J4 | ADR creation if a hard-to-reverse decision was made during implementation | Same — agent flags the candidate, human decides whether it earns an ADR (per the three-part test: hard to reverse + surprising + real trade-off). |
| J5 | `REVIEW-NOTES.md` from `/self-review` exists at repo root — keep on `main` (audit trail) or delete (clean main) | This is the call `/self-review` deferred at merge-time (per its own SKILL.md guidance). Don't auto-decide — the answer depends on whether the team treats deliberate-decision records as ship-with-main or strip-before-merge artifacts. If the user says delete, do it as part of the cleanup commit; if keep, no action needed. |

If posture is `comment-only`, both columns become a checklist with no action taken. If `draft`, both columns are shown together for confirmation. If `auto`, the mechanical column executes immediately and the judgment column surfaces after.

### 4. Detect re-runs (idempotency)

Before executing any task, detect whether cleanup has already run on this PR. Re-runs are common — network failure mid-`auto`, accidental re-trigger, user retries after a partial failure — and should short-circuit per task, not refuse the whole skill.

**Detection signals (vary by posture):**

- **`auto`** posture: look for a commit on `main` matching `chore: post-merge cleanup for #<PR>` (the canonical commit message). Its presence means the file changes (M3, M4, M5) already landed.
- **`comment-only`** posture: look for `.scratch/post-merge-cleanup/<pr>.md`. Its presence means the ledger was produced; no actions were taken so M1/M2/M6/M7 may or may not have happened manually.
- **`draft`** posture: no automatic sentinel (the user confirms or aborts each batch). Rely on per-task checks below.

**Per-task semantics on re-run** — each task is independent, each checks its own done-state and skips silently if work is already complete:

- **M1** (close issue): if the issue is already closed, skip silently — don't re-comment.
- **M2** (delete branch): if the branch is gone (locally and/or on remote), skip silently — auto-delete-on-merge would have done this; we shouldn't fail.
- **M3** (strip TODOs): regex match returns zero, skip silently — the work is done.
- **M4** (remove instrumentation): same — zero matches means done.
- **M5** (CHANGELOG): if an entry referencing this PR already exists, skip silently — don't double-write.
- **M6** (close sub-issues): each sub-issue checked independently; skip already-closed ones.
- **M7** (schedule follow-ups): re-runs surface the same `/schedule` proposals; let the user say "already scheduled" or re-confirm. Don't auto-skip without confirmation — scheduled routines can drift between runs and the user may want to refresh.

If a re-run signal fires, surface it before executing: *"This PR was already cleaned up at &lt;timestamp&gt; (`auto` cleanup commit `&lt;hash&gt;`). Per-task: M1 done, M2 done, M3 done, M4 partial (1 console.log still present in src/foo.ts:45), M5 done, M6 done, M7 outstanding. Continue?"* Let the user choose continue (process the per-task gaps) or abort.

### 5. Act per posture

#### `auto` posture

Execute the mechanical column in order. Group all file changes (M3, M4, M5) into one `chore: post-merge cleanup for #<PR>` commit on `main` (or whatever the default branch is). Push that commit. Then:

- M1: close the issue with a one-line comment linking the merged PR
- M2: delete branches
- M6: close sub-issues with a comment naming the parent PR
- M7: surface the proposed `/schedule` routines for one final confirm — *don't* schedule unattended; scheduling sends future agents to do work, and the user should explicitly green-light that even in `auto`

After the mechanical column finishes, surface the judgment column to the user:

> "Mechanical cleanup done (closed #42, deleted `feature/auth-refactor`, stripped 3 TODOs, removed 2 debug logs, drafted CHANGELOG entry, closed sub-issue #45). Now your call:
>
> - **J1** This work was gated behind `feature.new_auth` flag. Ramp / remove?
> - **J3** New term `SessionToken` introduced — should I draft a CONTEXT.md entry for review?
> - **M7 candidates** — `/schedule` proposed: remove flag in 2 weeks; check error-rate metric in 3 days. Confirm?"

The user answers each; act on confirmations.

#### `draft` posture

Build the full ledger (mechanical + judgment together). Show as a unified preview:

```
Will close: issue #42 (with comment)
Will delete: branch feature/auth-refactor (local + remote)
Will commit on main (chore: post-merge cleanup for #142):
  - Strip 3 TODOs in: src/auth/login.ts (line 45), src/auth/session.ts (line 87, 102)
  - Remove 2 console.log in: src/auth/session.ts (line 110, 115)
  - Add CHANGELOG.md entry: "Auth refactor (#142)"
Will close sub-issue: #45
Will propose /schedule:
  - one-time, +14 days: open PR removing feature.new_auth flag
  - one-time, +3 days: query error-rate dashboard, comment on issue

Will surface for your decision:
  - J1: feature flag rollout strategy (ramp / remove / leave)
  - J3: new term `SessionToken` — draft CONTEXT.md entry?

Confirm batch? [yes / no / let me edit]
```

On `yes`: execute mechanical, then surface judgment-column items one-by-one. On `no`: surface the ledger as a markdown checklist for manual action.

#### `comment-only` posture

Write the full ledger to `.scratch/post-merge-cleanup/<pr>.md` and stdout. No closes, no commits, no schedules. The human acts manually.

### 6. Done

Tell the user:

1. **What ran** — count of mechanical tasks executed, with the cleanup-commit short-hash if applicable
2. **What's still on you** — list of judgment-column items still awaiting decision (J1 / J2 / J3 / J4 etc.), with the framing already drafted so the user can answer with one or two words
3. **What's scheduled** — list of `/schedule` routines created (if any), with their fire-times
4. **Suggested next** — if the user has more PRDs queued, mention `/grill-me` on the next plan; if not, no suggestion (don't manufacture work)

## Edge cases

- **PR didn't actually close an issue** (no `Closes #N` in body) — skip M1; surface to user: "This PR has no closing reference. Should I close issue #X manually, or was this not issue-tracked?"
- **Branch already deleted** (auto-delete-on-merge enabled in the repo) — skip M2 silently; not a failure.
- **TODOs reference an issue that wasn't actually closed by this PR** — leave them alone; only strip TODOs whose referenced issue is now closed/merged.
- **Temp instrumentation that the session memory doesn't account for** — surface the candidates to the user; don't auto-strip. Risk of removing instrumentation a teammate added on a different commit.
- **CHANGELOG.md doesn't exist in the repo** — skip M5 silently; surface as judgment-column item: "Repo has no CHANGELOG.md. Want me to scaffold one?"
- **CHANGELOG.md exists but uses a non-standard format** (Keep-a-Changelog, custom, generated) — propose an entry matching the existing format; if format is unclear, surface for confirmation rather than guessing.
- **Sub-issues weren't tracked** — skip M6.
- **Multiple PRs merged in quick succession** — run cleanup per PR; don't batch (each has its own context, each closes different issues). Concretely: if the user signals "I merged #141 and #142," run Process steps 1–5 per PR sequentially in merge-time order. Each PR gets its own ledger, its own cleanup commit on `main`, and its own confirm-batch prompt under `draft` posture. The user sees N reports, not one combined report — combining would conflate two unrelated cleanups and make re-run detection ambiguous.
- **`/schedule` skill not installed in this Claude Code config** — skip M7 silently; surface the proposed follow-ups as a checklist for the user to action manually.
- **Push to `main` blocked by branch protection** — abort the cleanup commit and surface: "Couldn't push cleanup commit to `main` (branch protection). Open a PR for the cleanup, or run with `--posture comment-only`."
- **Cleanup commit fails CI on `main`** — surface immediately; don't keep going. The cleanup itself shouldn't break the build.
- **Agent's session has no memory of the work** (e.g., user invokes `/post-merge-cleanup` from a fresh session) — fall back to PR-metadata-only inference. **M4 is downgraded from mechanical to judgment in this case** — surface candidates for confirmation, never auto-strip, regardless of posture. (The risk of removing instrumentation a teammate added on a different commit is too high without session memory to anchor what *this agent* added.) Flag in the report that the run was cold-context and which tasks degraded.
- **PR was reverted shortly after merge** — abort cleanup; surface: "PR #N was reverted; cleanup is moot. Re-run after the next merge."

## Anti-patterns

- **Don't post stakeholder notifications without explicit per-message authorization.** Even in `auto` posture, J2 is judgment, not mechanical. The user must approve the destination AND the message.
- **Don't strip instrumentation the agent didn't add.** Session memory is the source of truth; absent that, surface candidates rather than acting.
- **Don't commit cleanup directly to `main` if the repo uses PR-only-merges.** Detect branch protection up front; abort cleanly and route through a PR if needed.
- **Don't schedule routines unattended.** M7 always surfaces for confirmation, even in `auto` — scheduling future agents is an action with consequences and deserves a green-light.
- **Don't auto-write CONTEXT.md or ADRs.** These are editorial; agent flags the candidate, human writes it.
- **Don't run cleanup on a PR that's still open.** Pre-flight catches this; treat the failure clearly.
- **Don't run cleanup twice on the same PR.** If `.scratch/post-merge-cleanup/<pr>.md` already exists from an earlier run, surface and ask whether to re-run idempotently or skip.
- **Don't rubber-stamp judgment items.** Surface each one with a real trade-off framing, not "should I do this? y/n".

## Worked example

> **User:** *"merged #142"*
>
> **Pre-flight:** posture in `docs/agents/post-merge-cleanup.md` is `draft`. PR #142 confirmed `MERGED`. Closes issue #42. Originating session is alive (this same agent ran `/tdd` on #42 a few hours ago).
>
> **Gather context:** PR diff, issue body, agent's session memory. Session memory: I added 2 `console.log` calls during diagnose (`session.ts:110` and `session.ts:115`); I spawned sub-issue #45 ("add session-rotation tests") which is now done; I tagged 3 TODOs `// TODO(#142): remove once auth refactor merges`. CHANGELOG.md exists in Keep-a-Changelog format.
>
> **Build ledger:**
>
> - **Mechanical:** close #42, delete `feature/auth-refactor`, strip 3 TODOs, remove 2 console.logs, draft CHANGELOG entry, close #45.
> - **Judgment:** feature flag `feature.new_auth` was added during work — needs rollout decision. New domain term `SessionToken` appears in the diff but not yet in `CONTEXT.md`. ADR candidate: chose JWT over opaque tokens (recorded in PR body but no ADR yet — three-part test passes: hard to reverse, surprising without context, real trade-off).
> - **Scheduled follow-ups:** propose one-time agent in 14d to remove `feature.new_auth` flag; propose one-time agent in 3d to check error-rate dashboard and post on PR.
>
> **Draft view:**
>
> ```
> Will close: issue #42, sub-issue #45 (with comments)
> Will delete: branch feature/auth-refactor (local + remote)
> Will commit on main (chore: post-merge cleanup for #142):
>   - src/auth/login.ts: strip TODO at line 45
>   - src/auth/session.ts: strip TODOs at lines 87, 102
>   - src/auth/session.ts: remove console.log at lines 110, 115
>   - CHANGELOG.md: add "Auth refactor (#142)" under [Unreleased]
> Will propose to /schedule:
>   - +14d, one-time: open PR removing feature.new_auth flag
>   - +3d,  one-time: check error-rate dashboard for /auth/* routes, comment on PR #142
>
> Will surface for your decision:
>   - J1 (flag): feature.new_auth currently at 0%. Ramp to 10%, 100%, or leave?
>   - J3 (CONTEXT.md): new term `SessionToken` — draft entry?
>   - J4 (ADR): JWT-over-opaque-tokens decision — draft ADR?
>
> Confirm batch? [yes / no / edit]
> ```
>
> **User:** *"yes; J1 ramp to 10% Monday, J3 yes draft, J4 yes draft"*
>
> **Apply:** close #42 + #45 with linking comments. Delete branch. Commit cleanup changes on `main` and push (branch protection allows direct push for `chore:` commits per repo config). Schedule both routines (after one final confirm). Draft `CONTEXT.md` entry for `SessionToken` and ADR for JWT-over-opaque, surface both for human edit.
>
> **Final report:**
>
> - Closed: #42, #45 (with comments linking PR #142)
> - Deleted: `feature/auth-refactor` (local + remote)
> - 1 commit on `main`: `chore: post-merge cleanup for #142` (`a3f7c2e`)
> - Scheduled: 2 routines (+14d flag-removal PR, +3d error-rate check)
> - Surfaced for your edit: `CONTEXT.md` entry draft for `SessionToken`, ADR draft for JWT-over-opaque-tokens
> - Open follow-up: ramp `feature.new_auth` to 10% Monday (J1) — that's on you

## When to use `/post-merge-cleanup`

- Right after merging a PR an agent built (the canonical case)
- Right after merging an inbound PR that an agent reviewed via `/resolve-reviews`
- After `/dispatch` has merged a batch — invoke once per merged PR
- When a teammate's PR you reviewed is merged and you want to chase the rollout / cleanup follow-ups

## When NOT to use `/post-merge-cleanup`

- Before merge — pre-flight refuses
- For PRs the agent has zero context for (no session memory, no clear closing-issue link) — possible but lossy; surface the limitation
- For trivial PRs (typo fixes, dependency bumps) where there's nothing to clean up — overhead exceeds value
