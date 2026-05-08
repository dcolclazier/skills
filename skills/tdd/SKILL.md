---
name: tdd
description: Test-driven development with red-green-refactor loop. Implements vertical-slice TDD on issues marked `ready-for-agent` by /triage — reads the agent brief as contract, treats acceptance criteria as the test list, and closes the loop on the issue tracker when all tests pass. Use when the user wants to build features or fix bugs using TDD, mentions "red-green-refactor", wants integration tests, asks for test-first development, or has a `ready-for-agent` issue to implement. For ambiguous, unscoped, or vague work, run /grill-me first; this skill assumes alignment is already done upstream.
---

# Test-Driven Development

## Where this enters the workflow

`/tdd` is the implementation phase of the engineering pipeline:

```
grill-me → to-prd → /score(prd) → to-issues → triage → tdd → /self-review → PR
                                                         ↑                    ↓
                                                         you                /resolve-reviews
                                                         are                   ↓
                                                         here              human merges
                                                                              ↓
                                                                    /post-merge-cleanup
```

It picks up issues that `/triage` has marked **`ready-for-agent`** (the canonical role; the actual label string in your tracker lives in `docs/agents/triage-labels.md`). The **agent brief** posted on the issue (see `triage/AGENT-BRIEF.md` for format reference) is the contract — it specifies the desired behavior, key interfaces, acceptance criteria, and out-of-scope items.

**North star:** *lossless brief-to-implementation handoff* — every acceptance criterion in the agent brief becomes one or more passing tests, and every test verifies behavior the brief specified, not implementation that emerged. The brief is the source of truth.

`/tdd` ends with the implementation done and tests passing — but it's *not* the last step in the per-feature pipeline. Two skills bracket the PR:

- **Pre-PR quality gate (`/self-review`)** runs *between* `/tdd` and `git push` — multi-persona review of the local diff, with auto-fix for clear-cut findings and `REVIEW-NOTES.md` for deliberate disagreements. See step 5 below.
- **Post-merge cleanup (`/post-merge-cleanup`)** runs *after* the human merges — closes the issue, deletes the branch, strips "remove once #N merges" TODOs, removes temp instrumentation the agent added during diagnose, drafts a CHANGELOG entry, schedules rollout follow-ups. See step 7.

If the issue has no agent brief, or the brief is vague, **stop and escalate** to `/triage` — running TDD on an unspecified issue produces the wrong tests. Don't guess.

## Philosophy

**Core principle**: Tests should verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't.

*Why this matters:* the brief specifies behavior; implementation choices (class names, file structure, collaborators) emerge during the GREEN phase. Tests coupled to implementation lock the design in place — and break the moment a refactor improves it. Tests through public interfaces survive any refactor that preserves behavior. That's the whole point.

**Good tests** are integration-style: they exercise real code paths through public APIs. They describe _what_ the system does, not _how_ it does it. A good test reads like a specification — "user can checkout with valid cart" tells you exactly what capability exists.

**Bad tests** are coupled to implementation. They mock internal collaborators, test private methods, or verify through external means (querying a database directly instead of using the interface). The warning sign: your test breaks when you refactor, but behavior hasn't changed.

See [tests.md](tests.md) for examples and [mocking.md](mocking.md) for mocking guidelines.

## Anti-Pattern: Horizontal Slicing

**DO NOT write all tests first, then all implementation.** This is "horizontal slicing" — treating RED as "write all tests" and GREEN as "write all code."

This produces **crap tests**:

- Tests written in bulk test _imagined_ behavior, not _actual_ behavior
- You end up testing the _shape_ of things (data structures, function signatures) rather than user-facing behavior
- Tests become insensitive to real changes — they pass when behavior breaks, fail when behavior is fine
- You outrun your headlights, committing to test structure before understanding the implementation

**Correct approach**: Vertical slices via tracer bullets. One test → one implementation → repeat. Each test responds to what you learned from the previous cycle. Because you just wrote the code, you know exactly what behavior matters and how to verify it.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
  ...
