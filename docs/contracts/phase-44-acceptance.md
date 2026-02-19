# Phase 44 Acceptance Checklist

## Dispatcher Refresh With Invalid Registry Skill Lists

- [x] Dispatcher treats non-list `list_skills` replies as refresh failures.
- [x] Dispatcher keeps existing route subscriptions and handlers when `list_skills` returns invalid non-list data.
- [x] Registry update signal handling remains non-fatal under invalid `list_skills` refresh responses.

## Validation

- [x] Added dispatcher regression proving `refresh/1` surfaces an explicit invalid-result `list_skills_failed` error.
- [x] Regression verifies the dispatcher process stays alive and continues dispatching existing routes after invalid registry payload refresh attempts.
