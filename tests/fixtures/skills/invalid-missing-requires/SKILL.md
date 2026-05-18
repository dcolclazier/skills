---
name: invalid-missing-requires
description: This fixture omits the required `requires-skills` and `requires-config` fields so the validator must reject it.
---

# Invalid: missing requires-* fields

`validate.sh` must reject this file because `requires-skills` and `requires-config` are required frontmatter fields per the v1 spec.
