# Phase 92 Acceptance Checklist

## Dispatcher Repeated Invalid Bus-Name Lookup Resilience Across Settings Reload

- [x] Dispatcher preserves cached bus dispatch when registry `:bus_name` lookup returns invalid values during refresh.
- [x] Dispatcher keeps route subscriptions stable on the cached bus while invalid `:bus_name` results continue.
- [x] Dispatcher migrates route and registry-update subscriptions to the refreshed bus once invalid `:bus_name` results recover.

## Validation

- [x] Added dispatcher integration regression proving two consecutive refresh-time invalid `:bus_name` results keep dispatch on cached bus subscriptions.
- [x] Added dispatcher integration regression proving a subsequent successful refresh migrates dispatch from the cached bus to the recovered refreshed bus.
