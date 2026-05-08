# Rubric Format

A rubric defines how `/score` should evaluate a specific artifact type. Drop a new file into `rubrics/<type>.md` and it becomes available to the orchestrator.

## Structure

```markdown
# <Artifact-type> Rubric

## Detection

(How the orchestrator decides to use this rubric. Choose one or more:)

- **File glob**: `**/SKILL.md`, `*.tf`, `*.py`, etc.
- **Content marker**: a regex or literal string the file must contain (e.g. `^---\nname:` for skill frontmatter)
- **Invocation context**: e.g. `git diff --staged` is non-empty, or invocation is `gh pr view`
- **Explicit override**: rubric name passed via `--rubric <type>`

If multiple rubrics match, the orchestrator asks the user.

## Best-practice sources

(URLs the personas should ground their critiques in. These travel with each persona's prompt so they cite specific docs, not their priors.)

- https://example.com/best-practices-doc-1
- https://example.com/best-practices-doc-2

## Personas

Each persona is a fresh sub-agent dispatched in parallel. Define each with:

### <persona-name>

- **Lens** (required): focused charge — what this persona looks at and *only* what this persona looks at. Specific is better than broad.
- **Sources** (optional): persona-specific best-practice URLs (in addition to rubric-wide sources)
- **Weight** (required): contribution to the weighted total. Decimal, 0.0–1.0.

(All weights across all personas must sum to **exactly 1.0**. The orchestrator validates this on rubric load and refuses to load malformed rubrics.)

## Anti-patterns

(Critiques the orchestrator should reject during dialogue without ceremony. These are the failure modes the artifact's author has explicitly rejected — usually documented in author memory or prior `/score` runs.)

- Speculative pre-engineering when the artifact is well under threshold
- Mechanical-rule additions that contradict the artifact's stated north star
- Conflating different audiences (e.g. skill-author vs skill-consumer)

## Optional sections

### Concurrency cap

Override the default (no cap) if personas need rate-limited dispatch:

- `max_concurrent: 3`

### Output format

Override the default markdown ledger; e.g. force JSON output for CI consumption:

- `output: json`
- `output: markdown` (default)
- `output: both`

### Rubric-specific persona instructions

Free-form notes that travel with every persona's prompt (e.g. "this codebase uses TypeScript strict mode; flag `any` usage").

## Weights — how to choose

Weights reflect *which lenses matter most* for this artifact type. They are not popularity contests or first-instinct numbers. Some heuristics:

- **Workflow-load-bearing dimensions get higher weight.** A skill's "integration with workflow" matters more than its "voice / POV" if it sits in a pipeline.
- **Failure-mode dimensions get higher weight.** PR rubrics weight "security" and "correctness" higher than "comment density."
- **Cap any single persona at 0.25.** No single lens should dominate; multi-perspective synthesis is the whole point.
- **Floor at 0.05.** Below that, the persona isn't earning its dispatch cost.

Common pattern: 5–8 personas, each weighted 0.10–0.20, with one or two at 0.20–0.25 and the rest filling in.

## Recursive scoring

Rubrics are themselves artifacts, and `/score` can be run on a rubric file using a `rubric` rubric (or this very file's spec as the implicit rubric). When you write a new rubric, consider running `/score` on it before shipping.
