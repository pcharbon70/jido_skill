# Phase 67 Acceptance Checklist

## Dispatcher Startup With `hook_defaults` Call Exceptions

- [x] Dispatcher startup treats `GenServer.call/2` argument exceptions during initial `hook_defaults` reads as fallback conditions.
- [x] Dispatcher initializes route subscriptions when startup `list_skills` succeeds but startup `hook_defaults` calls raise call exceptions.
- [x] Dispatcher starts with empty hook defaults in this fallback path and recovers hook emission after refresh when `hook_defaults` calls succeed.

## Validation

- [x] Added dispatcher regression that fails only startup `hook_defaults` lookup calls via deterministic `:via` name-resolution exceptions.
- [x] Regression verifies route dispatch remains active before refresh recovery, hook signals are absent before recovery, and hook signals emit after refresh with recovered cached defaults.