```

## Workflow

### 0. Read the brief and the config

#### AFK git pre-flight (parallel-safety guard)

If running **unattended** (AFK mode — no user actively answering prompts in this conversation), check the git state BEFORE doing anything else:

```
working_tree_dirty   = `git status --porcelain` returns non-empty
on_protected_branch  = current branch is main/master/trunk
branch_matches_issue = current branch name contains this issue's number, slug, or
                       matches a workflow pattern (`tdd/<N>-*`, `dispatch/<N>-*`)
```

**Refuse and surface** if `working_tree_dirty AND NOT on_protected_branch AND NOT branch_matches_issue`:

> "Polluted working tree (on `<branch>` with N unrelated modified files). Parallel `/tdd` runs cannot safely commit here without mixing scopes. Invoke this work via `/dispatch` instead — `/dispatch` spawns each subagent in an isolated git worktree (per `dispatch/SKILL.md:88`), branched cleanly off `main` as `dispatch/<issue>-<slug>`. If you really meant to run `/tdd` standalone in this state, clean the working tree first (`git stash` or `git checkout main`) and rerun."

*Why refuse rather than auto-handle:* silently committing to the wrong branch — or auto-stashing the host's in-flight work without recovery semantics — is exactly the failure mode this guards against. Parallel agents serializing on user-input prompts is the bug we're escaping; failing fast and loud preserves both parallelism and correctness. The branching question belongs to `/dispatch`'s worktree setup, not to per-issue `/tdd` runs.

**Skip this check entirely in interactive mode** — when a user is in the conversation, they can answer the branching dialogue (per step 6 below). The refusal only fires when no human is available.

#### Read the brief and configuration

Before writing any code:

- Read `docs/agents/issue-tracker.md` (written by `/setup-workflow`) to learn how to fetch issues from this repo's tracker (`gh`, `glab`, `.scratch/`, or "Other").
- Fetch the issue and read the **agent brief** from its comments. The brief is structured: Category, Summary, Current behavior, Desired behavior, Key interfaces, Acceptance criteria, Out of scope. (Format reference: `triage/AGENT-BRIEF.md`.)
- Read the project's `CONTEXT.md` (or per-context glossaries via `CONTEXT-MAP.md`) to learn the domain vocabulary. Test names and interface vocabulary should match the project's language; respect any ADRs in the area.

If the issue is missing a brief, has a brief that says "see PRD" without specifics, or has acceptance criteria too vague to convert into tests, **stop and escalate** — ask the user whether to send the issue back to `/triage` for sharper specification. Don't guess your way past a vague brief; that's how implementations drift from intent.

### 1. Plan (AFK or interactive)

**AFK mode** — default when picking up a `ready-for-agent` issue with no user in the loop:

- Map each acceptance criterion in the brief to one or more tests. Every criterion gets at least one test; every test traces back to a criterion.
- Identify opportunities for [deep modules](deep-modules.md) (small interface, deep implementation) consistent with the brief's "Key interfaces" section.
- Design interfaces for [testability](interface-design.md) — the brief's interface specs are the contract; you choose how to make them testable.
- Order the test list: the first test is the **tracer bullet** that proves end-to-end pickup; subsequent tests cover the rest of the behavior space.

**Interactive mode** — when the user is in the conversation (e.g. running `/tdd` directly without going through triage):

- All of the above, plus:
- Confirm with the user what interface changes are needed.
- Confirm which behaviors to test (prioritise). *"You can't test everything"* — focus on critical paths and complex logic, not every edge case.
- Get user approval on the plan before proceeding to step 2.

### 2. Tracer Bullet

Write ONE test that confirms ONE thing about the system:

```
RED:   Write test for first behavior → test fails
GREEN: Write minimal code to pass → test passes
```

This is your tracer bullet — proves the path works end-to-end.

### 3. Incremental Loop

For each remaining acceptance criterion / behavior:

```
RED:   Write next test → fails
GREEN: Minimal code to pass → passes
```

Rules:

- One test at a time
- Only enough code to pass the current test
- Don't anticipate future tests

*Why "don't anticipate future tests":* speculative code adds surface area without driving behavior. Each anticipated branch is one more thing the next test might contradict. Wait for the test that actually demands the branch — then you're sure it's needed and you know exactly how to shape it.

### 4. Refactor

After all tests pass, look for [refactor candidates](refactoring.md):

- Extract duplication
- Deepen modules (move complexity behind simple interfaces)
- Apply SOLID where natural
- Consider what new code reveals about existing code
- Run tests after each refactor step

**Never refactor while RED.** Get to GREEN first.

### 5. Self-review (pre-PR quality gate)

**Before pushing the branch and opening the PR, run `/self-review` on the local diff.** This is the pre-PR quality gate of the per-feature pipeline.

```
/tdd implementation done → /self-review  ←  QUALITY GATE
                              ↓
                         git push + open PR
