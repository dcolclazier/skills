# PRD Rubric

Rubric for scoring a Product Requirements Document — the synthesised spec produced by `/to-prd` and published to the issue tracker. Used at the **upstream artifact-quality gate** of the engineering pipeline: a bad PRD multiplies into many bad issues, so catching gaps here has the highest leverage in the workflow.

## Detection

- **File glob**: `**/PRD-*.md`, `.scratch/**/prd.md`, `.scratch/**/PRD.md`
- **Content marker**: file contains the headings `## Problem Statement`, `## Solution`, `## User Stories` (the canonical `/to-prd` template)
- **Invocation context**: `/score` invoked on a freshly-published PRD issue (passed as a tracker reference like `gh issue view <N>`) where the issue body matches the template
- **Explicit override**: `--rubric prd`

## Best-practice sources

The grounding source for this rubric is the project's own `/to-prd` skill, which documents both the canonical template and the failure modes ("what a lossy PRD looks like"). Personas should treat that file as the contract, not external best-practice URLs.

- `~/.claude/skills/to-prd/SKILL.md` — the PRD contract (template, section purposes, lossy-PRD anti-patterns)
- The repo's `CONTEXT.md` (and `CONTEXT-MAP.md` if multi-context) — domain glossary the PRD must use canonically
- The repo's `docs/adr/` — architectural decisions the PRD must respect

External references the personas may consult for vocabulary:
- https://www.atlassian.com/agile/product-management/requirements
- https://www.productplan.com/glossary/product-requirements-document/

## Personas

### problem-statement

- **Lens**: is the Problem Statement framed *from the user's perspective* and not as a thinly-disguised solution? "The API is slow → add caching" is the canonical anti-pattern: it conflates symptom and remedy and loses the user's actual problem. A good Problem Statement names the user, the situation, and the friction — not the fix.
- **Sources**: `~/.claude/skills/to-prd/SKILL.md` (Problem Statement section + lossy-PRD examples)
- **Weight**: 0.20

### scope-clarity

- **Lens**: is "Out of Scope" populated with real exclusions? An empty Out of Scope means the implementer treats *everything* as in-scope and gold-plates. Are deferred items explicit ("X deferred to next iteration") or implicit (silently dropped)? Are constraints from grilling preserved (timeline, must-not-touch areas)?
- **Sources**: `~/.claude/skills/to-prd/SKILL.md` (Out of Scope section)
- **Weight**: 0.15

### slice-readiness

- **Lens**: are User Stories shaped such that `/to-issues` can produce vertical slices that each cut through every layer (schema → API → UI → tests)? Sparse stories produce a sparse slice graph and downstream gaps. Stories that conflate actor and benefit ("As a user, I want caching, so that performance is better") are unsliceable — generic actor, benefit just restates the feature. Each story should have a *specific* actor, a *concrete* feature, and a *user-observable* benefit.
- **Sources**: `~/.claude/skills/to-prd/SKILL.md` (User Stories section), `~/.claude/skills/to-issues/SKILL.md` if present
- **Weight**: 0.20

### decision-traceability

- **Lens**: does Implementation Decisions capture *what was rejected* alongside what was chosen? "We'll use Redis" without recording the rejected alternatives (Memcached? in-memory? CDN?) means the team re-litigates from scratch when implementation hits a wall. ADR-worthy decisions (hard to reverse + surprising + real trade-off) should be flagged for capture in `docs/adr/`. Are the load-bearing technical alignments from `/grill-me` present, or did they evaporate in synthesis?
- **Sources**: `~/.claude/skills/to-prd/SKILL.md` (Implementation Decisions section + lossy-PRD example), `~/.claude/skills/grill-me/ADR-FORMAT.md` if present
- **Weight**: 0.15

### testing-anchor

- **Lens**: does Testing Decisions give `/tdd` a real anchor for what "good" looks like? Or is it a hand-wave ("we'll add tests")? Specifically: which behaviours will be tested through public interfaces? What's the prior art (similar tests already in the codebase)? Without this, the red-green loop has no contract.
- **Sources**: `~/.claude/skills/to-prd/SKILL.md` (Testing Decisions section), `~/.claude/skills/tdd/SKILL.md`
- **Weight**: 0.10

### vocabulary-alignment

- **Lens**: does the PRD use the canonical terms from `CONTEXT.md`? Drift from canonical vocabulary at the PRD layer cascades into `/to-issues`, `/triage`, and `/tdd` — every downstream slice inherits the wrong word. If the project uses `Customer` and the PRD says `User`, that's a real flaw, not a style preference. If `CONTEXT.md` doesn't exist, mark as N/A and abstain from this critique.
- **Sources**: the repo's `CONTEXT.md` / `CONTEXT-MAP.md`
- **Weight**: 0.10

### gap-honesty

- **Lens**: does "Further Notes" surface real unresolved questions, or is it suspiciously empty? A PRD with zero acknowledged gaps after a real grilling session is almost always a PRD that *swallowed* gaps rather than resolved them. If the upstream `/grill-me` was incomplete, that should show up here as honest uncertainty — not as silence. Conversely, gaps so large they cascade into `/to-issues` should trigger a recommendation to grill more before slicing.
- **Sources**: `~/.claude/skills/to-prd/SKILL.md` (Further Notes section), `~/.claude/skills/grill-me/SKILL.md` (when to stop)
- **Weight**: 0.10

(Total: 1.00)

## Anti-patterns

The orchestrator should reject these critique patterns during dialogue:

- **Demanding more user stories** when the existing set already covers the user's stated outcomes — quantity is not quality, and PRDs aren't ceremonies for story counts
- **Bikeshedding on PRD section ordering** — the `/to-prd` template fixes the order; reordering critiques are noise
- **Suggesting the PRD include code snippets or file paths** — `/to-prd` explicitly excludes these because they go stale; flagging their absence is contradicting the contract
- **Demanding ADR creation for every Implementation Decision** — only hard-to-reverse + surprising + real-trade-off decisions warrant ADRs; over-applying creates archive bloat
- **Inventing scope expansions** — "you should also handle X" when X wasn't part of the grilled plan is scope-creep dressed as critique
- **Re-litigating decisions visible in the rejected-critiques ledger** — if a prior `/score` run rejected a critique with reasoning, don't re-suggest it
- **Demanding business-context the PRD's audience already has** — PRDs ship inside a project; not every word of context needs to be re-stated

## Persona dispatch notes

Each persona should receive:

- The full PRD content (file or issue body)
- The repo's `CONTEXT.md` / `CONTEXT-MAP.md` if present
- The repo's `docs/adr/` listing
- The relevant section of `~/.claude/skills/to-prd/SKILL.md` (the contract for that persona's lens)
- The rubric's anti-patterns
- Any `prior_rejected_critiques` from earlier runs

For very large PRDs (>1000 words): tell each persona to focus their critique on the highest-leverage gaps within their lens, not exhaustively cover every paragraph.

## When this rubric runs

`/score --rubric prd <path-or-issue-ref>` is the canonical invocation, used at the upstream gate of the per-feature pipeline:

```
grill-me → to-prd → /score (this rubric)  ← QUALITY GATE
                      ↓
                   to-issues (only if score is acceptable)
```

The output is **read-only** — `/score` produces a ledger; the human iterates on the PRD by hand. Unlike `/self-review` (which uses `pre-pr` rubric and includes an auto-fix layer), there is no automation pass on the PRD: the lifecycle is human-iterated, so applying fixes mechanically would skip the editorial judgment that a PRD requires.

If the user wants `/score` to *also* edit the PRD issue body, they should explicitly invoke a separate edit step — this rubric and skill don't do that automatically.
