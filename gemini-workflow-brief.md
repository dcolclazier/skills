# Engineering Workflow Briefing — for Gemini

You are being given a complete briefing on an AI-coding workflow built around a suite of slash-command "skills" that together bracket the entire feature lifecycle from idea to post-merge cleanup. The user wants you to engage with this workflow critically — understand what it solves, where its load-bearing ideas come from, what it deliberately does *not* solve, and where it could be improved. After you've read this brief, the user will ask you specific questions or give you a task; treat this document as authoritative context for everything that follows.

---

## 1. The diagnosis this workflow exists to treat

Every common AI-coding failure mode reduces to one of three root causes: **the agent is missing context, has shipped without a quality gate, or has forgotten to close the loop after merge.** The workflow is a set of surgical interventions for the **five most common failure modes** that flow from those roots:

1. **Misalignment** — *"the agent didn't do what I want."* Misunderstanding what to build is the most common bug in software, and AI agents amplify it: they happily build the wrong thing fast. Fix: a grilling session before any code is written.
2. **Verbose code / jargon drift** — *"the agent uses 20 words where 1 will do."* Agents dropped into projects without a shared vocabulary spend tokens rephrasing concepts the team already has names for, and name variables `customerOrUser` because they don't know which is canonical. Fix: a shared language captured in `CONTEXT.md` and architectural decisions captured in `docs/adr/`.
3. **Code doesn't work** — *"the agent is flying blind."* Without fast feedback loops, agents produce plausible-looking code that doesn't run. Fix: TDD's red-green-refactor loop, plus a disciplined six-phase diagnosis loop for bugs that surface anyway.
4. **Ball of mud** — *"AI accelerates entropy."* Agents speed up coding but also speed up complexity accumulation; without active design care, codebases become harder to change at an unprecedented rate. Fix: invest in design every day — quiz which modules a change touches before it lands, surface deepening opportunities, and lift the abstraction when the area is unfamiliar.
5. **Unreviewed handoffs and forgotten loose ends** — *"agent ships without a gate, then forgets to clean up."* Agents will happily push code straight from "tests pass" to "PR opened" with no quality gate, and they leave behind a trail (debug logs, "remove once #N" TODOs, sub-issues, feature flags) that nobody remembers to clean up after merge. Fix: a multi-persona review at each artifact boundary, plus an agent-owned cleanup pass triggered by the merge signal.

These are not abstract worries. They are the failure modes the skill suite was reverse-engineered from.

---

## 2. The pipeline shape

The per-feature pipeline:

```
idea / change request
    │
    ▼
[grill-me]            align on what to build; capture terms in CONTEXT.md, trade-offs in ADRs
    │
    ▼
[to-prd]              synthesise a PRD from the conversation; publish to issue tracker
    │
    ▼
[score --rubric prd]  QUALITY GATE — multi-persona PRD review BEFORE slicing.
                      A bad PRD multiplies into many bad issues; this is the
                      highest-leverage upstream catch. Read-only — human edits PRD by hand.
    │
    ▼
[to-issues]           break PRD into tracer-bullet vertical-slice issues
    │
    ▼
[triage]              move each issue through a 5-role state machine
                      (needs-triage → needs-info / ready-for-agent / ready-for-human / wontfix)
    │
    ▼
[tdd]                 red-green-refactor implementation against the agent brief
    │
    ▼
[self-review]         QUALITY GATE — multi-persona review of the local diff
                      BEFORE PR-open. Wraps /score's pre-pr rubric and adds an
                      auto-fix layer. Disagreements recorded in REVIEW-NOTES.md.
    │
    ▼
PR opened
    │
    ▼
[resolve-reviews]     handle inbound review comments (Copilot or human)
    │
    ▼
human merges
    │
    ▼
[post-merge-cleanup]  BACK-BOOKEND — close issue, delete branch, strip "remove once #N"
                      TODOs, drop temp instrumentation, draft CHANGELOG, schedule rollouts.
                      Triggered by the user's "merged" signal.
    │
    ▼
[diagnose]            invoked whenever a bug surfaces, at any stage
```

Periodic hygiene (run weekly-ish, **not** per-feature):

- `/improve-codebase-architecture` — surfaces architectural debt and proposes deepening
- `/zoom-out` — broader context for unfamiliar areas

The pipeline has **two quality gates** (PRD and pre-PR) and a **back-bookend** (post-merge cleanup) that brackets the PR around its merge.

