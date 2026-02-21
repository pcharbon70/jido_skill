# Phase 89 Acceptance Checklist

## Dispatcher Startup Bus Migration Fallback and Recovery

- [x] Dispatcher falls back to configured startup bus when registry `:bus_name` points to an unavailable bus.
- [x] Dispatcher keeps route dispatch active on the configured bus while refreshed startup bus is unavailable.
- [x] Dispatcher migrates route and registry-update subscriptions to the refreshed bus after it becomes available.

## Validation

- [x] Added dispatcher integration regression proving startup migration fallback to configured bus when refreshed bus is unavailable.
- [x] Added dispatcher integration regression proving dispatch migrates from cached startup bus to refreshed bus after recovery-triggered registry update.
