# Architecture Overview

This runtime is a small OTP application that loads settings, compiles/discovers skills, and dispatches signal-driven execution.

## Runtime Boundaries

- Entry point: `JidoSkill.Application`.
- Configuration and merge rules: `JidoSkill.Config` and `JidoSkill.Config.Settings`.
- Skill discovery and cached metadata: `JidoSkill.SkillRuntime.SkillRegistry`.
- Signal route dispatch and execution: `JidoSkill.SkillRuntime.SignalDispatcher`.
- Hook emission: `JidoSkill.SkillRuntime.HookEmitter` (called by compiled skill modules).
- Observability subscriber: `JidoSkill.Observability.SkillLifecycleSubscriber`.

## Supervision Topology

```mermaid
graph TD
  A["JidoSkill.Application"] --> B["Jido.Signal.Bus"]
  A --> C["JidoSkill.SkillRuntime.SkillRegistry"]
  A --> D["JidoSkill.SkillRuntime.SignalDispatcher"]
  A --> E["JidoSkill.Observability.SkillLifecycleSubscriber"]

  C -- "registry state" --> D
  C -- "registry state" --> E

  C -- "publish skill.registry.updated" --> B
  D -- "subscribe routes and dispatch" --> B
  E -- "subscribe lifecycle and telemetry" --> B
```

## Startup Sequence

```mermaid
sequenceDiagram
  participant App as JidoSkill.Application
  participant Settings as Config.Settings
  participant Bus as Jido.Signal.Bus
  participant Registry as SkillRegistry
  participant Dispatcher as SignalDispatcher
  participant Lifecycle as SkillLifecycleSubscriber

  App->>Settings: load_settings()
  Settings-->>App: {:ok, settings}
  App->>Bus: start_link(name, middleware)
  App->>Registry: start_link(bus_name, paths, hook_defaults, permissions)
  App->>Dispatcher: start_link(bus_name, refresh_bus_name: true)
  App->>Lifecycle: start_link(bus_name, refresh_bus_name: true, hook_signal_types)
```

## Data Inputs

- Global settings: `~/.jido_code/settings.json`
- Local settings: `.jido_code/settings.json`
- Global skills: `~/.jido_code/skills/**/SKILL.md`
- Local skills: `.jido_code/skills/**/SKILL.md`

## Design Constraints (Current)

- Settings merge order is deterministic: defaults -> global -> local.
- Local skill name collisions override global skill entries.
- Only `pre`/`post` hook points are recognized.
- Route and signal subscription paths are normalized to dot form on the bus.
