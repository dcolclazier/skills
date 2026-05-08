# Staged-Commit Rubric

Rubric for scoring `git diff --staged` content before commit — does the upcoming commit pass hygiene checks?

## Detection

- **Invocation context**: `git diff --staged` is non-empty AND no other artifact reference is provided
- **Explicit override**: `--rubric staged-commit`

## Best-practice sources

- https://cbea.ms/git-commit/ (canonical "How to write a git commit message")
- https://www.conventionalcommits.org/ (if the repo uses conventional commits)
- https://owasp.org/www-project-top-ten/ (secrets detection)

## Personas

### atomicity

- **Lens**: does this commit represent *one logical change*? Are unrelated changes mixed in (a refactor + a feature in the same commit)? Could it be split into multiple cleaner commits?
- **Weight**: 0.20

### message-quality

- **Lens**: subject line under 72 chars, imperative mood ("Add X" not "Added X"), capital first letter, no trailing period; body explains *why* not *what* (the diff already shows what); body wrapped at ~72 chars; references issues / PRs where appropriate. If the repo uses conventional commits, format compliance.
- **Weight**: 0.20

### diff-cohesion

- **Lens**: does the diff actually deliver what the message claims? Are there orphan changes the message doesn't mention? Files touched that shouldn't be (e.g. `package-lock.json` in a docs-only commit)?
- **Weight**: 0.15

### secrets-and-credentials

- **Lens**: API keys, tokens, passwords, private keys, connection strings, `.env` files, AWS access keys, SSH keys. Hard-coded secrets even temporarily. Grounded in pattern detection (sk-, pk-, AKIA, ghp_, BEGIN PRIVATE KEY, etc.).
- **Sources**: https://owasp.org/www-project-top-ten/, https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html
- **Weight**: 0.20

### debug-artefacts

- **Lens**: debug code that shouldn't ship (`console.log`, `print()`, `debugger`, `pdb.set_trace()`, `// TODO: remove`, `XXX`, hardcoded test values, commented-out blocks). `.skip` / `.only` / `xit` / `fdescribe` in test files.
- **Weight**: 0.10

### test-and-doc-completeness

- **Lens**: if behaviour changed, are tests updated? If public APIs changed, are docs/comments updated? Don't demand for trivial changes (formatting, comment fixes).
- **Weight**: 0.10

### large-binary-or-noise

- **Lens**: binary files committed where they shouldn't be (build artefacts, bundled deps, `node_modules`, generated files). Whitespace-only changes that should have been excluded by `.gitignore`. Auto-formatter sweeps mixed with logic changes.
- **Weight**: 0.05

(Total: 1.00)

## Anti-patterns

The orchestrator should reject these critique patterns during dialogue:

- **Style critiques the project's linter / formatter doesn't enforce** — if the repo uses Prettier/Black/etc., that's the source of truth; don't second-guess.
- **Demanding tests for non-behaviour changes** — typo fixes, comment changes, dependency-bump-with-no-API-change.
- **Suggesting commit splits for genuinely-cohesive changes** — if a feature requires changes in 3 files (handler + test + docs), that's *one* logical change, not three.
- **Re-litigating commit message format if the repo's existing log uses a different style consistently** — match what the project does, not the canonical doc, when there's a clear pattern.
- **Flagging "this looks like sensitive data" when it's clearly a public test fixture** — fake API keys in test files (`sk-test-...`, `00000000-0000-0000-0000-...`) are not real secrets.

## Persona dispatch notes

Each persona should receive:

- The full `git diff --staged` output
- The proposed commit message (if the user has drafted one — read from `.git/COMMIT_EDITMSG` or pass via context)
- The repo's `.gitignore` (so "should this file be tracked?" critiques are grounded)
- Recent commit log (`git log -10 --oneline`) so the message-quality persona can match repo conventions

The secrets-and-credentials persona should pattern-match aggressively but flag findings as "review before committing" rather than blocking — a string that looks like a secret might be test data, but the human should confirm.
