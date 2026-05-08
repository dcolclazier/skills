---
name: self-review
description: Run a multi-persona pre-PR self-review on the current branch (or specified branch), classify each finding into agree-and-fix / disagree-and-justify / unsure-and-ask-user, then act per a configured posture. Agree-and-fix applies the fix as a new commit on the branch. Disagree-and-justify records the deliberate decision in `REVIEW-NOTES.md` (committed alongside) explaining why we're shipping despite the suggestion. Unsure surfaces to the user. Reuses `/score`'s `pre-pr` rubric (multi-persona review combining `pr` + `staged-commit` lenses). Use when the user wants to self-review their own work before opening a PR, says "review this branch before I push", "self-review", "audit before PR", or wants a multi-persona pass on local changes. NOT for reviewing already-open PRs (use `/resolve-reviews` for inbound, `/score --rubric pr` for outbound assessment without action).
argument-hint: "[optional: branch name, defaults to current] [optional: --posture auto|draft|comment-only] [optional: --filter <regex>]"
---

# Self-Review

Pre-PR multi-persona self-review with a fix-locally action layer.

## Where this enters the workflow

```
/tdd implements → tests pass → branch ready
                                  ↓
                           /self-review (NEW)
                                  ↓
                           user opens PR (cleaner)
                                  ↓
                         (Copilot / human reviews)
                                  ↓
                           /resolve-reviews
                                  ↓
                              merge
```

Sits between implementation completion and PR-open. Symmetric twin of `/resolve-reviews`:

