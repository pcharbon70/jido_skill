# Phase 51 Acceptance Checklist

## Lifecycle Startup With Hook-Default Inheritance Failures

- [x] Lifecycle subscriber startup remains alive when initial `hook_defaults` reads fail while registry skills still load.
- [x] Startup does not subscribe inherited lifecycle signal types that depend on unavailable global hook defaults.
- [x] Subscriber recovers inherited lifecycle subscriptions after hook-default reads recover and registry refresh is processed.

## Validation

- [x] Added lifecycle regression proving inherited custom lifecycle signals are unobserved before hook-default recovery at startup.
- [x] Regression verifies inherited custom lifecycle telemetry becomes observable after clearing hook-default failures and processing `skill.registry.updated`.
