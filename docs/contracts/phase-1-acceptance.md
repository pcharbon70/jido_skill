# Phase 1 Acceptance Checklist

## Runtime Skeleton

- [x] Added `Jido.Code.Skill.SkillRuntime.SkillRegistry` scaffold.
- [x] Added `Jido.Code.Skill.SkillRuntime.HookEmitter` scaffold.
- [x] Added `Jido.Code.Skill.SkillRuntime.Skill` contract/macro scaffold.
- [x] Added `Jido.Code.Skill.Observability.SkillLifecycleSubscriber` scaffold.

## Supervision Wiring

- [x] Added `Jido.Signal.Bus` child under `Jido.Code.Skill.Application`.
- [x] Added `SkillRegistry` child under `Jido.Code.Skill.Application`.
- [x] Added lifecycle subscriber child under `Jido.Code.Skill.Application`.

## Configuration Defaults

- [x] Added `config/config.exs` runtime defaults for bus and paths.
- [x] Added `Jido.Code.Skill.Config` accessor module.

## Validation

- [x] `mix test` passes with app booting against empty skill directories.
- [x] Added tests for runtime children startup and registry API scaffolding.

## Notes

Current `jido_signal` router uses dot-delimited routes. Phase 1 normalizes slash-style contract paths to dot format at bus boundaries so the architecture contract remains forward-compatible.
