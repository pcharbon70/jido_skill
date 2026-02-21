# Phase 86 Acceptance Checklist

## Lifecycle Bus-Name Call-Exception Resilience Across Settings Reload

- [x] Lifecycle subscriber preserves cached bus subscriptions when registry `:bus_name` lookup raises call exceptions during refresh.
- [x] Lifecycle subscriber migrates lifecycle and registry-update subscriptions after `:bus_name` lookup recovers from call exceptions.
- [x] Lifecycle subscriber preserves cached bus subscriptions when repeated `:bus_name` lookup call exceptions occur during refresh.

## Validation

- [x] Added lifecycle integration regression proving refresh keeps cached bus subscriptions when `:bus_name` lookup raises call exceptions and migrates after recovery.
- [x] Added lifecycle integration regression proving repeated `:bus_name` call exceptions during refresh keep lifecycle telemetry on cached bus subscriptions.
