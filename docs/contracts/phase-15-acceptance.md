# Phase 15 Acceptance Checklist

## Hook Bus Alias Normalization

- [x] Colon-prefixed hook bus aliases (for example `":jido_code_bus"`) resolve to existing atom bus names when available.
- [x] Non-prefixed bus names remain unchanged to preserve string-based bus configurations.
- [x] Hook emission continues to support both frontmatter and settings-provided hook bus values.

## Validation

- [x] Added settings loader test asserting colon-prefixed hook bus values normalize to existing atom names.
- [x] Added hook emitter test asserting frontmatter `bus: ":..."` publishes successfully to an atom-named bus.
