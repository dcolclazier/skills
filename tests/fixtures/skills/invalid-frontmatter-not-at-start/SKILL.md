# Pre-frontmatter prose

This text appears before the opening `---` delimiter. Per the spec, frontmatter
must start at the beginning of the file — so this fixture must be rejected.

---
name: invalid-frontmatter-not-at-start
description: Fixture exercising the "opening --- must be on line 1" rule. The validator must reject this file because prose appears before the frontmatter.
requires-skills: []
requires-config: []
---

# Body

Without the start-of-file rule, the validator would happily extract the
"frontmatter" from the middle of the file and accept it.
