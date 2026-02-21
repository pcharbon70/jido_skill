# Phase 83 Acceptance Checklist

## Dispatcher Bus-Name Lookup Resilience Across Settings Reload

- [x] Dispatcher startup keeps configured bus subscriptions when registry `:bus_name` lookup returns an invalid value.
- [x] Dispatcher migrates route and registry-update subscriptions after `:bus_name` lookup recovers to a valid refreshed bus.
- [x] Dispatcher preserves cached bus dispatch behavior when registry `:bus_name` lookup raises during refresh.

## Validation

- [x] Added dispatcher integration regression proving startup fallback to the configured bus when `:bus_name` returns an invalid result and successful migration after recovery.
- [x] Added dispatcher integration regression proving refresh preserves cached bus subscriptions when `:bus_name` call raises exceptions.
