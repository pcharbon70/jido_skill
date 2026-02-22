# Phase 104 Acceptance Checklist

## Lifecycle Startup Hook-Defaults Call-Exception Repeated Refresh Fallback and Recovery

- [x] Lifecycle subscriber starts without inherited registry-derived subscriptions and with empty cached hook defaults when the initial registry `:hook_defaults` call raises call exceptions.
- [x] Lifecycle subscriber preserves fallback subscription behavior and empty cached hook defaults when repeated refresh attempts continue raising startup-origin `:hook_defaults` call exceptions.
- [x] Lifecycle subscriber recovers inherited registry-derived subscriptions after `:hook_defaults` call exceptions stop and refresh succeeds.

## Validation

- [x] Added lifecycle integration regression proving startup `:hook_defaults` call-exception fallback remains stable across two consecutive refresh attempts and recovers inherited subscriptions after call-exception recovery.
