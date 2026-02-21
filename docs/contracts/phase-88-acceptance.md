# Phase 88 Acceptance Checklist

## Dispatcher Repeated Bus-Name Call-Exception Resilience Across Settings Reload

- [x] Dispatcher preserves cached bus dispatch when registry `:bus_name` lookup raises repeated call exceptions during refresh.
- [x] Dispatcher keeps route subscriptions stable on the cached bus while repeated `:bus_name` call exceptions continue.
- [x] Dispatcher migrates route and registry-update subscriptions to the refreshed bus once repeated `:bus_name` call exceptions recover.

## Validation

- [x] Added dispatcher integration regression proving two consecutive refresh-time `:bus_name` call exceptions keep dispatch on the cached bus.
- [x] Added dispatcher integration regression proving a subsequent successful refresh migrates dispatch from the cached bus to the recovered refreshed bus.
