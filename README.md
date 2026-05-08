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
