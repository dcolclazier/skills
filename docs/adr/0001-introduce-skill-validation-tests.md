# ADR 0001 — Introduce skill validation tests + CI

**Status:** accepted
**Date:** 2026-05-18
**Issue:** #01-frontmatter-spec-and-validator (the foundational slice of the engineering-skills-plugin PRD)

## Context

Before this change, the `dcolclazier/skills` repo (the upstream source for the engineering-skills plugin) had:

- No test directory.
- No CI test runner.
- No frontmatter contract for `SKILL.md` files — fields were ad-hoc per skill.
- No way to catch a malformed skill at publish time. A typo in a required field (or an undeclared dependency) would surface only at runtime, in a downstream adopting team's repo, mid-pipeline.

The engineering-skills plugin is designed to be adopted by other teams (MMC being the first pilot — see the PRD at `.scratch/mmc-plugin-pilot/PRD.md` if running locally). Adopting teams take on a quality risk they can't easily inspect: silent frontmatter drift in upstream skills becomes their mystery mid-pipeline failure.

## Decision

Introduce a test directory (`tests/`) and a CI gate (`.github/workflows/validate.yml`) that runs `validate.sh` against the `skills/` tree on every PR and push. The validator enforces a written frontmatter spec (`skills/_format/FRONTMATTER-SPEC.md`).

Specifically:

1. `validate.sh` exists at the repo root. Pure bash; no external dependencies.
2. Fixture skills under `tests/fixtures/skills/` cover the success and failure modes (3 valid + 4 invalid fixtures: missing required field, missing the new `requires-*` fields, malformed YAML, unknown field).
3. A pure-bash test runner (`tests/test_validate.sh`) exercises the validator against each fixture and against the real `skills/` tree.
4. `.github/workflows/validate.yml` runs the test runner on every PR and push.

The spec adds two new required frontmatter fields (`requires-skills:` and `requires-config:`) to every SKILL.md. These declare the skill's cross-skill and cross-config dependencies; future slices (issue #02 dependency-graph walker, issue #04 schema validator) consume the declarations.

## Rationale

- **Catches regressions before adopting teams see them.** Today's adopter quality risk shifts left: a typo in `requires-skils` (note the missing `l`) is caught at PR-open in upstream, not at `/setup-workflow` time in downstream.
- **Pure bash, no dependency drift.** A Python or Node-based validator would add a runtime that adopting teams' environments may not have. Pure bash + grep/awk runs everywhere.
- **Documented contract enables incremental tightening.** Future slices (per-field deeper validation, dependency-graph walking, schema validation for `docs/agents/*.md`) extend the contract without breaking the v1 shape.
- **Trust signal for adopters.** "Our skills have CI" is meaningful to a team evaluating whether to adopt — it's part of what differentiates a maintained plugin from a personal-experiment repo.

## Rejected alternatives

- **Defer testing until first bug.** Rejected. The pipeline ships to adopting teams; the first bug they hit is the first impression. Test infrastructure is a foundational dependency of every subsequent slice.
- **Use a third-party YAML linter.** Rejected for v1. Adds a tool dependency; our YAML subset is narrow enough (top-level `key:` pairs, inline arrays, single-line quoted strings) that pure bash + sed/awk handles it. Future tightening may revisit.
- **Single-file SKILL.md with a co-located test.** Rejected. Conventional separation: `skills/<name>/` for skill source, `tests/` for tests, `tests/fixtures/` for fixtures. Mirrors how most engineering codebases organize.

## Consequences

**Positive:**
- Every PR is gated by validate.sh.
- New skills must declare `requires-skills:` and `requires-config:` — explicit dependency declarations replace implicit prose references.
- Adopting teams get a defined contract to rely on.

**Negative:**
- One-time cost: 14 existing SKILL.md files updated to declare the new fields (empty arrays for v1 — issue #02 audits and populates them correctly).
- New contributors must learn the frontmatter spec (mitigated by `skills/_format/FRONTMATTER-SPEC.md`).
- `disable-model-invocation` is an existing Claude Code skill metadata field; added to the known-fields allowlist (not invented here, but documented here for the first time).

## Follow-ups

- Issue #02: dependency-graph walker that consumes the `requires-*` declarations and detects cycles + unresolved references.
- Issue #03 + #04: schema extractor + validator for `docs/agents/*.md` consumer files (a different file shape than SKILL.md frontmatter).
