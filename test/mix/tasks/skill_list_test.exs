defmodule Jido.Code.Skill.MixTasks.SkillListTestActions.Noop do
end

defmodule Mix.Tasks.Skill.ListTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Jido.Code.Skill.SkillRuntime.SkillRegistry
  alias Jido.Signal.Bus
  alias Mix.Tasks.Skill.List

  setup do
    unique_suffix = Integer.to_string(System.unique_integer([:positive]))
    tmp_dir = Path.join(System.tmp_dir!(), "jido_skill_mix_task_list_test_#{unique_suffix}")
    local_root = Path.join(tmp_dir, "local")
    global_root = Path.join(tmp_dir, "global")

    File.mkdir_p!(Path.join(local_root, "skills"))
    File.mkdir_p!(Path.join(global_root, "skills"))

    global_skill_name = "global-skill-#{unique_suffix}"
    local_skill_name = "local-skill-#{unique_suffix}"

    write_skill(global_root, global_skill_name, "scope/global", ["Read"])
    write_skill(local_root, local_skill_name, "scope/local", ["Bash(git:status)"])

    bus = "mix_task_skill_list_bus_#{unique_suffix}"
    start_supervised!({Bus, [name: bus, middleware: []]})

    registry = unique_name("mix_task_skill_list_registry")

    start_supervised!(
      {SkillRegistry,
       [
         name: registry,
         bus_name: bus,
         global_path: global_root,
         local_path: local_root,
         settings_path: Path.join(local_root, "settings.json"),
         hook_defaults: %{},
         permissions: %{
           allow: ["Read"],
           ask: ["Bash(git:*)"],
           deny: []
         }
       ]}
    )

    on_exit(fn ->
      Mix.Task.reenable("skill.list")
      File.rm_rf!(tmp_dir)
    end)

    {:ok,
     registry: registry, global_skill_name: global_skill_name, local_skill_name: local_skill_name}
  end

  test "lists discovered skills with routes and permission metadata", context do
    output =
      capture_io(fn ->
        List.run([
          "--no-start-app",
          "--no-pretty",
          "--registry",
          Atom.to_string(context.registry)
        ])
      end)

    payload = Jason.decode!(output)
    skills = payload["skills"]
    skill_names = Enum.map(skills, & &1["name"]) |> Enum.sort()

    assert payload["status"] == "ok"
    assert payload["count"] == 2
    assert payload["filters"]["scope"] == "all"
    assert skill_names == Enum.sort([context.global_skill_name, context.local_skill_name])

    global_skill = Enum.find(skills, &(&1["name"] == context.global_skill_name))
    local_skill = Enum.find(skills, &(&1["name"] == context.local_skill_name))

    assert global_skill["routes"] == ["scope/global"]
    assert global_skill["permission_status"]["status"] == "allowed"
    assert local_skill["routes"] == ["scope/local"]
    assert local_skill["permission_status"]["status"] == "ask"
    assert local_skill["permission_status"]["tools"] == ["Bash(git:status)"]
  end

  test "applies scope and permission status filters", context do
    output =
      capture_io(fn ->
        List.run([
          "--no-start-app",
          "--no-pretty",
          "--registry",
          Atom.to_string(context.registry),
          "--scope",
          "local",
          "--permission-status",
          "ask"
        ])
      end)

    payload = Jason.decode!(output)
    [skill] = payload["skills"]

    assert payload["status"] == "ok"
    assert payload["count"] == 1
    assert payload["filters"]["scope"] == "local"
    assert payload["filters"]["permission_status"] == "ask"
    assert skill["name"] == context.local_skill_name
  end

  test "validates unsupported filter values", context do
    assert_raise Mix.Error, ~r/--scope must be one of: all, global, local/, fn ->
      capture_io(fn ->
        List.run([
          "--no-start-app",
          "--registry",
          Atom.to_string(context.registry),
          "--scope",
          "team"
        ])
      end)
    end

    assert_raise Mix.Error, ~r/--permission-status must be one of: allowed, ask, denied/, fn ->
      capture_io(fn ->
        List.run([
          "--no-start-app",
          "--registry",
          Atom.to_string(context.registry),
          "--permission-status",
          "pending"
        ])
      end)
    end
  end

  defp write_skill(root, skill_name, route, allowed_tools) do
    markdown = """
    ---
    name: #{skill_name}
    description: Skill list test skill
    version: 1.0.0
    allowed-tools: #{Enum.join(allowed_tools, ", ")}
    jido:
      actions:
        - Jido.Code.Skill.MixTasks.SkillListTestActions.Noop
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
