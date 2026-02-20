# Phase 58 Acceptance Checklist

## Lifecycle Startup With `hook_defaults` Exceptions

- [x] Lifecycle subscriber startup no longer fails when initial registry `hook_defaults` reads raise exceptions.
- [x] Subscriber initializes with base subscriptions when startup hook-default reads fail due to exceptions.
- [x] Subscriber recovers inherited/registry-derived lifecycle subscriptions after registry recovery and registry-update refresh.

## Validation

- [x] Added lifecycle regression proving startup succeeds when initial `hook_defaults` raises while registry skill reads remain valid.
- [x] Regression verifies inherited custom lifecycle telemetry is absent before recovery and observable after replacing the failing registry and publishing `skill.registry.updated`.
