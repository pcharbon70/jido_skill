# Phase 29 Acceptance Checklist

## Hook Emitter Inheritance Regression Coverage

- [x] Frontmatter hook `enabled: true` overrides globally disabled hook defaults while inheriting global `signal_type`.
- [x] Frontmatter hook `signal_type` alone does not bypass globally disabled enablement.
- [x] Hook payload merge behavior remains frontmatter-over-global when inherited hook routing is used.

## Validation

- [x] Added hook emitter regression test proving inherited global `signal_type` emits when frontmatter explicitly enables the hook.
- [x] Added hook emitter regression test proving disabled global enablement still suppresses emission without frontmatter `enabled: true`.
