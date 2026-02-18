# Phase 4 Acceptance Checklist

## Frontmatter Parser And Compiler

- [x] Implemented `JidoSkill.SkillRuntime.Skill.from_markdown/1` parser/compiler pipeline.
- [x] Supports extracting YAML frontmatter + markdown body.
- [x] Parses and normalizes `name`, `description`, `version`, `allowed-tools`, `jido.actions`, `jido.router`, and `jido.hooks`.
- [x] Compiles deterministic runtime modules from skill file paths.

## Guardrails

- [x] Errors on missing required fields.
- [x] Errors on missing `actions` or `router` config.
- [x] Errors on unresolved action modules.
- [x] Errors on unknown router action references.

## Registry Integration

- [x] `SkillRegistry` now loads skills via `Skill.from_markdown/1`.
- [x] Registry entries now carry compiled module references.

## Validation

- [x] Added compiler tests for valid compile, missing required fields, and unresolved action modules.
- [x] Existing registry discovery tests pass with compiled-skill loading.