```

*Why a gate here, and why this gate specifically:*

- **Catches what tests don't.** TDD verifies the code does what the brief said. `/self-review` catches a different class of issues: security holes the tests don't exercise, debug artifacts (`console.log`, `print()`, `.skip`) the agent left behind, scope-cohesion problems (an unrelated tweak slipped into the branch), backwards-compat breakage, secrets accidentally committed. These are review-level concerns, not behavior-level.
- **Multi-persona, not single-pass.** The `pre-pr` rubric runs ~9 personas (security, correctness, test-coverage, readability, scope-cohesion, backwards-compat, secrets-and-credentials, debug-artefacts, diff-cohesion). A single self-read by the agent that just wrote the code will miss things — the implementer's lens is too close to the work. Multi-persona dialogue is the catch.
- **Auto-fix is safe here.** Unlike the PRD gate (read-only, because PRDs are human-iterated), the diff is reviewable as commits. `/self-review`'s `auto` posture applies clear-cut findings as new commits and records deliberate disagreements in `REVIEW-NOTES.md` (committed alongside). The PR reviewer sees both the cleanup and the rationale for what was kept.

Phrase the chaining educationally:

> "Tests pass and refactor is settled. Before opening the PR, run `/self-review` — multi-persona pre-PR review. It catches what TDD doesn't (security, debug artifacts, scope mixing, secrets). Auto-fixes the clear-cut findings as new commits and records deliberate disagreements in `REVIEW-NOTES.md`. Posture (`auto` / `draft` / `comment-only`) is set per-repo in `docs/agents/self-review.md` or asked at start."

Run `/self-review` directly. **In AFK mode, invoke `/self-review --posture auto` without surfacing for posture confirmation** — auto is the right default for unattended runs because (a) the diff is on a feature branch (not `main`), so a bad fix is one revert away, (b) every agree-fix runs the test suite first and aborts on red, and (c) the PR reviewer sees both the cleanup commits and `REVIEW-NOTES.md` before merge. Surfacing the posture dialogue in AFK mode is exactly the parallel-blocking pattern this skill suite is designed to avoid.

In **interactive mode** (user in conversation), let `/self-review` ask its posture question normally — the user has context the agent doesn't (high-blast-radius branch? learning the skill?).

When `/self-review` ends with the branch ready, proceed to step 6.

If the user (interactive mode) or the AFK invoker (via `--no-self-review` or equivalent) explicitly waives the gate, proceed without it but flag in the run report that the gate was skipped.

### 6. Close the loop (open PR)

When all acceptance criteria are passing tests, refactor is settled, and `/self-review` has finished, walk this checklist:

- [ ] **Verify lossless handoff** — every acceptance criterion in the brief has a corresponding passing test. If any criterion has no test, the loop isn't done.
- [ ] **Push the branch and open a PR / merge request**, referencing the issue (e.g. `Closes #42`).
- [ ] **Comment on the issue** summarising: which acceptance criteria are covered, which tests verify each, and any context worth recording (dependencies you noticed, ADRs touched, surprises).
- [ ] **Apply the appropriate post-implementation label** per `docs/agents/triage-labels.md` if your repo uses one (`done`, `in-review`, etc.), or close the issue directly on PR merge.
- [ ] **If an out-of-scope bug surfaced during implementation, stop and escalate to `/diagnose`** rather than expanding the slice — the brief is the contract, and out-of-scope work needs separate triage.

