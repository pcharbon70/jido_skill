# Phase 97 Acceptance Checklist

## Lifecycle Startup Bus-Name Call-Exception Repeated Refresh Fallback and Recovery

- [x] Lifecycle subscriber keeps configured startup bus subscriptions when registry `:bus_name` lookup raises call exceptions during startup.
- [x] Lifecycle subscriber preserves cached startup bus subscriptions when repeated refreshes continue raising `:bus_name` call exceptions.
- [x] Lifecycle subscriber migrates lifecycle and registry-update subscriptions to the refreshed bus after startup/refresh `:bus_name` call-exception lookups recover.

## Validation

- [x] Added lifecycle integration regression proving startup `:bus_name` call-exception fallback remains stable across two consecutive refresh call exceptions and migrates after recovery.
