# Phase 116 Acceptance Checklist

## Skill CLI Routes Command Support

- [x] Added `mix skill.routes` terminal task to inspect active route subscriptions from `SignalDispatcher`.
- [x] `mix skill.routes` supports `--dispatcher`, `--registry`, and `--reload` runtime overrides for terminal operations.
- [x] Added `skill routes [options]` CLI routing for terminal route inspection.
- [x] Explicit `skill run <skill_name> ...` remains available for skill names that collide with subcommands (for example, `routes`).

## Validation

- [x] Added CLI resolver tests covering `routes` subcommand routing and explicit `run` disambiguation.
- [x] Added mix task tests covering route output, reload-driven route refresh, and argument validation.
