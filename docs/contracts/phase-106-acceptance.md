# Phase 106 Acceptance Checklist

## Lifecycle Startup Hook-Defaults Invalid-Result Repeated Refresh Fallback and Recovery

- [x] Lifecycle subscriber starts without inherited registry-derived subscriptions and with empty cached hook defaults when the initial registry `:hook_defaults` read returns invalid non-map data.
- [x] Lifecycle subscriber preserves fallback subscription behavior and empty cached hook defaults when repeated refresh attempts continue returning startup-origin invalid `:hook_defaults` data.
- [x] Lifecycle subscriber recovers inherited registry-derived subscriptions after `:hook_defaults` invalid results stop and refresh succeeds.

## Validation

- [x] Added lifecycle integration regression proving startup invalid `:hook_defaults` fallback remains stable across two consecutive refresh attempts and recovers inherited subscriptions after invalid-result recovery.
