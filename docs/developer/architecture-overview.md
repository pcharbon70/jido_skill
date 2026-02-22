# Architecture Overview

This runtime is a small OTP application that loads settings, compiles/discovers skills, and dispatches signal-driven execution.

## Runtime Boundaries

- Entry point: `Jido.Code.Skill.Application`.
- Configuration and merge rules: `Jido.Code.Skill.Config` and `Jido.Code.Skill.Config.Settings`.
- Skill discovery and cached metadata: `Jido.Code.Skill.SkillRuntime.SkillRegistry`.
- Signal route dispatch and execution: `Jido.Code.Skill.SkillRuntime.SignalDispatcher`.
- Hook emission: `Jido.Code.Skill.SkillRuntime.HookEmitter` (called by compiled skill modules).
- Observability subscriber: `Jido.Code.Skill.Observability.SkillLifecycleSubscriber`.

## Supervision Topology

```mermaid
graph TD
  A["Jido.Code.Skill.Application"] --> B["Jido.Signal.Bus"]
  A --> C["Jido.Code.Skill.SkillRuntime.SkillRegistry"]
  A --> D["Jido.Code.Skill.SkillRuntime.SignalDispatcher"]
  A --> E["Jido.Code.Skill.Observability.SkillLifecycleSubscriber"]

  C -- "registry state" --> D
  C -- "registry state" --> E

  C -- "publish skill.registry.updated" --> B
  D -- "subscribe routes and dispatch" --> B
  E -- "subscribe lifecycle and telemetry" --> B
```

## Startup Sequence

```mermaid
sequenceDiagram
  participant App as Jido.Code.Skill.Application
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
