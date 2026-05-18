---
name: resolve-reviews
description: Resolve **inbound** PR review comments (Copilot, automated bots, or human reviewers). NOT for writing outbound review comments yourself — use `/review` or `/security-review` for that. Classifies each comment into agree-and-act / disagree-and-justify / unsure-and-ask-user against project conventions (CONTEXT.md, ADRs, existing patterns, prior rejected-suggestions), then acts per a configured posture (`auto` / `draft` / `comment-only`). Agree-and-act commits the change + posts thread comment + resolves the conversation. Disagree-and-justify posts a project-grounded denial leaving the thread OPEN for human review. Unsure surfaces to the user. Bounded re-review loop (default 3 iterations). Use when the user has a PR with review comments to resolve, says "respond to copilot", "resolve the review comments on PR #N", "address the PR feedback", or wants to close out review feedback before merge.
argument-hint: "[PR ref or URL] [optional: --posture auto|draft|comment-only] [optional: --max-loops N] [optional: --filter <regex>]"
requires-skills: []
requires-config: []
---

# Resolve Reviews

Lossless review-to-merge loop for PR review comments (Copilot, automated, or human).

## Where this enters the workflow

```
[/dispatch or /tdd opens PR] → [Copilot reviews] → /resolve-reviews → [merge gate]
                                                                          ↓
                                                                   human merges
                                                                          ↓
                                                                /post-merge-cleanup
```

Sits between PR-creation and merge. After the human merges, control hands off to `/post-merge-cleanup` (close issue, delete branch, strip TODOs, draft CHANGELOG, schedule rollout follow-ups, surface judgment-call cleanup). The same `auto` / `draft` / `comment-only` posture model used here applies there — junior dev learns one mental model that brackets the whole PR lifecycle.

This skill is not in the upstream per-feature pipeline (`grill-me → to-prd → /score(prd) → to-issues → triage → tdd → /self-review`); it's applied opportunistically when a PR has review comments to resolve.

**North star:** *lossless review-to-merge.* Every actionable Copilot review comment ends in either:

- (a) committed code addressing the critique + thread comment + thread resolved, **or**
- (b) a posted denial comment with project-grounded justification (thread left OPEN for human review).

Judgment is applied per-comment — categorises against project conventions before deciding. Never rubber-stamps either way.

## Process

### 1. Pre-flight

Before reading any reviews:

- [ ] `docs/agents/issue-tracker.md` exists. If not, run `/setup-workflow` first.
- [ ] PR reference resolves; user has push access to the branch.
- [ ] **Posture is set** — via `docs/agents/resolve-reviews.md` (`posture: auto|draft|comment-only`), `--posture <name>` argument, or asked at start (see below).

#### Asking for posture

If posture isn't set, ask:

> "How should I handle agree-and-act commits?
>
> - **auto** — make the change + commit + push + comment + resolve thread, no per-comment confirmation. Right when branch protection + CI catch anything we miss.
> - **draft** — show you the full batched diff before commit/push. One confirmation for the whole batch. Right when you want a human look first.
> - **comment-only** — never commit; post 'I would change X' comments on the thread; you take action manually. Right when you want classification work only."

Wait for the answer. Don't proceed with an assumed posture.

#### When to pick which posture

The same three-way model is shared by `/self-review` (pre-PR front-bookend) and `/post-merge-cleanup` (back-bookend) — picking the same posture across all three skills gives you predictable behavior across the whole PR lifecycle. Each posture fits a real situation, not a personal preference:

- **`auto`** — when your repo has branch protection + CI + required reviewers in place to catch anything this skill misses. Right when reviews are routine (Copilot suggestion accepted, push commit, resolve thread) and the PR has dozens of comments where per-comment confirmation would be exhausting. *Why the safety net matters:* `auto` commits and pushes without per-comment confirmation. The safety net is what stops a bad fix from reaching `main`. **Don't pick `auto` unless the safety net is in place** — pick `draft` while building trust, or `comment-only` if the repo has neither.
- **`draft`** — when you're learning the skill, when the PR is high-blast-radius (auth, payments, schema migrations), or when you want a single batch view before any commits push. *The default for new users.* Cost: one batch confirmation. Benefit: human eye on the full proposed response set before agree-fixes commit and denial-comments post.
- **`comment-only`** — when you want the classification work but plan to action manually, when running unattended in an audit-trail context, or when you'd rather keep the PR-thread-update authority entirely with the human. *Why distinct from `draft`:* `draft` still commits + pushes + posts on confirmation; `comment-only` posts the *classification* on the thread but never commits.

If you're undecided, pick `draft`. The cost of one batch-confirmation prompt is much smaller than the cost of an unwanted push to a PR branch under review.

#### Unattended runs

