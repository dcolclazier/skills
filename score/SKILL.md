---
name: score
description: Universal artifact review/validation/red-team/scoring through weighted multi-perspective critique. Detects artifact type (skill, PR, staged commit, etc.), loads the matching rubric from `rubrics/<type>.md`, dispatches sub-agent personas in parallel (each grounded in published best-practice sources for that artifact type), engages each persona in consensus dialogue to retire speculative critiques, then synthesises a weighted score and structured action ledger. Unlike single-perspective peer skills (`/review`, `/security-review`, `/simplify`), `/score` runs multiple expert lenses in parallel and engages each in dialogue before synthesising — favour those peers for narrow, fast feedback; favour `/score` when multi-angle assessment of the same artifact is the value. Use when the user wants to score, review, validate, red-team, or critically assess any artifact — skill files, PRs, staged commits, code, infra, etc. Dialogue is non-optional — single-pass scoring without engagement is the failure mode this skill exists to prevent.
argument-hint: "[artifact path or reference] [optional: --rubric <name>]"
---

# Score

Universal artifact validation through weighted, consensus-validated multi-perspective critique.

## North star

*Honest, dialogue-validated assessment that drives iterative improvement.* The score is a summary statistic; the critiques are the value; the consensus loop ensures no critique is acted on or rejected without being engaged. Default output is a structured ledger of `[applied / deferred / rejected]` action items, weighted score per persona, and a synthesised total — not just a number.

## Architecture

`/score` is a thin orchestrator. Per-artifact-type detail lives in **rubrics**:

```
~/.claude/skills/score/
├── SKILL.md           ← this file: universal orchestration logic
├── RUBRIC-FORMAT.md   ← spec for writing new rubrics
└── rubrics/
    ├── skill.md       ← Anthropic skill best practices
    ├── pr.md          ← code review best practices
    └── staged-commit.md  ← commit hygiene + diff cohesion
```

A rubric specifies: **detection heuristic** (when this rubric applies), **persona definitions** (each with a lens, best-practice sources, and weight), and **anti-patterns** the orchestrator should reject in dialogue without ceremony. Add new rubrics by dropping a file into `rubrics/` — see [RUBRIC-FORMAT.md](RUBRIC-FORMAT.md).

## Process

### 1. Detect artifact type

Inputs you might receive:

- A file path (`/path/to/SKILL.md`, `/path/to/some-code.py`)
- A PR reference (`#42`, GitHub URL, or a `gh pr view 42` invocation context)
- A staged-changes invocation (no path; uses `git diff --staged`)
- An explicit rubric override (`--rubric skill`, `--rubric pr`, etc.)

For each rubric in `rubrics/`, read its "Detection" section; pick the first rubric whose detection rule matches. If multiple match or none match, ask:

> "I see {artifact context}. I think this is a {best-guess} — should I use the `{best-guess}` rubric, or specify another? Available: {list rubrics}."

If the user passed `--rubric <name>`, skip detection and use that rubric. If no rubric matches and the user can't disambiguate, **stop and surface** — don't try to score with a generic rubric. Better to fail clearly than score against the wrong yardstick.

*Why ask rather than pick the first match:* different rubrics measure different quality dimensions (a `pr` rubric weights security 0.20; a `skill` rubric doesn't have security at all). Picking the wrong yardstick produces confidently-wrong feedback — exactly what `/score` exists to prevent.

### 2. Load the rubric

Read `rubrics/<type>.md`. Extract:

- **Personas** — name, lens (focused charge), best-practice sources, weight
- **Anti-patterns** — critiques the orchestrator should reject during dialogue without ceremony
- **Validation** — weights must sum to 1.0; if not, the rubric is malformed; refuse to load and surface. *Why refuse rather than normalise silently:* weights are the contract between orchestrator and rubric author. Silent normalisation hides authoring mistakes and makes rubric drift impossible to debug across runs. Surface the bug; let the human fix it.

### 3. Dispatch personas in parallel

For each persona in the rubric, spawn an `Agent` (subagent_type: `claude-code-guide` preferred for documentation grounding; `general-purpose` acceptable). Each persona's prompt must be self-contained and include:

- The artifact path / content / reference
- The persona's **lens** (e.g. "score this skill on machine-readability and structure only")
- Cite-able best-practice sources to ground in
- Required output: score `/10`, paragraph justification grounded in the cited docs, top critiques to push to `N+1`
- The rubric's anti-patterns (so the persona doesn't suggest critiques the author has already explicitly rejected)
- Any **prior rejected critiques** for this artifact (see step 7)

Mark each Agent as `run_in_background: true` so personas run concurrently. Wait for all to complete (the harness notifies on each).

