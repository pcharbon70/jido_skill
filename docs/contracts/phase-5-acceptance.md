# Phase 5 Acceptance Checklist

## Hook Engine

- [x] Implemented pre/post hook resolution with frontmatter-over-global precedence.
- [x] `enabled: false` in frontmatter disables hook emission.
- [x] Partial frontmatter hook definitions inherit missing fields from global defaults.

## Payload Templating

- [x] Implemented interpolation for `{{phase}}`, `{{skill_name}}`, `{{route}}`, `{{status}}`, and `{{timestamp}}`.
- [x] Runtime fields override template collisions.

## Signal Publishing

- [x] Hook signal types are normalized for current bus path format.
- [x] Publishing errors are non-fatal and logged.

## Validation

- [x] Added tests for global fallback behavior.
- [x] Added tests for `enabled: false` short-circuit behavior.
- [x] Added tests for partial frontmatter override + global default inheritance.
