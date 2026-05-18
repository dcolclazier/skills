---
name: invalid-indented-key
description: This fixture has an indented top-level-shaped key that should be rejected. Under the previous loose-continuation rule it would have been silently dropped from declared_fields. The strict rule treats this as malformed YAML.
  fnord: this-should-not-be-silently-dropped
requires-skills: []
requires-config: []
---

# Invalid: indented key

`validate.sh` must reject this file. An indented `key: value` line is
ambiguous YAML (intended nesting? typo? block scalar leak?) and our
narrow grammar doesn't support nested maps. Rejecting it surfaces
typos that the loose-continuation rule would have hidden.
