# Phase 2 Acceptance Checklist

## Config Loader

- [x] Added `Jido.Code.Skill.Config.Settings` loader for optional global/local settings files.
- [x] Implemented merge order `defaults <- global <- local`.
- [x] Kept local settings as precedence winner.

## Validation

- [x] Added strict key validation at root, `signal_bus`, `permissions`, and `hooks` scopes.
- [x] Validates `version`, bus name, middleware shape, and hook fields.
- [x] Rejects invalid hook signal type formats and unknown keys.

## Runtime Wiring

- [x] `Jido.Code.Skill.Application` now loads validated settings before starting children.
- [x] Signal bus name and middleware are sourced from normalized settings.
- [x] `SkillRegistry` receives normalized hook defaults from settings.

## Tests

- [x] Added tests for missing-file defaults.
- [x] Added tests for global/local precedence behavior.
- [x] Added tests for unknown key and invalid hook validation failures.
