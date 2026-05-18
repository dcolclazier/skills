# Skill frontmatter specification (v1)

> Why this file exists: every `SKILL.md` in this plugin carries YAML frontmatter that declares its identity and dependencies. `validate.sh` enforces the contract documented here. Without a written spec, the validator's rules would only be readable from the bash source — this file is the human-readable canonical reference.

## Shape

Every `SKILL.md` begins with a fenced YAML block:

```markdown
---
name: <skill-name>
description: <one paragraph; the trigger sentence for skill activation>
argument-hint: "<usage syntax — optional>"
disable-model-invocation: <true|false — optional>
requires-skills: [<skill-name>, ...]
requires-config: [<config-name>, ...]
---

# Skill body starts here
```

The block must be delimited by `---` on its own line at the start of the file and again to close.

## Fields

### Required fields

| Field | Type | Description |
|---|---|---|
| `name` | string | The skill's slash-command name. Lower-kebab-case; matches the directory name (`skills/<name>/SKILL.md`). |
| `description` | string | One paragraph describing what the skill does and when to invoke it. The first sentence is the trigger phrase Claude Code uses to decide when to surface the skill. |
| `requires-skills` | array of strings | Skills this skill invokes or composes with. Empty array `[]` if none. Used by `validate.sh`'s dependency-graph walker (issue #02) to detect cycles and unresolved references. |
| `requires-config` | array of strings | Consumer files (under `docs/agents/`) this skill reads at runtime. Empty array `[]` if none. Used by `/setup-workflow` to know which seed templates to scaffold for a given skill set. |

### Optional fields

| Field | Type | Description |
|---|---|---|
| `argument-hint` | string | Usage syntax shown to users. Free-form; commonly `"[arg1] [arg2] [--flag]"`. |
| `disable-model-invocation` | boolean | Set `true` for skills that should only be invoked by explicit user command, not auto-surfaced by Claude Code. Defaults to `false` if omitted. |

### Unknown fields

**Unknown fields are rejected** by `validate.sh` in v1. This is strict by design — the goal is to catch typos early (`requires-skils` → `requires-skills`). Future schema-validator slice (issue #04) may relax this for `docs/agents/*.md` consumer files where forward-compatibility matters more.

## Examples

### Minimal valid frontmatter

```yaml
---
name: my-skill
description: A short trigger sentence describing what the skill does and when to invoke it.
requires-skills: []
requires-config: []
---
```

### Frontmatter with all optional fields

```yaml
---
name: my-skill
description: A short trigger sentence.
argument-hint: "[--posture auto|draft|comment-only]"
disable-model-invocation: true
requires-skills: [score, tdd]
requires-config: [issue-tracker, story-conventions]
---
```

## Validation

Run `bash validate.sh` from the repo root to validate the whole `skills/` tree. Run `bash validate.sh <path>` to validate a single SKILL.md.

The validator is deliberately narrow:
- Pure bash + grep/awk; no external dependencies.
- Parses a restricted YAML subset (top-level `key: value` pairs, inline `[]` and block-style arrays, single-line quoted strings).
- Rejects: missing required field, malformed YAML (unterminated quoted string), unknown top-level field.
- Accepts: free-text descriptions containing apostrophes (English contractions like `you're`, `PRD's` are not flagged).

## Upgrading from pre-v1 (for forks / adopting teams)

If you have a fork of this repo predating v1 of the frontmatter spec, syncing this change will fail your CI on every existing SKILL.md until you adapt. The breaking changes:

1. **Two new required fields** must be declared in every SKILL.md: `requires-skills:` and `requires-config:`. Empty arrays (`[]`) satisfy v1 — dependency-graph correctness is issue #02's job.
2. **Unknown fields are rejected.** Any custom field you may have added to your fork's SKILL.md files (e.g., `category:`, `owner:`, `version:`) will now fail validation. You must either rename the field to one of the known fields (`name`, `description`, `argument-hint`, `disable-model-invocation`, `requires-skills`, `requires-config`), drop the field, or contribute it upstream and add it to the known-fields allowlist in `validate.sh`.

A one-liner to add the required empty arrays to every existing SKILL.md in your fork (run from the repo root):

```bash
for f in skills/*/SKILL.md; do
  awk '/^---$/{n++; if (n == 2) { print "requires-skills: []"; print "requires-config: []" }} {print}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
```

Unknown-field cleanup is necessarily manual (decide rename vs drop vs upstream per field). Run `bash validate.sh skills/` to surface any remaining failures.

## Out of scope for v1

- **CRLF line endings.** `validate.sh` matches frontmatter delimiters with `/^---$/` against LF-terminated lines. SKILL.md files saved with CRLF endings (e.g., on Windows without `core.autocrlf` configured) will produce "no frontmatter found." Git's default LF normalization on `text=auto`-attributed files handles this for most contributors; explicit out-of-scope here so anyone hitting it knows to check `git config core.autocrlf` or add `*.md text eol=lf` to `.gitattributes` rather than file a validator bug.
- **Full YAML support.** Block scalars (`|`, `>`), multi-line strings, anchors, aliases, and other YAML features beyond the narrow grammar above are out of scope. The validator runs against SKILL.md frontmatter only, which uses a restricted subset.

## Future work

- Issue #02 adds the dependency-graph walker that consumes `requires-skills:` and `requires-config:` to detect cycles and dangling references.
- Issue #03 adds the schema extractor for `docs/agents/*.md` files (a different file shape — fenced YAML at top of markdown documentation, not whole-file frontmatter).
- Per-field deeper validation (e.g., `description` length cap, `name` slug format check) is deliberately out of scope for v1.
