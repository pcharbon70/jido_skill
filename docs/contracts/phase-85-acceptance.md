# Phase 85 Acceptance Checklist

## Dispatcher Bus-Name Call-Exception Resilience Across Settings Reload

- [x] Dispatcher startup keeps configured bus subscriptions when registry `:bus_name` lookup raises call exceptions.
- [x] Dispatcher migrates route and registry-update subscriptions after `:bus_name` lookup recovers from startup call exceptions.
- [x] Dispatcher preserves cached bus dispatch behavior when registry `:bus_name` lookup raises call exceptions during refresh.

## Validation

- [x] Added dispatcher integration regression proving startup fallback to the configured bus when `:bus_name` lookup raises call exceptions and successful migration after recovery.
- [x] Added dispatcher integration regression proving refresh preserves cached bus subscriptions when `:bus_name` lookup raises call exceptions.
