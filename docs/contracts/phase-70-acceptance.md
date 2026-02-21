# Phase 70 Acceptance Checklist

## Lifecycle Startup With `list_skills` Call Exceptions

- [x] Lifecycle subscriber startup treats `GenServer.call/2` argument exceptions during initial `list_skills` reads as base-subscription fallback conditions.
- [x] Lifecycle subscriber initializes without inherited registry-derived subscriptions when startup `list_skills` calls raise call exceptions, even when startup `hook_defaults` reads succeed.
- [x] Lifecycle subscriber preserves startup cached hook defaults in this fallback path and recovers inherited lifecycle subscriptions after refresh when `list_skills` calls succeed.

## Validation

- [x] Added lifecycle startup regression that fails only the initial `list_skills` lookup via deterministic `:via` name-resolution exceptions.
- [x] Regression verifies inherited lifecycle telemetry is absent before refresh recovery, confirms cached hook defaults remain populated, and confirms inherited lifecycle telemetry becomes observable after refresh.
