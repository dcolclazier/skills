#!/usr/bin/env bash
# Re-request a Copilot PR review after a successful `git push`.
#
# Wired as a Claude Code PostToolUse hook against the Bash tool. Receives the
# tool-use JSON via stdin; only acts if the command was a `git push` and the
# current branch has an open PR with Copilot listed as a reviewer or having
# previously reviewed.
#
# Opt-out: set SKIP_COPILOT=true in the environment to disable for one session.
#
# Failure mode: any error inside this script is silenced (stderr → /dev/null) and
# the script exits 0. A broken hook must never break the user's workflow.

# Read the tool-use JSON from stdin.
input=$(cat)

# Extract the command field. We avoid jq (not installed); use python for robust
# JSON parsing.
command=$(printf '%s' "$input" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''), end='')
except Exception:
    pass
" 2>/dev/null)

# Only act on git push commands. Match \`git push\` at start or after && / ; / |.
# We don't try to be perfect — false negatives just skip the re-request.
if ! printf '%s' "$command" | grep -qE '(^|[;&|]\s*)git\s+push(\s|$)'; then
    exit 0
fi

# Honor opt-out.
if [[ "${SKIP_COPILOT:-}" == "true" ]]; then
    exit 0
fi

# gh must be available and authenticated.
command -v gh >/dev/null 2>&1 || exit 0

# Fetch PR state for the current branch. If no PR, exit silently.
pr_json=$(gh pr view --json number,reviewRequests,reviews,headRefName 2>/dev/null) || exit 0
[[ -z "$pr_json" ]] && exit 0

# Decide whether Copilot applies + extract the PR number.
should_request=$(printf '%s' "$pr_json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

pr = d.get('number')
requests = d.get('reviewRequests', []) or []
reviews   = d.get('reviews', []) or []

def is_copilot(login):
    if not login: return False
    return 'copilot' in login.lower()

# Already requested (sitting in reviewRequests) OR has reviewed in the past.
copilot_in_requests = any(is_copilot((r.get('login') or r.get('name') or '')) for r in requests)
copilot_in_reviews  = any(is_copilot(((r.get('author') or {}).get('login') or '')) for r in reviews)

if pr and (copilot_in_requests or copilot_in_reviews):
    print(pr)
" 2>/dev/null)

[[ -z "$should_request" ]] && exit 0

# Re-request review. The reviewer slug for GitHub's built-in Copilot Code Review
# integration is 'copilot-pull-request-reviewer'. Failures (already-pending,
# permission denied, integration not on the repo) are swallowed.
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || exit 0

response=$(gh api --method POST \
    "/repos/$repo/pulls/$should_request/requested_reviewers" \
    -f 'reviewers[]=copilot-pull-request-reviewer' \
    2>&1) || true

# Brief, single-line note to stderr if the request landed; stays out of stdout
# so it doesn't pollute tool output.
if printf '%s' "$response" | grep -q '"requested_reviewers"'; then
    printf '[hook] Re-requested Copilot review on PR #%s\n' "$should_request" >&2
fi

exit 0
