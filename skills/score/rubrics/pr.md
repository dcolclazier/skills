# PR Rubric

Rubric for scoring a pull request / merge request against modern code-review best practices.

## Detection

- **Invocation context**: argument is a PR number (`#42`), a GitHub PR URL, a GitLab MR URL, or a `gh pr view`/`glab mr view` reference
- **Explicit override**: `--rubric pr`

## Best-practice sources

- https://google.github.io/eng-practices/review/reviewer/standard.html
- https://google.github.io/eng-practices/review/reviewer/looking-for.html
- https://owasp.org/www-project-top-ten/ (security-relevant changes)

## Personas

### security

- **Lens**: input validation, auth/authz, secret handling, injection vectors (SQL, command, path traversal), CSRF/SSRF, dependency vulnerabilities introduced. Grounded in OWASP top-10.
- **Sources**: https://owasp.org/www-project-top-ten/, https://cheatsheetseries.owasp.org/
- **Weight**: 0.20

### correctness

- **Lens**: does the code do what the PR description claims? Are edge cases handled? Are errors handled correctly (not just suppressed)? Off-by-one, null handling, race conditions.
- **Weight**: 0.20

### test-coverage

- **Lens**: are tests added/updated for the changes? Do they test behaviour through public interfaces (per the project's `tdd` conventions)? Are critical paths covered?
- **Weight**: 0.15

### readability

- **Lens**: naming, structure, function-length, comment quality (signal vs noise), self-documentation. Will a teammate reading this in 6 months understand it?
- **Weight**: 0.15

### scope-cohesion

- **Lens**: does the PR do *one thing*? Are unrelated changes mixed in? Could it be split into multiple cleaner PRs? PR description matches the diff.
- **Weight**: 0.10

### performance

- **Lens**: obvious performance regressions, N+1 queries, unbounded loops, memory growth, cache invalidation. Not micro-optimisation; just "would this break in production at scale?"
- **Weight**: 0.10

### backwards-compat

- **Lens**: does this break consumers? Type-signature changes, removed exports, schema migrations, API endpoint shape changes. Is migration strategy explicit if applicable?
- **Weight**: 0.10

(Total: 1.00)

## Anti-patterns

The orchestrator should reject these critique patterns during dialogue:

- **Bikeshedding on naming** when the name is acceptable and the persona is just stating preference
- **Suggesting unrelated refactors** that expand the PR's scope rather than evaluating the change as proposed
- **Demanding test coverage for trivial changes** (typo fix, doc change, dependency bump with no behaviour change)
- **Performance speculation without evidence** — flagging "this might be slow" without measurement or clear mechanism
- **Style critiques the project's linter doesn't enforce** — the linter is the source of truth for style; the human reviewer is for design
- **Re-litigating decisions documented in ADRs** — if the choice was deliberately made and recorded, "I would have done X differently" is noise

## Persona dispatch notes

Each persona should receive:

- The PR number / URL and full diff (`gh pr diff <number>` or equivalent)
- The PR description and discussion comments
- The repo's `CLAUDE.md` / `AGENTS.md` if present (so they respect project conventions)
- The repo's `docs/adr/` listing if present (so they don't re-litigate documented decisions)
- The relevant subset of changed files at full content (not just diff) for context

For very large PRs (>500 lines changed): split the dispatch — each persona scores the whole PR but is told to focus their critique on the highest-impact changes within their lens, not exhaustively cover every line.
