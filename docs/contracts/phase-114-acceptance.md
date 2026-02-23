# Phase 114 Acceptance Checklist

## Skill CLI Watch Command Support

- [x] Added `mix skill.watch` terminal task to subscribe to skill signal patterns and stream JSON line events.
- [x] `mix skill.watch` supports `--pattern` filters, `--timeout`, `--limit`, `--bus`, and `--registry` options.
- [x] Added `jido --skill watch [options]` CLI routing for terminal watch operations.
- [x] Explicit `jido --skill run <skill_name> ...` remains available for skill names that collide with subcommands (for example, `watch`).

## Validation

- [x] Added CLI resolver tests covering `watch` subcommand routing and explicit `run` disambiguation.
- [x] Added mix task tests covering watch streaming output, timeout completion, default patterns, and invalid limit validation.
