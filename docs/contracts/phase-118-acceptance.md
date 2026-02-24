# Phase 118 Acceptance Checklist

## Lifecycle Startup Bus-Name Exit Repeated Refresh Fallback and Recovery

- [x] Lifecycle subscriber starts on the configured bus when the initial registry `:bus_name` call exits.
- [x] Lifecycle subscriber preserves configured-bus lifecycle subscriptions when repeated refresh attempts continue triggering startup-origin `:bus_name` exits.
- [x] Lifecycle subscriber migrates lifecycle subscriptions to the refreshed bus after `:bus_name` exits stop and refresh succeeds.

## Validation

- [x] Added lifecycle integration regression proving startup `:bus_name` exit fallback remains stable across two consecutive refresh attempts and recovers bus migration after exit recovery.
