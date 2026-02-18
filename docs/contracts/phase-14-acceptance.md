# Phase 14 Acceptance Checklist

## Frontmatter Hook Inheritance

- [x] Compiler preserves omitted hook fields (`enabled`, `signal_type`, `bus`) as unset values.
- [x] Frontmatter partial hook overrides inherit global hook bus and signal type at runtime.
- [x] Frontmatter hook `data` overrides still merge on top of global hook template data.

## Validation

- [x] Added compiler test asserting missing hook fields remain `nil` in compiled metadata.
- [x] Added runtime dispatch test asserting partial frontmatter hooks publish on global bus/signal defaults.
