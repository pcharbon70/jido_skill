defmodule Jido.Code.Skill.MixTasks.SkillRunTestActions.Notify do
  use Jido.Action,
    name: "mix_task_skill_run_notify",
    schema: [
      value: [type: :string, required: false]
    ]

  @notify_pid_key {__MODULE__, :notify_pid}

  def set_notify_pid(pid), do: :persistent_term.put(@notify_pid_key, pid)
  def clear_notify_pid, do: :persistent_term.erase(@notify_pid_key)

  @impl true
  def run(params, _context) do
    value = Map.get(params, :value) || Map.get(params, "value")
    notify_pid = :persistent_term.get(@notify_pid_key, nil)

    if is_pid(notify_pid), do: send(notify_pid, {:skill_run_action, value})
    {:ok, %{"echo" => value}}
  end
end

defmodule Mix.Tasks.Skill.RunTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Jido.Code.Skill.MixTasks.SkillRunTestActions.Notify
  alias Jido.Code.Skill.SkillRuntime.SignalDispatcher
  alias Jido.Code.Skill.SkillRuntime.SkillRegistry
  alias Jido.Signal.Bus
  alias Mix.Tasks.Skill.Run

  setup do
    unique_suffix = Integer.to_string(System.unique_integer([:positive]))
    tmp_dir = Path.join(System.tmp_dir!(), "jido_skill_mix_task_run_test_#{unique_suffix}")

    local_root = Path.join(tmp_dir, "local")
    global_root = Path.join(tmp_dir, "global")
    File.mkdir_p!(Path.join(local_root, "skills"))
    File.mkdir_p!(Path.join(global_root, "skills"))

    single_skill_name = "terminal-single-#{unique_suffix}"
    multi_skill_name = "terminal-multi-#{unique_suffix}"
    single_route = "terminal/run"

    write_single_route_skill(local_root, single_skill_name, single_route)
    write_multi_route_skill(local_root, multi_skill_name)

    bus = "mix_task_skill_run_bus_#{unique_suffix}"
    start_supervised!({Bus, [name: bus, middleware: []]})

    registry = unique_name("mix_task_skill_run_registry")

    start_supervised!(
      {SkillRegistry,
       [
         name: registry,
         bus_name: bus,
         global_path: global_root,
         local_path: local_root,
         settings_path: Path.join(local_root, "settings.json"),
         hook_defaults: %{},
         permissions: %{allow: [], deny: [], ask: []}
       ]}
    )

    dispatcher = unique_name("mix_task_skill_run_dispatcher")

    start_supervised!(
      {SignalDispatcher,
       [
         name: dispatcher,
         bus_name: bus,
         registry: registry,
         refresh_bus_name: false
       ]}
    )

    Notify.set_notify_pid(self())

    on_exit(fn ->
      Mix.Task.reenable("skill.run")
      Notify.clear_notify_pid()
      File.rm_rf!(tmp_dir)
    end)

    {:ok,
     bus: bus,
     registry: registry,
     single_skill_name: single_skill_name,
     single_route: single_route,
     multi_skill_name: multi_skill_name}
  end

  test "publishes a routed signal and triggers dispatcher execution", context do
    output =
      capture_io(fn ->
        Run.run([
          context.single_skill_name,
          "--route",
          context.single_route,
          "--data",
          ~s({"value":"hello"}),
          "--no-start-app",
          "--no-pretty",
          "--bus",
          context.bus,
          "--registry",
          Atom.to_string(context.registry)
        ])
      end)

    payload = Jason.decode!(output)

    assert payload["status"] == "published"
    assert payload["skill_name"] == context.single_skill_name
    assert payload["route"] == context.single_route
    assert get_in(payload, ["request", "type"]) == "terminal.run"
    assert_receive {:skill_run_action, "hello"}, 1_000
  end

  test "uses the only available route when --route is omitted", context do
    output =
      capture_io(fn ->
        Run.run([
          context.single_skill_name,
          "--data",
          ~s({"value":"auto-route"}),
          "--no-start-app",
          "--no-pretty",
          "--bus",
          context.bus,
          "--registry",
          Atom.to_string(context.registry)
        ])
      end)

    payload = Jason.decode!(output)

    assert payload["status"] == "published"
    assert payload["route"] == context.single_route
    assert_receive {:skill_run_action, "auto-route"}, 1_000
  end

  test "raises when the skill is unknown", context do
    assert_raise Mix.Error, ~r/Unknown skill/, fn ->
      capture_io(fn ->
        Run.run([
          "missing-skill",
          "--no-start-app",
          "--no-pretty",
          "--bus",
          context.bus,
          "--registry",
          Atom.to_string(context.registry)
        ])
      end)
    end
  end

  test "requires --route when the skill has multiple routes", context do
    assert_raise Mix.Error, ~r/has multiple routes; pass --route/, fn ->
      capture_io(fn ->
        Run.run([
          context.multi_skill_name,
          "--data",
          "{}",
          "--no-start-app",
          "--no-pretty",
          "--bus",
          context.bus,
          "--registry",
          Atom.to_string(context.registry)
        ])
      end)
    end
  end

  defp write_single_route_skill(local_root, skill_name, route) do
    markdown = """
    ---
    name: #{skill_name}
    description: Mix task single-route test skill
    version: 1.0.0
    jido:
      actions:
        - Jido.Code.Skill.MixTasks.SkillRunTestActions.Notify
      router:
        - "#{route}": Notify
    ---

    # #{skill_name}
    """

    path = Path.join([local_root, "skills", skill_name, "SKILL.md"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, markdown)
    path
  end

  defp write_multi_route_skill(local_root, skill_name) do
    markdown = """
    ---
    name: #{skill_name}
    description: Mix task multi-route test skill
    version: 1.0.0
    jido:
      actions:
        - Jido.Code.Skill.MixTasks.SkillRunTestActions.Notify
      router:
        - "terminal/first": Notify
        - "terminal/second": Notify
    ---

    # #{skill_name}
    """

    path = Path.join([local_root, "skills", skill_name, "SKILL.md"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, markdown)
    path
  end

  defp unique_name(prefix) do
    :"#{prefix}_#{System.unique_integer([:positive])}"
  end
end
