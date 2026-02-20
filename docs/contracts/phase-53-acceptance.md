# Phase 53 Acceptance Checklist

## Lifecycle Startup With Registry Unavailable

- [x] Lifecycle subscriber startup no longer fails when the configured registry process is unavailable (`:noproc`) at init.
- [x] Subscriber starts with base lifecycle subscriptions when registry-derived hook metadata cannot be read at startup.
- [x] Subscriber recovers registry-derived lifecycle subscriptions after the registry process starts and `skill.registry.updated` is processed.

## Validation

- [x] Added lifecycle regression proving startup succeeds with an unavailable named registry and no custom lifecycle subscription before registry startup.
- [x] Regression verifies custom lifecycle telemetry becomes observable after the registry starts and a registry-update refresh completes.
