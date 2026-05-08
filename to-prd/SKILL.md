---
name: to-prd
description: Synthesise the current conversation context (typically after /grill-me has aligned the plan) into a PRD and publish it to the project issue tracker. Use when the user wants to create a PRD from the current conversation, capture aligned decisions as a published spec, or hand off context-rich work to the issue tracker. Does NOT interview the user — synthesise from existing alignment.
---

# To PRD

Take the current conversation context and codebase understanding and produce a PRD. **Do NOT interview the user — synthesise from what you already know.**

*Why synthesise-don't-interview:* this skill runs *after* `/grill-me` has aligned the plan. Re-asking would re-litigate decisions the user has already settled, contradicting the *lossless handoff* north star (every decision aligned during grilling must survive the PRD path without re-clarification). If the conversation context feels too thin to write a PRD, that's a signal to run `/grill-me` first — not to start interviewing here.

## Process

### 1. Read your config

Before writing anything, read `docs/agents/issue-tracker.md` (written by `/setup-workflow`) to learn this repo's tracker — whether to publish via `gh issue create`, `glab issue create`, write a markdown file under `.scratch/`, or follow an "Other" workflow. If the file doesn't exist, run `/setup-workflow` first.

### 2. Explore the repo (if you haven't already)

Understand the current state of the codebase. Use the project's domain glossary (`CONTEXT.md`) vocabulary throughout the PRD — drift from canonical terms here cascades into `/to-issues`, `/triage`, and `/tdd`. Respect any ADRs in the area you're touching.

### 3. Sketch modules (verify, don't interview)

List the major modules you will need to build or modify. Actively look for opportunities to extract **deep modules** that can be tested in isolation.

> *A deep module encapsulates a lot of functionality behind a simple, testable interface that rarely changes — the opposite of a shallow module, which is mostly pass-through.*

**Verify these against the conversation history**, not by re-asking the user. If the conversation has been clear about a module ("we'll add a `RetryPolicy` type"), record it. If something is genuinely ambiguous, surface it as a *known gap* in the PRD's "Further Notes" section rather than re-interviewing. If gaps are large, the upstream `/grill-me` was incomplete; flag that the user might want to grill more before publishing.

### 4. Write and publish the PRD

Write the PRD using the template below, then publish it to the issue tracker (using the conventions from `docs/agents/issue-tracker.md`). Apply the `needs-triage` triage label so it enters the normal triage flow.

*Why `needs-triage` automatically:* the PRD is a synthesised spec but hasn't been evaluated by a maintainer yet — they still need to apply a category (`bug`/`enhancement`) and decide whether to break it into issues via `/to-issues` or send it back via `needs-info`. Auto-applying `needs-triage` puts the PRD in the right queue without skipping evaluation.

<prd-template>

## Problem Statement

The problem the user is facing, *from the user's perspective*. Not "the system lacks X" but "the user can't accomplish Y because of X."

## Solution

The solution to the problem, *from the user's perspective*. What the user will be able to do that they couldn't before.

## User Stories

A LONG, numbered list of user stories. Each user story should be in the format:

1. As an &lt;actor&gt;, I want a &lt;feature&gt;, so that &lt;benefit&gt;

Example:

1. As a mobile bank customer, I want to see balance on my accounts, so that I can make better informed decisions about my spending

This list should be extensive and cover all aspects of the feature.

## Implementation Decisions

A list of implementation decisions made during grilling. Can include:

- Modules that will be built/modified
- Interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets — they go stale quickly.

## Testing Decisions

A list of testing decisions made. Include:

- A description of what makes a good test (test external behaviour, not implementation details)
- Which modules will be tested
- Prior art — similar tests already in the codebase

## Out of Scope

A description of things explicitly *not* in this PRD.

## Further Notes

Any unresolved questions, open assumptions, or known gaps from the alignment phase. If this section has substance, consider running `/grill-me` again before letting `/to-issues` slice — gaps here cascade.

</prd-template>

#### Why each section earns its place

