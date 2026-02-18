# Phase 11 Acceptance Checklist

## Skill Permission Policy

- [x] Registry receives normalized permissions (`allow`, `deny`, `ask`) from settings.
- [x] Registry evaluates each skill's `allowed-tools` and records a permission status (`allowed`, `ask`, or `denied`).
- [x] Skill entries expose `allowed_tools` and `permission_status` metadata for runtime consumers.

## Dispatcher Enforcement

- [x] Signal dispatcher skips execution for skills with `ask` status (approval required).
- [x] Signal dispatcher skips execution for skills with `denied` status.
- [x] Dispatcher still allows normal execution for skills with `allowed` status.

## Integration

- [x] Application wiring passes settings permissions into `SkillRegistry` startup options.

## Validation

- [x] Added registry tests for permission status classification using `allowed-tools`.
- [x] Added dispatcher tests ensuring ask-gated skills do not execute actions.
