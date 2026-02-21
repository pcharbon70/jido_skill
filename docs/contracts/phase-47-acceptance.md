# Phase 47 Acceptance Checklist

## Lifecycle Startup With Invalid Registry Hook Paths

- [x] Lifecycle subscriber startup no longer fails when registry-derived hook signal paths are invalid.
- [x] Subscriber initializes with base subscriptions when registry-derived lifecycle subscriptions cannot be created at startup.
- [x] Subscriber remains eligible for registry-update refresh recovery after startup fallback.

## Validation

- [x] Added lifecycle regression proving startup succeeds with invalid registry hook signal metadata and no lifecycle telemetry is emitted for the invalid path.
- [x] Regression verifies subscriber recovers and emits lifecycle telemetry after registry metadata is corrected and a registry update is published.
