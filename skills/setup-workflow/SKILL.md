---
name: setup-workflow
description: Bootstraps per-repo configuration for the engineering skill suite (grill-me, to-prd, score, to-issues, triage, tdd, self-review, resolve-reviews, post-merge-cleanup, diagnose, improve-codebase-architecture, zoom-out). Writes a `## Agent skills` block in CLAUDE.md/AGENTS.md plus the core config files in `docs/agents/` that downstream skills consume. Includes an opt-in 2-minute tutorial for first-time users. Run once per repo before using the workflow; rerun later for guided, section-scoped updates (switch tracker, adjust labels, change context layout, set posture for the PR-bookending skills). Use when the user says set up engineering skills, configure this repo for the workflow, set up triage, set up agent skills, or onboard a junior dev to the skill suite.
disable-model-invocation: true
---

# Setup Engineering Workflow

Scaffold the per-repo configuration that the engineering skill suite consumes:

- **Issue tracker** — where issues live (GitHub, GitLab, local markdown, or other). Read by `to-prd`, `to-issues`, `triage`, `tdd`, `resolve-reviews`, `post-merge-cleanup`.
- **Triage labels** — strings used for the five canonical triage roles. Read by `triage`, `tdd`, `post-merge-cleanup`.
- **Domain docs** — where `CONTEXT.md` and ADRs live, and how they're consumed. Read by `grill-me`, `tdd`, `diagnose`, `improve-codebase-architecture`, `score` (when scoring artifacts that must use canonical vocabulary), `self-review`, `resolve-reviews`, `post-merge-cleanup`.
- **PR-bookending posture configs (optional)** — `docs/agents/self-review.md`, `docs/agents/resolve-reviews.md`, `docs/agents/post-merge-cleanup.md`. Each holds a `posture: auto|draft|comment-only` line that controls how aggressively the skill acts unattended. Not scaffolded on first run — created lazily when a junior dev locks in a posture for that skill. The same three-way model is shared across all three skills, so a junior dev learns one mental model that brackets the whole PR lifecycle. *Why optional:* postures are project-policy decisions (does branch protection + CI catch what we miss? do reviewers want to see drafts first?), so we don't pick one for the user — each skill asks at first run if no config exists, and the user can lock the answer in by hand.

**This skill teaches as it configures.** Every decision is presented with its downstream impact so junior devs adopting the workflow understand *why* each piece exists, not just *what* it is. Reruns are section-scoped and non-destructive — manual edits are preserved unless explicitly overwritten.

This is a prompt-driven skill, not a deterministic script. Explore, present what you found, confirm with the user, then write.

## Process

### 0. Tutorial (opt-in)

Before exploring, offer the tutorial:

