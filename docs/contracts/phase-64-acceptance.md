# Phase 64 Acceptance Checklist

## Lifecycle Registry Call Exception Fallback

- [x] Lifecycle subscriber startup treats `GenServer.call/2` argument exceptions as base-subscription fallback conditions.
- [x] Lifecycle subscriber startup keeps cached hook defaults empty under registry call exceptions and recovers cached hook defaults after registry recovery.
- [x] Lifecycle subscriber refresh preserves active lifecycle subscriptions when `list_skills` call exceptions occur.
- [x] Registry update signal handling remains non-fatal after refresh-time registry call exceptions.

## Validation

- [x] Added lifecycle startup regression with an invalid registry reference that recovers after swapping in a valid registry and publishing a registry update.
- [x] Added lifecycle refresh regression proving lifecycle telemetry remains observable after a `list_skills` call exception and registry-update retry.
