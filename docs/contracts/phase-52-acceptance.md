# Phase 52 Acceptance Checklist

## Dispatcher Startup With Registry Unavailable

- [x] Dispatcher startup no longer fails when the configured registry process is unavailable (`:noproc`) at init.
- [x] Dispatcher initializes with empty route subscriptions when registry reads fail during startup due to registry unavailability.
- [x] Dispatcher recovers route subscriptions after the registry process starts and a `skill.registry.updated` refresh is processed.

## Validation

- [x] Added dispatcher regression proving startup succeeds with a missing named registry.
- [x] Regression verifies route dispatch is inactive before registry startup and recovers once the registry becomes available.
