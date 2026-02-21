# Phase 68 Acceptance Checklist

## Lifecycle Startup With `hook_defaults` Call Exceptions

- [x] Lifecycle subscriber startup treats `GenServer.call/2` argument exceptions during initial `hook_defaults` reads as fallback conditions.
- [x] Lifecycle subscriber initializes with base subscriptions when startup `list_skills` succeeds but startup `hook_defaults` calls raise call exceptions.
- [x] Lifecycle subscriber starts with empty cached hook defaults in this fallback path and recovers inherited lifecycle subscriptions after refresh when `hook_defaults` calls succeed.

## Validation

- [x] Added lifecycle startup regression that fails only the initial `hook_defaults` lookup via deterministic `:via` name-resolution exceptions.
- [x] Regression verifies inherited lifecycle telemetry remains absent before refresh recovery and becomes observable after a registry update refresh restores cached hook defaults.
