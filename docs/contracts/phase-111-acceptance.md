# Phase 111 Acceptance Checklist

## Skill CLI Terminal Command Support

- [x] Project exposes an escript entrypoint named `jido` backed by `Jido.Code.Skill.CLI`.
- [x] CLI requires `--skill` as the first argument and routes `jido --skill <skill_name> <opts>` to `mix skill.run`.
- [x] Added `mix skill.run` task that resolves skill metadata from `SkillRegistry`, validates route selection, and publishes the corresponding route signal on the configured bus.
- [x] `mix skill.run` supports runtime overrides needed for terminal usage (`--route`, `--data`, `--bus`, `--registry`, `--reload`, `--source`).

## Validation

- [x] Added CLI resolver tests for shorthand, explicit subcommand, and invalid argument handling.
- [x] Added integration-style mix task tests proving published signals invoke dispatcher execution and error handling for unknown/multi-route invocations.
