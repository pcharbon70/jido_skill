# Phase 108 Acceptance Checklist

## Lifecycle Startup Hook-Defaults Exit Repeated Refresh Fallback and Recovery

- [x] Lifecycle subscriber starts without inherited registry-derived subscriptions and with empty cached hook defaults when the initial registry `:hook_defaults` call exits.
- [x] Lifecycle subscriber preserves fallback subscription behavior and empty cached hook defaults when repeated refresh attempts continue triggering startup-origin `:hook_defaults` exits.
- [x] Lifecycle subscriber recovers inherited registry-derived subscriptions after `:hook_defaults` exits stop and refresh succeeds.

## Validation

- [x] Added lifecycle integration regression proving startup `:hook_defaults` exit fallback remains stable across two consecutive refresh attempts and recovers inherited subscriptions after exit recovery.
