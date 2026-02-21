# Phase 69 Acceptance Checklist

## Dispatcher Startup With `list_skills` Call Exceptions

- [x] Dispatcher startup treats `GenServer.call/2` argument exceptions during initial `list_skills` reads as empty-route fallback conditions.
- [x] Dispatcher initializes with empty routes when startup `list_skills` calls raise call exceptions, even when startup `hook_defaults` reads succeed.
- [x] Dispatcher preserves startup hook defaults in this fallback path and recovers route dispatch plus hook emission after refresh when `list_skills` calls succeed.

## Validation

- [x] Added dispatcher startup regression that fails only the first `list_skills` lookup via deterministic `:via` name-resolution exceptions.
- [x] Regression verifies startup route dispatch remains blocked before recovery, confirms cached hook defaults are retained, and confirms route dispatch plus hook signals recover after refresh.
