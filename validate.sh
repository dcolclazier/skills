#!/usr/bin/env bash
# validate.sh — frontmatter validator for engineering-skills plugin SKILL.md files.
# Usage:
#   bash validate.sh                  # validate skills/ (default)
#   bash validate.sh <path>           # validate a single SKILL.md file
#   bash validate.sh <directory>      # recurse and validate every SKILL.md under it
#
# Exits 0 if all targets pass, non-zero if any fail.
# See skills/_format/FRONTMATTER-SPEC.md for the contract.

set -uo pipefail

# Keep these arrays in sync with skills/_format/FRONTMATTER-SPEC.md.
# Adding/removing fields here without updating the spec doc creates contract drift
# that neither side surfaces.
KNOWN_FIELDS=(name description argument-hint disable-model-invocation requires-skills requires-config)
REQUIRED_FIELDS=(name description requires-skills requires-config)

# Extract the YAML frontmatter block (between the first two `---` lines).
# Prints the frontmatter body to stdout. Exits awk with status 2 if no opening
# `---` is found, or with status 3 if the closing `---` is missing (file has
# `---` at top but no matching close — the entire body would otherwise be
# silently treated as frontmatter). Returns 0 on success.
extract_frontmatter() {
    local file="$1"
    awk '
        BEGIN { n = 0 }
        /^---$/ {
            n++
            if (n == 1) { in_block = 1; next }
            if (n == 2) { found_close = 1; exit }
        }
        in_block && !/^---$/ { print }
        END {
            if (n == 0) exit 2
            if (!found_close) exit 3
        }
    ' "$file"
}

# Return 0 if YAML frontmatter is well-formed enough for our limited subset:
#   - Top-level keys are `key:` at start of line (no indentation)
#   - Quoted string values (starting with " or ') must close their quote on the same line
#   - Arrays are either `[]` inline or block-style with indented `-` items
# Apostrophes inside unquoted free-text values are NOT flagged (English contractions
# like "you're" / "PRD's" appear in real descriptions and aren't a YAML problem).
# This is intentionally a narrow grammar, not full YAML.
yaml_wellformed() {
    local frontmatter="$1"

    while IFS= read -r line; do
        [ -z "$line" ] && continue                # blank lines OK
        [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]] && continue  # list items OK
        [[ "$line" =~ ^[[:space:]]+[^:[:space:]] ]] && continue # indented continuation OK (loose)

        # Check key shape on top-level lines: must be `<key>:` or `<key>: <value>`.
        if ! [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*:[[:space:]]*.*$ ]]; then
            return 1
        fi

        # Extract value portion (everything after the first colon + optional whitespace).
        local value
        value=$(echo "$line" | sed -E 's/^[a-zA-Z_][a-zA-Z0-9_-]*:[[:space:]]*//')

        # If the value starts with a double-quote, it must end with one.
        if [[ "$value" =~ ^\" ]] && [[ ! "$value" =~ \"[[:space:]]*$ ]]; then
            return 1
        fi
        # If the value starts with a single-quote, it must end with one.
        if [[ "$value" =~ ^\' ]] && [[ ! "$value" =~ \'[[:space:]]*$ ]]; then
            return 1
        fi
    done <<< "$frontmatter"

    return 0
}

# Return the list of top-level field names declared in the frontmatter (one per line).
declared_fields() {
    local frontmatter="$1"
    printf '%s\n' "$frontmatter" | grep -E "^[a-zA-Z_][a-zA-Z0-9_-]*:" | sed -E 's/^([a-zA-Z_][a-zA-Z0-9_-]*):.*/\1/'
}

# Validate one SKILL.md file. Prints errors to stderr; returns 0 on success.
validate_file() {
    local file="$1"

    if [ ! -f "$file" ]; then
        echo "ERROR: $file: file not found" >&2
        return 1
    fi

    local frontmatter extract_status
    frontmatter=$(extract_frontmatter "$file")
    extract_status=$?

    case $extract_status in
        2)
            echo "ERROR: $file: no frontmatter found (expected YAML block between --- delimiters)" >&2
            return 1
            ;;
        3)
            echo "ERROR: $file: unterminated frontmatter (opening --- found, closing --- missing)" >&2
            return 1
            ;;
    esac

    if [ -z "$frontmatter" ]; then
        echo "ERROR: $file: empty frontmatter" >&2
        return 1
    fi

    if ! yaml_wellformed "$frontmatter"; then
        echo "ERROR: $file: malformed YAML frontmatter" >&2
        return 1
    fi

    local declared
    declared=$(declared_fields "$frontmatter")

    # Check required fields are present
    for field in "${REQUIRED_FIELDS[@]}"; do
        if ! grep -qFx "$field" <<< "$declared"; then
            echo "ERROR: $file: missing required field '${field}'" >&2
            return 1
        fi
    done

    # Check for unknown fields
    while IFS= read -r field; do
        [ -z "$field" ] && continue
        local known=0
        for k in "${KNOWN_FIELDS[@]}"; do
            if [ "$field" = "$k" ]; then known=1; break; fi
        done
        if [ $known -eq 0 ]; then
            echo "ERROR: $file: unknown field '${field}' (allowed: ${KNOWN_FIELDS[*]})" >&2
            return 1
        fi
    done <<< "$declared"

    return 0
}

# Entry point.
TARGET="${1:-skills}"
FAIL=0

if [ -d "$TARGET" ]; then
    while IFS= read -r -d '' f; do
        validate_file "$f" || FAIL=1
    done < <(find "$TARGET" -name "SKILL.md" -type f -print0)
elif [ -f "$TARGET" ]; then
    validate_file "$TARGET" || FAIL=1
else
    echo "ERROR: target not found: $TARGET" >&2
    exit 1
fi

exit $FAIL
