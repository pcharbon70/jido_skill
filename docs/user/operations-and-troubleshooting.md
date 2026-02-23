# Operations and Troubleshooting

This guide covers common runtime operations and failure checks.

## Daily Operations

Reload skills and settings:

```elixir
Jido.Code.Skill.SkillRuntime.SkillRegistry.reload()
```

Inspect loaded skills:

```elixir
Jido.Code.Skill.SkillRuntime.SkillRegistry.list_skills()
```

Inspect active routes:

```elixir
Jido.Code.Skill.SkillRuntime.SignalDispatcher.routes()
```

Run a skill route from terminal:

```bash
mix skill.run <skill-name> --route <route/path> --data '{"value":"hello"}'
```

or with the `jido` escript:

```bash
./jido --skill <skill-name> --route <route/path> --data '{"value":"hello"}'
```

List discovered skills from terminal:

```bash
mix skill.list --scope all
./jido --skill list --scope local
```

Reload skills and runtime settings:

```bash
mix skill.reload
./jido --skill reload --no-start-app
```

Inspect active dispatcher routes from terminal:

```bash
mix skill.routes --reload
./jido --skill routes
```

Watch lifecycle/permission/registry signals from terminal:

```bash
mix skill.watch --limit 50
./jido --skill watch --pattern skill.registry.updated --timeout 30000
```

Publish manual signals for runtime checks:

```bash
mix skill.signal skill.pre --data '{"skill_name":"pdf-processor","route":"pdf/extract/text"}'
./jido --skill signal custom.health.check --data '{"status":"ok"}'
```

## Runtime Health Checks

From IEx:

```elixir
Process.alive?(Process.whereis(Jido.Code.Skill.SkillRuntime.SkillRegistry))
Process.alive?(Process.whereis(Jido.Code.Skill.SkillRuntime.SignalDispatcher))
Process.alive?(Process.whereis(Jido.Code.Skill.Observability.SkillLifecycleSubscriber))
```

## Common Issues

### Startup fails with invalid settings

- Cause: schema/validation failure in `settings.json`.
- Check for unknown keys and invalid formats.
- Validate against:
  - `schemas/settings.schema.json`

### Skills are not discovered

- Ensure files are named `SKILL.md`.
- Confirm location under:
  - `~/.jido_code/skills/...`
  - `.jido_code/skills/...`
- Check required frontmatter fields and valid `jido` section.

### Route signals do not dispatch

- Confirm route is present in `SignalDispatcher.routes/0`.
- Publish using dot-normalized type (`pdf.extract.text`), not slash path.
- Ensure action modules are compiled and loadable.

### Hook signals missing

- Verify global hooks enabled in settings.
- Verify frontmatter did not disable with `enabled: false`.
- Ensure hook `signal_type` and `bus` values are valid.

### Permission blocked execution

- Check `allowed-tools` in skill frontmatter.
- Check `permissions.allow|deny|ask` patterns in settings.
- Look for `skill.permission.blocked` signals and `reason`.

## Bus Migration and Fallback Behavior

Dispatcher and lifecycle subscriber support resilient refresh behavior:

- On refresh target-bus lookup failures, they keep cached subscriptions.
- On recovery, they migrate subscriptions to the resolved bus.
- Registry updates are published to both previous and current bus names when needed.

If you see warnings about failed migration/subscription, confirm the target bus exists and then trigger a registry reload.

## Recommended Validation Commands

```bash
mix test
mix credo
mix dialyzer
```
