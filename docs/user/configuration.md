# Configuration Guide

Runtime configuration is loaded from JSON and merged with deterministic precedence.

## File Locations

- Global settings: `~/.jido_code/settings.json`
- Local settings: `.jido_code/settings.json`

Merge order:

1. Internal defaults
2. Global settings
3. Local settings

Local always overrides global for overlapping keys.

## Settings Shape

Top-level keys:

- `version` (required): semantic version string (`x.y.z`).
- `signal_bus` (required): bus name and middleware list.
- `permissions` (optional): `allow`, `deny`, `ask` pattern lists.
- `hooks` (required): `pre` and `post` defaults.

Reference schema:

- `schemas/settings.schema.json`

## Signal Bus

`signal_bus.name` accepts an atom-like identifier as string (`"jido_code_bus"`).

`signal_bus.middleware` is a list of:

- `module`: module name as string, for example `Elixir.Jido.Signal.Bus.Middleware.Logger`
- `opts`: object or `null`

## Hooks

Only `pre` and `post` are supported.

Each hook supports:

- `enabled` (`true` or `false`)
- `signal_type` (`skill/pre`, `skill/post`, or custom slash-delimited lower-case path)
- `bus` (atom-like string, optionally `:prefixed`)
- `data_template` (flat key/value object)

At runtime:

- Hook signal type is published in dot form (for example `skill/pre` becomes `skill.pre`).
- Signal source uses slash form (for example `/hooks/skill/pre`).

## Permissions

`permissions` classifies skill entries from `allowed-tools` and glob-like patterns:

- `deny` has highest priority.
- `allow` acts as an allowlist when non-empty.
- `ask` marks tools requiring approval.

Examples:

- `Bash(git:*)`
- `Bash(rm -rf:*)`
- `Read`

If a route hits a skill with `ask` or `denied`, the dispatcher skips execution and emits `skill.permission.blocked`.

## Validation Behavior

Settings are strict:

- Unknown keys are rejected.
- Invalid formats fail validation.
- Startup fails if settings are invalid.

On reload:

- If reload parsing fails, cached settings remain active.

## Reload Behavior

Reload through:

```elixir
Jido.Code.Skill.SkillRuntime.SkillRegistry.reload()
```

Reload updates:

- Discovered skills
- Hook defaults
- Permission classification
- Active signal bus target (dispatcher and lifecycle subscriber migrate/fallback with resilience logic)
