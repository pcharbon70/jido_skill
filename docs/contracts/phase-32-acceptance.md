# Phase 32 Acceptance Checklist

## Lifecycle Subscriber Refresh Resilience

- [x] Lifecycle subscription refresh subscribes new paths before removing existing subscriptions.
- [x] Existing lifecycle subscriptions remain active when refresh fails while adding new registry-derived hook signal types.
- [x] Partially added lifecycle subscriptions are rolled back on refresh failure.

## Validation

- [x] Added lifecycle subscriber regression test forcing refresh failure with malformed registry hook signal type metadata.
- [x] Regression test verifies previously active lifecycle signal telemetry remains observable after the failed refresh.
