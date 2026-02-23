defmodule Jido.Code.Skill.MixTasks.SkillRoutesTestActions.Noop do
end

defmodule Mix.Tasks.Skill.RoutesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Jido.Code.Skill.SkillRuntime.SignalDispatcher
  alias Jido.Code.Skill.SkillRuntime.SkillRegistry
  alias Jido.Signal.Bus
  alias Mix.Tasks.Skill.Routes

  setup do
    unique_suffix = Integer.to_string(System.unique_integer([:positive]))
    tmp_dir = Path.join(System.tmp_dir!(), "jido_skill_mix_task_routes_test_#{unique_suffix}")
    local_root = Path.join(tmp_dir, "local")
    global_root = Path.join(tmp_dir, "global")

    File.mkdir_p!(Path.join(local_root, "skills"))
    File.mkdir_p!(Path.join(global_root, "skills"))

    first_skill_name = "routes-skill-#{unique_suffix}"
    write_skill(local_root, first_skill_name, "routes/one")

    bus = "mix_task_skill_routes_bus_#{unique_suffix}"
    start_supervised!({Bus, [name: bus, middleware: []]})

    registry = unique_name("mix_task_skill_routes_registry")

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

    dispatcher = unique_name("mix_task_skill_routes_dispatcher")

    start_supervised!(
      {SignalDispatcher,
       [
         name: dispatcher,
         bus_name: bus,
         registry: registry,
         refresh_bus_name: false
       ]}
    )

    on_exit(fn ->
      Mix.Task.reenable("skill.routes")
      File.rm_rf!(tmp_dir)
    end)

    {:ok,
     local_root: local_root,
     registry: registry,
     dispatcher: dispatcher,
     first_skill_name: first_skill_name}
  end

  test "lists active routes from dispatcher", context do
    output =
      capture_io(fn ->
        Routes.run([
          "--no-start-app",
          "--no-pretty",
          "--dispatcher",
          Atom.to_string(context.dispatcher)
        ])
      end)

    payload = Jason.decode!(output)

    assert payload["status"] == "ok"
    assert payload["dispatcher"] == inspect(context.dispatcher)
    assert payload["count"] == 1
    assert payload["routes"] == ["routes.one"]
  end

  test "reload picks up new routes from skill registry", context do
    second_skill_name = "routes-skill-second-#{System.unique_integer([:positive])}"
    write_skill(context.local_root, second_skill_name, "routes/two")

    output =
      capture_io(fn ->
        Routes.run([
          "--no-start-app",
          "--no-pretty",
          "--reload",
          "--registry",
          Atom.to_string(context.registry),
          "--dispatcher",
          Atom.to_string(context.dispatcher)
        ])
      end)

    payload = Jason.decode!(output)

    assert payload["status"] == "ok"
    assert payload["count"] == 2
    assert Enum.sort(payload["routes"]) == ["routes.one", "routes.two"]
  end

  test "rejects unknown dispatcher atom values" do
    assert_raise Mix.Error, ~r/--dispatcher must reference an existing atom name/, fn ->
      capture_io(fn ->
        Routes.run(["--no-start-app", "--dispatcher", "missing_dispatcher_name"])
      end)
    end
  end

  test "rejects unexpected positional arguments", context do
    assert_raise Mix.Error, ~r/Unexpected positional arguments/, fn ->
      capture_io(fn ->
        Routes.run([
          "--no-start-app",
          "--dispatcher",
          Atom.to_string(context.dispatcher),
          "extra"
        ])
      end)
    end
  end

  defp write_skill(root, skill_name, route) do
    markdown = """
    ---
    name: #{skill_name}
    description: Skill routes test skill
    version: 1.0.0
    jido:
      actions:
        - Jido.Code.Skill.MixTasks.SkillRoutesTestActions.Noop
      router:
        - "#{route}": Noop
    ---

    # #{skill_name}
    """

    path = Path.join([root, "skills", skill_name, "SKILL.md"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, markdown)
    path
  end

  defp unique_name(prefix) do
    :"#{prefix}_#{System.unique_integer([:positive])}"
  end
end
