# Phase 50 Acceptance Checklist

## Dispatcher Startup With Hook-Default Read Failures

- [x] Dispatcher startup no longer fails when initial `hook_defaults` reads return invalid non-map values.
- [x] Dispatcher starts with discovered routes when startup hook defaults are unavailable, using empty hook defaults until recovery.
- [x] Dispatcher can recover global hook emission after startup hook-default failures clear and a refresh succeeds.

## Validation

- [x] Added dispatcher regression proving startup succeeds with valid routes while initial hook defaults are invalid.
- [x] Regression verifies lifecycle hook signals are absent before recovery and emitted after hook-default refresh succeeds.
- [x] Regression asserts dispatcher state caches recovered hook defaults after refresh.
