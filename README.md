# skills

Source of truth for personal Claude Code skills.

## Layout

Each top-level directory is a single skill. `~/.claude/skills` is a symlink to this repo, so Claude Code loads skills directly from here — edits in this repo take effect immediately on the local machine, no sync step required.

```
~/.claude/skills -> /mnt/c/dev/skills
```

## Adding a skill

Drop a new directory at the top level with a `SKILL.md` (and any supporting files the skill needs). It's picked up on the next session.

## Removing a skill

Delete the directory and commit. Don't leave tombstone files behind.

## Syncing to other machines

Other machines (Windows host, remote boxes) don't share the WSL filesystem, so they need an actual copy. `~/.claude/migrate-skills.sh` rsyncs from `~/.claude/skills/` (which resolves to this repo via the symlink) to those targets.

```
~/.claude/migrate-skills.sh windows           # → /mnt/c/Users/<user>/.claude/skills/
~/.claude/migrate-skills.sh spark2            # → bender@192.168.1.8:~/.claude/skills/
~/.claude/migrate-skills.sh all
~/.claude/migrate-skills.sh windows --dry-run
```

The script does not pull — only push. The repo is always the SoT; remote copies are downstream replicas.

## Initial setup on a new machine

```
git clone <this-repo> /path/to/skills
mv ~/.claude/skills ~/.claude/skills.bak  # if it exists
ln -s /path/to/skills ~/.claude/skills
```

## Per-repo setup

Once skills are installed on the machine, wire each repo that wants to use the engineering suite (`grill-me`, `to-prd`, `score`, `to-issues`, `triage`, `tdd`, `self-review`, `resolve-reviews`, `post-merge-cleanup`, `diagnose`, `improve-codebase-architecture`, `zoom-out`) by running the bootstrapping skill from inside that repo:

```
/setup-workflow
```

It detects the repo's starting state and walks you through three sections, one at a time. On first run it offers an opt-in 2-minute tutorial — take it if you're new to the suite.

**What it writes**

- `## Agent skills` block in `CLAUDE.md` (or `AGENTS.md` if that's the convention the repo uses) — three short sub-sections pointing at the config files.
- `docs/agents/issue-tracker.md` — where issues live (GitHub / GitLab / local markdown / other) and the CLI used to create, comment on, and label them. Read by `to-prd`, `to-issues`, `triage`, `tdd`, `resolve-reviews`, `post-merge-cleanup`.
- `docs/agents/triage-labels.md` — the five canonical triage roles (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`) mapped to the actual label strings your tracker uses. Read by `triage`, `tdd`, `post-merge-cleanup`.
- `docs/agents/domain.md` — single-context (`CONTEXT.md` + `docs/adr/` at the root) vs multi-context (`CONTEXT-MAP.md` + per-context `CONTEXT.md` files). Read by `grill-me`, `tdd`, `diagnose`, `improve-codebase-architecture`, `score`, `self-review`, `resolve-reviews`, `post-merge-cleanup`.

**What it does NOT write on first run**

The PR-bookending posture configs — `docs/agents/self-review.md`, `docs/agents/resolve-reviews.md`, `docs/agents/post-merge-cleanup.md`. Each holds one line (`posture: auto|draft|comment-only`) controlling how aggressively the skill acts unattended. Created lazily the first time you lock in a posture for that skill, after you've actually used it and have informed taste.

**Reruns**

Rerunning `/setup-workflow` is section-scoped and non-destructive. It detects which sections are already configured vs manually edited and asks which to update. Manual edits in `docs/agents/*.md` are preserved unless you explicitly confirm overwrite.

**The pipeline these files unlock**

```
grill-me → to-prd → /score(prd) → to-issues → triage → tdd
        → /self-review → PR → /resolve-reviews → merge → /post-merge-cleanup
```

Two quality gates (`/score` upstream, `/self-review` pre-PR) and one back-bookend (`/post-merge-cleanup`) bracket the implementation. See `setup-workflow/WORKFLOW-PRIMER.md` for the full orientation.
