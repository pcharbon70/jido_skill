# Phase 84 Acceptance Checklist

## Lifecycle Bus-Name Lookup Resilience Across Settings Reload

- [x] Lifecycle subscriber preserves cached bus subscriptions when registry `:bus_name` lookup returns an invalid value during refresh.
- [x] Lifecycle subscriber migrates lifecycle and registry-update subscriptions after `:bus_name` lookup recovers to a valid refreshed bus.
- [x] Lifecycle subscriber preserves cached bus subscriptions and telemetry behavior when registry `:bus_name` lookup raises during refresh.

## Validation

- [x] Added lifecycle integration regression proving refresh keeps cached bus subscriptions after invalid `:bus_name` lookup and migrates after lookup recovery.
- [x] Added lifecycle integration regression proving refresh keeps cached bus subscriptions when `:bus_name` lookup raises call exceptions.