- **Problem Statement** — anchors the rest of the document in user-observable reality. Without it, downstream readers can't verify whether the proposed solution actually addresses the problem.
- **Solution** — paired with Problem Statement, gives `/to-issues` a clear target when slicing; every vertical slice should advance toward this stated solution.
- **User Stories** — `/to-issues` uses these to define vertical slices; each story typically maps to one or more tracer-bullet issues. Sparse stories produce a sparse slice graph and downstream gaps.
- **Implementation Decisions** — captures the load-bearing technical alignment from `/grill-me` so `/to-issues` and the eventual implementer don't have to reverse-engineer it from the conversation.
- **Testing Decisions** — feeds into `/tdd` downstream. Without this, the TDD red-green loop has no anchor for what "good" looks like.
- **Out of Scope** — prevents implementation gold-plating. Implementers (agent or human) need explicit boundaries to avoid scope creep.
- **Further Notes** — honest record of what's *not* settled. Surfacing assumptions here lets the maintainer re-triage or request more grilling, rather than letting `/to-issues` inherit ambiguous intent and slice around guesses.

#### What a lossy PRD looks like

A *lossy* PRD silently drops signal between the aligned conversation and the published spec. Common failure modes — if your draft pattern-matches one of these, the upstream `/grill-me` left gaps. Surface them in "Further Notes" or run `/grill-me` again before publishing:

- **Problem Statement that's actually a Solution.** *"The API is slow → add a caching layer."* Conflates symptom and remedy; loses the user's actual problem. Downstream, `/to-issues` slices toward the prescribed fix without checking whether faster-API was even what the user wanted.
- **User Stories that conflate actor and benefit.** *"As a user, I want caching, so that performance is better."* Generic actor; the benefit just restates the feature. Slices have no clear demo target.
- **Implementation Decisions hiding undecided trade-offs.** *"We'll use Redis."* — without recording what was rejected (Memcached? in-memory? CDN?). When the implementation hits a wall, the team re-litigates from scratch.
- **Out of Scope left empty.** Implementer treats *everything* as in-scope and gold-plates.

### 5. Recommend the upstream quality gate (`/score --rubric prd`)

After publishing the PRD, **recommend the user run `/score --rubric prd <issue-ref-or-path>` before invoking `/to-issues`.** This is the upstream quality gate of the per-feature pipeline:

```
to-prd → /score --rubric prd  ←  QUALITY GATE
            ↓
       to-issues (only if score is acceptable)
```

*Why a gate here, and why this gate specifically:*

- **A bad PRD multiplies into many bad issues.** The PRD is the single artifact that every downstream slice inherits scope, vocabulary, and trade-offs from. Catching gaps at the PRD layer is strictly higher-leverage than catching them in any single issue or PR. One round of `/score` on the PRD prevents N rounds of re-grilling on N slices.
- **Read-only, not auto-fix.** The PRD is iterated by the human — phrasing matters, the audience is human, and editorial judgment can't be safely automated. So the gate is `/score` (read-only ledger), not `/self-review` (which auto-fixes). The complementary auto-fix gate runs *later*, on the local diff before PR-open (`/self-review` after `/tdd`).
- **Multi-persona, not single-reviewer.** A single reviewer brings one lens. The `prd` rubric runs ~7 personas (problem-statement, scope-clarity, slice-readiness, decision-traceability, testing-anchor, vocabulary-alignment, gap-honesty), each grounded in this skill's contract. That's the catch you can't get from re-reading the PRD yourself.

Phrase the recommendation educationally, not just procedurally:

> "Published the PRD. Before slicing it into issues, run `/score --rubric prd <ref>` — this is the upstream quality gate. A bad PRD cascades into many bad issues, so catching gaps here has the highest leverage in the pipeline. The score is read-only — you'll iterate the PRD by hand based on the ledger, then `/to-issues` once it's sound."

If the user explicitly waives the gate (e.g., trivial PRD, time pressure), proceed without it but flag in the run report that the gate was skipped — so a later "downstream slices feel off" investigation has a thread to pull on.
