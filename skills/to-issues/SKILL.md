---
name: to-issues
description: Break a plan, spec, or PRD (typically produced by /to-prd) into independently-grabbable vertical-slice issues on the project issue tracker. Each slice cuts through every layer (schema, API, UI, tests) end-to-end — never a horizontal layer of one. Reads `docs/agents/issue-tracker.md` (written by /setup-workflow) to know how to publish (gh, glab, local markdown, or "Other"). Applies `needs-triage` so each issue enters the normal triage flow consumed by /triage. Distinguishes HITL (human-in-the-loop) from AFK (agent-implementable) slices. Use when the user wants to convert a plan or PRD into actionable issues, create implementation tickets, or break work into vertical slices.
argument-hint: "[plan, PRD reference, or issue URL]"
requires-skills: []
requires-config: []
---

# To Issues

Break a plan into independently-grabbable issues using vertical slices (tracer bullets).

## Why vertical slices?

A **horizontal slice** ships one layer at a time — schema first, then API, then UI, then tests. Each individual slice is undemoable: a schema with no API does nothing; an API with no UI does nothing. Reviewers can't verify anything works end-to-end until every layer is done.

A **vertical slice** cuts a thin path through *every* layer at once — a tiny but complete piece of the feature. Each slice is independently demoable, independently mergeable, and unblocks parallel work. *Independently grabbable* is the north star — every published issue must be pickup-ready by an AFK agent or human, with no "see the PRD" footnotes that require additional reading.

## HITL vs AFK

Each slice carries exactly one of:

- **HITL** (human-in-the-loop) — requires human judgment, design decisions, manual testing, or external access an agent can't perform
- **AFK** (away-from-keyboard) — fully specified enough that an agent can implement and merge without further human interaction

*Why the distinction matters:* it tells `/triage` which `ready-for-*` state to apply downstream (`ready-for-agent` for AFK, `ready-for-human` for HITL). It also helps the user prioritise their time — HITL slices block humans, AFK slices block nothing once triaged.

*Borderline examples* (the cases junior devs typically misclassify):

- **Database schema migration** — *HITL*. Even with well-specified SQL, production deploys need human approval; agents shouldn't run migrations unattended.
- **API design** (new endpoint shape, return types, error semantics) — *HITL*. Trade-offs about response structure and versioning need human judgment. Once shape is decided, the *implementation* of that shape is *AFK*.
- **Config rename across modules** — *AFK* if the rename has clear acceptance criteria (search-and-replace + tests). *HITL* if other teams' configs depend on the old name (external coordination needed).

Prefer AFK over HITL where possible. If you're unsure, lean AFK and let the user override.

## Process

### 1. Read your config and the source

Before drafting anything:

- Read `docs/agents/issue-tracker.md` (written by `/setup-workflow`) to learn this repo's tracker — whether to publish via `gh`, `glab`, `.scratch/`, or "Other". If the file doesn't exist, run `/setup-workflow` first.
- If the user passed an issue reference (number, URL, or path) as an argument, fetch it from the tracker and read its full body and comments. Otherwise work from the conversation context (typically a PRD just written by `/to-prd`).

### 2. Explore the codebase (if you haven't already)

Understand the current state. Issue titles and descriptions should use the project's domain glossary (`CONTEXT.md`) vocabulary, and respect ADRs in the area you're touching.

### 3. Draft vertical slices

Break the plan into **tracer-bullet** issues:

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
- Each slice carries one HITL or AFK label
</vertical-slice-rules>

### 4. Quiz the user

Present the proposed breakdown as a **numbered list** so the user can reference slices by number ("split #3", "merge #2 and #4"). For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories this addresses (if the source has them)

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are HITL and AFK labels correctly applied?

Iterate until the user approves the breakdown.

**Edge cases:**

- *User says "merge all of them"* — granularity is too fine; collapse into fewer thicker slices and re-quiz.
- *User says "split that one"* — break into smaller vertical slices, never split into horizontal layers (don't separate schema from API from UI).
- *Dependency cycle in the slice graph* — flag it; cycles indicate a design issue. Ask whether to combine the cyclic slices or revisit the architecture before publishing.
- *Plan can't be sliced vertically* (e.g., pure data migration) — say so, propose an alternative (one slice with the migration + a verification step), let the user decide whether that's acceptable.

### 5. Publish in dependency order

For each approved slice, publish a new issue to the tracker (using the conventions from `docs/agents/issue-tracker.md`). Apply the `needs-triage` triage label so each issue enters the normal triage flow consumed by `/triage`.

Publish in **dependency order** — blockers first.

*Why dependency-order publishing:* the issue tracker assigns IDs at creation time. If you publish a dependent slice before its blocker, you can't reference the blocker's real ID in the "Blocked by" field — you'd have to use a placeholder and edit the issue later. That's drift. Publishing blockers first lets you reference real IDs throughout.

<issue-template>

## Parent

A reference to the parent issue on the tracker (if the source was an existing issue, otherwise omit this section).

## What to build

A concise description of this vertical slice. Describe the end-to-end *behaviour*, not layer-by-layer implementation.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- A reference to the blocking ticket (if any)

Or "None — can start immediately" if no blockers.

</issue-template>

Do NOT close or modify any parent issue.
