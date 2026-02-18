# Phase 12 Acceptance Checklist

## Permission-Blocked Signal Emission

- [x] Signal dispatcher emits `skill/permission/blocked` when a matched skill is gated by `ask` permissions.
- [x] Signal dispatcher emits `skill/permission/blocked` when a matched skill is denied by policy.
- [x] Blocked signal payload includes `skill_name`, `route`, `reason`, `tools`, and `timestamp`.

## Runtime Behavior

- [x] Ask-gated and denied skills remain non-executable and do not run actions.
- [x] Blocked signal emission failures are handled without crashing the dispatcher.

## Observability

- [x] Lifecycle subscriber subscribes to `skill.permission.blocked` in addition to pre/post lifecycle signals.
- [x] Telemetry metadata includes permission context (`reason`, `tools`) when present.

## Validation

- [x] Added dispatcher tests asserting blocked signal emission for `ask` and `denied` permission statuses.
- [x] Added subscriber tests asserting telemetry emission for `skill.permission.blocked`.
