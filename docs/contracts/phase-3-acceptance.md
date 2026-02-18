# Phase 3 Acceptance Checklist

## Skill Discovery

- [x] `SkillRegistry` discovers `**/SKILL.md` from global and local skill roots.
- [x] Discovery records skill metadata (`name`, `description`, `version`, `path`, `scope`, `loaded_at`).
- [x] Discovery skips malformed skill files with warning logs.

## Conflict Handling

- [x] Local skill definitions override global skill definitions on name collisions.
- [x] Duplicate names within the same scope are handled deterministically.

## Registry APIs

- [x] Added `list_skills/0,1` API.
- [x] Added server-targeted API variants for testing and isolated registry instances.
- [x] `reload/0,1` refreshes discovery state and publishes update signal.

## Signals

- [x] `reload` publishes `skill/registry/updated` (normalized to `skill.registry.updated` on the current bus router).

## Validation

- [x] Added tests for discovery from global + local roots.
- [x] Added tests for local-over-global precedence.
- [x] Added tests for reload signal publication.
