# Issue tracker: GitLab

> **Why this file exists.** The engineering skills (`/to-prd`, `/to-issues`, `/triage`) consult this file to know how to create, read, comment on, and label issues in your tracker. Without it, those skills can't act on issues at all.
>
> **Who reads it.** Every Claude session that runs an issue-related skill in this repo. The file is durable — it lives in your repo, not in a Claude session.
>
> **What to change later.** Add or adjust `glab` patterns below if your repo has special conventions. GitLab calls comments "notes" and uses `opened` (not `open`) for issue state — those quirks are baked in below; preserve them. Rerun `/setup-workflow` if you switch trackers entirely.

Issues and PRDs for this repo live as GitLab issues. Use the [`glab`](https://gitlab.com/gitlab-org/cli) CLI for all operations.

## Conventions

- **Create an issue**: `glab issue create --title "..." --description "..."`. Use a heredoc for multi-line descriptions. Pass `--description -` to open an editor.
- **Read an issue**: `glab issue view <number> --comments`. Use `-F json` for machine-readable output.
- **List issues**: `glab issue list --state opened -F json` with appropriate `--label` filters. Note that GitLab uses `opened` (not `open`) for the state value.
- **Comment on an issue**: `glab issue note <number> --message "..."`. GitLab calls comments "notes".
- **Apply / remove labels**: `glab issue update <number> --label "..."` / `--unlabel "..."`. Multiple labels can be comma-separated or by repeating the flag.
- **Close**: `glab issue close <number>`. `glab issue close` does not accept a closing comment, so post the explanation first with `glab issue note <number> --message "..."`, then close.
- **Merge requests**: GitLab calls PRs "merge requests". Use `glab mr create`, `glab mr view`, `glab mr note`, etc. — the same shape as `gh pr ...` with `mr` in place of `pr` and `note`/`--message` in place of `comment`/`--body`.

Infer the repo from `git remote -v` — `glab` does this automatically when run inside a clone.

## When a skill says "publish to the issue tracker"

Create a GitLab issue.

## When a skill says "fetch the relevant ticket"

Run `glab issue view <number> --comments`.
