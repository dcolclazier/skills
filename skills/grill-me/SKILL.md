---
name: grill-me
description: Stress-test a plan or design by interrogating terminology, scope, edge cases, trade-offs, and code conflicts — surfacing ambiguity before implementation begins. Captures resolved terms to CONTEXT.md and trade-offs to ADRs when the repo uses them. Use when the user says grill me, poke holes, challenge me, stress-test this, or what am I missing.
---

<what-to-do>

Interview the user relentlessly about every aspect of their plan. Your job is to surface enough ambiguity that the eventual implementation has the highest possible chance of success.

**Q0: Establish the north star — always first, never skipped.**

Before grilling anything else, confirm the plan's success criterion with the user. The default frame is *statistically significant context alignment*, but every plan can have additional or modifying north stars (junior-dev education, reversibility, performance ceiling, simplicity, time-to-merge, etc.). Propose your reading of the right north star, then ask the user to confirm or refine. **Never assume the north star — it sits at the root of the dependency tree and shapes every later answer.** This step is mandatory even in auto mode: wait for explicit user confirmation before walking the rest of the tree. Auto mode permits proceeding on dependent decisions; the root decision still belongs to the user.

For each subsequent question:

1. Tag the axis you're grilling on (Terminology / Scope / Edge cases / Trade-offs / Code reality).
2. Ask one question at a time. Wait for the answer before continuing.
3. Provide your recommended answer with one line of reasoning. If 2–3 real alternatives exist, list them.
4. If a question can be answered by reading the codebase, read instead of asking.

Walk the dependency tree — resolve load-bearing decisions before dependent ones. The north star is the root.

</what-to-do>

<supporting-info>

## The five axes

Hunt for ambiguity along these five dimensions. Pursue the strongest thread, not all five mechanically.

1. **Terminology** — fuzzy or overloaded terms. *"You said 'account' — Customer or User?"* If a `CONTEXT.md` exists, also check the term against the existing glossary.
2. **Scope** — what's in, what's out, what's deferred. *"Does this include cancellations, or only order placement?"*
3. **Edge cases** — concrete scenarios that force precision at boundaries. *"What if the order is partially fulfilled when the customer cancels?"*
4. **Trade-offs** — real alternatives considered. *"You picked Postgres — what ruled out DynamoDB?"* Capture as an ADR when the decision is **hard to reverse + surprising without context + a real trade-off** (see [ADR-FORMAT.md](./ADR-FORMAT.md)).
5. **Code reality** — does the existing code agree with the claim? *"You said cancellation is partial, but `OrderState` has a single `cancelled` transition — which is right?"*

## Detect what the repo already uses

On the first grill question, scan once:

- `CONTEXT.md` or `CONTEXT-MAP.md` at the root → repo uses domain glossaries. Capture resolved terms inline. Format: [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).
- `docs/adr/`, `docs/decisions/`, or `docs/rfcs/` → repo captures architectural decisions. Offer ADRs when the trade-off passes the three-part test.
- Neither, and the repo isn't shaped like a glossary-bearing system (small CLI, library, ML repo, infra/config) → grill verbally. Don't push artifacts. Ask once at session end whether to capture anything.

Create files lazily — only when there's something to write.

## When to stop

Stop when **any** of these are true:

- Answers stop changing your understanding (you're confirming, not learning).
- The five axes have each been walked at least once, and remaining gaps are deferred-with-rationale, not undefined.
- The user signals closure ("I think we're good", "let's just build it").

When stopping, summarise: resolved decisions, captured artifacts, deferred items.

## Anti-patterns

- **Don't grill aesthetics.** Naming preferences, formatting, file layout — out of scope. Stick to domain and architecture.
- **Don't accept hand-waving.** If the user says "we'll figure it out later," press once. If still vague, mark deferred and move on.
- **Don't propose ADRs prematurely.** The decision must actually be *made*, not just discussed.
- **Don't write artifact files unprompted.** If the repo has no `CONTEXT.md` or ADR convention and isn't DDD-shaped, don't create one — just grill.
- **Don't chase diminishing returns.** Three follow-up questions on the same point with no new information = stop and defer.

## Worked example

The pattern works on any decision-bearing context — backend domain models, CLI surface, library APIs, infra modules. Example below: adding a flag to a CLI tool. Note how each user answer steers the next question rather than mechanically cycling through axes.

> **User:** I want to add a `--dry-run` flag to the `deploy` command.
>
> **Claude [Scope]:** Just `deploy`, or also `migrate`, `rollback`, and `seed`? All four mutate state.
> *Recommended: all four. A `--dry-run` that only works on one command is a footgun.*
>
> **User:** All four. But `--dry-run` on `rollback` should still print what it would restore.
>
> **Claude [Terminology]:** Earlier docs use "dry-run" and "preview" interchangeably. Canonical?
> *Recommended: `--dry-run`. Matches kubectl/terraform conventions, so users won't have to relearn. (If the repo tracks CLI vocabulary in `CONTEXT.md`, capture there.)*
>
> **User:** Yes, dry-run. We don't have a `CONTEXT.md` — skip the capture.
>
> **Claude [Trade-offs]:** Implementation — `if dry_run` checks per call site, or wrap the real flow in a transaction and abort at the end?
> *Recommended: explicit `if dry_run` checks. Considered transaction-and-abort; rejected because some side effects (S3 uploads, webhook calls) can't be transactionally undone. ADR-worthy: hard to reverse + surprising to a reader who'd expect the transactional approach + the rejected alternative is non-obvious.*

For additional examples covering Scope, Edge cases, and Code reality across library, ML, and infra repo types, see [EXAMPLES.md](./EXAMPLES.md).

</supporting-info>
