# Workflow Primer

A 2-minute orientation to the engineering skill suite. Loaded only when the user asks for a tutorial during `/setup-workflow` — read it once, summarise the five failure modes and pipeline shape in your own words, then proceed to setup.

## Why these skills exist

Every common AI-coding failure mode has the same root cause: **the agent is missing context, or has shipped without a quality gate, or has forgotten to close the loop after merge**. These skills are surgical interventions for the five most common failure modes.

## The five failure modes

### 1. Misalignment — "the agent didn't do what I want"

The most common bug in software is misunderstanding what to build. AI agents amplify it — they happily build the wrong thing fast. The fix is a **grilling session** before any code: the agent interrogates your plan until ambiguity is gone.

→ `/grill-me` runs this loop on any plan, design, or proposal. Walks the dependency tree of decisions one at a time and surfaces ambiguity along five axes (terminology, scope, edge cases, trade-offs, code reality).

### 2. Verbose code / jargon drift — "agent uses 20 words where 1 will do"

Agents dropped into projects without a shared vocabulary spend tokens rephrasing concepts the team already has names for. They name variables `customerOrUser` because they don't know which is canonical. The fix is a **shared language**: a `CONTEXT.md` glossary capturing domain terms, plus `docs/adr/` for architectural decisions worth remembering.

→ `/grill-me` produces these artifacts as it grills. Every other skill in the pipeline reads them.

### 3. Code doesn't work — "the agent is flying blind"

Without feedback loops, agents produce plausible-looking code that doesn't run. The fix is **fast, deterministic feedback**: TDD's red-green-refactor loop, plus a disciplined diagnosis loop for bugs that surface anyway.

→ `/tdd` runs the red-green-refactor flow with guidance on what makes good vs bad tests.
→ `/diagnose` runs a six-step bug-hunting loop (reproduce → minimise → hypothesise → instrument → fix → regression-test).

### 4. Ball of mud — "AI accelerates entropy"

Agents speed up coding but also speed up complexity accumulation. Without active design care, codebases become harder to change at an unprecedented rate. The fix is to **invest in design every day**.

→ `/to-prd` quizzes you about which modules a change touches, before turning the conversation into a PRD.
→ `/improve-codebase-architecture` finds deepening opportunities (modules that should consolidate or expose simpler interfaces).
→ `/zoom-out` gives broader context when you hit unfamiliar code.

### 5. Unreviewed handoffs and forgotten loose ends — "agent ships without a gate, then forgets to clean up"

Agents will happily push code straight from "tests pass" to "PR opened" with no quality gate, and they leave behind a trail (debug logs, "remove once #N" TODOs, sub-issues, feature flags) that nobody remembers to clean up after merge. The fix has two halves: a **multi-persona review at each artifact boundary** before handing off, and an **agent-owned cleanup pass** triggered by the merge signal.

→ `/score` runs a multi-persona, dialogue-validated review on any artifact — used as a quality gate at the PRD boundary (`--rubric prd`) before slicing into issues. Read-only output; the human iterates the PRD by hand.
→ `/self-review` wraps `/score` (with the `pre-pr` rubric) and adds an auto-fix layer — used at the pre-PR boundary, between `/tdd` finishing and `git push`. Apply agree-and-fix as commits; record disagree-and-justify in `REVIEW-NOTES.md`.
→ `/resolve-reviews` handles inbound PR review comments (Copilot or human) with the same posture model.
→ `/post-merge-cleanup` runs after the human merges — closes the issue, deletes the branch, strips "remove once #N" TODOs, removes temp instrumentation, drafts a CHANGELOG entry, schedules rollout follow-ups, surfaces feature-flag / stakeholder / `CONTEXT.md` decisions for the human. The agent that built the PR is the right one to clean up because it has the session context (which `console.log`s did *I* add? which sub-issues did *I* spawn?) — that memory disappears when the session ends.

The last three skills (`/self-review`, `/resolve-reviews`, `/post-merge-cleanup`) share a posture model — `auto` / `draft` / `comment-only` — so a junior dev learns one mental model that brackets the whole PR lifecycle.

## How the pieces fit together

The per-feature pipeline:

```
idea / change request
    ↓
[grill-me]              align on what to build, capture terms in CONTEXT.md and trade-offs in ADRs
    ↓
[to-prd]                synthesise a PRD from the conversation, publish to the issue tracker
    ↓
[score --rubric prd]    QUALITY GATE — multi-persona review of the PRD
                        before slicing. A bad PRD multiplies into many bad
                        issues; this is the highest-leverage upstream catch.
                        Read-only — the human iterates the PRD by hand.
    ↓
[to-issues]             break the PRD into tracer-bullet vertical-slice issues on the tracker
    ↓
[triage]                move each issue through a 5-role state machine
                        (needs-triage → needs-info / ready-for-agent / ready-for-human / wontfix)
    ↓
[tdd]                   red-green-refactor implementation of an issue
    ↓
[self-review]           QUALITY GATE — multi-persona review of the local
                        branch BEFORE PR-open. Uses /score's pre-pr rubric
                        internally and adds an auto-fix layer (apply agree-and-fix
                        as commits; record disagree-and-justify in REVIEW-NOTES.md).
    ↓
PR opened
    ↓
[resolve-reviews]       handle inbound review comments (Copilot / human reviewers)
    ↓
human merges
    ↓
[post-merge-cleanup]    BACK-BOOKEND — close originating issue, delete branch,
                        strip "remove once #N" TODOs, remove temp instrumentation,
                        draft CHANGELOG, schedule rollout follow-ups. Surfaces
                        feature-flag / stakeholder / CONTEXT.md decisions for the
                        human. Triggered when the user signals "merged".
    ↓
[diagnose]              when bugs surface during/after implementation (any stage)
```

The pipeline now has **two quality gates** (PRD and pre-PR) and a **back-bookend** (post-merge cleanup) that brackets the PR around its merge. Three of these (`/self-review`, `/resolve-reviews`, `/post-merge-cleanup`) share the same posture model — `auto` / `draft` / `comment-only` — so a junior dev learns one mental model that applies across the whole PR-bookending suite.

### Why two gates and not one

`/score` and `/self-review` both run multi-persona review, but their lifecycles differ:

| | Artifact | Iteration mode | Tool | Rubric |
|---|---|---|---|---|
| **PRD gate** | The PRD doc | Human edits by hand | `/score` (read-only) | `prd` |
| **pre-PR gate** | The local diff | Auto-fixable as commits | `/self-review` (act + record) | `pre-pr` |

Running both at the same gate would be redundant — `/self-review` *uses* `/score` internally with the `pre-pr` rubric. The split is *one tool per gate, picked because the artifact's lifecycle differs*.

### Why post-merge cleanup is its own skill

Because it's mechanical, it's easy to forget, and the agent that built the PR has the context to do it. Reconstructing the cleanup trail from PR metadata alone is lossy — the agent knows which `console.log`s *it* added during diagnose, which sub-issues *it* spawned, which TODOs *it* tagged "remove once #N merges." That memory disappears once the session does. So cleanup chains off the merge signal in the same session, before the context evaporates.

Periodic hygiene (run weekly-ish, not per-feature):

- `/improve-codebase-architecture` — surfaces architectural debt
- `/zoom-out` — broader context for unfamiliar areas

## What `setup-workflow` does

It writes three config files that every skill above reads:

- **`docs/agents/issue-tracker.md`** — what tracker you use, how to create/read/comment on issues, which CLI to call.
- **`docs/agents/triage-labels.md`** — which label strings in your tracker map to the five canonical roles.
- **`docs/agents/domain.md`** — single- or multi-context layout, where `CONTEXT.md` and ADRs live, how to consume them.

It also adds a `## Agent skills` block to `CLAUDE.md` (or `AGENTS.md`) pointing at those three files.

Run it once per repo to bootstrap. After that, downstream skills just work — they read the config and act on it. Rerun later if you switch trackers or adjust your label vocabulary; reruns are section-scoped and won't overwrite manual edits without asking.

## What this primer is *not*

- Not a replacement for the individual skill docs. Each skill has its own `SKILL.md` with the details.
- Not a tutorial on TDD, ADRs, or domain-driven design. It assumes you've heard of these and want to know how this skill suite uses them.
- Not exhaustive. There are smaller utility skills (`/zoom-out`, `/improve-codebase-architecture`) that aren't in the per-feature pipeline but are worth knowing.

When in doubt, run `/grill-me` first. Most failure modes upstream of "the code is wrong" are alignment problems that grilling catches.