> "Want a 2-minute tutorial on what these skills do before we set up your repo?
>
> - **yes** — walk me through it *(recommended if you're new to this workflow)*
> - **no** — skip the tutorial, go straight to setup"

- **yes** — read [WORKFLOW-PRIMER.md](./WORKFLOW-PRIMER.md), summarise the four failure modes + pipeline shape in your own words, then ask "Ready to set up your repo?" and proceed to step 1.
- **no** — proceed directly to step 1.

### 1. Explore

Look at the current repo to understand its starting state. Read whatever exists; don't assume:

- `git remote -v` and `.git/config` — GitHub? GitLab? Self-hosted? No remote?
- `AGENTS.md` and `CLAUDE.md` at the repo root — does either exist? Is there already an `## Agent skills` section in either?
- `CONTEXT.md` and `CONTEXT-MAP.md` at the repo root.
- `docs/adr/` and any `src/*/docs/adr/` directories.
- `docs/agents/` — does this skill's prior output already exist? Read each file present.
- `.scratch/` — sign that a local-markdown issue tracker convention is already in use.

**Detect which sections are already configured.** For each of the three (issue tracker, triage labels, domain docs), classify the corresponding `docs/agents/*.md` file as:

- **not configured** — file doesn't exist
- **configured** — file exists and matches a known seed template
- **manually edited** — file exists but diverges from any seed template (treat as user-customised; don't silently overwrite)

Report findings before asking anything:

> "Found: existing `docs/agents/issue-tracker.md` configured for GitHub. `docs/agents/triage-labels.md` looks manually edited — your labels are `bug:triage`, `bug:ready`, etc. `docs/agents/domain.md` not yet configured."

### 2. Present and ask

**If all three sections are not-configured (first run):** walk through Sections A → B → C below in order. One section at a time. Wait for the user's response before moving to the next. Don't dump all three at once.

**If any section is already configured:** ask which sections to change.

> "Which sections would you like to update? [Issue tracker / Labels / Domain docs / All / None — just confirm what's already there.]"

Then walk through only the chosen sections.

For each section, the explainer is **required, not optional** — junior devs adopting the workflow need to understand the *why*, not just answer questions. Treat the explainer text as load-bearing content.

**Section A — Issue tracker.**

> *Why this matters:* The skills `to-prd`, `to-issues`, and `triage` write and read issues. They need to know whether to call `gh issue create`, `glab issue create`, or write a markdown file under `.scratch/`. If the skill picks the wrong tool, every downstream step silently breaks — `to-issues` would create GitHub issues even though your team uses Jira. The setting is per-repo (different repos can use different trackers).

Default posture: detect from `git remote`.

- **GitHub remote** → propose GitHub.
- **GitLab remote** (`gitlab.com` or self-hosted) → propose GitLab.
- **No remote / other** → propose Local markdown unless the user prefers otherwise.

Choices:

- **GitHub** — issues live in GitHub Issues. Uses the `gh` CLI. *Recommended when your team's actual workflow is GitHub Issues; not just because the repo is on GitHub.*
- **GitLab** — issues live in GitLab Issues. Uses the [`glab`](https://gitlab.com/gitlab-org/cli) CLI. *GitLab calls comments "notes" and uses `opened` (not `open`) for issue state — the seed template handles this.*
- **Local markdown** — issues as files under `.scratch/<feature>/`. *Best for solo projects, prototypes, or repos without a remote. Issues stay private to the repo and travel with checkouts.*
- **Other** (Jira, Linear, ClickUp, etc.) — see "Other tracker" below.

**For "Other" trackers, ask three follow-ups, one at a time:**

1. *"How are issues created in your tracker — CLI, web UI only, or API?"* (Determines whether automation is possible. If web UI only, downstream skills will need to defer to a human for issue creation rather than running automatically — record this clearly in the generated `issue-tracker.md`.)
2. *"How is issue state recorded — labels, custom fields, status column, something else?"* (Determines how `triage` will apply state.)
3. *"What CLI or API endpoint would you use to automate creation/comments/labels?"* (e.g., `jira issue create`, `linear-cli issue create`, REST endpoint with curl.)

Then write `docs/agents/issue-tracker.md` from the user's answers, **mirroring the structure of [issue-tracker-github.md](./issue-tracker-github.md)** — the same headings (Conventions / "publish to the issue tracker" / "fetch the relevant ticket") so downstream skills find what they expect. Don't skip headings even if a section is "the user opens the web UI manually" — say so explicitly.

**Section B — Triage label vocabulary.**

> *Why this matters:* The `triage` skill processes incoming issues through a state machine — needs evaluation, waiting on reporter, ready for an AFK agent, ready for a human, or won't fix. To do that it applies labels (or the equivalent in your tracker). If the skill's labels don't match what your repo *already uses*, you get duplicate labels (e.g. both `needs-triage` and `bug:triage`) and broken triage runs. This file maps each canonical role to the actual string in your tracker.

The five canonical roles:

- `needs-triage` — maintainer needs to evaluate
- `needs-info` — waiting on reporter
- `ready-for-agent` — fully specified, AFK-ready (an agent can pick it up with no human context)
- `ready-for-human` — needs human implementation
- `wontfix` — will not be actioned

> *Default: each role's string equals its name.* Recommended unless your tracker already has labels with conflicting meaning — keeping the canonical names across repos makes `triage`'s behavior predictable. Override when your team's existing labels already cover one of these roles (e.g. `bug:triage` already exists — map `needs-triage` to it instead of creating a duplicate).

If the tracker has no existing labels, the defaults are fine. The skill applies them on first triage run.

**Section C — Domain docs.**

> *Why this matters:* The skills `grill-me`, `tdd`, `diagnose`, and `improve-codebase-architecture` read `CONTEXT.md` (your project's domain glossary) and `docs/adr/` (past architectural decisions). They need to know whether the repo has one global context or multiple, so they look in the right place. Wrong layout means the skills miss your glossary entirely and start inventing language — exactly the verbosity / jargon-drift problem the workflow exists to prevent.

Confirm the layout:

- **Single-context** — one `CONTEXT.md` + `docs/adr/` at the repo root. *Most repos.*
- **Multi-context** — `CONTEXT-MAP.md` at the root pointing to per-context `CONTEXT.md` files. *Typically a monorepo with multiple distinct domains, each with their own glossary.*

If neither file exists yet, that's fine — `grill-me` creates them lazily when terms or decisions get resolved. The setup just records which layout to expect.

### 3. Confirm and edit

Show the user a draft of:

- The `## Agent skills` block being added/updated in `CLAUDE.md` / `AGENTS.md`.
- The contents of each `docs/agents/*.md` file being written or updated.

For files being **updated** (not freshly written), show a unified diff. Let the user edit before writing.

For sections classified as **manually edited** in step 1, do not overwrite without explicit confirmation:

> "`docs/agents/triage-labels.md` looks manually edited (your labels diverge from the seed template). Confirm overwrite? Your customisations will be lost."

If they confirm: proceed. If they decline: skip that section, leave it untouched.

### 4. Write

**Pick the file to edit (CLAUDE.md vs AGENTS.md):**

- If `CLAUDE.md` exists, edit it.
- Else if `AGENTS.md` exists, edit it.
- If neither exists, ask the user which to create — don't pick for them. Brief explainer: *"`CLAUDE.md` is read by Claude Code specifically; `AGENTS.md` is the more generic convention read by multiple agent tools. Pick whichever fits your team."*

Never create `AGENTS.md` when `CLAUDE.md` already exists (or vice versa) — always edit the one that's there.

If an `## Agent skills` block already exists in the chosen file, update its contents in-place rather than appending a duplicate. Don't touch sections outside it.

The block:

```markdown
## Agent skills

### Issue tracker

[one-line summary of where issues are tracked]. See `docs/agents/issue-tracker.md`.

### Triage labels

[one-line summary of the label vocabulary]. See `docs/agents/triage-labels.md`.

### Domain docs

[one-line summary of layout — "single-context" or "multi-context"]. See `docs/agents/domain.md`.
```

Then write the three docs files using the seed templates in this skill folder as starting points:

- [issue-tracker-github.md](./issue-tracker-github.md) — GitHub
- [issue-tracker-gitlab.md](./issue-tracker-gitlab.md) — GitLab
- [issue-tracker-local.md](./issue-tracker-local.md) — local markdown
- [triage-labels.md](./triage-labels.md) — label mapping
- [domain.md](./domain.md) — domain doc consumer rules

For "Other" issue trackers, write `docs/agents/issue-tracker.md` from scratch using the user's answers to the three follow-up questions, mirroring the structure of the GitHub template.

Each seed template includes a teaching preamble (why this file exists / who reads it / what to change later). Preserve it when writing into the target repo — it's part of the durable education layer.

### 5. Done

Tell the user:

1. **What was written/changed** — list each file with a one-line description (created / updated / preserved-on-decline).
2. **Which engineering skills now read from these files** — `grill-me`, `to-prd`, `score` (when grounding in canonical vocabulary), `to-issues`, `triage`, `tdd`, `self-review`, `resolve-reviews`, `post-merge-cleanup`, `diagnose`, `improve-codebase-architecture`, `zoom-out`.
3. **The pipeline at a glance** — point the user at `WORKFLOW-PRIMER.md` for the full per-feature pipeline, but mention the shape: `grill-me → to-prd → /score(prd) → to-issues → triage → tdd → /self-review → PR → /resolve-reviews → merge → /post-merge-cleanup`. Two quality gates (`/score` upstream, `/self-review` pre-PR) and one back-bookend (`/post-merge-cleanup`) bracket the implementation. If the user is brand-new, recommend the tutorial.
4. **PR-bookending postures (optional, lazy)** — three skills (`/self-review`, `/resolve-reviews`, `/post-merge-cleanup`) share a posture model (`auto` / `draft` / `comment-only`). On first invocation each will ask which posture to use; the answer can be locked in by writing `posture: <name>` to `docs/agents/<skill>.md`. Don't scaffold these on first setup — let the user lock them in once they've actually used the skill and have informed taste. Surface the option here so they know it exists.
5. **How to update later** — small tweaks: edit `docs/agents/*.md` directly. Larger changes (switch tracker, change layout): rerun `/setup-workflow` for a guided, section-scoped update. Reruns detect existing config and only change what the user explicitly chooses to change.
6. **Suggested next step** — usually `/grill-me` on a plan, then `/to-prd`, then `/score --rubric prd <issue-ref>` (the upstream gate), then `/to-issues`. If the user skipped the tutorial and wants context, mention they can read `WORKFLOW-PRIMER.md` directly.
