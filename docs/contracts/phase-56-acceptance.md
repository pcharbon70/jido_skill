# Phase 56 Acceptance Checklist

## Lifecycle Startup With `list_skills` Exceptions

- [x] Lifecycle subscriber startup no longer fails when initial registry `list_skills` reads raise exceptions.
- [x] Subscriber initializes with base subscriptions when startup registry skill reads fail due to exceptions.
- [x] Subscriber recovers registry-derived lifecycle subscriptions after the registry error clears and a registry-update refresh is processed.

## Validation

- [x] Added lifecycle regression proving startup succeeds when initial `list_skills` raises.
- [x] Regression verifies custom lifecycle telemetry is absent before recovery and observable after replacing the failing registry and publishing `skill.registry.updated`.