---

## 3. The vocabulary the workflow assumes

These terms are load-bearing — every skill reads them, writes them, or chains on them.

| Term | Definition |
|---|---|
| **CONTEXT.md** | Project domain glossary; canonical terminology that grill-me, tdd, diagnose, improve-codebase-architecture, and score all use to ground language. Lives at repo root or per-context. |
| **ADR** | Architectural Decision Record under `docs/adr/`. Captured only when a trade-off is hard-to-reverse + surprising-without-context + has a real rejected alternative. |
| **Vertical slice** | A thin but complete path through every layer (schema, API, UI, tests) end-to-end. Independently demoable, independently mergeable. |
| **Tracer bullet** | A minimal vertical slice that proves the architecture end-to-end without gold-plating. Each `/to-issues` issue is one. |
| **HITL** | Human-in-the-Loop — issue requires human judgment, design decisions, manual testing, or external access an agent can't perform. Routed to `ready-for-human`. |
| **AFK** | Away-From-Keyboard — issue is fully specified for an agent to implement and merge unattended. Routed to `ready-for-agent`. |
| **Agent brief** | Structured comment posted on a `ready-for-agent` issue. Authoritative spec; the original issue is context, the brief is the contract. |
| **Deep module** | High leverage at the interface — a lot of behaviour behind a small, stable interface. Locality of change, bugs, and knowledge concentrate in one place. The opposite is a *shallow module* whose complexity leaks across seams. |
| **North star** | The root decision in a dependency tree of choices (e.g., "statistically significant context alignment"). Confirmed by the user before grilling proceeds; every later answer is judged against it. |
| **Lossless handoff** | Every decision made during `/grill-me` must survive `/to-prd` without re-clarification or silent loss. North star of the synthesis-not-interview posture. |
| **Posture** | One of `auto` / `draft` / `comment-only`. Shared vocabulary across `/self-review`, `/resolve-reviews`, `/post-merge-cleanup`. Explained in §6. |
| **Classification triad** | `agree-and-fix` / `disagree-and-justify` / `unsure-and-ask-user` (or `agree-and-act` for inbound reviews). Explained in §6. |
| **REVIEW-NOTES.md** | File committed alongside a PR recording deliberate disagreements with reviewer suggestions. Each entry cites a grounding source (ADR-NNNN, CONTEXT.md term, prior rejection, existing pattern). |
| **Grounding sources** | The four sources every disagreement must cite: `CONTEXT.md`, ADRs, existing code patterns, and `prior-rejected-suggestions.md`. Prevents "I disagree" handwaving. |

---

## 4. The skill catalog

Each entry: trigger, inputs, outputs, mechanism, hand-off, and explicit boundaries.

### 4.1 `/setup-workflow` — bootstrap a repo's configuration

- **Trigger:** Onboarding a new repo, or reconfiguring an existing one.
- **Inputs:** Current repo state (git remote, existing CLAUDE.md/AGENTS.md, CONTEXT.md, docs/adr/, .scratch/).
- **Outputs:** `## Agent skills` block in CLAUDE.md/AGENTS.md; `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md`, `docs/agents/domain.md`. Optional posture configs.
- **Mechanism:** Non-destructive detection → guided per-section questionnaire (every decision prefaced with *Why this matters*) → draft review → write. Idempotent reruns; manual edits require explicit override.
- **Hand-off:** Without these config files, every downstream skill runs blind.
- **Does NOT solve:** Tracker autodetection (asks GitHub/GitLab/local-markdown/Other). Multi-repo monorepos beyond per-context configs. PR-bookending postures on first run — those are written lazily.

### 4.2 `/grill-me` — stress-test a plan before implementation