| | direction | trigger | action layer |
|---|---|---|---|
| **`/self-review`** | outbound (your own work) | **before** PR open | apply agree-fixes locally; record disagrees in `REVIEW-NOTES.md`; surface unsure |
| **`/resolve-reviews`** | inbound (others' reviews) | **after** PR open | commit + push + thread comment + resolve thread on agree; denial comment on disagree; surface unsure |

**North star:** *lossless self-review-to-PR-open.* Every finding ends in either (a) a fix applied to the local branch + a commit message acknowledging the fix, or (b) a deliberate decision recorded in `REVIEW-NOTES.md` (committed alongside) explaining why we're shipping despite the suggestion. PR opens only after every finding has resolved into one of those two states.

## Process

### 1. Pre-flight

- [ ] Branch is a working branch (default: current). Refuse if `main` / `master`.
- [ ] Branch has commits not on `main`/`master`. Otherwise nothing to review; exit cleanly.
- [ ] Working tree is clean (no uncommitted changes) for `auto`/`draft`. `comment-only` is allowed dirty.
- [ ] **Posture is set** — via `docs/agents/self-review.md` (`posture: auto|draft|comment-only`), `--posture <name>` argument, or asked at start.

#### Asking for posture

If posture isn't set, ask:

> "How should I handle agree-and-fix actions?
>
> - **auto** — apply each fix as a new commit on the branch + write `REVIEW-NOTES.md` for disagreed findings + commit it. No per-finding confirmation.
> - **draft** — show you the full proposed diff (all fixes + `REVIEW-NOTES.md`) before any commit. One confirmation for the whole batch.
> - **comment-only** — never commit; produce a ledger of 'I would apply these fixes' to stdout and `.scratch/self-review/<branch>.md`."

Wait for the answer. Don't proceed with an assumed posture.

#### When to pick which posture

The same three-way model is shared by `/resolve-reviews` (inbound review responses) and `/post-merge-cleanup` (back-bookend) — picking the same posture across all three skills gives you predictable behavior across the whole PR lifecycle. Each posture fits a real situation, not a personal preference:

- **`auto`** — when your test suite is reliable, the diff is on a feature branch (not `main`), and you trust this skill to apply clear-cut fixes (security improvements, missing tests, debug-artifact removal) without per-fix confirmation. Right when you've used the skill before, the branch is your work, and the cost of a bad fix is "revert one commit." *Why it's safe here:* fixes commit on the feature branch (never `main`), each fix runs the test suite first and aborts on red, and the PR reviewer sees granular history before merge.
- **`draft`** — when you're learning the skill, when the branch touches something high-blast-radius (auth, payments, schema migrations), or when you want a single batch view before any commits land. *The default for new users.* Cost: one confirmation per branch. Benefit: you see all fixes + `REVIEW-NOTES.md` in one view before any of it commits.
- **`comment-only`** — when you want the assessment but plan to action manually, when running unattended in an audit-trail context where commits aren't allowed, or when the working tree is dirty and you can't move it. *Why distinct from `draft`:* `draft` still commits on confirmation; `comment-only` never commits. Useful for "I want a second opinion but I'll do the typing."

If you're undecided, pick `draft`. The cost of one confirmation prompt is much smaller than the cost of an unwanted commit, even on a feature branch.

#### Unattended runs

In CI / non-interactive contexts, posture must be set via `--posture` or `docs/agents/self-review.md`. If neither is set and no user is present, refuse to run.

### 2. Run multi-persona review (delegate to `/score`)

Invoke `/score --rubric pre-pr <branch>` internally. The `pre-pr` rubric (in `/score`'s rubric library) combines `pr` and `staged-commit` lenses with weights tuned for pre-publication review (security, correctness, test-coverage, readability, scope-cohesion, backwards-compat, secrets, debug-artifacts, diff-cohesion).

`/score` runs the multi-persona dispatch + dialogue + synthesis. Returns a structured ledger with action items.

*Why delegate to `/score`:* the multi-persona dispatch + dialogue + synthesis machinery is the same. `/self-review`'s value-add is the **action layer** — fix locally, record deliberate decisions, never just produce a ledger.

### 3. Classify findings (3 buckets)

For each action item from the ledger, classify per project conventions (CONTEXT.md, ADRs, existing patterns, prior rejected suggestions in `docs/agents/prior-rejected-suggestions.md`):

- **agree-and-fix** — applies. Default for clear-cut wins (security improvement, real bug, missing test, follows conventions).
- **disagree-and-justify** — finding contradicts a grounding source. Record the decision with citation.
- **unsure-and-ask-user** — legitimate trade-off the grounding sources don't resolve. Surface and wait.

Same classification logic as `/resolve-reviews`. The four grounding sources are the source of truth.

*Why grounded disagreements matter:* same reasoning as `/resolve-reviews` — a `REVIEW-NOTES.md` entry that just says "ignored this" is worse than no entry. Citing the source ("contradicts ADR-0007", "matches prior rejection #88") lets the PR reviewer either accept the citation or argue with the source.

### 4. Act per posture

#### `auto` posture

For each finding, in order:

- **agree-and-fix** — apply the fix to the working tree → run tests → if green: `git commit -m "Self-review: <persona> — <one-line description>"`. If tests fail: abort that fix, surface to user, continue to next finding.
- **disagree-and-justify** — append to `REVIEW-NOTES.md` (create at repo root if not exists):

  ```markdown
  ## <persona name> — <ISO date>

  **Critique:** <quote of what the persona suggested>
  **Decision:** ship despite suggestion
  **Reasoning:** contradicts <ADR-NNNN | CONTEXT.md term | pattern | prior rejection> — <one-line explanation>
  ```

- **unsure-and-ask-user** — surface trade-off; wait for decision; act per their answer.

After all findings: `git commit REVIEW-NOTES.md -m "Self-review notes: <N> deliberate decisions recorded"` if any disagree entries were added.

**Don't push.** Pushing is the user's call when opening PR.

#### `draft` posture

- Apply all agree-and-fix changes to working tree (no commits yet). Run tests; abort any fix that reds.
- Stage `REVIEW-NOTES.md` with disagree entries (no commit).
- Show user a unified diff (per-file, grouped by which finding drove each change).
- Surface unsure cases inline in the same view.
- Ask once: *"Confirm batch? [yes / no / let me edit]"*
- **On yes:** commit each fix as a separate commit (granular history) + commit `REVIEW-NOTES.md`.
- **On no:** revert working tree changes; user can rerun.

#### `comment-only` posture

- Produce a markdown ledger to stdout AND `.scratch/self-review/<branch>.md`:
  - **agree-and-fix**: "<persona> suggests <fix>; rationale: <why>; apply manually."
  - **disagree-and-justify**: "<persona> suggested <X>; deliberate ship-anyway: <reasoning>."
  - **unsure-and-ask-user**: "Trade-off: <framing>. Your call."
- Never commit, never modify files.

### 5. Done

Tell the user:

1. **What changed** — list of new commits (one per fix + the `REVIEW-NOTES.md` commit, if any).
2. **What's recorded** — counts: agreed-and-fixed, disagreed-with-justification, unsure-resolved-with-user, unsure-deferred.
3. **Suggested next** — review the new commits before opening PR. Consider including `REVIEW-NOTES.md` content in your PR description and deleting the file before merge if you'd rather keep `main` clean. Then open the PR.

## Edge cases

- **Branch is `main`/`master`** — refuse; self-review is for feature branches.
- **No commits vs `main`** — exit cleanly; nothing to review.
- **Working tree dirty** — refuse in `auto`/`draft` (would mix uncommitted user work with self-review fixes); allow in `comment-only` since no commits are made.
- **A fix introduces a test failure** — abort that specific fix, surface to user with the test output, continue with remaining findings.
- **`REVIEW-NOTES.md` already exists from a prior `/self-review` run on this branch** — append new entries with date markers; don't overwrite history.
- **Branch has merge conflicts vs `main`** — refuse; tell user to rebase first.
- **`/score` returns no actionable findings** — emit "Branch passes self-review. No fixes needed." Skip commit step.
- **User invokes on a branch with `REVIEW-NOTES.md` from a different feature** — the file is branch-local; treat as continuing the same review session.

## Anti-patterns

- **Don't apply fixes that fail tests.** Run tests after each fix; abort that fix on red.
- **Don't open the PR yourself.** That's the user's call. `/self-review` ends with branch ready, not PR open.
- **Don't push the branch.** Pushing is part of PR-open, not self-review.
- **Don't relitigate prior rejections.** `prior-rejected-suggestions.md` entries auto-apply as disagree without re-engaging dialogue.
- **Don't fix what the linter handles.** Skip formatting nits handled by Prettier/Black/etc; focus on substantive findings.
- **Don't squash fix commits.** Each fix is a separate commit so PR reviewers can see the granular self-review history. The user can squash later if they prefer.
- **Don't write `REVIEW-NOTES.md` for every persona by default.** Only disagree-and-justify findings land there. Agree-and-fix decisions live in commit messages.

## Worked example

> **User:** `/self-review`
>
> **Pre-flight:** posture not in `docs/agents/self-review.md` and no `--posture` flag. Branch is `feature/auth-refactor` (3 commits ahead of `main`). Working tree clean.
>
> **Claude:** "How should I handle agree-and-fix actions? — `auto` / `draft` / `comment-only`?"
> **User:** *"draft"*
>
> **Run review:** delegate to `/score --rubric pre-pr feature/auth-refactor`. Returns ledger with 5 action items.
>
> **Classify** (against `CONTEXT.md`, 2 ADRs, existing patterns, prior rejections):
>
> - **#1** (security persona): "use `crypto.randomUUID()` instead of custom UUID gen" → **agree-and-fix** (security improvement, no contradiction)
> - **#2** (test-coverage persona): "add a test for the empty-string case in `validateEmail`" → **agree-and-fix** (genuine gap)
> - **#3** (correctness persona): "wrap DB call in transaction" → **disagree-and-justify** (contradicts ADR-0011, intentional non-transactional path)
> - **#4** (readability persona): "rename `user_id` to `userId`" → **disagree-and-justify** (matches prior rejection #88; project uses snake_case for DB-mapped fields)
> - **#5** (scope-cohesion persona): "branch mixes auth + an unrelated logging tweak in commit 2" → **unsure-and-ask-user** (could split or merge; trade-off)
>
> **Draft view:**
>
> ```
> Will commit (3 commits + REVIEW-NOTES.md):
>   feat: replace UUID gen with crypto.randomUUID()  (Self-review: security)
>   test: cover empty-string case in validateEmail   (Self-review: test-coverage)
>   docs: REVIEW-NOTES.md (2 deliberate decisions)
>
> REVIEW-NOTES.md preview:
>   ## correctness — 2026-04-30
>   Critique: wrap DB call in transaction
>   Decision: ship despite
>   Reasoning: contradicts ADR-0011 (write path is intentionally non-transactional)
>
>   ## readability — 2026-04-30
>   Critique: rename user_id → userId
>   Decision: ship despite
>   Reasoning: matches prior rejection #88; project uses snake_case for DB-mapped fields
>
> Surfacing for your decision:
>   #5 (scope-cohesion): branch mixes auth + a logging tweak. Split into two PRs (cleaner history,
>      slower) or keep as one (faster, slightly noisier diff)?
>
> Confirm batch? [yes / no / edit]
> ```
>
> **User:** *"yes; on #5, keep as one PR — the logging tweak supports the auth changes."*
>
> **Apply:** apply both fixes (each as own commit), run tests after each (both pass), append #5 user-decision to REVIEW-NOTES.md as a third entry, commit notes file.
>
> **Final report:**
>
> - 3 new commits on `feature/auth-refactor` (2 fixes + REVIEW-NOTES.md)
> - Agreed-and-fixed: 2; disagreed-with-justification: 2; unsure-resolved-with-user: 1
> - Branch ready for PR. Suggested next: open PR; consider including `REVIEW-NOTES.md` content in the PR description.
