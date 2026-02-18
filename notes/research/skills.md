# JidoCode Skill System Design (Jido v2)

**A signal-first skill architecture based on Jido v2 primitives**

JidoCode can implement a narrow, predictable skill runtime centered on `Jido.Skill`, `Jido.Action`, and `JidoSignal.Bus`. Hook behavior is retained only as optional pre/post signal emission configured in skill frontmatter.

> **Jido v2 Architecture Note**: Jido v2 exposes modular dependencies (`jido`, `jido_action`, `jido_signal`) and path-based signal routing with CloudEvents-compliant envelopes.

## Jido v2 primitives for a skill-only architecture

The skill runtime is built from three primitives:

- **Actions** (`jido_action`): schema-validated units of work.
- **Signals** (`jido_signal`): CloudEvents-compliant pub/sub for lifecycle and hook emission.
- **Skills** (`jido`): action composition with route-based dispatch.

| Runtime Component | Jido v2 Primitive | Implementation Pattern |
|-------------------|-------------------|------------------------|
| Skill definitions | `Jido.Skill` | Markdown + frontmatter + compiled module |
| Skill operations | `Jido.Action` | Zoi-validated action execution |
| Hook lifecycle | `JidoSignal.Signal` + `JidoSignal.Bus` | Optional `pre`/`post` signals around skill execution |

## Jido v2 dependency structure

```text
jido/           # Core: Skill and runtime orchestration
jido_action/    # Action primitive with Zoi validation
jido_signal/    # Signal primitive with Bus (CloudEvents v1.0.2)
```

## Directory structure

The configuration model keeps global and project-local layers, with local values overriding global defaults.

```text
~/.jido_code/                          # Global configuration
├── settings.json                      # Global settings + signal defaults
├── JIDO.md                            # Global memory/instructions
├── skills/                            # Personal skills
│   └── skill-name/
│       ├── SKILL.md
│       └── scripts/
└── logs/

.jido_code/                            # Project-level configuration
├── settings.json                      # Project settings (overrides global)
├── JIDO.md                            # Project memory/instructions
├── skills/
│   └── skill-name/
│       └── SKILL.md
```

## JSON configuration schema (bus-first)

`settings.json` defines signal bus defaults and global pre/post hook defaults. Skill frontmatter can override or disable these defaults per skill.

```json
{
  "$schema": "https://jidocode.dev/schemas/settings.json",
  "version": "2.0.0",

  "signal_bus": {
    "name": "jido_code_bus",
    "middleware": [
      {
        "module": "JidoSignal.Bus.Middleware.Logger",
        "opts": { "level": "debug" }
      }
    ]
  },

  "permissions": {
    "allow": ["Bash(git:*)", "Read", "Write", "Edit"],
    "deny": ["Bash(rm -rf:*)"],
    "ask": ["Bash(npm:*)"]
  },

  "hooks": {
    "pre": {
      "enabled": true,
      "signal_type": "skill/pre",
      "bus": ":jido_code_bus",
      "data_template": {
        "phase": "pre",
        "skill": "{{skill_name}}",
        "route": "{{route}}",
        "timestamp": "{{timestamp}}"
      }
    },
    "post": {
      "enabled": true,
      "signal_type": "skill/post",
      "bus": ":jido_code_bus",
      "data_template": {
        "phase": "post",
        "skill": "{{skill_name}}",
        "route": "{{route}}",
        "status": "{{status}}",
        "timestamp": "{{timestamp}}"
      }
    }
  }
}
```

### Hook model

Only two hook points are supported:

| Hook | Trigger Point | Required Fields | Description |
|------|---------------|-----------------|-------------|
| `pre` | Immediately before route dispatch | `signal_type`, `bus` | Emits lifecycle context before execution |
| `post` | Immediately after execution completes | `signal_type`, `bus` | Emits lifecycle context after execution |

## Skill markdown format with optional pre/post hooks

Each skill is defined in markdown with YAML frontmatter. The `jido.hooks` section is optional.

