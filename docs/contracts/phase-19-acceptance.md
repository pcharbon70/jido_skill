# Phase 19 Acceptance Checklist

## Settings Schema Alignment

- [x] `schemas/settings.schema.json` allows signal bus middleware `opts` to be either an object or `null`.
- [x] Settings schema contract tests assert middleware `opts` type and required `hooks.pre`/`hooks.post` invariants.

## Runtime Validation

- [x] Settings loader accepts middleware entries with `opts: null`.
- [x] Normalized runtime middleware converts `null` opts to empty keyword list (`[]`).

## Validation

- [x] Added schema contract tests for `settings.schema.json`.
- [x] Added settings loader regression test for middleware `opts: null`.
