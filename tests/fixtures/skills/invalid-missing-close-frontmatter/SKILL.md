---
name: invalid-missing-close-frontmatter
description: This fixture has an opening `---` but no closing `---`, so the validator must reject it — otherwise the entire markdown body would be silently treated as frontmatter.
requires-skills: []
requires-config: []

# Invalid: missing closing ---

This file deliberately omits the second `---` delimiter. `validate.sh` must
detect the unterminated frontmatter rather than treating the whole body
as YAML.