```yaml
---
name: pdf-processor
description: Extract text, tables, and forms from PDF documents.
version: 1.2.0
allowed-tools: Read, Write, Bash(python:*)

jido:
  skill_module: JidoCode.Skills.PdfProcessor

  actions:
    - JidoCode.Actions.ExtractPdfText
    - JidoCode.Actions.ExtractPdfTables
    - JidoCode.Actions.FillPdfForm

  router:
    - "pdf/extract/text": ExtractPdfText
    - "pdf/extract/tables": ExtractPdfTables
    - "pdf/form/fill": FillPdfForm

  hooks:
    pre:
      enabled: true
      signal_type: "skill/pdf_processor/pre"
      bus: ":jido_code_bus"
      data:
        source: "skill_frontmatter"
        skill: "{{skill_name}}"
        route: "{{route}}"
    post:
      enabled: true
      signal_type: "skill/pdf_processor/post"
      bus: ":jido_code_bus"
      data:
        source: "skill_frontmatter"
        skill: "{{skill_name}}"
        route: "{{route}}"
        status: "{{status}}"
---

# PDF Processing Skill

## Quick Start

Extract text from a PDF:

```python
import pdfplumber

with pdfplumber.open("document.pdf") as pdf:
    for page in pdf.pages:
        text = page.extract_text()
        print(text)
```

## Available Operations

- Text extraction with layout awareness
- Structured table extraction to CSV/JSON
- Form filling via action routes
```

### Frontmatter hook precedence

When both global and frontmatter hook configs exist:

1. Skill frontmatter `jido.hooks.pre` overrides global `hooks.pre`.
2. Skill frontmatter `jido.hooks.post` overrides global `hooks.post`.
3. `enabled: false` in frontmatter disables that hook for the skill.
4. If both are absent, no hook signals are emitted.

## Elixir code architecture using Jido v2 patterns

### Core skill registry and loader

```elixir
defmodule JidoCode.SkillRuntime.SkillRegistry do
  @moduledoc """
  Registry for loaded skills and global hook defaults.
  Uses the signal bus for registry update notifications.
  """

  use GenServer

  alias JidoSignal.Signal
  alias JidoSignal.Bus

  defstruct skills: %{},
            skill_paths: [],
            hook_defaults: %{}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    state = %__MODULE__{
      hook_defaults: load_hook_defaults(opts[:settings_path]),
      skill_paths: skill_paths(opts)
    }

    {:ok, load_all_skills(state)}
  end

  def get_skill(name), do: GenServer.call(__MODULE__, {:get_skill, name})
  def hook_defaults, do: GenServer.call(__MODULE__, :hook_defaults)
  def reload, do: GenServer.call(__MODULE__, :reload)

  def handle_call({:get_skill, name}, _from, state) do
    {:reply, Map.get(state.skills, name), state}
  end

  def handle_call(:hook_defaults, _from, state) do
    {:reply, state.hook_defaults, state}
  end

  def handle_call(:reload, _from, state) do
    new_state = load_all_skills(%{state | skills: %{}})
    publish_registry_update(new_state.skills)
    {:reply, :ok, new_state}
  end

  defp skill_paths(opts) do
    [opts[:global_path], opts[:local_path]]
    |> Enum.map(&Path.join(&1, "skills"))
  end

  defp load_all_skills(state) do
    loaded_skills =
      state.skill_paths
      |> Enum.flat_map(&load_skills_from_path/1)
      |> Map.new(fn {name, module} -> {name, module} end)

    %{state | skills: loaded_skills}
  end

  defp publish_registry_update(skills) do
    {:ok, signal} =
      Signal.new(
        "skill/registry/updated",
        %{skills: Map.keys(skills), count: map_size(skills)},
        source: "/skill_registry"
      )

    Bus.publish(:jido_code_bus, [signal])
  end
end
```

### Signal-only hook emitter

