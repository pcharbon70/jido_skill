# User Guides

This directory contains user-facing guides for running and operating the current Jido.Code.Skill runtime.

## Guide Index

- `docs/user/getting-started.md`: install, configure, and boot the runtime.
- `docs/user/configuration.md`: `settings.json` structure, precedence, hooks, and permissions.
- `docs/user/authoring-skills.md`: write valid `SKILL.md` files and map routes to actions.
- `docs/user/runtime-signals-and-telemetry.md`: signal contracts, routing normalization, and telemetry.
- `docs/user/operations-and-troubleshooting.md`: reload workflows, run terminal commands, runtime checks, and common failure modes.

## Scope

These guides describe the current architecture implemented in this repository:

- Skill-only runtime (`Jido.Skill` + `Jido.Action` via compiled skill modules).
- Signal transport on `Jido.Signal.Bus`.
- Optional `pre` and `post` hooks only.
- No agent, command, or extension runtime abstractions.
