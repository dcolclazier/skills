# Issue tracker: Local Markdown

> **Why this file exists.** The engineering skills (`/to-prd`, `/to-issues`, `/triage`) consult this file to know how to create, read, and update issues. With local markdown, "issues" are files in `.scratch/` — durable, private to the repo, and travel with checkouts.
>
> **Who reads it.** Every Claude session that runs an issue-related skill in this repo. The file is durable — it lives in your repo, not in a Claude session.
>
> **What to change later.** Adjust the directory layout or status-line conventions below if your workflow diverges (e.g., you prefer one file per slice instead of per feature). Rerun `/setup-workflow` if you switch to a hosted tracker.

Issues and PRDs for this repo live as markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The PRD is `.scratch/<feature-slug>/PRD.md`
- Implementation issues are `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01`
- Triage state is recorded as a `Status:` line near the top of each issue file (see `triage-labels.md` for the role strings)
- Comments and conversation history append to the bottom of the file under a `## Comments` heading

## When a skill says "publish to the issue tracker"

Create a new file under `.scratch/<feature-slug>/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.
