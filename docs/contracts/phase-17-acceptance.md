# Phase 17 Acceptance Checklist

## Skill Module Collision Guards

- [x] Compiler refuses to override non-skill runtime modules when `jido.skill_module` points at an existing module.
- [x] Compiler detects explicit `jido.skill_module` collisions across different skill source files.
- [x] Compiler allows recompiling an explicit `jido.skill_module` when the source path is unchanged.

## Module Ownership Metadata

- [x] Compiled skill modules expose ownership markers used for safe recompilation checks.
- [x] Backward-compatible generated module namespace (`JidoSkill.CompiledSkills.*`) remains purgeable.

## Validation

- [x] Added compiler test for existing runtime module protection.
- [x] Added compiler test for cross-source module conflict detection.
- [x] Added compiler test for same-source module recompilation behavior.
