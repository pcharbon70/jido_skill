# Phase 120 Acceptance Checklist

## Lifecycle Refresh Bus-Name Exit Repeated Fallback and Recovery

- [x] Lifecycle subscriber preserves configured-bus lifecycle subscriptions when refresh-time registry `:bus_name` calls exit.
- [x] Lifecycle subscriber preserves configured-bus lifecycle subscriptions when repeated refresh attempts continue returning `:bus_name` exits.
- [x] Lifecycle subscriber migrates lifecycle subscriptions to the refreshed bus after `:bus_name` exits stop and refresh succeeds.

## Validation

- [x] Added lifecycle integration regression proving repeated refresh-time `:bus_name` exit fallback remains stable across two consecutive refresh attempts and recovers bus migration after exit recovery.
