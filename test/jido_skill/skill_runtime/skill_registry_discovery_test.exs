defmodule JidoSkill.TestActions.DiscoveryAction do
end

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
    assert global_only.permission_status == :allowed
    assert global_only.allowed_tools == []
  end

  test "classifies skill permission status from allowed-tools and settings permissions" do
    tmp = tmp_dir("permissions")
    global_root = Path.join(tmp, "global")
    local_root = Path.join(tmp, "local")

    write_skill(local_root, "allowed_skill", "allowed-skill", "1.0.0", "Allowed",
      allowed_tools: "Read"
    )

    write_skill(local_root, "ask_skill", "ask-skill", "1.0.0", "Ask",
      allowed_tools: "Bash(git:*)"
    )

    write_skill(local_root, "denied_skill", "denied-skill", "1.0.0", "Denied",
      allowed_tools: "Bash(rm -rf:*)"
    )

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
          hook_defaults: %{pre: %{}, post: %{}},
          permissions: %{
            "allow" => ["Read"],
            "deny" => ["Bash(rm -rf:*)"],
            "ask" => ["Bash(git:*)"]
          }
        ]
      })

    assert SkillRegistry.get_skill(registry, "allowed-skill").permission_status == :allowed

    assert SkillRegistry.get_skill(registry, "ask-skill").permission_status ==
             {:ask, ["Bash(git:*)"]}

    assert SkillRegistry.get_skill(registry, "denied-skill").permission_status ==
             {:denied, ["Bash(rm -rf:*)"]}
  end

  test "trims whitespace in settings permission patterns before classification" do
    tmp = tmp_dir("permissions_trim")
    global_root = Path.join(tmp, "global")
    local_root = Path.join(tmp, "local")

    write_skill(local_root, "allowed_skill", "allowed-skill", "1.0.0", "Allowed",
      allowed_tools: "Read"
    )

    write_skill(local_root, "ask_skill", "ask-skill", "1.0.0", "Ask",
      allowed_tools: "Bash(git:*)"
    )

    write_skill(local_root, "denied_skill", "denied-skill", "1.0.0", "Denied",
      allowed_tools: "Bash(rm -rf:*)"
    )

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
          hook_defaults: %{pre: %{}, post: %{}},
          permissions: %{
            "allow" => ["  Read  "],
            "deny" => ["  Bash(rm -rf:*)  "],
            "ask" => ["  Bash(git:*)  "]
          }
        ]
      })

    assert SkillRegistry.get_skill(registry, "allowed-skill").permission_status == :allowed

    assert SkillRegistry.get_skill(registry, "ask-skill").permission_status ==
             {:ask, ["Bash(git:*)"]}

    assert SkillRegistry.get_skill(registry, "denied-skill").permission_status ==
             {:denied, ["Bash(rm -rf:*)"]}
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
    assert signal.source == "/skill_registry"

    count = Map.get(signal.data, :count) || Map.get(signal.data, "count")
    skills = Map.get(signal.data, :skills) || Map.get(signal.data, "skills")

    assert count == 1
    assert Enum.sort(skills) == ["alpha"]
  end

  test "reload publishes sorted skill names in registry update payload" do
    tmp = tmp_dir("reload_sorted")
    global_root = Path.join(tmp, "global")
    local_root = Path.join(tmp, "local")

    write_skill(local_root, "zeta", "zeta", "1.0.0", "Zeta")
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

    skills = Map.get(signal.data, :skills) || Map.get(signal.data, "skills")
    assert skills == ["alpha", "zeta"]
  end

  test "reload refreshes hook defaults from settings files when settings are present" do
    tmp = tmp_dir("reload_hook_defaults")
    global_root = Path.join(tmp, "global")
    local_root = Path.join(tmp, "local")

    write_skill(local_root, "alpha", "alpha", "1.0.0", "Alpha")

    local_settings_path = Path.join(local_root, "settings.json")
    write_settings(local_settings_path, "skill/reloaded/pre", "skill/reloaded/post")

    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Jido.Signal.Bus, [name: bus_name, middleware: []]})

    initial_hook_defaults = %{
      pre: %{enabled: true, signal_type: "skill/pre", bus: bus_name, data: %{}},
      post: %{enabled: true, signal_type: "skill/post", bus: bus_name, data: %{}}
    }

    registry =
      start_supervised!({
        SkillRegistry,
        [
          name: nil,
          bus_name: bus_name,
          global_path: global_root,
          local_path: local_root,
          settings_path: local_settings_path,
          hook_defaults: initial_hook_defaults
        ]
      })

    assert SkillRegistry.hook_defaults(registry) == initial_hook_defaults
    assert :ok = SkillRegistry.reload(registry)

    assert %{pre: pre_hook, post: post_hook} = SkillRegistry.hook_defaults(registry)
    assert pre_hook.signal_type == "skill/reloaded/pre"
    assert pre_hook.bus == :jido_code_bus
    assert post_hook.signal_type == "skill/reloaded/post"
    assert post_hook.bus == :jido_code_bus
  end

  test "reload keeps cached hook defaults when settings reload fails" do
    tmp = tmp_dir("reload_hook_defaults_invalid")
    global_root = Path.join(tmp, "global")
    local_root = Path.join(tmp, "local")

    write_skill(local_root, "alpha", "alpha", "1.0.0", "Alpha")

    local_settings_path = Path.join(local_root, "settings.json")
    File.mkdir_p!(Path.dirname(local_settings_path))
    File.write!(local_settings_path, "{invalid")

    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Jido.Signal.Bus, [name: bus_name, middleware: []]})

    initial_hook_defaults = %{
      pre: %{enabled: true, signal_type: "skill/pre", bus: bus_name, data: %{}},
      post: %{enabled: true, signal_type: "skill/post", bus: bus_name, data: %{}}
    }

    registry =
      start_supervised!({
        SkillRegistry,
        [
          name: nil,
          bus_name: bus_name,
          global_path: global_root,
          local_path: local_root,
          settings_path: local_settings_path,
          hook_defaults: initial_hook_defaults
        ]
      })

    assert SkillRegistry.hook_defaults(registry) == initial_hook_defaults
    assert :ok = SkillRegistry.reload(registry)
    assert SkillRegistry.hook_defaults(registry) == initial_hook_defaults
  end

  test "reload refreshes permissions from settings and reclassifies skill entries" do
    tmp = tmp_dir("reload_permissions")
    global_root = Path.join(tmp, "global")
    local_root = Path.join(tmp, "local")

    write_skill(local_root, "ask_skill", "ask-skill", "1.0.0", "Ask",
      allowed_tools: "Bash(git:*)"
    )

    local_settings_path = Path.join(local_root, "settings.json")

    write_settings(local_settings_path, "skill/reloaded/pre", "skill/reloaded/post", %{
      "allow" => [],
      "deny" => [],
      "ask" => ["Bash(git:*)"]
    })

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
          settings_path: local_settings_path,
          hook_defaults: %{
            pre: %{enabled: true, signal_type: "skill/pre", bus: bus_name, data: %{}},
            post: %{enabled: true, signal_type: "skill/post", bus: bus_name, data: %{}}
          },
          permissions: %{
            "allow" => [],
            "deny" => [],
            "ask" => []
          }
        ]
      })

    assert SkillRegistry.get_skill(registry, "ask-skill").permission_status == :allowed

    assert :ok = SkillRegistry.reload(registry)

    assert SkillRegistry.get_skill(registry, "ask-skill").permission_status ==
             {:ask, ["Bash(git:*)"]}
  end

  test "reload keeps cached permissions when settings reload fails" do
    tmp = tmp_dir("reload_permissions_invalid")
    global_root = Path.join(tmp, "global")
    local_root = Path.join(tmp, "local")

    write_skill(local_root, "ask_skill", "ask-skill", "1.0.0", "Ask",
      allowed_tools: "Bash(git:*)"
    )

    local_settings_path = Path.join(local_root, "settings.json")
    File.mkdir_p!(Path.dirname(local_settings_path))
    File.write!(local_settings_path, "{invalid")

    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Jido.Signal.Bus, [name: bus_name, middleware: []]})

    cached_permissions = %{
      "allow" => [],
      "deny" => [],
      "ask" => ["Bash(git:*)"]
    }

    registry =
      start_supervised!({
        SkillRegistry,
        [
          name: nil,
          bus_name: bus_name,
          global_path: global_root,
          local_path: local_root,
          settings_path: local_settings_path,
          hook_defaults: %{
            pre: %{enabled: true, signal_type: "skill/pre", bus: bus_name, data: %{}},
            post: %{enabled: true, signal_type: "skill/post", bus: bus_name, data: %{}}
          },
          permissions: cached_permissions
        ]
      })

    assert SkillRegistry.get_skill(registry, "ask-skill").permission_status ==
             {:ask, ["Bash(git:*)"]}

    assert :ok = SkillRegistry.reload(registry)

    assert SkillRegistry.get_skill(registry, "ask-skill").permission_status ==
             {:ask, ["Bash(git:*)"]}
  end

  defp write_skill(root, dir_name, skill_name, version, description, opts \\ []) do
    skill_path = Path.join([root, "skills", dir_name])
    File.mkdir_p!(skill_path)
    allowed_tools = Keyword.get(opts, :allowed_tools)

    content = """
    ---
    name: #{skill_name}
    description: #{description}
    version: #{version}
    #{allowed_tools_line(allowed_tools)}
    jido:
      actions:
        - JidoSkill.TestActions.DiscoveryAction
      router:
        - "skill/#{skill_name}/run": DiscoveryAction
    ---

    # #{skill_name}
    """

    File.write!(Path.join(skill_path, "SKILL.md"), content)
  end

  defp write_settings(
         path,
         pre_signal_type,
         post_signal_type,
         permissions \\ %{"allow" => [], "deny" => [], "ask" => []}
       ) do
    settings = %{
      "version" => "2.0.0",
      "signal_bus" => %{"name" => "jido_code_bus", "middleware" => []},
      "permissions" => permissions,
      "hooks" => %{
        "pre" => %{
          "enabled" => true,
          "signal_type" => pre_signal_type,
          "bus" => ":jido_code_bus",
          "data_template" => %{}
        },
        "post" => %{
          "enabled" => true,
          "signal_type" => post_signal_type,
          "bus" => ":jido_code_bus",
          "data_template" => %{}
        }
      }
    }

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(settings))
  end

  defp allowed_tools_line(nil), do: ""
  defp allowed_tools_line(value), do: "allowed-tools: #{value}"

  defp tmp_dir(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    path = Path.join(System.tmp_dir!(), "jido_skill_registry_#{prefix}_#{suffix}")

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
