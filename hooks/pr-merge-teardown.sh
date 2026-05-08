#!/usr/bin/env bash
# Lifecycle teardown after a successful `gh pr merge`.
#
# What this does:
#   1. Detects whether the just-run Bash command was `gh pr merge` and succeeded.
#   2. Resolves the merged PR's branch name.
#   3. Tears down the branch (local + remote), removes the worktree if any,
#      and updates dispatch state.json if applicable.
#   4. Outputs JSON with `hookSpecificOutput.additionalContext` so the agent's
#      next turn knows to invoke /post-merge-cleanup for the in-repo cleanup
#      (TODOs, instrumentation, CHANGELOG, sub-issues).
#
# Opt-out: SKIP_PR_TEARDOWN=true
#
# Failure mode: silenced + exit 0. Never break the user's flow.

set +e

input=$(cat)

# --- Helpers --------------------------------------------------------------

extract_command() {
    printf '%s' "$1" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''), end='')
except Exception:
    pass
" 2>/dev/null
}

extract_exit_code() {
    printf '%s' "$1" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    r = d.get('tool_response', {}) or {}
    # Common shapes the harness uses for Bash response
    for k in ('exit_code', 'exitCode', 'returncode'):
        if k in r:
            print(r[k]); break
    else:
        # Fall back to 'success' boolean if exit_code not present
        print(0 if r.get('success') else 1)
except Exception:
    print(1)
" 2>/dev/null
}

# --- Filters --------------------------------------------------------------

if [[ "${SKIP_PR_TEARDOWN:-}" == "true" ]]; then exit 0; fi

command_str=$(extract_command "$input")

# Only act on `gh pr merge` invocations. Be permissive about position
# (allow leading subshells, env vars, etc.) but require the verb sequence.
if ! printf '%s' "$command_str" | grep -qE '(^|[[:space:]&|;]+)gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)'; then
    exit 0
fi

# Only act if the command actually succeeded.
exit_code=$(extract_exit_code "$input")
[[ "$exit_code" != "0" ]] && exit 0

command -v gh >/dev/null 2>&1 || exit 0

# --- Resolve PR + branch --------------------------------------------------

# Try explicit `gh pr merge <N>`; fall back to current-branch lookup.
pr_num=$(printf '%s' "$command_str" | grep -oE 'gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
if [[ -z "$pr_num" ]]; then
    pr_num=$(gh pr view --json number -q .number 2>/dev/null)
fi
[[ -z "$pr_num" ]] && exit 0

branch=$(gh pr view "$pr_num" --json headRefName -q .headRefName 2>/dev/null)
[[ -z "$branch" ]] && exit 0

# Never delete protected branches even if a PR was somehow merged from one.
case "$branch" in
    main|master|trunk|develop|production|prod)
        exit 0
        ;;
esac

# --- Teardown ------------------------------------------------------------

actions=()

# If the merge command already passed --delete-branch, gh handled it for us;
# skip our own delete to avoid noisy "branch not found" errors.
already_deleted=false
if printf '%s' "$command_str" | grep -qE -- '--delete-branch|--delete'; then
    already_deleted=true
fi

if [[ "$already_deleted" != true ]]; then
    if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
        if git branch -D "$branch" 2>/dev/null; then
            actions+=("deleted local branch $branch")
        fi
    fi
    if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
        if git push origin --delete "$branch" >/dev/null 2>&1; then
            actions+=("deleted remote branch origin/$branch")
        fi
    fi
fi

# Worktree teardown — find by branch ref.
worktree_path=$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$branch" '
    /^worktree / { wt=$2 }
    /^branch / && $2 == b { print wt }
' | head -1)

if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
    if git worktree remove --force "$worktree_path" 2>/dev/null; then
        actions+=("removed worktree $worktree_path")
    fi
fi

# Update dispatch state.json files (if any reference this PR/branch).
state_files_updated=0
for state in .scratch/dispatch-*/state.json; do
    [[ -f "$state" ]] || continue
    if grep -qE "(\"$branch\"|\"#?$pr_num\")" "$state" 2>/dev/null; then
        STATE_PATH="$state" PR_NUM="$pr_num" BRANCH="$branch" python3 -c "
import json, os, sys, datetime
path = os.environ['STATE_PATH']
pr_num = os.environ['PR_NUM']
branch = os.environ['BRANCH']
try:
    with open(path) as f: d = json.load(f)
except Exception:
    sys.exit(0)
issues = d.get('issues') or d.get('per_issue') or {}
changed = False
items = issues.items() if isinstance(issues, dict) else enumerate(issues)
for k, v in items:
    if not isinstance(v, dict): continue
    if str(v.get('issue', '')).lstrip('#') == pr_num.lstrip('#') or v.get('branch') == branch:
        v['state'] = 'completed'
        v['merged_at'] = datetime.datetime.now().isoformat(timespec='seconds')
        changed = True
if changed:
    with open(path, 'w') as f:
        json.dump(d, f, indent=2)
    print('updated', file=sys.stderr)
" 2>/dev/null && state_files_updated=$((state_files_updated + 1))
    fi
done
[[ $state_files_updated -gt 0 ]] && actions+=("updated $state_files_updated dispatch state file(s)")

# --- Output --------------------------------------------------------------

# Always inject a nudge to run /post-merge-cleanup, even if no teardown actions
# fired (the agent still needs to handle the in-repo cleanup).
summary=""
if [[ ${#actions[@]} -gt 0 ]]; then
    summary="Lifecycle teardown for PR #${pr_num}: $(IFS=', '; echo "${actions[*]}")."
else
    summary="PR #${pr_num} merged. No branch/worktree teardown needed."
fi

system_msg="${summary} Now run \`/post-merge-cleanup\` to handle the in-repo cleanup (close issue, strip TODOs, draft CHANGELOG, surface judgment-call items)."
context_msg="Lifecycle hook ran after \`gh pr merge\` for PR #${pr_num} on branch \`${branch}\`. ${summary} The agent should invoke /post-merge-cleanup next — branch teardown is done; the skill handles the agent-context-rich cleanup (TODOs that referenced this PR, temp instrumentation added during diagnose, CHANGELOG entry, sub-issue closes, follow-up scheduling, judgment-call items like feature-flag rollout)."

python3 -c "
import json
print(json.dumps({
    'systemMessage': '''$system_msg''',
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'additionalContext': '''$context_msg'''
    }
}))
" 2>/dev/null

exit 0
