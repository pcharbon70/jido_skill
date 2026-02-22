# Phase 93 Acceptance Checklist

## Lifecycle Repeated Invalid Bus-Name Lookup Resilience Across Settings Reload

- [x] Lifecycle subscriber preserves cached bus subscriptions when registry `:bus_name` lookup returns repeated invalid values during refresh.
- [x] Lifecycle subscriber keeps lifecycle telemetry active on the cached bus while invalid `:bus_name` results continue.
- [x] Lifecycle subscriber migrates lifecycle and registry-update subscriptions to the refreshed bus once repeated invalid `:bus_name` results recover.

## Validation

- [x] Added lifecycle integration regression proving two consecutive refresh-time invalid `:bus_name` results keep lifecycle telemetry on cached bus subscriptions.
- [x] Added lifecycle integration regression proving a subsequent successful refresh migrates lifecycle telemetry from the cached bus to the recovered refreshed bus.