After the PR opens: if Copilot or human reviewers leave comments, run `/resolve-reviews` to address them. The same posture model from `/self-review` applies (`auto` / `draft` / `comment-only`).

### 7. Post-merge cleanup (when the user signals merge)

**When the user tells you the PR has merged — "I merged it", "we shipped #142", "merged" — run `/post-merge-cleanup`.** Don't wait to be asked a second time; the merge signal *is* the cue.

```
human merges PR → user signals merge → /post-merge-cleanup
```

*Why the agent that built the PR runs the cleanup:*

- **Session memory is load-bearing.** This same agent ran TDD, wrote tests, may have invoked `/diagnose` mid-implementation, may have spawned sub-issues, may have tagged TODOs `// TODO(#42): remove once merged`, may have added temporary `console.log`s. That memory disappears when the session ends. Reconstructing the cleanup trail from PR metadata alone is lossy. Cleanup chains off the merge signal *before* the context evaporates.
- **It's mechanical and easy to forget.** Closing the issue, deleting the branch, stripping TODOs, removing temp instrumentation, drafting a CHANGELOG entry, scheduling rollout follow-ups — none of these require judgment, all of them are easy to skip under deadline. That's exactly the work an agent should own.
- **Judgment-call cleanup gets surfaced, not skipped.** Feature-flag rollout, stakeholder notification, `CONTEXT.md` updates if new domain terms entered — those are the human's call. `/post-merge-cleanup` surfaces them with framing; it doesn't decide for the human.

Phrase the chaining:

> "Merged. Running `/post-merge-cleanup` — closing the originating issue, deleting the branch, stripping the `remove once #N` TODOs I tagged during implementation, removing the temp instrumentation I added during diagnose, drafting a CHANGELOG entry. Surfacing the judgment calls (feature flag, CONTEXT.md updates) for your decision after."

Posture is set in `docs/agents/post-merge-cleanup.md` (`auto` / `draft` / `comment-only`). The same three-way posture model from `/self-review` and `/resolve-reviews` applies — the junior dev learns one mental model that brackets the whole PR lifecycle.

## Edge cases

- **Test passes for the wrong reason.** The GREEN code accidentally passes the test without implementing the behavior. Add an assertion that *would* fail under the bug; if both pass, the test is too loose.
- **Refactor breaks a test.** First ask: did behavior change? If no, the test was coupled to implementation; loosen it (assert on observable behavior, not internal calls). If yes, the refactor changed behavior accidentally; roll back.
- **Multi-behavior issue.** If the brief specifies more behaviors than feel like one slice, ask the user whether to split the issue via `/to-issues` or proceed in a single TDD pass. Splitting is usually the right call — slices are supposed to be thin.
- **Brief contradicts existing code.** Surface it; don't silently override. The brief might be stale (the codebase moved) or the codebase might be drifting (the brief is right). The user decides.

## Checklist per cycle

```
[ ] Test traces back to an acceptance criterion in the brief
[ ] Test describes behavior, not implementation
[ ] Test uses public interface only
[ ] Test would survive internal refactor
[ ] Code is minimal for this test
[ ] No speculative features added
```

## Note on language coverage

Examples in `tests.md`, `mocking.md`, and `interface-design.md` use TypeScript. The principles are language-universal:

- **Dependency injection** — pass external dependencies in rather than constructing them internally. Every language supports this (Python params, Go interface args, Java constructor args).
- **Return-don't-mutate** — calculate-and-return is more testable than mutate-in-place, regardless of language.
- **Public-interface testing** — every language has a notion of public surface (exported symbols, public methods, module boundaries). Test through that.
- **Mock at boundaries only** — every language can stub at its FFI / IO / clock boundaries (Python `unittest.mock`, Go interfaces with test doubles, Java `@Mock`).

Translate the TypeScript examples mechanically; the patterns transfer.