Persona count is usually 3–7 per rubric; no concurrency cap unless the rubric defines one explicitly. (Sub-agent rate limits or the user's parallelism preference can be surfaced via `--concurrency N` if needed.)

### 4. Per-persona dialogue (consensus loop)

For each persona's returned scorecard:

- **Categorise** their top critiques into **real / debatable / push back**.
- For debatable and push-back items, **the orchestrator (you) sends a `SendMessage` to that persona** with this structure:

  > Quote the specific critique you're pushing back on. Explain *why* (anti-pattern flagged in the rubric? speculative pre-engineering? already addressed at SKILL.md:NN?). Ask the persona to either stand by their critique with reasoning or revise.

- **Wait** for the persona's response; settle one of:
  - **Concede** — persona retracts; revise score
  - **Recalibrate** — partial concession; revise score partially
  - **Stand by** — persona defends; keep critique; record their reasoning

The dialogue is **non-optional**, even under time pressure — it's where speculative critiques get retired and real ones get sharpened.

*Why the mechanism works:* a fresh sub-agent is grounded in best-practice docs but lacks context about the artifact's intentional design choices. Without dialogue, those choices look like gaps. With dialogue, the orchestrator can show the persona that "extracting templates to companion files" is an anti-pattern flagged in the rubric, and the persona recalibrates rather than re-suggesting it on every run. *This is the failure mode `/score` exists to prevent.*

If a persona's score shifts during dialogue, record both before/after so the trajectory is visible in the ledger.

### 5. Synthesise the weighted score

For each persona: `weighted_contribution = consensus_score × weight`

Final: `weighted_total = sum(weighted_contributions)`

Weights come from the rubric. **Don't normalise silently** — if weights don't sum to 1.0, that's a rubric bug surfaced in step 2.

### 6. Emit the action ledger

Output a structured markdown report:

```markdown
# Score: <artifact-id> — <weighted_total>/10

**Rubric:** <type>
**Scored at:** <timestamp>
**Trajectory:** v1 7.2 → v2 8.5 → **v3 8.7**  (if priors exist)

## Per-persona breakdown

| Persona | Lens | Raw | Weight | Weighted |
|---|---|---|---|---|
| frontmatter | name, description, triggers | 8.5 | 0.10 | 0.85 |
| structure | headers, decision trees | 9.0 | 0.15 | 1.35 |
| ... | ... | ... | ... | ... |
| **Total** | | | **1.00** | **8.7** |

## Action items (top to push to N+1)

1. <highest-impact change>
2. <next>
3. <next>

## Critiques applied this run

- [persona] critique → action taken
- ...

## Critiques deferred

- [persona] critique → why deferred (e.g. "scope of next iteration")

## Critiques rejected (preserved for future scorers)

- [persona] critique → reasoning for rejection (so v4's persona doesn't re-suggest)
```

Include a structured JSON appendix for tooling consumption (CI gates, dashboards) if the rubric or invocation requests it.

### 7. Persist for future scorings

Write the ledger to `.scratch/score/<artifact-slug>-<timestamp>.md` (or per the user's repo conventions). On re-score:

- Read the most recent prior ledger if it exists
- Pass `prior_rejected_critiques` to each persona in step 3 so they don't re-suggest them
- Show the trajectory in the new ledger header

This is what makes `/score` an *improvement loop* rather than a one-shot grading tool — rejected critiques stay rejected unless the artifact changes in a way that revives them.

## Edge cases

- **No matching rubric** — surface; don't pick a generic. Better to fail clearly than score against the wrong yardstick.
- **Persona spawns but never reports** — timeout 10 min per persona. Mark that lens as "no signal," **exclude from synthesis and re-weight the remaining personas to sum to 1.0** (this is the only case where re-weighting is acceptable; note it in the ledger).
- **Persona returns malformed scorecard** — ask the agent to revise once via `SendMessage`. If still malformed, exclude from synthesis with a note in the ledger.
- **Stalled dialogue** — persona neither concedes nor stands by (deflects, asks for more info, returns unintelligible response). Mark as `irreconcilable`; record both positions verbatim in the ledger; proceed to synthesis without revising the score. Don't loop indefinitely.
- **Ledger write fails** — if `.scratch/score/` doesn't exist, create it. If the write still fails (permissions, disk full), output the ledger to stdout and surface the file-write failure to the user. Don't silently swallow the failure.
- **`prior_rejected_critiques` schema** — pass to each persona in their prompt as a YAML list: `[{persona: <name>, critique: <text>, rationale: <why-rejected>}, ...]`. Personas should treat this list as "do not re-suggest" (rather than re-grading the same critiques).
- **Weights don't sum to 1.0** — rubric is malformed; refuse to load. Don't normalize. (Single exception: timeout-induced re-weighting in the persona-no-report case above. Note in ledger when invoked.)
- **All personas concede every critique during dialogue** — possible but suspicious. Surface in the ledger ("all personas conceded all critiques — was the artifact already at ceiling, or was dialogue too aggressive?")
- **User runs `/score` on a rubric file itself** — recursive: use a `rubric` rubric to score rubrics. Same flow.
- **Artifact is large (whole repo)** — rubric should subset the repo to representative files; don't try to score every file.
- **No `git` available for staged-commit rubric** — surface and stop.

## Anti-patterns

- **Don't skip the dialogue.** Single-pass scoring is exactly what this skill exists to improve on.
- **Don't ask sub-agents to dialogue with each other.** O(N²) message passing, hard to converge. The orchestrator is the synthesis point.
- **Don't normalize weights silently.** Surface malformed rubrics; don't paper over.
- **Don't average across personas.** Use the rubric's weights; weights are the whole point.
- **Don't pre-judge personas' critiques.** Push back where the rubric's anti-patterns flag is hit; otherwise engage on merits, not on whether you (orchestrator) "agree."
- **Don't make this a CI pass/fail gate without the user's explicit opt-in.** Scores are gradient signals (7→8→9), not pass/fail bars.

## Worked example

> **User:** `/score ~/.claude/skills/dispatch/SKILL.md`
>
> **Detect:** matches `rubrics/skill.md` detection rule (`**/SKILL.md` glob).
> **Load rubric:** 9 personas (frontmatter / description-specificity / structure / progressive-disclosure / behavioral-completeness / voice-pov / integration-with-workflow / education-layer / worked-example), weights sum to 1.0.
> **Read prior ledger:** `.scratch/score/dispatch-skill-<previous-timestamp>.md` exists from an earlier run. Extract `prior_rejected_critiques` — e.g., a previous run rejected *"extract templates to companion files"* with rationale *"speculative pre-engineering — file under 500 lines."* Pass these forward to each persona in step 3 so they don't re-suggest them.
>
> **Dispatch:** 9 sub-agents spawn in parallel. Each receives the SKILL.md path, their persona's lens, Anthropic best-practice URLs, the rubric's anti-patterns, and the `prior_rejected_critiques` YAML list.
>
> **All return scorecards.** frontmatter: 8.5/10. structure: 9.0/10. progressive-disclosure: 8.0/10 (critique: *"RUBRIC-FORMAT.md not prominently signaled in SKILL.md"*). worked-example: 7.5/10 (critique: *"current example tells about dialogue but doesn't show a full exchange"*). Etc.
>
> **Per-persona dialogue.** Two illustrative exchanges:
>
> - **progressive-disclosure (push-back → concede):** orchestrator sends:
>   > *"You wrote 'RUBRIC-FORMAT.md not prominently signaled.' But SKILL.md:27 reads `Add new rubrics by dropping a file into rubrics/ — see [RUBRIC-FORMAT.md](RUBRIC-FORMAT.md).` That's a clear signal with an explicit when-hook. Did you miss it?"*
>
>   Persona replies: *"You're right, I missed line 27. Concede; revise to 9.0/10."* Score updated.
>
> - **worked-example (push-back → stand by):** orchestrator sends:
>   > *"Your critique 'show full exchange' — current example is intentionally compressed for readability. Is the failure mode you're concerned about model-confusion when running the dialogue, or human-confusion reading the example?"*
>
>   Persona replies: *"Model-confusion. Compressed form lets the orchestrator skip the dialogue mechanics on a real run. I stand by 7.5/10."* Score held; critique applied to action items.
>
> **Synthesise weighted total: 8.7/10.** Trajectory: 8.6 → **8.7**.
>
> **Ledger written to** `.scratch/score/dispatch-skill-<timestamp>.md`:
>
> - **Applied:** worked-example expansion → next iteration produces v2 with full dialogue exchange.
> - **Deferred:** structure persona's *"add edge-case sub-headers"* — pure polish, low impact, defer to v3 if file grows.
> - **Rejected (preserved for future scorers):** progressive-disclosure's *"RUBRIC-FORMAT.md not signaled"* — false claim, line 27 references it. Future personas: don't re-suggest.
>
> Future re-scores inherit both prior- and current-run rejected critiques, so the dialogue doesn't re-litigate settled ground.

## When to use `/score`

- Reviewing a teammate's PR before merge
- Self-scoring a skill you just authored
- Red-teaming an architecture proposal
- Validating staged commits before pushing
- Periodic codebase health check
- CI gate on artifact quality (with explicit opt-in; default is interactive)

## When NOT to use `/score`

- Single-line grammar fix (overhead exceeds value)
- Anything where pass/fail is the right framing (use a linter or a hardcoded rule)
- Time-critical hotfix where dialogue would slow you down (use a single-agent quick-check instead)
