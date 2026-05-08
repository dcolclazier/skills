# Pre-PR Rubric

Rubric for scoring the local diff on a feature branch *before* the PR is opened. Combines the `pr` rubric's code-quality lenses with the `staged-commit` rubric's hygiene lenses, weighted for the pre-publication moment.

## Detection

- **Invocation context**: `/score` invoked on a branch state (no PR reference provided), OR `git diff main...HEAD` is non-empty AND the user mentions "self-review", "pre-PR", "before opening PR", "audit branch"
- **Explicit override**: `--rubric pre-pr`

This rubric is the default that `/self-review` delegates to.

## Best-practice sources

- https://google.github.io/eng-practices/review/reviewer/standard.html
- https://google.github.io/eng-practices/review/reviewer/looking-for.html
- https://owasp.org/www-project-top-ten/ (security-relevant changes)
- https://cbea.ms/git-commit/ (commit hygiene)

## Personas

### security

- **Lens**: input validation, auth/authz, secret handling, injection vectors, dependency vulnerabilities introduced. Grounded in OWASP top-10.
- **Sources**: https://owasp.org/www-project-top-ten/, https://cheatsheetseries.owasp.org/
- **Weight**: 0.15

### correctness

- **Lens**: does the code do what the branch's commits/tests claim? Edge cases handled? Errors handled (not just suppressed)? Off-by-one, null handling, race conditions.
- **Weight**: 0.15

### test-coverage

- **Lens**: are tests added/updated for the changes? Do they test behaviour through public interfaces? Are critical paths covered?
- **Weight**: 0.10

### readability

- **Lens**: naming, structure, function-length, comment quality (signal vs noise). Will a teammate reading this in 6 months understand it?
- **Weight**: 0.10

### scope-cohesion

- **Lens**: do the commits represent *one logical change*? Are unrelated changes mixed in? Could the branch be split? Atomicity at the commit level.
- **Weight**: 0.10

### backwards-compat

- **Lens**: does this break consumers? Type-signature changes, removed exports, schema migrations, API endpoint shape changes. Is migration strategy explicit if applicable?
- **Weight**: 0.10

### secrets-and-credentials

- **Lens**: API keys, tokens, passwords, private keys, connection strings, `.env` files, AWS access keys, SSH keys, hard-coded secrets even temporarily.
- **Sources**: https://owasp.org/www-project-top-ten/, https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html
- **Weight**: 0.10

### debug-artefacts

- **Lens**: debug code that shouldn't ship (`console.log`, `print()`, `debugger`, `pdb.set_trace()`, `// TODO: remove`, `XXX`, hardcoded test values, commented-out blocks, `.skip` / `.only` / `xit` / `fdescribe`).
- **Weight**: 0.10

### diff-cohesion

- **Lens**: do the diffs match what the commit messages and PR-intent claim? Orphan changes? Auto-formatter sweeps mixed with logic? Binary files that shouldn't be committed?
- **Weight**: 0.10

(Total: 1.00)

## Anti-patterns

The orchestrator should reject these critique patterns during dialogue:

- **Bikeshedding on naming** when the name is acceptable — preference, not flaw
- **Suggesting unrelated refactors** that expand scope rather than evaluate the change as proposed
- **Demanding tests for trivial changes** (typo, doc, dependency bump with no behaviour change)
- **Performance speculation without evidence** — flagging "this might be slow" without measurement or clear mechanism
- **Style critiques the project's linter doesn't enforce** — linter is the source of truth for style; humans are for design
- **Re-litigating decisions documented in ADRs** — if the choice was deliberately made and recorded, "I would have done X differently" is noise
- **Flagging "this looks like sensitive data" when it's clearly a public test fixture** — fake API keys (`sk-test-...`, `00000000-0000-0000-0000-...`) aren't real secrets
- **Demanding commit splits for genuinely-cohesive changes** — a feature spanning handler + test + docs is *one* logical change

## Persona dispatch notes

Each persona should receive:

- The diff (`git diff main...HEAD` or equivalent base)
- The commit log (`git log main..HEAD --oneline` and full bodies)
- The repo's `CLAUDE.md` / `AGENTS.md` if present
- The repo's `docs/adr/` listing
- The relevant changed files at full content (not just diff) for context
- The rubric's anti-patterns

For very large branches (>500 lines changed): tell each persona to focus their critique on the highest-impact changes within their lens, not exhaustively cover every line.

## When this rubric runs through `/self-review`

The orchestrator (`/self-review`) takes the action ledger and acts:

- **agree-and-fix** → applied as a new commit on the branch
- **disagree-and-justify** → recorded in `REVIEW-NOTES.md` (committed alongside)
- **unsure-and-ask-user** → surfaced to user with trade-off framed

This rubric only produces the assessment; the action layer is `/self-review`'s job.
