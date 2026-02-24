# Phase 117 Acceptance Checklist

## Dispatcher Startup Bus-Name Exit Repeated Refresh Fallback and Recovery

- [x] Dispatcher starts on the configured bus when the initial registry `:bus_name` call exits.
- [x] Dispatcher preserves configured-bus route dispatch when repeated refresh attempts continue triggering startup-origin `:bus_name` exits.
- [x] Dispatcher migrates route dispatch to the refreshed bus after `:bus_name` exits stop and refresh succeeds.

## Validation

- [x] Added dispatcher integration regression proving startup `:bus_name` exit fallback remains stable across two consecutive refresh attempts and recovers bus migration after exit recovery.
