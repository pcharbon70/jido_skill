# Phase 113 Acceptance Checklist

## Skill CLI Reload Command Support

- [x] Added `mix skill.reload` terminal task to reload `SkillRegistry` from disk and print JSON summary output.
- [x] Added `skill reload [options]` CLI routing for terminal reload operations.
- [x] Explicit `skill run <skill_name> ...` remains available for skill names that collide with subcommands (for example, `reload`).

## Validation

- [x] Added CLI resolver tests covering `reload` subcommand routing and explicit `run` disambiguation.
- [x] Added mix task tests covering successful reload output, disk-change pickup after startup, and invalid argument handling.
