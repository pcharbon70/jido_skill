# Runtime Signals and Telemetry

This runtime is signal-first. Dispatcher, hooks, registry updates, and observability all flow through the signal bus.

## Core Signal Types

- Route dispatch signals: derived from skill router paths (`/` becomes `.`).
- Lifecycle hooks:
  - `skill.pre`
  - `skill.post`
  - or custom types from settings/frontmatter.
- Permission block signal:
  - `skill.permission.blocked`
- Registry update signal:
  - `skill.registry.updated`

## Route Normalization

- Skill router path: `pdf/extract/text`
- Bus subscription and publish type: `pdf.extract.text`

## Hook Emission

`HookEmitter` resolves hooks with precedence:

1. Frontmatter hook (`jido.hooks.pre|post`)
2. Global hook defaults (`settings.json` hooks)

Runtime fields override template collisions:

- `phase`
- `skill_name`
- `route`
- `status` (post only)
- `timestamp`

## Permission Blocking

When permissions classify a skill as `ask` or `denied`:

- Dispatcher does not execute the skill.
- Dispatcher emits `skill.permission.blocked` with:
  - `skill_name`
  - `route`
  - `reason` (`ask` or `denied`)
  - `tools`
  - `timestamp`

## Registry Updates

`SkillRegistry.reload/0` publishes `skill.registry.updated` with:

- `skills` (sorted skill names)
- `count`

Dispatcher and lifecycle subscriber listen for this signal to refresh subscriptions.

## Lifecycle Telemetry

`SkillLifecycleSubscriber` emits telemetry on:

- Event: `[:jido_skill, :skill, :lifecycle]`
- Measurement: `%{count: 1}`
- Metadata includes:
  - `type`
  - `source`
  - `data`
  - `bus`
  - `timestamp`
  - `phase`
  - `skill_name`
  - `route`
  - `status`
  - `reason`
  - `tools`

Attach a telemetry handler:

```elixir
:telemetry.attach(
  "jido-skill-lifecycle-debug",
  [:jido_skill, :skill, :lifecycle],
  fn _event, measurements, metadata, _config ->
    IO.inspect({measurements, metadata}, label: "lifecycle")
  end,
  nil
)
```