```elixir
defmodule JidoCode.SkillRuntime.HookEmitter do
  @moduledoc """
  Emits optional pre/post skill lifecycle signals.
  No other hook types are supported.
  """

  alias JidoSignal.Signal
  alias JidoSignal.Bus

  def emit_pre(skill_name, route, frontmatter_hooks, global_hooks) do
    hook = resolve_hook(:pre, frontmatter_hooks, global_hooks)

    if enabled?(hook) do
      publish(hook, %{
        phase: "pre",
        skill_name: skill_name,
        route: route,
        timestamp: DateTime.utc_now()
      })
    else
      :ok
    end
  end

  def emit_post(skill_name, route, status, frontmatter_hooks, global_hooks) do
    hook = resolve_hook(:post, frontmatter_hooks, global_hooks)

    if enabled?(hook) do
      publish(hook, %{
        phase: "post",
        skill_name: skill_name,
        route: route,
        status: status,
        timestamp: DateTime.utc_now()
      })
    else
      :ok
    end
  end

  defp resolve_hook(type, frontmatter_hooks, global_hooks) do
    Map.get(frontmatter_hooks || %{}, type) || Map.get(global_hooks || %{}, type)
  end

  defp enabled?(nil), do: false
  defp enabled?(hook), do: Map.get(hook, :enabled, true)

  defp publish(hook, runtime_data) do
    signal_type = Map.fetch!(hook, :signal_type)
    bus = hook |> Map.get(:bus, :jido_code_bus) |> normalize_bus()

    payload =
      hook
      |> Map.get(:data, %{})
      |> interpolate(runtime_data)
      |> Map.merge(runtime_data)

    {:ok, signal} = Signal.new(signal_type, payload, source: "/hooks/#{signal_type}")
    Bus.publish(bus, [signal])
  end

  defp normalize_bus(bus) when is_atom(bus), do: bus
  defp normalize_bus(":" <> value), do: String.to_atom(value)
  defp normalize_bus(value) when is_binary(value), do: String.to_atom(value)

  defp interpolate(template_data, runtime_data) do
    Enum.reduce(template_data, %{}, fn {k, v}, acc ->
      rendered =
        case v do
          "{{skill_name}}" -> runtime_data.skill_name
          "{{route}}" -> runtime_data.route
          "{{status}}" -> Map.get(runtime_data, :status)
          _ -> v
        end

      Map.put(acc, k, rendered)
    end)
  end
end
```

### Skill implementation with route dispatch + pre/post hooks

```elixir
defmodule JidoCode.SkillRuntime.Skill do
  @moduledoc """
  Skill wrapper that emits optional pre/post lifecycle signals.
  """

  defmacro __using__(opts) do
    quote do
      use Jido.Skill,
        name: unquote(opts[:name]),
        state_key: unquote(opts[:state_key]),
        actions: unquote(opts[:actions] || [])

      @description unquote(opts[:description])
      @version unquote(opts[:version])
      @router_config unquote(opts[:router])
      @hook_config unquote(opts[:hooks] || %{})

      @impl Jido.Skill
      def mount(_context, _config) do
        {:ok, %{initialized_at: DateTime.utc_now()}}
      end

      @impl Jido.Skill
      def router(_config) do
        Enum.map(@router_config, fn {path, action} ->
          {path, %Jido.Instruction{action: action}}
        end)
      end

      @impl Jido.Skill
      def handle_signal(signal, skill_opts) do
        global_hooks = Keyword.get(skill_opts, :global_hooks, %{})

        case find_matching_route(signal.type, @router_config) do
          nil ->
            {:skip, signal}

          action ->
            JidoCode.SkillRuntime.HookEmitter.emit_pre(
              __MODULE__,
              signal.type,
              @hook_config,
              global_hooks
            )

            {:ok, %Jido.Instruction{action: action, params: signal.data}}
        end
      end

      @impl Jido.Skill
      def transform_result(result, action, skill_opts) do
        global_hooks = Keyword.get(skill_opts, :global_hooks, %{})

        status =
          case result do
            {:ok, _} -> "ok"
            {:error, _} -> "error"
            _ -> "ok"
          end

        JidoCode.SkillRuntime.HookEmitter.emit_post(
          __MODULE__,
          action_to_route(action),
          status,
          @hook_config,
          global_hooks
        )

        {:ok, result, []}
      end

      defp action_to_route(action), do: to_string(action)
    end
  end

  def from_markdown(path) do
    skill_dir = Path.dirname(path)
    {:ok, content} = File.read(path)
    {frontmatter, body} = parse_frontmatter(content)

    jido_config = frontmatter["jido"] || %{}
    module_name = module_name_from_path(path)

    actions = compile_skill_actions(jido_config["actions"], skill_dir)

    Module.create(
      module_name,
      quote do
        use JidoCode.SkillRuntime.Skill,
          name: unquote(frontmatter["name"]),
          description: unquote(frontmatter["description"]),
          version: unquote(frontmatter["version"]),
          state_key: :skill_state,
          actions: unquote(actions),
          router: unquote(jido_config["router"]),
          hooks: unquote(normalize_hooks(jido_config["hooks"]))

        @allowed_tools unquote(parse_tools(frontmatter["allowed-tools"]))
        @skill_body unquote(body)

        def skill_documentation, do: @skill_body
      end,
      Macro.Env.location(__ENV__)
    )

    {:ok, module_name}
  end

  defp normalize_hooks(nil), do: %{}

  defp normalize_hooks(hooks) do
    %{
      pre: normalize_hook(Map.get(hooks, "pre")),
      post: normalize_hook(Map.get(hooks, "post"))
    }
  end

  defp normalize_hook(nil), do: nil

  defp normalize_hook(hook) do
    %{
      enabled: Map.get(hook, "enabled", true),
      signal_type: Map.get(hook, "signal_type"),
      bus: Map.get(hook, "bus", ":jido_code_bus"),
      data: Map.get(hook, "data", %{})
    }
  end
end
```

