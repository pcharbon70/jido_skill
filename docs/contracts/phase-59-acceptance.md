# Phase 59 Acceptance Checklist

## Dispatcher Refresh With `list_skills` Exceptions

- [x] Dispatcher treats raised `list_skills` calls as refresh failures.
- [x] Dispatcher keeps existing route subscriptions and handlers when `list_skills` raises during refresh.
- [x] Registry update signal handling remains non-fatal when registry reads raise during refresh.

## Validation

- [x] Added dispatcher regression proving `refresh/1` surfaces a `list_skills_failed` exit error when registry reads raise.
- [x] Regression verifies the dispatcher process stays alive and continues dispatching existing routes after a refresh-time registry exception.
