# skills

Source of truth for personal Claude Code skills, plus the hooks and migration tooling that go with them.

## Layout

```
.
├── skills/         # → ~/.claude/skills (symlinked)
│   ├── diagnose/
│   ├── grill-me/
│   ├── ...
│   └── gemini-workflow-brief.md
├── hooks/          # → ~/.claude/hooks (symlinked)
│   ├── copilot-rerequest.sh        # PostToolUse on `git push` — re-requests Copilot review
│   └── pr-merge-teardown.sh        # PostToolUse on `gh pr merge` — branch teardown + triggers /post-merge-cleanup
├── migrate.sh      # push skills + hooks to other machines (Windows host, remote boxes)
└── README.md
```

The local machine consumes the repo directly via symlinks, so edits in this repo take effect immediately — no sync step.

## Why symlinks

Symlinking `~/.claude/{skills,hooks}` at the repo is what makes this a true source of truth: there's only one copy, edits land in version control as you make them, and there's no drift between "what Claude Code reads" and "what's in git". The alternative (rsync into `~/.claude/`) creates a second copy that can silently fall behind the repo. Symlink wherever you can; only fall back to `migrate.sh` for boxes that can't follow the symlink (true remote machines like spark2).

This applies to both sides of the WSL/Windows divide. The repo lives on the Windows filesystem (`C:\dev\skills`), so both WSL (`/mnt/c/dev/skills`) and Windows (`C:\dev\skills`) can symlink to it directly. Doing both eliminates the `migrate.sh windows` step entirely.

## Adding / removing a skill

Drop a directory under `skills/` with a `SKILL.md` (and any supporting files). Picked up next session. Delete the directory to remove — don't leave tombstones.

## Hooks

Two PostToolUse hooks support the engineering skill suite:

- **`copilot-rerequest.sh`** — runs after `git push`. If the current branch has an open PR with Copilot as a reviewer, re-requests a Copilot review automatically. Supports `/resolve-reviews`. Opt out per-session with `SKIP_COPILOT=true`.
- **`pr-merge-teardown.sh`** — runs after `gh pr merge`. Tears down the branch (local + remote), removes the worktree if any, updates dispatch state, and tells the agent's next turn to invoke `/post-merge-cleanup` for in-repo cleanup. Opt out with `SKIP_PR_TEARDOWN=true`.

Both fail silently with exit 0 — a broken hook never breaks your workflow.

These scripts only run if `~/.claude/settings.json` wires them up. See "Initial setup on a new machine" below for the snippet.

## Migrating to other machines

For machines that can't reach the repo's filesystem (true remotes like `spark2`), or where symlinking isn't viable (no admin, no Dev Mode), `migrate.sh` rsyncs `skills/` and `hooks/` separately to the right destinations. Prefer symlinks where you can — see "Why symlinks" above.

```
./migrate.sh windows           # → /mnt/c/Users/<user>/.claude/{skills,hooks}/
./migrate.sh spark2            # → bender@192.168.1.8:~/.claude/{skills,hooks}/
./migrate.sh all
./migrate.sh windows --dry-run
./migrate.sh spark2 --delete   # mirror exactly (delete dest files not in source)
```

Push only — the repo is the SoT, remote copies are downstream replicas. The script does not touch `settings.json` on the receiving side; each machine still needs the hook wiring (see below) the first time.

## Initial setup on a new machine

### WSL / Linux / macOS side

```bash
git clone <this-repo> ~/dev/skills

# Symlink skills, hooks, and the migrate script into ~/.claude/
mv ~/.claude/skills ~/.claude/skills.bak  2>/dev/null || true
mv ~/.claude/hooks  ~/.claude/hooks.bak   2>/dev/null || true
ln -s ~/dev/skills/skills      ~/.claude/skills
ln -s ~/dev/skills/hooks       ~/.claude/hooks
ln -s ~/dev/skills/migrate.sh  ~/.claude/migrate-skills.sh   # optional convenience
```

### Windows side (when the repo is on the Windows filesystem)

`mklink /D` needs an elevated terminal **or** Developer Mode enabled (Settings → Privacy & security → For developers → Developer Mode). With Dev Mode on, regular cmd/PowerShell can create symlinks without admin.

From an **elevated** Command Prompt (or any cmd if Dev Mode is on):

```cmd
move "%USERPROFILE%\.claude\skills" "%USERPROFILE%\.claude\skills.bak"
move "%USERPROFILE%\.claude\hooks"  "%USERPROFILE%\.claude\hooks.bak"
mklink /D "%USERPROFILE%\.claude\skills" "C:\dev\skills\skills"
mklink /D "%USERPROFILE%\.claude\hooks"  "C:\dev\skills\hooks"
```

Or PowerShell (elevated):

```powershell
Move-Item "$env:USERPROFILE\.claude\skills" "$env:USERPROFILE\.claude\skills.bak"
Move-Item "$env:USERPROFILE\.claude\hooks"  "$env:USERPROFILE\.claude\hooks.bak"
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.claude\skills" -Target "C:\dev\skills\skills"
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.claude\hooks"  -Target "C:\dev\skills\hooks"
```

Once both sides are symlinked, `migrate.sh windows` is no longer needed — the Windows-side `.claude/` reads the same files the WSL side does. Use `migrate.sh` only for true remote machines (e.g. `spark2`) that can't reach the repo's filesystem.

### Wire the hooks

Both sides need the hooks wired into their respective `settings.json` (merge with existing config — don't overwrite):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/home/<user>/.claude/hooks/copilot-rerequest.sh",
            "if": "Bash(git push *)",
            "timeout": 30
          },
          {
            "type": "command",
            "command": "/home/<user>/.claude/hooks/pr-merge-teardown.sh",
            "if": "Bash(gh pr merge *)",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

Replace `<user>` with the actual home path. On Windows-side `.claude/settings.json`, use Windows-style paths (e.g. `C:\\Users\\<user>\\.claude\\hooks\\copilot-rerequest.sh` — note the doubled backslashes inside JSON strings).

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

Two quality gates (`/score` upstream, `/self-review` pre-PR) and one back-bookend (`/post-merge-cleanup`) bracket the implementation. The PR-bookending hooks (`copilot-rerequest.sh`, `pr-merge-teardown.sh`) are what make `/resolve-reviews` and `/post-merge-cleanup` trigger automatically. See `skills/setup-workflow/WORKFLOW-PRIMER.md` for the full orientation.
