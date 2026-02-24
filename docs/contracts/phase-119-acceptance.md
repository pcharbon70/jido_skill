# Phase 119 Acceptance Checklist

## Dispatcher Refresh Bus-Name Exit Repeated Fallback and Recovery

- [x] Dispatcher preserves configured-bus route dispatch when refresh-time registry `:bus_name` calls exit.
- [x] Dispatcher preserves configured-bus route dispatch when repeated refresh attempts continue returning `:bus_name` exits.
- [x] Dispatcher migrates route dispatch to the refreshed bus after `:bus_name` exits stop and refresh succeeds.

## Validation

- [x] Added dispatcher integration regression proving repeated refresh-time `:bus_name` exit fallback remains stable across two consecutive refresh attempts and recovers bus migration after exit recovery.
