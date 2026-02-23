# Phase 115 Acceptance Checklist

## Skill CLI Signal Command Support

- [x] Added `mix skill.signal` terminal task to publish arbitrary skill signal types with JSON payloads.
- [x] `mix skill.signal` supports `--data`, `--source`, `--bus`, and `--registry` runtime overrides for terminal usage.
- [x] Added `skill signal <signal_type> [options]` CLI routing for terminal signal publishing.
- [x] Explicit `skill run <skill_name> ...` remains available for skill names that collide with subcommands (for example, `signal`).

## Validation

- [x] Added CLI resolver tests covering `signal` subcommand routing and explicit `run` disambiguation.
- [x] Added mix task tests covering signal publish output, registry-derived bus resolution, and argument/data validation.
