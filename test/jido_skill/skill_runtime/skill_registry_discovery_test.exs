defmodule JidoSkill.SkillRuntime.SkillRegistryDiscoveryTest do
  use ExUnit.Case, async: false

  alias Jido.Signal.Bus
  alias JidoSkill.SkillRuntime.SkillRegistry

  test "discovers skills from global and local paths with local precedence" do
    tmp = tmp_dir("discovery")
    global_root = Path.join(tmp, "global")
    local_root = Path.join(tmp, "local")

    write_skill(global_root, "common", "common", "1.0.0", "Global common")
    write_skill(global_root, "global_only", "global-only", "1.1.0", "Global only")
    write_skill(local_root, "common", "common", "2.0.0", "Local common")
    write_skill(local_root, "local_only", "local-only", "0.9.0", "Local only")

    bus_name = "bus_#{System.unique_integer([:positive])}"

    start_supervised!({Jido.Signal.Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!({
        SkillRegistry,
        [
          name: nil,
          bus_name: bus_name,
          global_path: global_root,
          local_path: local_root,
          hook_defaults: %{pre: %{}, post: %{}}
        ]
      })

    skills = SkillRegistry.list_skills(registry)
    assert Enum.map(skills, & &1.name) == ["common", "global-only", "local-only"]

    common = SkillRegistry.get_skill(registry, "common")
    assert common.scope == :local
    assert common.version == "2.0.0"

    global_only = SkillRegistry.get_skill(registry, "global-only")
    assert global_only.scope == :global
    assert global_only.version == "1.1.0"
  end

  test "reload publishes skill.registry.updated signal" do
    tmp = tmp_dir("reload")
    global_root = Path.join(tmp, "global")
    local_root = Path.join(tmp, "local")

    write_skill(local_root, "alpha", "alpha", "1.0.0", "Alpha")

    bus_name = "bus_#{System.unique_integer([:positive])}"

    start_supervised!({Jido.Signal.Bus, [name: bus_name, middleware: []]})

    assert {:ok, _sub_id} =
             Bus.subscribe(bus_name, "skill.registry.updated",
               dispatch: {:pid, target: self(), delivery_mode: :async}
             )

    registry =
      start_supervised!({
        SkillRegistry,
        [
          name: nil,
          bus_name: bus_name,
          global_path: global_root,
          local_path: local_root,
          hook_defaults: %{pre: %{}, post: %{}}
        ]
      })

    assert :ok = SkillRegistry.reload(registry)

    assert_receive {:signal, signal}, 1_000
    assert signal.type == "skill.registry.updated"

    count = Map.get(signal.data, :count) || Map.get(signal.data, "count")
    skills = Map.get(signal.data, :skills) || Map.get(signal.data, "skills")

    assert count == 1
    assert Enum.sort(skills) == ["alpha"]
  end

  defp write_skill(root, dir_name, skill_name, version, description) do
    skill_path = Path.join([root, "skills", dir_name])
    File.mkdir_p!(skill_path)

    content = """
    ---
    name: #{skill_name}
    description: #{description}
    version: #{version}
    ---

    # #{skill_name}
    """

    File.write!(Path.join(skill_path, "SKILL.md"), content)
  end

  defp tmp_dir(prefix) do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_skill_registry_#{prefix}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
  end
end
