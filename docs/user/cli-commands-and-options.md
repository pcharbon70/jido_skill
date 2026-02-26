# CLI Commands and Options

This guide is the complete reference for terminal skill commands.

## Command Entry Points

Use either:

- Escript CLI: `./skill ...` (after `mix escript.build`)
- Mix tasks: `mix skill.* ...`

Command mapping:

| CLI command | Mix task |
| --- | --- |
| `./skill <skill-name> [options]` | `mix skill.run <skill-name> [options]` |
| `./skill run <skill-name> [options]` | `mix skill.run <skill-name> [options]` |
| `./skill list [options]` | `mix skill.list [options]` |
| `./skill reload [options]` | `mix skill.reload [options]` |
| `./skill routes [options]` | `mix skill.routes [options]` |
| `./skill watch [options]` | `mix skill.watch [options]` |
| `./skill signal <signal-type> [options]` | `mix skill.signal <signal-type> [options]` |

Build the escript:

```bash
mix escript.build
```

## CLI Behavior

- `./skill <skill-name> ...` is shorthand for `./skill run <skill-name> ...`.
- `help`, `--help`, and `-h` show usage.
- To run a skill whose name collides with a subcommand (`list`, `reload`, `routes`, `watch`, `signal`), use `run` explicitly.
- `./skill --skill ...` is still accepted for compatibility.
- Commands run inside the nearest parent Mix project (searches current directory and parent directories for `mix.exs`).

## `run` Command

Usage:

```bash
./skill <skill-name> [options]
./skill run <skill-name> [options]
mix skill.run <skill-name> [options]
```

Options:

| Option | Alias | Type | Default | Notes |
| --- | --- | --- | --- | --- |
| `--route` | `-r` | string | auto | Optional if the skill has exactly one route. Required when multiple routes exist. |
| `--data` | `-d` | JSON object string | `{}` | Must decode to a JSON object. |
| `--source` | `-s` | string | `/mix/skill.run` | Signal source path. |
| `--bus` | `-b` | string/atom | registry bus | Supports `:atom_name` and plain names. |
| `--registry` | none | string | `Jido.Code.Skill.SkillRuntime.SkillRegistry` | Must resolve to an existing atom name. |
| `--reload` | none | boolean | `false` | Reloads registry before dispatch. |
| `--start-app` / `--no-start-app` | none | boolean | `true` | Starts app dependencies before running. |
| `--pretty` / `--no-pretty` | none | boolean | `true` | Pretty JSON output toggle. |

## `list` Command

Usage:

```bash
./skill list [options]
mix skill.list [options]
```

Options:

| Option | Alias | Type | Default | Notes |
| --- | --- | --- | --- | --- |
| `--scope` | `-s` | `all\|global\|local` | `all` | Skill scope filter. |
| `--permission-status` | `-p` | `allowed\|ask\|denied` | none | Permission state filter. |
| `--registry` | `-r` | string | `Jido.Code.Skill.SkillRuntime.SkillRegistry` | Must resolve to an existing atom name. |
| `--reload` | none | boolean | `false` | Reloads registry before listing. |
| `--start-app` / `--no-start-app` | none | boolean | `true` | Starts app dependencies before listing. |
| `--pretty` / `--no-pretty` | none | boolean | `true` | Pretty JSON output toggle. |

## `reload` Command

Usage:

```bash
./skill reload [options]
mix skill.reload [options]
```

Options:

| Option | Alias | Type | Default | Notes |
| --- | --- | --- | --- | --- |
| `--registry` | `-r` | string | `Jido.Code.Skill.SkillRuntime.SkillRegistry` | Must resolve to an existing atom name. |
| `--start-app` / `--no-start-app` | none | boolean | `true` | Starts app dependencies before reload. |
| `--pretty` / `--no-pretty` | none | boolean | `true` | Pretty JSON output toggle. |

## `routes` Command

Usage:

```bash
./skill routes [options]
mix skill.routes [options]
```

Options:

| Option | Alias | Type | Default | Notes |
| --- | --- | --- | --- | --- |
| `--dispatcher` | `-d` | string | `Jido.Code.Skill.SkillRuntime.SignalDispatcher` | Must resolve to an existing atom name. |
| `--registry` | `-r` | string | `Jido.Code.Skill.SkillRuntime.SkillRegistry` | Used when `--reload` is set. |
| `--reload` | none | boolean | `false` | Reloads registry and refreshes dispatcher before output. |
| `--start-app` / `--no-start-app` | none | boolean | `true` | Starts app dependencies before reading routes. |
| `--pretty` / `--no-pretty` | none | boolean | `true` | Pretty JSON output toggle. |

## `watch` Command

Usage:

```bash
./skill watch [options]
mix skill.watch [options]
```

Options:

| Option | Alias | Type | Default | Notes |
| --- | --- | --- | --- | --- |
| `--pattern` | `-p` | repeatable string | built-in patterns | Repeat to watch multiple signal types. |
| `--bus` | `-b` | string/atom | registry/config bus | Supports `:atom_name` and plain names. |
| `--registry` | `-r` | string | `Jido.Code.Skill.SkillRuntime.SkillRegistry` | Used for bus resolution when `--bus` is omitted. |
| `--timeout` | `-t` | positive integer (ms) | none | Stops watch after elapsed timeout. |
| `--limit` | `-l` | positive integer | none | Stops after receiving N signals. |
| `--start-app` / `--no-start-app` | none | boolean | `true` | Starts app dependencies before subscribing. |
| `--pretty` / `--no-pretty` | none | boolean | `true` | Pretty JSON output toggle. |

Default watch patterns:

- `skill.pre`
- `skill.post`
- `skill.permission.blocked`
- `skill.registry.updated`

## `signal` Command

Usage:

```bash
./skill signal <signal-type> [options]
mix skill.signal <signal-type> [options]
```

Options:

| Option | Alias | Type | Default | Notes |
| --- | --- | --- | --- | --- |
| `--data` | `-d` | JSON object string | `{}` | Must decode to a JSON object. |
| `--source` | `-s` | string | `/mix/skill.signal` | Signal source path. |
| `--bus` | `-b` | string/atom | registry/config bus | Supports `:atom_name` and plain names. |
| `--registry` | `-r` | string | `Jido.Code.Skill.SkillRuntime.SkillRegistry` | Used for bus resolution when `--bus` is omitted. |
| `--start-app` / `--no-start-app` | none | boolean | `true` | Starts app dependencies before publish. |
| `--pretty` / `--no-pretty` | none | boolean | `true` | Pretty JSON output toggle. |

## Common Errors

- Unknown flags: tasks fail with `Unknown options: ...`.
- Unexpected positional arguments: tasks fail if extra positional values are passed.
- Invalid JSON: `--data` must decode to a JSON object map.
- Invalid atom references: `--registry` and `--dispatcher` must reference existing atom names.

## Quick Examples

```bash
# Run one route
./skill pdf-processor --route pdf/extract/text --data '{"file":"report.pdf"}'

# List local skills waiting for permissions
./skill list --scope local --permission-status ask

# Refresh runtime state
./skill reload

# Inspect current route subscriptions
./skill routes --reload

# Watch lifecycle and registry events
./skill watch --pattern skill.pre --pattern skill.post --limit 20

# Publish a manual signal
./skill signal custom.health.check --data '{"status":"ok"}'
```
