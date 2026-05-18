---
name: invalid-malformed-yaml
description: "This description has an unterminated quoted string that breaks YAML parsing.
requires-skills: []
requires-config: []
---

# Invalid: malformed YAML

`validate.sh` must reject this file because the description's quoted string is never closed — the YAML frontmatter is malformed.
