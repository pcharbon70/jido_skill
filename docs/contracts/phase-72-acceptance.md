# Phase 72 Acceptance Checklist

## Lifecycle Refresh With `list_skills` Call Exceptions (Hook Continuity)

- [x] Lifecycle subscriber refresh treats `GenServer.call/2` argument exceptions during `list_skills` reads as refresh failures.
- [x] Lifecycle subscriber preserves existing inherited lifecycle subscriptions when refresh-time `list_skills` calls raise call exceptions.
- [x] Lifecycle subscriber preserves cached hook defaults while refresh-time `list_skills` calls raise call exceptions.
- [x] Registry update signal handling remains non-fatal across repeated refresh-time `list_skills` call exceptions.

## Validation

- [x] Added lifecycle regression that swaps to a deterministic `:via` lookup plan failing repeated refresh-time `list_skills` lookups.
- [x] Regression verifies old inherited lifecycle telemetry remains observable, new lifecycle subscription activation stays blocked while refresh fails, and cached hook defaults remain unchanged.
