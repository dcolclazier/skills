#!/usr/bin/env bash
# migrate — push skills + hooks from this repo to other machines.
#
# This script lives in the SoT repo. The local machine consumes the repo
# directly via symlinks (~/.claude/skills, ~/.claude/hooks), so no sync is
# needed locally. Other machines (Windows host, remote boxes) need an actual
# copy because they can't follow WSL paths — that's what this script does.
#
# Usage:
#   ./migrate.sh windows                # WSL → /mnt/c/Users/<user>/.claude/{skills,hooks}/
#   ./migrate.sh spark2                 # WSL → bender@192.168.1.8:~/.claude/{skills,hooks}/
#   ./migrate.sh all                    # windows + spark2
#   ./migrate.sh windows --dry-run      # show what would change, copy nothing
#   ./migrate.sh spark2  --delete       # also delete dest files not in source
#
# Targets (extend by adding a case branch below):
#   windows  — local Windows-side .claude (auto-detects user via /mnt/c/Users/*/.claude)
#   spark2   — DGX Spark #2 (spark-45aa, 192.168.1.8) — needs `ssh spark2` to work key-based
#
# Notes:
#   - rsync is required.
#   - For spark2: SSH key auth must be set up (see ~/.ssh/config `Host spark2` entry).
#       ssh-keygen -t ed25519 -f ~/.ssh/spark2 -N ''
#       ssh-copy-id -i ~/.ssh/spark2.pub bender@192.168.1.8
#   - Default behavior is non-destructive (no --delete). Pass --delete to mirror exactly.
#   - This script does NOT touch settings.json on the remote — receiving machines
#     must wire the hooks into their own settings.json (PostToolUse on Bash,
#     `if` matching `git push *` and `gh pr merge *`). See README for the snippet.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SOURCE="$SCRIPT_DIR/skills/"
HOOKS_SOURCE="$SCRIPT_DIR/hooks/"
SPARK_REMOTE_HOME="/home/bender/.claude"

DRY_RUN=""
DELETE_FLAG=""
TARGETS=()

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//' | sed '$d'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN="--dry-run" ;;
    --delete)     DELETE_FLAG="--delete" ;;
    -h|--help)    usage; exit 0 ;;
    windows|spark2) TARGETS+=("$1") ;;
    all)          TARGETS+=("windows" "spark2") ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "Pick a target: windows, spark2, or all (windows + spark2)." >&2
  usage >&2
  exit 2
fi

if ! command -v rsync &>/dev/null; then
  echo "rsync not found. Install it first (apt install rsync)." >&2
  exit 1
fi

[[ -d "$SKILLS_SOURCE" ]] || { echo "Skills source not found: $SKILLS_SOURCE" >&2; exit 1; }
[[ -d "$HOOKS_SOURCE" ]]  || { echo "Hooks source not found: $HOOKS_SOURCE"  >&2; exit 1; }

detect_windows_user_dir() {
  for u in /mnt/c/Users/*/; do
    if [[ -d "${u}.claude" ]]; then
      echo "${u}.claude"
      return 0
    fi
  done
  return 1
}

sync_windows() {
  local dest_root
  if ! dest_root=$(detect_windows_user_dir); then
    echo "Couldn't find a Windows-side .claude under /mnt/c/Users/*/. Skipping." >&2
    return 1
  fi
  mkdir -p "$dest_root/skills" "$dest_root/hooks"
  echo "[windows] Syncing skills → $dest_root/skills/"
  rsync -av $DRY_RUN $DELETE_FLAG "$SKILLS_SOURCE" "$dest_root/skills/"
  echo "[windows] Syncing hooks  → $dest_root/hooks/"
  rsync -av $DRY_RUN $DELETE_FLAG "$HOOKS_SOURCE" "$dest_root/hooks/"
}

sync_spark2() {
  local alias="spark2"
  if ! ssh -o BatchMode=yes -o ConnectTimeout=3 "$alias" 'true' 2>/dev/null; then
    echo "[$alias] Key-based SSH not working. Set up the alias + key in ~/.ssh/config first:" >&2
    echo "       ssh-keygen -t ed25519 -f ~/.ssh/$alias -N ''" >&2
    echo "       ssh-copy-id -i ~/.ssh/$alias.pub bender@192.168.1.8" >&2
    return 1
  fi
  echo "[$alias] Syncing skills → $alias:$SPARK_REMOTE_HOME/skills/"
  rsync -av $DRY_RUN $DELETE_FLAG -e ssh "$SKILLS_SOURCE" "$alias:$SPARK_REMOTE_HOME/skills/"
  echo "[$alias] Syncing hooks  → $alias:$SPARK_REMOTE_HOME/hooks/"
  rsync -av $DRY_RUN $DELETE_FLAG -e ssh "$HOOKS_SOURCE"  "$alias:$SPARK_REMOTE_HOME/hooks/"
}

exit_code=0
for target in "${TARGETS[@]}"; do
  case "$target" in
    windows) sync_windows  || exit_code=$? ;;
    spark2)  sync_spark2   || exit_code=$? ;;
  esac
done

if [[ $exit_code -eq 0 ]]; then
  echo "Done."
else
  echo "Done with errors (some targets skipped or failed)." >&2
fi
exit $exit_code
