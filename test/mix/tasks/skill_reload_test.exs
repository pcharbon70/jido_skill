defmodule Jido.Code.Skill.MixTasks.SkillReloadTestActions.Noop do
  use Jido.Action,
    name: "mix_task_skill_reload_noop",
    schema: []

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule Mix.Tasks.Skill.ReloadTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Jido.Code.Skill.SkillRuntime.SkillRegistry
  alias Jido.Signal.Bus
  alias Mix.Tasks.Skill.Reload

  setup do
    unique_suffix = Integer.to_string(System.unique_integer([:positive]))
    tmp_dir = Path.join(System.tmp_dir!(), "jido_skill_mix_task_reload_test_#{unique_suffix}")
    local_root = Path.join(tmp_dir, "local")
    global_root = Path.join(tmp_dir, "global")

    File.mkdir_p!(Path.join(local_root, "skills"))
    File.mkdir_p!(Path.join(global_root, "skills"))

    first_skill_name = "reload-skill-#{unique_suffix}"
    write_skill(local_root, first_skill_name, "reload/one")

    bus = "mix_task_skill_reload_bus_#{unique_suffix}"
    start_supervised!({Bus, [name: bus, middleware: []]})

    registry = unique_name("mix_task_skill_reload_registry")

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

    on_exit(fn ->
      Mix.Task.reenable("skill.reload")
      File.rm_rf!(tmp_dir)
    end)

    {:ok,
     registry: registry, bus: bus, local_root: local_root, first_skill_name: first_skill_name}
  end

  test "reloads registry and returns summary payload", context do
    output =
      capture_io(fn ->
        Reload.run([
          "--no-start-app",
          "--no-pretty",
          "--registry",
          Atom.to_string(context.registry)
        ])
      end)

    payload = Jason.decode!(output)

    assert payload["status"] == "reloaded"
    assert payload["skills_count"] == 1
    assert payload["skills"] == [context.first_skill_name]
    assert get_in(payload, ["bus_name", "before"]) == context.bus
    assert get_in(payload, ["bus_name", "after"]) == context.bus
    assert get_in(payload, ["hooks", "pre"]) == nil
    assert get_in(payload, ["hooks", "post"]) == nil
  end

  test "reload picks up new skills added after startup", context do
    assert SkillRegistry.list_skills(context.registry) |> length() == 1

    second_skill_name = "reload-skill-second-#{System.unique_integer([:positive])}"
    write_skill(context.local_root, second_skill_name, "reload/two")

    output =
      capture_io(fn ->
        Reload.run([
          "--no-start-app",
          "--no-pretty",
          "--registry",
          Atom.to_string(context.registry)
        ])
      end)

    payload = Jason.decode!(output)
    skill_names = payload["skills"] |> Enum.sort()

    assert payload["status"] == "reloaded"
    assert payload["skills_count"] == 2
    assert skill_names == Enum.sort([context.first_skill_name, second_skill_name])
  end

  test "rejects unknown registry atom values" do
    assert_raise Mix.Error, ~r/--registry must reference an existing atom name/, fn ->
      capture_io(fn ->
        Reload.run(["--no-start-app", "--registry", "missing_registry_name"])
      end)
    end
  end

  test "rejects unexpected positional arguments", context do
    assert_raise Mix.Error, ~r/Unexpected positional arguments/, fn ->
      capture_io(fn ->
        Reload.run([
          "--no-start-app",
          "--registry",
          Atom.to_string(context.registry),
          "extra"
        ])
      end)
    end
  end

  defp write_skill(root, skill_name, route) do
    markdown = """
    ---
    name: #{skill_name}
    description: Skill reload test skill
    version: 1.0.0
    jido:
      actions:
        - Jido.Code.Skill.MixTasks.SkillReloadTestActions.Noop
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
