# Getting Started

This guide gets a local runtime running with the current architecture.

## Prerequisites

- Erlang/OTP and Elixir installed (`mix.exs` targets Elixir `~> 1.17`).
- `git` installed.

## 1) Install Dependencies

```bash
mix deps.get
```

## 2) Create Runtime Directories

The runtime reads from:

- Global root: `~/.jido_code`
- Project-local root: `.jido_code`

Create local directories in your project:

```bash
mkdir -p .jido_code/skills
```

## 3) Add Local Settings

Create `.jido_code/settings.json`:

```json
{
  "version": "2.0.0",
  "signal_bus": {
    "name": "jido_code_bus",
    "middleware": [
      {
        "module": "Elixir.Jido.Signal.Bus.Middleware.Logger",
        "opts": { "level": "debug" }
      }
    ]
  },
  "permissions": {
    "allow": ["Read", "Write"],
    "deny": ["Bash(rm -rf:*)"],
    "ask": ["Bash(git:*)"]
  },
  "hooks": {
    "pre": {
      "enabled": true,
      "signal_type": "skill/pre",
      "bus": ":jido_code_bus",
      "data_template": {}
    },
    "post": {
      "enabled": true,
      "signal_type": "skill/post",
      "bus": ":jido_code_bus",
      "data_template": {}
    }
  }
}
```

## 4) Start the Runtime

```bash
iex -S mix
```

From IEx, verify children are alive:

```elixir
alias Jido.Code.Skill.SkillRuntime.{SkillRegistry, SignalDispatcher}
alias Jido.Code.Skill.Observability.SkillLifecycleSubscriber

Process.alive?(Process.whereis(SkillRegistry))
Process.alive?(Process.whereis(SignalDispatcher))
Process.alive?(Process.whereis(SkillLifecycleSubscriber))
```

## 5) Validate Discovery and Routes

```elixir
Jido.Code.Skill.SkillRuntime.SkillRegistry.list_skills()
Jido.Code.Skill.SkillRuntime.SignalDispatcher.routes()
```

If these are empty, add a skill file under `.jido_code/skills/.../SKILL.md` and run:

```elixir
Jido.Code.Skill.SkillRuntime.SkillRegistry.reload()
```

## 6) Invoke a Skill from Terminal

Run by mix task:

```bash
mix skill.run <skill-name> --route <route/path> --data '{"value":"hello"}'
```

Build and run through the `jido` CLI:

```bash
mix escript.build
./jido --skill <skill-name> --route <route/path> --data '{"value":"hello"}'
```

List discovered skills:

```bash
./jido --skill list
mix skill.list
```

Reload skills/settings after changing `SKILL.md` or `settings.json`:

```bash
./jido --skill reload
mix skill.reload
```

## Next Step

Use `docs/user/authoring-skills.md` to create your first valid `SKILL.md`.