### Signal subscription for observability

```elixir
defmodule JidoCode.Observability.SkillLifecycleSubscriber do
  @moduledoc """
  Subscribes to pre/post skill lifecycle signals and records telemetry.
  """

  use GenServer
  alias JidoSignal.Bus

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    Bus.subscribe(:jido_code_bus, "skill/pre", dispatch: {:pid, target: self()})
    Bus.subscribe(:jido_code_bus, "skill/post", dispatch: {:pid, target: self()})
    {:ok, state}
  end

  def handle_info({:signal, signal}, state) do
    emit_telemetry(signal)
    {:noreply, state}
  end

  defp emit_telemetry(signal) do
    :telemetry.execute(
      [:jido_code, :skill, :lifecycle],
      %{count: 1},
      %{type: signal.type, data: signal.data}
    )
  end
end
```

## Application supervision tree

```elixir
defmodule JidoCode.Application do
  use Application

  def start(_type, _args) do
    children = [
      {JidoSignal.Bus,
       [
         name: :jido_code_bus,
         middleware: [
           {JidoSignal.Bus.Middleware.Logger, level: :debug}
         ]
       ]},

      {JidoCode.SkillRuntime.SkillRegistry,
       [
         global_path: Path.expand("~/.jido_code"),
         local_path: ".jido_code"
       ]},

      JidoCode.Observability.SkillLifecycleSubscriber
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: JidoCode.Supervisor)
  end
end
```

## Summary of key integration points

This design keeps the runtime intentionally small:

- **Skills** remain markdown-defined and compile into `Jido.Skill` modules.
- **Hooks** are only optional `pre` and `post` signal emissions.
- **Signal transport** is exclusively `JidoSignal.Bus`; no secondary transport layer is required.

This gives a stable integration model with clear lifecycle semantics and consistent observability through a single bus.

## Key API changes relevant to this design

| Aspect | Jido v1 | Jido v2 |
|--------|---------|---------|
| Signal routing | Pattern-based (`"skill.**"`) | Path-based (`"skill/registry/updated"`) |
| Schema system | NimbleOptions | Zoi schemas |
| Dependency model | Monolithic `jido` | Modular (`jido`, `jido_action`, `jido_signal`) |
| Signal envelope | Custom format | CloudEvents v1.0.2 compliant |
| Hook lifecycle | Ad-hoc event contracts | Explicit `pre`/`post` lifecycle signals |
