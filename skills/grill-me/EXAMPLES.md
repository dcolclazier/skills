# Worked Examples

The example in SKILL.md shows a CLI flag design with Terminology + Trade-offs. The three below cover the remaining axes (Scope, Edge cases, Code reality) and span different repo types. Read them once when entering a grill session to internalize the pattern; don't quote them at the user.

Each example shows a real branching flow — every Claude turn is informed by the previous user answer, not mechanically cycling axes.

## Example 1 — Library / SDK API design

**Scenario:** Adding a `retry` option to an HTTP client library. Edge-cases dominant.

> **User:** I want to add a `retry` option to our HTTP client.
>
> **Claude [Edge cases]:** Retry on what — network timeouts only, or also HTTP 5xx, or also 4xx? And only for idempotent methods (GET, PUT) or all methods?
> *Recommended: timeouts + 5xx + 429, idempotent methods only by default, with an opt-in flag for non-idempotent. Reason: retrying a non-idempotent POST silently is the most common production footgun in this category.*
>
> **User:** Timeouts and 5xx, idempotent only. No opt-in for now.
>
> **Claude [Edge cases]:** What about a request that's been received by the server but the response is lost? The client sees a timeout but the server already processed it.
> *Recommended: document this explicitly as a known limitation. Mitigation requires idempotency keys server-side, which is out of scope for the client. Adding the warning to the docstring prevents the most common bug.*
>
> **User:** Good point — add the warning.
>
> **Claude [Trade-offs]:** Backoff strategy — fixed delay, exponential, or exponential-with-jitter?
> *Recommended: exponential-with-jitter, capped at 30s. Fixed-delay rejected (thundering herd on shared outages); plain exponential rejected (same problem, slightly less bad). ADR-worthy: hard to change later because callers will rely on the timing characteristics.*

## Example 2 — ML training pipeline

**Scenario:** Adding validation evaluation. Code-reality dominant — the user's mental model contradicts the code.

> **User:** I want to add validation set evaluation every N steps so we can catch overfitting earlier.
>
> **Claude [Code reality]:** Reading `train.py:142` — the loop already calls `evaluate(val_loader)` every epoch. You mentioned "we don't have validation eval" — is the existing one broken, missing, or just not what you want?
> *Recommended (pending answer): the existing eval runs but only at epoch boundaries; you want intra-epoch eval for long epochs. That's the actual gap.*
>
> **User:** Right, our epochs take 4 hours. By the time we see overfitting it's already happened.
>
> **Claude [Scope]:** Intra-epoch eval at every N steps — N as a config flag, or hardcoded? And does it replace the epoch-boundary eval or run in addition to it?
> *Recommended: configurable N, defaulting to 0 (disabled — preserves current behavior); when enabled, runs in addition to epoch-boundary eval, not instead. Reason: keeps current pipeline behavior unchanged for callers who don't opt in.*
>
> **User:** Configurable, additive.
>
> **Claude [Trade-offs]:** Re-use the existing `evaluate()` path or fork a lighter intra-epoch variant? The existing path runs the full validation set; intra-epoch on the full set every N steps could dominate training time.
> *Recommended: re-use `evaluate()` but accept a `subset_fraction` arg defaulting to 1.0; intra-epoch calls pass 0.1. Avoids forked code paths and lets users tune the cost. Not ADR-worthy — easily reversible.*

## Example 3 — Infra module (Terraform / Kubernetes)

**Scenario:** Enabling autoscaling. Scope-heavy with a code-reality surprise.

> **User:** I want to add autoscaling to the worker fleet.
>
> **Claude [Scope]:** Which workers? Looking at `modules/workers/` I see three pools — `queue-consumers`, `scheduler`, and `batch-runners`. All three?
> *Recommended: queue-consumers only for v1. Scheduler is single-leader so autoscaling would break leader election; batch-runners run sized jobs and autoscaling would cause mid-job evictions.*
>
> **User:** Just queue-consumers, agreed.
>
> **Claude [Code reality]:** `modules/workers/queue-consumers/hpa.tf` already defines an HPA — but `enabled = false`. Was this attempted before? Should we re-enable or replace?
> *Recommended: investigate before deciding. Git blame might explain why it was disabled.*
>
> **User:** Yeah it caused thrashing last year. Replace.
>
> **Claude [Edge cases]:** What about scale-down during in-flight messages? Killing a consumer mid-message either re-queues (at-least-once) or drops it (at-most-once) depending on the broker config.
> *Recommended: combine HPA scale-down with a `terminationGracePeriodSeconds` longer than the longest expected message processing time, plus `preStop` hook draining the consumer. Otherwise you'll silently lose work during scale-down. ADR-worthy: the interaction between autoscaling and message delivery semantics is exactly the kind of decision a future reader would re-litigate without context.*
