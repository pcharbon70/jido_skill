# Phase 95 Acceptance Checklist

## Lifecycle Startup Invalid Bus-Name Repeated Refresh Fallback and Recovery

- [x] Lifecycle subscriber keeps configured startup bus subscriptions when registry `:bus_name` lookup is invalid during startup.
- [x] Lifecycle subscriber preserves cached startup bus subscriptions when repeated refreshes continue returning invalid `:bus_name` values.
- [x] Lifecycle subscriber migrates lifecycle and registry-update subscriptions to the refreshed bus after invalid `:bus_name` startup/refresh lookups recover.

## Validation

- [x] Added lifecycle integration regression proving startup invalid `:bus_name` fallback remains stable across two consecutive invalid refreshes and migrates after recovery.
