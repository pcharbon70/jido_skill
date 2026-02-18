# Phase 18 Acceptance Checklist

## Frontmatter Schema Alignment

- [x] `schemas/skill-frontmatter.schema.json` route path pattern allows hyphenated segments (`-`) to match runtime compiler validation.
- [x] `schemas/skill-frontmatter.schema.json` validates `jido.skill_module` using module identifier rules.
- [x] Frontmatter hook override schema no longer requires `enabled`, `signal_type`, and `bus`, aligning with runtime partial-hook override support.

## Validation

- [x] Added schema contract tests that assert router pattern, `skill_module` pattern, and optional hook override fields.
- [x] Added compiler regression test ensuring hyphenated route paths compile successfully.
