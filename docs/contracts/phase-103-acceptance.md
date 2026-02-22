# Phase 103 Acceptance Checklist

## Dispatcher Startup Hook-Defaults Call-Exception Repeated Refresh Fallback and Recovery

- [x] Dispatcher starts with routes and empty cached hook defaults when the initial registry `:hook_defaults` call raises call exceptions.
- [x] Dispatcher preserves route dispatch with empty cached hook defaults when repeated refresh attempts continue raising startup-origin `:hook_defaults` call exceptions.
- [x] Dispatcher recovers inherited hook emission after `:hook_defaults` call exceptions stop and refresh succeeds.

## Validation

- [x] Added dispatcher integration regression proving startup `:hook_defaults` call-exception fallback remains stable across two consecutive refresh attempts and recovers hook emission after call-exception recovery.
