# Phase 26 Acceptance Checklist

## Lifecycle Subscription Removal

- [x] Registry-driven lifecycle subscriptions are removed when the originating skill hook signal type is no longer present after reload.
- [x] Removed hook signal types no longer emit lifecycle telemetry under repeated post-reload publishes.
- [x] Existing configured/default lifecycle subscriptions and permission-blocked coverage remain unchanged.

## Validation

- [x] Added observability regression test for removing a skill that previously contributed a custom hook signal type.
- [x] Regression test verifies custom hook telemetry is observed before removal and absent after reload/removal.
