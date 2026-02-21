# Phase 71 Acceptance Checklist

## Dispatcher Refresh With `list_skills` Call Exceptions (Hook-Aware Continuity)

- [x] Dispatcher refresh treats `GenServer.call/2` argument exceptions during `list_skills` reads as refresh failures.
- [x] Dispatcher preserves existing hook-aware route subscriptions when refresh-time `list_skills` calls raise call exceptions.
- [x] Dispatcher preserves cached hook defaults while refresh-time `list_skills` calls raise call exceptions.
- [x] Registry update signal handling remains non-fatal after repeated refresh-time `list_skills` call exceptions.

## Validation

- [x] Added dispatcher regression that swaps to a deterministic `:via` lookup plan failing repeated refresh-time `list_skills` lookups.
- [x] Regression verifies hook-aware route dispatch and hook emission continue on the preserved route, confirms new route activation is blocked while refresh fails, and confirms cached hook defaults remain unchanged.
