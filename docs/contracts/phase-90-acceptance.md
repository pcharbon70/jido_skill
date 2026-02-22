# Phase 90 Acceptance Checklist

## Lifecycle Repeated Bus-Name Call-Exception Resilience Across Settings Reload

- [x] Lifecycle subscriber preserves cached bus subscriptions when registry `:bus_name` lookup raises repeated call exceptions during refresh.
- [x] Lifecycle subscriber keeps lifecycle telemetry active on the cached bus while repeated `:bus_name` call exceptions continue.
- [x] Lifecycle subscriber migrates lifecycle and registry-update subscriptions to the refreshed bus once repeated `:bus_name` call exceptions recover.

## Validation

- [x] Added lifecycle integration regression proving two consecutive refresh-time `:bus_name` call exceptions keep lifecycle telemetry on cached bus subscriptions.
- [x] Added lifecycle integration regression proving a subsequent successful refresh migrates lifecycle telemetry from the cached bus to the recovered refreshed bus.
