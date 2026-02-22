# Phase 91 Acceptance Checklist

## Lifecycle Startup Bus-Name Call-Exception Fallback and Recovery

- [x] Lifecycle subscriber keeps configured startup bus subscriptions when registry `:bus_name` lookup raises call exceptions during startup.
- [x] Lifecycle subscriber keeps lifecycle telemetry active on the configured startup bus while startup `:bus_name` resolution fails.
- [x] Lifecycle subscriber migrates lifecycle and registry-update subscriptions to the refreshed bus after startup `:bus_name` call-exception recovery.

## Validation

- [x] Added lifecycle integration regression proving startup `:bus_name` call exceptions keep subscriptions on the configured startup bus.
- [x] Added lifecycle integration regression proving a subsequent successful refresh migrates lifecycle telemetry from the configured startup bus to the recovered refreshed bus.
