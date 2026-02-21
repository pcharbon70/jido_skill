# Phase 61 Acceptance Checklist

## Dispatcher Refresh With `hook_defaults` Exceptions

- [x] Dispatcher treats raised `hook_defaults` calls as refresh fallback conditions.
- [x] Dispatcher preserves cached hook defaults when `hook_defaults` raises during refresh.
- [x] Route subscription updates remain applied when `list_skills` succeeds but `hook_defaults` raises.
- [x] Registry update signal handling remains non-fatal after refresh-time `hook_defaults` exceptions.

## Validation

- [x] Added dispatcher regression proving refresh keeps route updates while `hook_defaults` raises.
- [x] Regression verifies the dispatcher process remains alive and continues dispatching refreshed routes after the registry process exits.
