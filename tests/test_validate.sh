#!/usr/bin/env bash
# Test runner for validate.sh — pure bash, no test framework dependency.
# Exits 0 if all tests pass, non-zero if any fail.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATE="$REPO_ROOT/validate.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/skills"

PASS=0
FAIL=0
FAILURES=()

assert_pass() {
    local label="$1"
    local target="$2"
    if bash "$VALIDATE" "$target" >/dev/null 2>&1; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (expected validate to ACCEPT, but it rejected)"
        FAIL=$((FAIL + 1))
        FAILURES+=("$label")
    fi
}

# assert_reject: like assert_pass but expects non-zero exit, AND optionally
# asserts the stderr error message contains a given substring (locks in *which*
# rejection path fired, so a regression that rejects for the wrong reason
# doesn't pass green).
assert_reject() {
    local label="$1"
    local target="$2"
    local expected_stderr_fragment="${3:-}"

    local stderr
    stderr=$(bash "$VALIDATE" "$target" 2>&1 >/dev/null)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "  FAIL: $label (expected validate to REJECT, but it accepted)"
        FAIL=$((FAIL + 1))
        FAILURES+=("$label")
        return
    fi

    if [ -n "$expected_stderr_fragment" ] && ! grep -qF "$expected_stderr_fragment" <<< "$stderr"; then
        echo "  FAIL: $label (rejected, but stderr missing expected fragment '$expected_stderr_fragment'; got: $stderr)"
        FAIL=$((FAIL + 1))
        FAILURES+=("$label")
        return
    fi

    echo "  PASS: $label"
    PASS=$((PASS + 1))
}

echo "== Fixture acceptance tests =="
assert_pass   "valid-minimal accepted"            "$FIXTURES/valid-minimal/SKILL.md"
assert_pass   "valid-with-argument-hint accepted" "$FIXTURES/valid-with-argument-hint/SKILL.md"
assert_pass   "valid-with-deps accepted"          "$FIXTURES/valid-with-deps/SKILL.md"

echo
echo "== Fixture rejection tests =="
assert_reject "invalid-missing-name rejected"             "$FIXTURES/invalid-missing-name/SKILL.md"             "missing required field 'name'"
assert_reject "invalid-missing-requires rejected"         "$FIXTURES/invalid-missing-requires/SKILL.md"         "missing required field 'requires-"
assert_reject "invalid-malformed-yaml rejected"           "$FIXTURES/invalid-malformed-yaml/SKILL.md"           "malformed YAML"
assert_reject "invalid-unknown-field rejected"            "$FIXTURES/invalid-unknown-field/SKILL.md"            "unknown field 'wat'"
assert_reject "invalid-missing-close-frontmatter rejected" "$FIXTURES/invalid-missing-close-frontmatter/SKILL.md" "unterminated frontmatter"
assert_reject "invalid-frontmatter-not-at-start rejected" "$FIXTURES/invalid-frontmatter-not-at-start/SKILL.md" "opening --- delimiter must be on line 1"
assert_reject "non-existent file rejected"                "$FIXTURES/does-not-exist/SKILL.md"                   "target not found"

echo
echo "== Real-codebase acceptance test =="
assert_pass   "skills/ dir accepted (whole codebase)" "$REPO_ROOT/skills"

echo
echo "== Summary =="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ $FAIL -gt 0 ]; then
    echo "Failures:"
    for f in "${FAILURES[@]}"; do
        echo "  - $f"
    done
    exit 1
fi
exit 0
