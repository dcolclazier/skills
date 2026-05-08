# Skill Rubric

Rubric for scoring Claude Code skills (`SKILL.md` files) against published Anthropic best practices.

## Detection

- **File glob**: `**/SKILL.md` — any file named `SKILL.md` at any depth
- **Content marker**: YAML frontmatter containing `name:` and `description:` fields
- **Explicit override**: `--rubric skill`

## Best-practice sources

- https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- https://code.claude.com/docs/en/skills

## Personas

### frontmatter

- **Lens**: name correctness (matches folder, valid YAML), description quality, trigger discoverability, disambiguation from peer skills, presence of `argument-hint` if the skill accepts arguments.
- **Weight**: 0.10

### description-specificity

- **Lens**: will the description trigger correctly when relevant, *and skip correctly when not*? Does it disambiguate against peer skills? Does it state both *what* the skill does and *when* to use it?
- **Weight**: 0.10

### structure

- **Lens**: section hierarchy, headers, decision-tree clarity, anti-pattern callouts. Is the skill machine-readable?
- **Weight**: 0.10

### progressive-disclosure

- **Lens**: companion files vs SKILL.md balance, token efficiency. Is the split serving the model or just bureaucracy? Is SKILL.md under the 500-line guidance?
- **Weight**: 0.10

### behavioral-completeness

- **Lens**: when to start, what to do at each step, when to stop, edge cases, what NOT to do, escalation paths.
- **Weight**: 0.15

### voice-pov

- **Lens**: imperative directed at the model, no ambiguity about who acts, consistent POV.
- **Weight**: 0.10

### integration-with-workflow

- **Lens**: correctly references peer skills, reads upstream artifacts, hands off cleanly to downstream skills, respects shared abstractions (e.g. `docs/agents/*.md`).
- **Weight**: 0.15

### education-layer

- **Lens**: does the skill teach the *why*, not just the *what*? Is reasoning surfaced for defaults and rules?
- **Weight**: 0.10

### worked-example

- **Lens**: are examples concrete? Do they show vs tell? Do they demonstrate edge cases as well as the happy path?
- **Weight**: 0.10

(Total: 1.00)

## Anti-patterns

The orchestrator should reject these critique patterns during dialogue without ceremony — they have been validated against real skill design and rejected in prior author sessions:

- **Speculative pre-engineering** — extracting templates / sections to companion files when SKILL.md is well under the 500-line threshold. Split when the file actually crosses; not in anticipation.
- **Mechanical-rule additions** — validation read-back, per-axis question quotas, "<N exchanges" thresholds, fixed concurrency caps for risk-tolerance parameters. Judgment-based design has been deliberately preferred.
- **Conflating skill-author and skill-consumer audiences** — guidance like "test this skill" footers belong in author tooling, not in the SKILL.md the runtime consumer reads.
- **Suggesting language-exhaustive examples** — adding ~40 lines of Python/Go/Java/Ruby examples when one example per axis closes the gap proportionally.
- **Suggesting more dimensions / more rules / more comprehensiveness for its own sake** — graders optimise for "what could be added"; skills optimise for "what serves the north star." When in doubt, fewer is better.
- **Recommending normalisation of weights or scores silently** — surfacing malformed rubrics is the right move; papering over is not.

## Persona dispatch notes

Each persona should be told:

- The artifact's **stated north star** (read it from the SKILL.md if present, or pass via orchestrator context)
- The skill's place in the user's broader workflow pipeline (if known)
- Any prior rejected critiques for this artifact (preserved in `.scratch/score/` history)

This prevents personas from re-suggesting critiques the author has already engaged with and rejected.