- **Trigger:** "Grill me", "poke holes", "stress-test this", "what am I missing".
- **Inputs:** Conversation context (user's plan); optional CONTEXT.md and ADRs.
- **Outputs:** Resolved terms appended to CONTEXT.md (only if the repo already has one); ADRs (only when the trade-off meets all three criteria above); a conversation artifact summarising decisions and deferred items.
- **Mechanism:** Confirm the **north star** first. Walk a dependency tree of decisions one at a time, surfacing ambiguity along five axes — *terminology, scope, edge cases, trade-offs, code reality*. Press once on vague answers; if still vague, mark deferred and move on. Stop when answers stop changing understanding, all axes have been walked once, or the user signals closure.
- **Hand-off:** Produces an aligned plan that `/to-prd` can synthesise into a PRD without re-interviewing.
- **Does NOT solve:** Aesthetics (naming, formatting, file layout). Hand-waving (won't accept it; presses once, then defers). Premature ADR proposals (decision must be *made*, not just discussed). Diminishing-returns spirals (three follow-ups on one point with no new learning ⇒ stop).

### 4.3 `/to-prd` — synthesise alignment into a published spec

- **Trigger:** "Create a PRD from this conversation"; "publish the aligned plan."
- **Inputs:** Conversation history (typically post-grill-me); `docs/agents/issue-tracker.md`; CONTEXT.md and ADRs.
- **Outputs:** PRD published to the tracker with `needs-triage`. Recommends `/score --rubric prd` before slicing.
- **Mechanism:** *Synthesise, do not interview.* Read the conversation once and extract Problem → Solution → User Stories → Implementation Decisions → Testing Decisions → Out of Scope → Further Notes (honest record of unsettled items). Surface gaps as known unknowns under "Further Notes," not as re-interview prompts.
- **Hand-off:** PRD is the single authoritative spec for `/to-issues` to slice from.
- **Does NOT solve:** Re-grilling. If conversation context is thin, signals to run `/grill-me` first. Lossy synthesis: rejects Problem=Solution conflation, generic actors, undecided trade-offs, empty Out-of-Scope.

### 4.4 `/score --rubric prd` — PRD quality gate

- **Trigger:** Before slicing the PRD into issues. Run on the tracker reference returned by `/to-prd`.
- **Inputs:** PRD text; `rubrics/prd.md`.
- **Outputs:** Read-only ledger: weighted score /10, per-persona breakdown, applied/deferred/rejected items.
- **Mechanism:** See §5 — the dialogue-validated multi-persona review.
- **Hand-off:** **Read-only.** The human iterates the PRD by hand based on the ledger. This is deliberate — running an action layer at the PRD boundary would let the agent rewrite spec text without human authorship, which corrupts the lossless-handoff invariant.
- **Does NOT solve:** Editing the PRD. Deciding what to ship. Catching every defect — only what its personas know to look for.

### 4.5 `/to-issues` — break the PRD into independent vertical slices

- **Trigger:** "Convert PRD into issues"; "break into vertical slices."
- **Inputs:** PRD reference; `docs/agents/issue-tracker.md`; CONTEXT.md, ADRs, codebase.
- **Outputs:** Tracer-bullet vertical-slice issues, each labelled HITL or AFK, each tagged `needs-triage`, published in dependency order so blockers exist before dependents reference them.
- **Mechanism:** Cut tracer-bullet vertical slices (every layer, end-to-end, narrow but complete). Quiz the user on granularity, dependencies, HITL vs AFK. Iterate until approved. Publish in dependency order.
- **Hand-off:** Each issue is independently grabbable — no "see the PRD" footnotes; acceptance criteria are self-contained.
- **Does NOT solve:** Horizontal slices ("schema first, then API, then UI" is rejected and corrected to thin vertical paths). Cycles (flagged as a design issue, sent back to the user). Pure data migrations (proposed as a single slice with migration + verification, not vertically sliced).

### 4.6 `/triage` — route issues through the 5-role state machine

- **Trigger:** "What needs attention?" / "look at #42" / "move #42 to ready-for-agent."
- **Inputs:** Unlabeled or previously-labelled issues; prior triage notes; the canonical→repo-specific label map in `docs/agents/triage-labels.md`; an `.out-of-scope/*.md` knowledge base for deduplication.
- **Outputs:** Issues transitioned through the state machine. **Agent briefs** posted as comments on `ready-for-agent` issues. Triage notes on `needs-info`. Files appended to `.out-of-scope/` for rejected enhancements.
- **Mechanism:** Gather context → recommend category (`bug` or `enhancement`) and state → reproduce (bugs) or grill (if needed) → post the right artifact (brief / notes / wontfix-with-explanation).
- **Hand-off:** `/tdd` consumes the agent brief. `/dispatch` consumes a set of `ready-for-agent` issues.
- **Does NOT solve:** Creating new issues (use `/to-issues`). Implementing code. Assuming label strings are constant (requires the mapping file).

The five canonical roles:

| Role | Meaning | Next actor |
|---|---|---|
| `needs-triage` | Has anyone evaluated this yet? | Maintainer reviews scope/clarity |
| `needs-info` | Can we act without more from the reporter? | Reporter; loops back to `needs-triage` once info is in |
| `ready-for-agent` | Spec is complete; an AFK agent can implement | `/tdd` picks up |
| `ready-for-human` | Needs human judgment / design / external access | Human implementer |
| `wontfix` | We will never act on this | Closed; enhancement reasons land in `.out-of-scope/` |

Orthogonal category labels: `bug` or `enhancement` (one per issue).

### 4.7 The agent-brief contract

The brief is the authoritative spec. Required structure:

```markdown
## Agent Brief

**Category:** bug / enhancement
**Summary:** one-line what needs to happen

**Current behavior:**
[bugs: broken behaviour; enhancements: status quo]

**Desired behavior:**
[what should happen, with edge cases and error conditions]

**Key interfaces:**
- `TypeName` — what changes and why
- `functionName()` return type — current vs desired
- Config shape — new options needed

**Acceptance criteria:**
- [ ] Specific, testable criterion 1
- [ ] Specific, testable criterion 2

**Out of scope:**
- Thing that should NOT be changed
- Adjacent feature that is separate
```

Durability rules: describe **interfaces and behavioural contracts**, not file paths or line numbers (they go stale). Describe **what** the system should do, not **how** to implement it. Every criterion must be independently testable. If `/tdd` finds the brief vague, it **refuses and escalates back to `/triage`** — no guessing.

### 4.8 `/tdd` — brief → tests → implementation → PR

- **Trigger:** A `ready-for-agent` issue with a posted brief. Run directly for one issue or via `/dispatch` in parallel.
- **Inputs:** The issue, the brief, `docs/agents/issue-tracker.md`, CONTEXT.md.
- **Outputs:** A feature branch with tests + implementation; optional `REVIEW-NOTES.md` from `/self-review`; PR opened; issue commented with acceptance-criteria coverage. Or: failure escalated back to `/triage`.
- **Mechanism:** RED → GREEN → REFACTOR, vertical not horizontal. Map each acceptance criterion to ≥1 test. Write one test, write minimal code to pass, repeat. Refactor only when GREEN.
- **Hand-off:** `/self-review` runs as the pre-PR gate.
- **Does NOT solve:** Vague briefs (refuses, escalates). Horizontal slicing ("all tests first, then code"). Merging the branch. AFK runs against a polluted working tree (parallel-safety guard).

### 4.9 `/dispatch` — multi-issue orchestration

- **Trigger:** "Ship a PRD's worth of work" or sweep `ready-for-agent` issues in parallel.
- **Inputs:** PRD ref, explicit issue list, or filter (`label:ready-for-agent`); dependency graph from "Blocked by" fields; an explicit concurrency cap (no safe default).
- **Outputs:** Parallel `/tdd` subagents in git-worktree isolation; PRs in dependency order; resumable state in `.scratch/dispatch-<run-id>/state.json`; a final report (Completed / Failed / HITL-blocked / Skipped).
- **Mechanism:** Pre-flight (validate briefs, acyclic graph, permissions, concurrency) → graph leaves dispatch loop → each subagent runs `/tdd` then `/self-review --posture auto` (default) then opens a PR → optional dependency-ordered merge.
- **Hand-off:** Opens PRs but **does not auto-merge by default**. The session that built each PR is the right one to run `/post-merge-cleanup` later, because it has the cleanup-trail context.
- **Does NOT solve:** Single-issue work (use `/tdd` directly). Predictive conflict detection (lets them race; recovers reactively). Unlimited parallelism (concurrency must be set).

### 4.10 `/score` — universal multi-persona review

- **Trigger:** On demand: `/score <artifact>` or `/score --rubric <name>`. No workflow auto-hook; explicitly invoked at gates.
- **Inputs:** Artifact (path / PR / staged commit); rubric file from `rubrics/` (artifact types include `prd`, `pre-pr`, `pr`, `staged-commit`, `skill`); optional prior-rejected-critiques ledger.
- **Outputs:** Structured ledger persisted to `.scratch/score/<artifact-slug>-<timestamp>.md`; weighted score /10; per-persona breakdown; applied / deferred / rejected items; optional JSON appendix for CI.
- **Mechanism:** Detect type → load rubric → spawn 3–7 expert personas in parallel, each grounded in published best-practice docs → each scores independently and proposes critiques → **the orchestrator engages each persona in per-critique dialogue**, pushing back on speculative items so the persona either defends the critique with evidence or revises/concedes → synthesise weighted total. **Dialogue is non-optional.** This is the move that prevents speculative pre-engineering and "every persona finds something so we change everything."
- **Hand-off:** The ledger is consumed by `/self-review` (pre-pr rubric) and `/resolve-reviews` (pr rubric).
- **Does NOT solve:** Acting on findings (no action layer). Multi-rubric matches without disambiguation. Silent weight normalisation (rejects malformed rubrics). Persona timeouts >10 min (excludes that persona, re-weights, notes in ledger).

### 4.11 `/self-review` — pre-PR action layer

- **Trigger:** Before `git push` and PR open. Sits between `/tdd` finishing and the PR being created.
- **Inputs:** Current branch (refuses `main`/`master`); clean tree (for `auto`/`draft`); posture (asked at start if not configured); delegates to `/score --rubric pre-pr`.
- **Outputs:** Posture-dependent — see §6. New commits + `REVIEW-NOTES.md` for `auto`/`draft`; ledger only for `comment-only`.
- **Mechanism:** Run `/score --rubric pre-pr` → classify each finding into the **classification triad** → act per posture. Agree fixes apply locally; tests run before each fix; failed fixes abort that fix only. Disagree decisions append to `REVIEW-NOTES.md` with grounding-source citation.
- **Hand-off:** Branch is PR-ready; `REVIEW-NOTES.md` documents deliberate decisions for the human reviewer.
- **Does NOT solve:** Pushing or opening the PR. Committing to `main`. Applying fixes that fail tests. Running on a dirty tree (except `comment-only`).

### 4.12 `/resolve-reviews` — inbound review-comment action layer

- **Trigger:** After Copilot/human posts review comments on a PR. Sits between PR-open and merge.
- **Inputs:** PR reference; posture; the four grounding sources (CONTEXT.md, ADRs, existing patterns, `prior-rejected-suggestions.md`); push access.
- **Outputs:** Per-comment action — see §6 classification triad. Updated `prior-rejected-suggestions.md`. Bounded re-review loop (max 3 iterations).
- **Mechanism:** Fetch comments → classify each against grounding sources → act per posture. Agree-and-act commits the fix, posts a thread comment, and **resolves the thread**. Disagree-and-justify posts a denial citing a grounding source and **leaves the thread open** for human review. Unsure surfaces to user.
- **Hand-off:** All actionable comments are either resolved or have a grounded denial; merge gate is clear.
- **Does NOT solve:** Rubber-stamping. Ungrounded denials. Unbounded loops. Resolving threads on the disagree side. Push conflicts (aborts push, surfaces for manual rebase).

### 4.13 `/post-merge-cleanup` — back-bookend

- **Trigger:** User signals merge: `/post-merge-cleanup [PR]` or "merged #142." Sits after merge, before the next feature.
- **Inputs:** PR reference; posture; PR diff, issue body, **agent session memory** (which TODOs *I* tagged, which sub-issues *I* spawned, which `console.log`s *I* added); grounding sources.
- **Outputs:** Two columns —
  - **Mechanical (agent-owned):** close issue, delete branch, strip `remove once #N` TODOs, remove debug instrumentation the session added, draft CHANGELOG, close sub-issues, schedule rollout follow-ups.
  - **Judgment (surfaced to human):** feature-flag rollout, stakeholder notification, CONTEXT.md candidates, ADR candidates, `REVIEW-NOTES.md` disposition.
- **Mechanism:** Validate merge → gather context (diff + issue + session memory + grounding) → build dual ledger → act per posture. Mechanical tasks are reversible and idempotent (each step checks done-state and skips).
- **Hand-off:** Closes the loop; next feature can start cleanly.
- **Does NOT solve:** Sending stakeholder messages without explicit per-message confirm. Stripping instrumentation the session didn't add (falls back to surface-for-confirm; the cold-context fallback). Auto-writing CONTEXT.md or ADRs (flags candidates for human editorial). Committing to `main` if the repo enforces PR-only merges (aborts and routes to a PR).

### 4.14 `/diagnose` — six-phase bug-hunting loop

- **Trigger:** Bug reported, performance regression, "broken/throwing/failing."
- **Inputs:** Reproducible environment or captured artifacts (HAR, logs, recordings).
- **Outputs:** Fixed bug; regression test at the **correct seam**; post-mortem with the root hypothesis; architectural flags handed to `/improve-codebase-architecture` if missing test seams or coupling enabled the bug.
- **Mechanism:** Six phases. **Phase 1: build a fast, deterministic feedback loop** (this is the skill itself; everything after is mechanical). 2: reproduce. 3: generate 3–5 ranked, falsifiable hypotheses. 4: instrument to test them — debugger > targeted logs > never "log everything." 5: write the regression test at the correct seam *before* fixing. 6: clean up and ask "what would have prevented this?" — escalating architectural debt.
- **Does NOT solve:** Hypothesising without a reproducible loop. Mid-diagnosis architectural redesign (only flags). Forcing tests into the wrong seam.

### 4.15 `/improve-codebase-architecture` — periodic deepening pass

- **Trigger:** "Refactor this area"; "make this more testable / AI-navigable"; periodic hygiene.
- **Inputs:** CONTEXT.md, ADRs, codebase exploration via Explore.
- **Outputs:** Ranked list of deepening candidates → grilling conversation on the chosen one → updated CONTEXT.md (new domain terms) → optional ADR when rejecting a candidate → alternative interface designs.
- **Mechanism:** Three phases — explore organically and apply the deletion test to suspect shallow modules; present candidates (problem, solution, locality/leverage benefits); grilling loop that walks the design tree and refines interfaces.
- **Does NOT solve:** Proposing without domain context. Re-litigating ADRs that aren't in real friction. Designing interfaces in isolation.

### 4.16 `/zoom-out` — abstraction lift

- **Trigger:** "I don't know this area"; "how does this fit?"
- **Inputs:** Current location or module; CONTEXT.md.
- **Outputs:** A map of relevant modules and their callers, phrased in domain language.
- **Mechanism:** Single phase — deliver context layer-by-layer without coding.
- **Does NOT solve:** Internals. Proposed changes.

---

## 5. The dialogue-validated multi-persona review (the heart of `/score`)

`/score` is the move that distinguishes this workflow from "ask the model to review the diff." Single-pass review is the failure mode `/score` exists to prevent. The mechanism:

1. **Multiple personas in parallel.** 3–7 expert lenses (e.g., security, performance, maintainability, API ergonomics) each scoped to the artifact type by its rubric.
2. **Each persona is grounded in published sources.** Not "play the role of a security engineer" — "you are a security engineer who has read these specific OWASP / IETF / project sources, here they are."
3. **Each persona scores and proposes critiques independently.**
4. **Per-critique dialogue.** The orchestrator pushes back on each critique. The persona must defend with evidence or revise/concede. **This is the non-optional move.** It retires speculative critiques that wouldn't survive a real code review.
5. **Weighted synthesis.** Scores combine per the rubric weights. Speculative items that didn't survive dialogue are excluded; deferred items are surfaced as deferred.

Why dialogue matters: without it, every persona finds something, and the agent dutifully changes everything. The artifact becomes worse — the worst kind of false-positive review. With dialogue, only the critiques that withstand pushback drive change.

---

## 6. The posture model and the classification triad (PR-bookending suite)

Three skills — `/self-review`, `/resolve-reviews`, `/post-merge-cleanup` — share **identical** posture vocabulary. A junior dev learns one mental model that brackets the entire PR lifecycle.

### Postures

| Posture | Behaviour | When to use | Safety net |
|---|---|---|---|
| `auto` | Apply / commit / push without per-item confirmation. | Routine work, high trust, branch protection + CI in place. | Commits land on feature branches, never `main`. Each fix runs tests first; failures abort that fix only. |
| `draft` | Show the full proposed batch in a unified view; one confirmation for the whole batch. | High-blast-radius areas (auth, payments, migrations); learning the skill. **Default for new users.** | User reviews everything before any commit/push lands. |
| `comment-only` | Never commit, never push. Produce a ledger; user actions manually. | Audit trails; dirty tree; want classification only; want authority to stay with a human. | Purely advisory — no file changes. |

### Classification triad

Every finding (a `/score` action item, an inbound review comment, a cleanup task) is sorted into one of three buckets:

- **`agree-and-fix`** (or `agree-and-act` for `/resolve-reviews`) → apply the fix as a commit (`/self-review`), commit + post thread comment + resolve thread (`/resolve-reviews`), or execute the mechanical task (`/post-merge-cleanup`). Rationale lives in the commit message or task ledger.
- **`disagree-and-justify`** → record the deliberate decision **with a citation to a grounding source** (ADR-NNNN, CONTEXT.md term, prior-rejection #N, project pattern). For `/self-review`, this lands in `REVIEW-NOTES.md` (committed alongside the PR). For `/resolve-reviews`, this is a denial comment posted on the thread, which is **left open** for human review. For `/post-merge-cleanup`, this lives in the judgment column.
- **`unsure-and-ask-user`** → surface the trade-off; wait for the user; act per their answer.

### Why grounded denials matter

A denial that says "I disagree" invites debate without giving the reviewer anything to respond to. Citing a source ("contradicts ADR-0007", "uses canonical CONTEXT.md term `customer_id`") lets the human accept the citation or argue with the *source*, not with the skill's opinion. The grounding-source spine — CONTEXT.md, ADRs, existing patterns, `prior-rejected-suggestions.md` — is the durable record that prevents the same critique from resurfacing on the next PR.

---

## 7. Why this is best practice — design rationale

For each major design choice, the rationale that justifies it:

- **Two quality gates, not one.** A bad PRD multiplies into many bad issues; a bad pre-PR diff multiplies into reviewer churn. The PRD gate is upstream-leverage (highest blast radius); the pre-PR gate is downstream-cleanup (catches what TDD doesn't see — security, debug artifacts, scope mixing). Running both at the same artifact would be redundant; placing them at different artifacts catches different defects.
- **PRD gate is read-only; pre-PR gate is action-able.** A PRD is human-authored prose; an action layer would corrupt the lossless-handoff invariant by letting the agent rewrite spec text. A diff is machine-readable code; an action layer is appropriate because fixes are diff-shaped and reversible. *One tool per gate, picked because the artifact's lifecycle differs.*
- **Vertical slices instead of horizontal layers.** Horizontal slicing ("schema first, then API, then UI") produces work that's individually unreviewable and individually un-mergeable; integration risk piles up at the end. Vertical slices are independently demoable, reviewable, mergeable. They also force tracer-bullet thinking — proving the architecture end-to-end before gold-plating any layer.
- **Brief-as-contract, not issue-as-contract.** Issues are messy human prose. Briefs are structured, interface-described, behaviour-contracted, criterion-listed. The brief survives codebase refactors because it doesn't reference file paths or line numbers — only interfaces and behaviour. `/tdd` reading the brief instead of the issue is what makes briefs durable specs.
- **Refuse vague briefs.** If `/tdd` guesses past a vague brief, the bug is detected at PR review (expensive). If `/tdd` refuses and escalates, the bug is detected at triage (cheap). Refusing is the right move.
- **Dialogue-validated multi-persona review.** Single-persona review is shallow; multi-persona without dialogue produces "every persona finds something" false-positives. Dialogue retires speculative critiques and is the move that distinguishes good review from over-engineering review.
- **Same posture vocabulary across three skills.** A junior dev learns `auto`/`draft`/`comment-only` once and applies it across the PR lifecycle. Predictability across the suite reduces cognitive load.
- **Same classification triad across the same three skills.** Every finding is `agree` / `disagree` / `unsure`. The action and recording surface differs by skill, but the classification is identical, so the user always knows what categories will appear.
- **Grounded denials with citations.** Forces the agent to find a source for every disagreement, which means disagreements are anchored to durable artifacts (ADRs, CONTEXT.md). Reviewers can argue with the source, not the agent's opinion. Prior rejections accumulate in `prior-rejected-suggestions.md` so the same critique doesn't resurface.
- **Agent-owned post-merge cleanup, in the same session.** Reconstructing the cleanup trail from PR metadata alone is lossy — the agent that opened the PR knows which `console.log`s *it* added during diagnose, which sub-issues *it* spawned, which TODOs *it* tagged "remove once #N." That memory disappears once the session ends. So cleanup chains off the merge signal in the same session, before the context evaporates.
- **Mechanical/judgment column split in cleanup.** Mechanical tasks (close issue, delete branch, strip TODOs) are reversible and agent-owned. Judgment tasks (CHANGELOG entry voice, stakeholder notification, ADR candidacy) are editorial and human-owned. Forcing the agent to attempt judgment tasks produces low-quality CHANGELOGs and unwanted notifications; refusing to surface them at all loses the work.
- **Hygiene skills outside the per-feature pipeline.** `/improve-codebase-architecture` and `/zoom-out` run weekly-ish, not per-feature. Forcing them into every PR creates decision fatigue (deepening candidates accumulate as half-considered noise) and clutters PR narratives. Skipping them indefinitely lets architectural debt compound until the codebase becomes AI-hostile.
- **`/diagnose` Phase 1 is "build the loop."** Most failed bug hunts fail because the agent hypothesises without a reproducible loop — every theory is unfalsifiable. The skill enforces "no hypotheses until the loop is fast and deterministic." Phase 2-onwards becomes mechanical once Phase 1 lands.

---

## 8. What this workflow does NOT solve

Explicit anti-claims, so you can engage with the workflow honestly:

- **It does not replace good design judgment.** Skills enforce process, not taste. A team that consistently writes shallow modules will write more of them faster.
- **It does not eliminate the need for human review of agent work.** The pre-PR gate catches what its rubric knows to look for; novel failure modes still require human eyes.
- **It does not detect predictive merge conflicts in `/dispatch`.** Parallel slices race; the merge step recovers reactively.
- **It does not handle multi-repo monorepos beyond per-context configs.** Each context configures separately.
- **It does not autodetect issue trackers.** The user picks GitHub / GitLab / local-markdown / Other in `/setup-workflow`.
- **It does not write CONTEXT.md or ADRs unprompted.** Capture only when the repo already has the convention. Cleanup only flags candidates.
- **It does not auto-merge PRs.** `/dispatch` opens PRs and stops at the merge gate by default. Merging is a human decision; the user signals "merged" to trigger cleanup.
- **It does not skip alignment work for "obvious" tasks.** A tasks that *looks* obvious has often hidden ambiguity that grilling surfaces; skipping `/grill-me` is a debt taken on, not a step saved.
- **It does not eliminate the cost of context.** CONTEXT.md, ADRs, briefs, REVIEW-NOTES.md are all artifacts that must be maintained. The trade-off is intentional: a small ongoing maintenance cost prevents large recurring re-explanation costs.
- **It does not enforce posture choices on a per-fix basis within `auto`.** `auto` means "all fixes apply without per-item confirmation"; if a single fix needs scrutiny, drop to `draft`.
- **It does not cover every PR-lifecycle hazard.** Force-pushes, reverts, branch protection bypasses, supply-chain drift — these are outside the skill suite's scope.

---

## 9. Where you (Gemini) come in

The user is bringing this to you because they want a second opinion. Specifically, useful contributions include:

- **Critique the load-bearing claims.** Are the five failure modes the right ones? Is the dialogue-validated review actually distinguishable from a sufficiently capable single-pass review? Is the brief-as-contract durable across the kinds of refactors real teams do?
- **Find the gaps.** What failure mode is not addressed by any skill? Where does a hand-off break under realistic conditions (the PRD-author leaves, the brief drifts from the issue, the merge happens in a different session, etc.)?
- **Compare to alternatives.** How does this compare to RFC-driven workflows (Rust, Kubernetes), to spec-driven dev (Amazon's PRFAQ), to Shape Up (Basecamp), to plain Conventional Commits + ADRs?
- **Stress-test the postures.** When does `auto` posture produce a worse outcome than `comment-only`? When does the classification triad collapse (e.g., a finding that's both "agree on the symptom" and "disagree on the fix")?
- **Probe the cleanup boundary.** Is "agent-owned cleanup in the same session" robust to session interruption? What's the recovery path if the merger isn't the PR-opening session?

When you reply, **be specific.** Quote the section you're engaging with, name the skill, cite the vocabulary. Vague critique is the failure mode the workflow itself was designed to prevent — don't recreate it in your response.

---

## 10. One last note on how this brief was produced

This brief was synthesised from the canonical sources in a `~/.claude/skills/` directory: each skill's `SKILL.md`, plus auxiliary docs (`triage/AGENT-BRIEF.md`, `setup-workflow/WORKFLOW-PRIMER.md`, `score/RUBRIC-FORMAT.md`, the `improve-codebase-architecture` design-language docs). Where this brief and a SKILL.md disagree, the SKILL.md is authoritative — flag the disagreement and ask before acting on the difference.
