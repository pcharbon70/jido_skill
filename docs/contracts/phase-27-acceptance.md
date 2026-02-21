# Phase 27 Acceptance Checklist

## Explicit Empty Lifecycle Hook Semantics

- [x] Lifecycle subscriber distinguishes between missing `hook_signal_types` and explicitly provided empty list.
- [x] Explicit `hook_signal_types: []` remains empty when `fallback_to_default_hook_signal_types: false`.
- [x] Application lifecycle subscriber wiring disables fallback so disabled pre/post hook settings can result in no lifecycle subscriptions.

## Validation

- [x] Added observability regression test proving explicit empty hook signal type configuration emits no lifecycle telemetry.
- [x] Existing fallback behavior remains covered for callers that omit `hook_signal_types` or keep fallback enabled.
