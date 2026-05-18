---
name: invalid-unknown-field
description: This fixture declares an unknown top-level frontmatter field so the validator must reject it.
requires-skills: []
requires-config: []
wat: a-field-not-in-the-known-allowlist
---

# Invalid: unknown field

`validate.sh` must reject this file because `wat` is not one of the known frontmatter fields. Unknown fields are strict-rejected in v1 (future schema-validator slice #04 may relax for `docs/agents/*.md`).
