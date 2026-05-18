---
name: valid-with-deps
description: A valid fixture demonstrating non-empty `requires-skills` and `requires-config` arrays — the dependency-declaration shape this slice introduces.
requires-skills:
  - score
  - tdd
requires-config:
  - issue-tracker
  - story-conventions
---

# Valid With Deps

Fixture for `validate.sh` — demonstrates block-style YAML arrays in `requires-*` fields are accepted.
