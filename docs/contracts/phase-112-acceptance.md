# Phase 112 Acceptance Checklist

## Skill CLI List Command Support

- [x] Added `mix skill.list` terminal task for enumerating discovered skills from `SkillRegistry`.
- [x] `mix skill.list` supports scope and permission-status filtering via `--scope` and `--permission-status`.
- [x] Added `skill list [options]` CLI routing that differentiates `list` from `run`.
- [x] Explicit `skill run <skill_name> ...` remains available for skill names that collide with subcommand names (for example, `list`).

## Validation

- [x] Added CLI resolver tests covering `list` subcommand routing and explicit `run` disambiguation.
- [x] Added mix task tests covering listing output, filtering behavior, and invalid filter validation.