In CI / non-interactive contexts, posture must be set via `--posture` argument or a `posture: <name>` line in `docs/agents/resolve-reviews.md`. If neither is set and no user is present, **refuse to run** with a clear error pointing to both paths.

### 2. Read project grounding

Read these once at start (cached for the rest of the invocation):

- `CONTEXT.md` (and `CONTEXT-MAP.md` if multi-context) — domain glossary
- Recent `docs/adr/*.md` (and `src/<context>/docs/adr/` for multi-context) — architectural decisions
- `docs/agents/prior-rejected-suggestions.md` if it exists — this skill's accumulated rejection history

These are the four grounding sources used for per-comment classification. The fourth (existing code patterns near the change) is read *per-comment* in step 4 since it depends on the comment's location.

If grounding sources are missing, proceed but flag in the report so the user knows judgment is weaker than usual.

### 3. Fetch the review

Use `docs/agents/issue-tracker.md` conventions:

- **GitHub**: `gh pr view <PR> --json reviews,reviewThreads,comments` and `gh pr diff <PR>`
- **GitLab**: equivalent `glab mr view <MR>` flags

Parse:

- Inline review comments (with file path + line range + suggestion)
- General review summary comments
- Existing thread state (resolved? has prior responses?)

**Skip already-resolved threads** unless the user explicitly says re-engage them.

### 4. Classify each comment

For each unresolved comment, decide one of three buckets:

- **agree-and-act** — suggestion doesn't contradict any grounding source AND is genuinely an improvement (clearer code, real fix, follows conventions). Default for clear-cut wins.
- **disagree-and-justify** — contradicts a grounding source (ADR / `CONTEXT.md` term / consistent existing pattern / prior rejection). The denial comment must name *which* source it conflicts with. *Why grounded denials matter:* a denial that just says "I disagree" is worse than no comment — it invites debate without giving the reviewer anything to respond to. Citing the source ("contradicts ADR-0007", "matches prior rejection #88", "uses canonical CONTEXT.md term `customer_id`") lets the human reviewer either accept the citation or argue with the source — not the skill's opinion. Ungrounded denials are noise.
- **unsure-and-ask-user** — legitimate trade-off the grounding sources don't resolve. Surface to the user with the trade-off framed; wait for their decision.

**What counts as "actionable":**

- **Skip** pure formatting nits already handled by the project's linter (don't relitigate)
- **Engage** everything else, including style suggestions that touch code semantics (variable naming, error-handling shape, control flow)
- A `--filter <regex>` flag tightens this further per-invocation (e.g., `--filter '^(security|correctness)'` to engage only those tiers)

### 5. Act per posture

#### `auto` posture

*Why `auto` requires branch protection + CI:* in `auto` mode, the skill commits and pushes without per-comment confirmation. The safety net is your repo's branch protection rules + CI — required reviewers, automated tests, lint gates. Without that net, an `auto` run can push code to `main` with no human-in-the-loop. **Don't pick `auto` unless the safety net is in place** — pick `draft` while building trust, or `comment-only` if the repo has neither.

For each comment:

- **agree-and-act** — make the change → commit (one commit per logical group, not one per comment unless they're independent) → push → post thread comment `Addressed in <short-hash>: [one-line description]` → **resolve the conversation**.
- **disagree-and-justify** — post denial comment naming the contradiction: e.g. *"This contradicts ADR-0007 (event-sourced orders) — the suggestion to use a synchronous insert would bypass our event log. Keeping current implementation."* **Leave thread open.**
- **unsure-and-ask-user** — surface to the user in chat with the trade-off framed; wait for their decision; then act per their choice.

#### `draft` posture

- Make all agree-and-act changes locally (working tree, no commit yet).
- Show the user a unified diff (per-file, grouped by which Copilot comment drove each change).
- Show denial comments staged for posting (drafted but not posted).
- Surface unsure cases inline.
- Ask once: *"Confirm this batch? [yes / no / let me edit]"*
- **On yes:** commit + push + post all agree-and-act thread comments + resolve those threads + post denial comments (leave open).
- **On no:** abort cleanly, leave working tree as draft, user can rerun with edits.

#### `comment-only` posture

- Post ALL classification decisions as comments on the PR thread (not as code changes):
  - **agree-and-act** → "Suggestion is sound; [proposed change]. Apply manually if you'd like."
  - **disagree-and-justify** → post denial as written.
  - **unsure-and-ask-user** → "Trade-off here — [framing]. Your call."
- **Never commit, never resolve threads** (no actual fix happened).

### 6. Re-review loop

After agree-and-act commits push, Copilot may re-review the new code. Bounded loop:

- After the first pass, wait for Copilot to re-review (or check after the user prompts).
- On each loop iteration: re-fetch the review state **AND re-read `docs/agents/prior-rejected-suggestions.md`** — so this iteration's denials apply automatically to any re-raised suggestions Copilot makes on the next pass. (Without re-reading, an iteration-1 rejection would surface as a "Copilot re-raised previously-rejected critique" edge case in iteration 2 instead of being auto-applied.)
- If new comments arrive, return to step 3 and process again.
- **Default `max-loops`: 3.** Override via `--max-loops N` argument or `max_loops: N` in `docs/agents/resolve-reviews.md`.
- If we hit the bound: **stop and surface** *"Hit max-loops; remaining unresolved threads need human review."* Don't loop indefinitely.

*Why bounded at 3:* unbounded loops fail two ways. **(a) Context economics** — each iteration re-reads grounding sources, re-fetches review state, and re-classifies; iteration 4+ burns context with diminishing returns. **(b) Semantic drift** — Copilot may re-suggest variants of the same critique on each pass, with the skill responding slightly differently each time; the loop orbits rather than converges. Three iterations covers genuine progressive refinement (initial pass + 2 follow-ups for surfaced clarifications); beyond that, surfacing to a human is the right call, not more loop iterations.

### 7. Persist for future runs

After the loop ends, append to `docs/agents/prior-rejected-suggestions.md` (create the file on first run):

```yaml
- pr: <PR-number>
  date: <ISO-date>
  rejections:
    - critique: "<what Copilot suggested, quoted>"
      rationale: "<why we rejected: cite ADR-NNNN / CONTEXT.md term / pattern-N>"
      file: <file-path>
      line: <line-or-range>
```

This file is read on future runs (step 2) — same suggestions get the same rejection without re-litigating.

## Edge cases

- **Comment on a now-deleted line** — Copilot reviewed an earlier diff that's since changed. Surface in the report; do nothing automatically.
- **Suggestion conflicts with another comment's suggestion** (Copilot disagrees with itself) — surface to the user; don't pick.
- **Push fails (rebase conflict, branch moved)** — in `auto` posture, abort the push and surface the conflict; **leave the working tree in its post-commit state** (commits are local but un-pushed) so the user can resolve manually (`git pull --rebase`, fix conflicts, `git push`) and then re-run `/resolve-reviews` to continue with remaining comments. Don't force-push. In `draft`, the user sees the conflict before confirming the batch and resolves manually before re-confirming.
- **User-response timeout in CI / unattended runs** — when an unsure-and-ask-user case surfaces and no user is present, the skill cannot proceed on that comment. Behaviour: leave the thread untouched (no commit, no thread comment), continue processing the remaining comments, surface unresolved unsure-cases in the final report. **Never default to a guess** — ambiguity is the user's call.
- **Copilot updates mid-skill-run** — re-fetch on each loop iteration; don't operate on stale review state.
- **Comment marked as a blocking review (request-changes)** — same flow but flag at the top of the report so the user knows merge is blocked until resolved.
- **No grounding sources exist** — proceed but flag in the report: *"No project-grounding files found; classifications based on Copilot's suggestion content alone — judgment is weaker than usual."* Surface so the user knows.
- **Thread has prior denial from this skill but Copilot re-raised the same concern** — don't post the same denial again; surface to user as "Copilot re-raised previously-rejected critique on `<file>:<line>` — your call to engage or close manually."

## Anti-patterns

- **Don't rubber-stamp.** Even in `auto` posture, classification still applies per-comment — the posture only controls whether to commit-and-push, not whether to engage.
- **Don't skip threads silently.** Every comment ends in a visible outcome (commit hash + thread resolution, OR denial comment, OR surface-to-user). No silent dismissals.
- **Don't relitigate prior rejections.** If `prior-rejected-suggestions.md` has a matching entry, apply same rejection without re-engaging.
- **Don't fight the linter.** Skip formatting nits the linter handles; engaging them creates churn between two systems disagreeing on whitespace.
- **Don't auto-resolve threads on disagree.** Resolution is the agree-side outcome; disagree leaves the thread open for human review.
- **Don't loop unbounded.** If hit `max-loops`, surface and stop — escalate, don't silence.
- **Don't draft denials without grounding.** A denial comment that just says "I disagree" is worse than no comment. Cite the source (ADR-NNNN, CONTEXT.md term, pattern-N, prior-rejection-N).

## Worked example

> **User:** `/resolve-reviews #142`
>
> **Pre-flight:** posture not in `docs/agents/resolve-reviews.md` and no `--posture` flag.
>
> **Claude:** "How should I handle agree-and-act commits? — `auto` / `draft` / `comment-only`?"
> **User:** *"draft"*
>
> **Read grounding:** `CONTEXT.md` (50 lines), 3 ADRs in `docs/adr/`, `prior-rejected-suggestions.md` exists with 2 prior rejections.
>
> **Fetch review:** PR #142 has 5 unresolved Copilot comments + 1 already-resolved (skip).
>
> **Classify:**
>
> - Comment #1 (`auth.ts:42`): *"consider extracting into a helper"* → **agree-and-act** (clear improvement, no contradiction)
> - Comment #2 (`auth.ts:87`): *"use `crypto.randomUUID()`"* → **agree-and-act** (security improvement)
> - Comment #3 (`db.ts:14`): *"wrap in transaction"* → **disagree-and-justify** (contradicts ADR-0011 — this write path is intentionally non-transactional for throughput)
> - Comment #4 (`cache.ts:102`): *"add a TTL"* → **unsure-and-ask-user** (trade-off the grounding sources don't resolve)
> - Comment #5 (`auth.ts:30`): *"use camelCase for `user_id`"* → **disagree-and-justify** (matches prior rejection #88 — this codebase uses snake_case for DB-mapped fields)
>
> **Draft view:**
>
> ```
> Will commit (1 commit, 2 changes):
>   auth.ts: extract helper at line 42  (Comment #1)
>   auth.ts: replace UUID gen with crypto.randomUUID() at line 87  (Comment #2)
>
> Will post denial comments (threads left open):
>   #3 (db.ts:14):  "Contradicts ADR-0011 — write path is intentionally non-transactional for throughput. Keeping current."
>   #5 (auth.ts:30): "Per prior rejection (#88), this codebase uses snake_case for DB-mapped fields."
>
> Surfacing for your decision:
>   #4 (cache.ts:102): Trade-off — adding TTL improves staleness risk but adds invalidation complexity. CONTEXT.md and ADRs don't speak to it. Your call.
>
> Confirm batch? [yes / no / edit]
> ```
>
> **User:** *"For #4 — what's actually at stake with TTL?"*
>
> **Claude:** *"Cache hit savings are ~50ms per call (small). The risk is staleness — if the cached value is wrong, downstream code computes against the wrong number until invalidation. `CONTEXT.md` doesn't define a staleness contract here, so it's a judgment call. Two reasonable options:*
> *(a) Add TTL with 60s default — caps staleness window to 1 minute, simple invalidation.*
> *(b) No TTL, rely on event-driven invalidation — tighter bound on staleness, but adds an event listener and a possible-failure mode (missed event → stale forever).*
> *Which fits your project's tolerance?"*
>
> **User:** *"(a). 60s. Log a follow-up ADR after we ship."*
>
> **Claude:** *"Confirmed; committing (a), posting thread comment, and surfacing an ADR follow-up reminder."*
>
> **Apply iteration 1:** commit batch (3 changes — Comments #1, #2, and #4-with-TTL-60s), push, post 3 agree-and-act thread comments + resolve those threads, post 2 denial comments (leave open), update `prior-rejected-suggestions.md` with entries for Comments #3 and #5, surface "Write ADR for TTL decision" as a follow-up reminder.
>
> **Loop iteration 2** (1/3 of max-loops used). Re-fetch review state AND re-read `prior-rejected-suggestions.md` (now containing iteration-1's entries). Copilot has re-reviewed and posted two new comments:
>
> - **New comment** on `auth.ts:45` (the helper extracted in iteration 1): *"add a doc-comment"* → **agree-and-act** (genuine improvement, no contradiction).
> - **Re-raised** on `auth.ts:30`: *"use camelCase for `user_id`"* — Copilot didn't see the iteration-1 denial. **Edge case: re-raised previously-rejected critique.** The skill matches against the just-loaded `prior-rejected-suggestions.md` entry and **auto-applies the prior rejection** — posts a brief denial (*"Per prior rejection in this PR's iteration 1 and standing project convention. See `prior-rejected-suggestions.md`. Keeping snake_case."*) without re-engaging the dialogue.
>
> **Apply iteration 2:** 1 new commit (doc-comment), 1 brief re-rejection comment, no `prior-rejected-suggestions.md` update (entry already exists).
>
> **Loop iteration 3:** Copilot re-reviews; no new unresolved comments. Loop ends naturally before hitting max.
>
> **Final report:**
>
> - 4 commits pushed across 2 active iterations (4 changes total)
> - 4 threads resolved; 3 denials posted (open for human); 1 unsure surfaced and resolved with multi-turn user dialogue
> - 1 follow-up reminder: write ADR for TTL decision
> - `prior-rejected-suggestions.md` updated with 2 entries from iteration 1; iteration 2's auto-applied prior rejection logged in the run ledger but not duplicated in the file
> - Loop ended naturally at iteration 3 / max 3 with no remaining unresolved comments
