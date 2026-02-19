defmodule JidoSkill.Observability.TestActions.HookSignal do
end

defmodule JidoSkill.Observability.TestSkills.ValidLifecycleHook do
  def skill_metadata do
    %{
      hooks: %{
        pre: %{
          enabled: true,
          signal_type: "skill/custom/pre"
        }
      }
    }
  end
end

defmodule JidoSkill.Observability.TestSkills.InvalidLifecycleHook do
  def skill_metadata do
    %{
      hooks: %{
        pre: %{
          enabled: true,
          signal_type: "skill//broken"
        }
      }
    }
  end
end

defmodule JidoSkill.Observability.LifecycleSubscriberTestRegistry do
  use GenServer

  def start_link(opts) do
    state = %{
      skills: Keyword.get(opts, :skills, []),
      hook_defaults: Keyword.get(opts, :hook_defaults, %{})
    }

    GenServer.start_link(__MODULE__, state)
  end

  def set_skills(server, skills), do: GenServer.call(server, {:set_skills, skills})

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call(:list_skills, _from, state), do: {:reply, state.skills, state}

  @impl GenServer
  def handle_call(:hook_defaults, _from, state), do: {:reply, state.hook_defaults, state}

  @impl GenServer
  def handle_call({:set_skills, skills}, _from, state) do
    {:reply, :ok, %{state | skills: skills}}
  end
end

defmodule JidoSkill.Observability.SkillLifecycleSubscriberTest do
  use ExUnit.Case, async: false

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoSkill.Observability.LifecycleSubscriberTestRegistry
  alias JidoSkill.Observability.SkillLifecycleSubscriber
  alias JidoSkill.SkillRuntime.SkillRegistry

  @telemetry_event [:jido_skill, :skill, :lifecycle]

  test "emits enriched telemetry for pre and post lifecycle signals" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})
    start_supervised!({SkillLifecycleSubscriber, [name: nil, bus_name: bus_name]})

    attach_handler!()

    {:ok, pre_signal} =
      Signal.new(
        "skill.pre",
        %{
          "phase" => "pre",
          "skill_name" => "pdf-processor",
          "route" => "pdf/extract/text"
        },
        source: "/hooks/skill/pre"
      )

    {:ok, post_signal} =
      Signal.new(
        "skill.post",
        %{
          "phase" => "post",
          "skill_name" => "pdf-processor",
          "route" => "pdf/extract/text",
          "status" => "error"
        },
        source: "/hooks/skill/post"
      )

    assert {:ok, _} = Bus.publish(bus_name, [pre_signal])
    assert {:ok, _} = Bus.publish(bus_name, [post_signal])

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, pre_metadata}, 1_000
    assert pre_metadata.type == "skill.pre"
    assert pre_metadata.source == "/hooks/skill/pre"
    assert pre_metadata.bus == bus_name
    assert pre_metadata.phase == "pre"
    assert pre_metadata.skill_name == "pdf-processor"
    assert pre_metadata.route == "pdf/extract/text"
    assert pre_metadata.status == nil

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, post_metadata}, 1_000
    assert post_metadata.type == "skill.post"
    assert post_metadata.source == "/hooks/skill/post"
    assert post_metadata.bus == bus_name
    assert post_metadata.phase == "post"
    assert post_metadata.skill_name == "pdf-processor"
    assert post_metadata.route == "pdf/extract/text"
    assert post_metadata.status == "error"
    assert post_metadata.reason == nil
    assert post_metadata.tools == nil
  end

  test "emits telemetry for permission-blocked signals" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})
    start_supervised!({SkillLifecycleSubscriber, [name: nil, bus_name: bus_name]})

    attach_handler!()

    {:ok, blocked_signal} =
      Signal.new(
        "skill.permission.blocked",
        %{
          "skill_name" => "dispatcher-ask",
          "route" => "demo/ask",
          "reason" => "ask",
          "tools" => ["Bash(git:*)"],
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        source: "/permissions/skill/permission/blocked"
      )

    assert {:ok, _} = Bus.publish(bus_name, [blocked_signal])

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, metadata}, 1_000
    assert metadata.type == "skill.permission.blocked"
    assert metadata.source == "/permissions/skill/permission/blocked"
    assert metadata.bus == bus_name
    assert is_binary(metadata.timestamp)
    assert metadata.phase == nil
    assert metadata.skill_name == "dispatcher-ask"
    assert metadata.route == "demo/ask"
    assert metadata.status == nil
    assert metadata.reason == "ask"
    assert metadata.tools == ["Bash(git:*)"]
  end

  test "surfaces timestamp from lifecycle signal payload in telemetry metadata" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    start_supervised!({Bus, [name: bus_name, middleware: []]})
    start_supervised!({SkillLifecycleSubscriber, [name: nil, bus_name: bus_name]})

    attach_handler!()

    {:ok, pre_signal} =
      Signal.new(
        "skill.pre",
        %{
          "phase" => "pre",
          "skill_name" => "timestamp-skill",
          "route" => "demo/run",
          "timestamp" => timestamp
        },
        source: "/hooks/skill/pre"
      )

    assert {:ok, _} = Bus.publish(bus_name, [pre_signal])

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, metadata}, 1_000
    assert metadata.type == "skill.pre"
    assert metadata.timestamp == timestamp
  end

  test "subscribes to configured lifecycle signal types" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    start_supervised!(
      {SkillLifecycleSubscriber,
       [
         name: nil,
         bus_name: bus_name,
         hook_signal_types: ["skill/custom/pre", "skill/custom/post"]
       ]}
    )

    attach_handler!()

    {:ok, custom_pre_signal} =
      Signal.new(
        "skill.custom.pre",
        %{
          "phase" => "pre",
          "skill_name" => "custom-skill",
          "route" => "custom/run"
        },
        source: "/hooks/skill/custom/pre"
      )

    assert {:ok, _} = Bus.publish(bus_name, [custom_pre_signal])

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, metadata}, 1_000
    assert metadata.type == "skill.custom.pre"
    assert metadata.source == "/hooks/skill/custom/pre"
    assert metadata.skill_name == "custom-skill"

    {:ok, default_pre_signal} =
      Signal.new(
        "skill.pre",
        %{
          "phase" => "pre",
          "skill_name" => "default-skill",
          "route" => "default/run"
        },
        source: "/hooks/skill/pre"
      )

    assert {:ok, _} = Bus.publish(bus_name, [default_pre_signal])

    refute_receive {:telemetry, @telemetry_event, %{count: 1}, _default_metadata}, 200
  end

  test "falls back to default lifecycle subscriptions when configured list is empty" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    start_supervised!(
      {SkillLifecycleSubscriber, [name: nil, bus_name: bus_name, hook_signal_types: []]}
    )

    attach_handler!()

    {:ok, pre_signal} =
      Signal.new(
        "skill.pre",
        %{
          "phase" => "pre",
          "skill_name" => "fallback-skill",
          "route" => "fallback/run"
        },
        source: "/hooks/skill/pre"
      )

    assert {:ok, _} = Bus.publish(bus_name, [pre_signal])

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, metadata}, 1_000
    assert metadata.type == "skill.pre"
    assert metadata.skill_name == "fallback-skill"
  end

  test "supports explicit empty lifecycle subscription list when fallback is disabled" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    start_supervised!(
      {SkillLifecycleSubscriber,
       [
         name: nil,
         bus_name: bus_name,
         hook_signal_types: [],
         fallback_to_default_hook_signal_types: false
       ]}
    )

    attach_handler!()

    :ok = publish_lifecycle_signal(bus_name, "skill.pre", "/hooks/skill/pre", "explicit-empty")
    refute_receive {:telemetry, @telemetry_event, %{count: 1}, _metadata}, 200
  end

  test "ignores invalid configured lifecycle signal types while keeping valid entries" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    start_supervised!(
      {SkillLifecycleSubscriber,
       [
         name: nil,
         bus_name: bus_name,
         hook_signal_types: ["skill/custom/pre", "skill//broken", "", 123],
         fallback_to_default_hook_signal_types: false
       ]}
    )

    attach_handler!()

    :ok =
      publish_lifecycle_signal(bus_name, "skill.custom.pre", "/hooks/skill/custom/pre", "valid")

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, metadata}, 1_000
    assert metadata.type == "skill.custom.pre"
    assert metadata.skill_name == "valid"

    :ok = publish_lifecycle_signal(bus_name, "skill.pre", "/hooks/skill/pre", "default")
    refute_receive {:telemetry, @telemetry_event, %{count: 1}, _default_metadata}, 200
  end

  test "falls back to defaults when configured lifecycle signal types are all invalid" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    start_supervised!(
      {SkillLifecycleSubscriber,
       [
         name: nil,
         bus_name: bus_name,
         hook_signal_types: ["skill//broken", "", 123]
       ]}
    )

    attach_handler!()

    :ok = publish_lifecycle_signal(bus_name, "skill.pre", "/hooks/skill/pre", "fallback-invalid")

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, metadata}, 1_000
    assert metadata.type == "skill.pre"
    assert metadata.skill_name == "fallback-invalid"
  end

  test "subscribes to inherited global signal type when frontmatter explicitly enables hook" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("hook_inherit_enabled")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    write_skill(
      local_root,
      "registry-inherit-enabled",
      "registry-inherit-enabled",
      "demo/inherit-enabled",
      pre_enabled: true
    )

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SkillRegistry,
         [
           name: nil,
           bus_name: bus_name,
           global_path: global_root,
           local_path: local_root,
           hook_defaults: %{
             pre: %{enabled: false, signal_type: "skill/pre"},
             post: %{enabled: false, signal_type: "skill/post"}
           },
           permissions: %{"allow" => [], "deny" => [], "ask" => []}
         ]}
      )

    start_supervised!(
      {SkillLifecycleSubscriber,
       [
         name: nil,
         bus_name: bus_name,
         registry: registry,
         hook_signal_types: [],
         fallback_to_default_hook_signal_types: false
       ]}
    )

    attach_handler!()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.pre",
          "/hooks/skill/pre",
          "inherit-enabled"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.pre" and metadata.skill_name == "inherit-enabled"
      after
        80 ->
          false
      end
    end)
  end

  test "does not subscribe frontmatter hook when disabled global default is not overridden" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("hook_inherit_disabled")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    write_skill(
      local_root,
      "registry-inherit-disabled",
      "registry-inherit-disabled",
      "demo/inherit-disabled",
      pre_signal_type: "skill/custom/inherit_disabled"
    )

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SkillRegistry,
         [
           name: nil,
           bus_name: bus_name,
           global_path: global_root,
           local_path: local_root,
           hook_defaults: %{
             pre: %{enabled: false, signal_type: "skill/pre"},
             post: %{enabled: false, signal_type: "skill/post"}
           },
           permissions: %{"allow" => [], "deny" => [], "ask" => []}
         ]}
      )

    start_supervised!(
      {SkillLifecycleSubscriber,
       [
         name: nil,
         bus_name: bus_name,
         registry: registry,
         hook_signal_types: [],
         fallback_to_default_hook_signal_types: false
       ]}
    )

    attach_handler!()

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.custom.inherit_disabled",
            "/hooks/skill/custom/inherit_disabled",
            "inherit-disabled"
          )
      end,
      8,
      50
    )
  end

  test "refreshes lifecycle subscriptions from registry hook signal types after reload" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("lifecycle_registry_refresh")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    write_skill(local_root, "registry-base", "registry-base", "demo/base")

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SkillRegistry,
         [
           name: nil,
           bus_name: bus_name,
           global_path: global_root,
           local_path: local_root,
           hook_defaults: %{pre: %{}, post: %{}},
           permissions: %{"allow" => [], "deny" => [], "ask" => []}
         ]}
      )

    start_supervised!(
      {SkillLifecycleSubscriber, [name: nil, bus_name: bus_name, registry: registry]}
    )

    attach_handler!()

    assert :ok =
             publish_lifecycle_signal(
               bus_name,
               "skill.custom.pre",
               "/hooks/skill/custom/pre",
               "before-reload"
             )

    refute_receive {:telemetry, @telemetry_event, %{count: 1}, _metadata}, 200

    write_skill(
      local_root,
      "registry-custom",
      "registry-custom",
      "demo/custom",
      pre_signal_type: "skill/custom/pre"
    )

    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.custom.pre",
          "/hooks/skill/custom/pre",
          "after-reload"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and metadata.skill_name == "after-reload"
      after
        80 ->
          false
      end
    end)
  end

  test "preserves existing lifecycle subscriptions when refresh fails adding new signal types" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [skills: [%{module: JidoSkill.Observability.TestSkills.ValidLifecycleHook}]]}
      )

    start_supervised!(
      {SkillLifecycleSubscriber,
       [
         name: nil,
         bus_name: bus_name,
         registry: registry,
         hook_signal_types: [],
         fallback_to_default_hook_signal_types: false
       ]}
    )

    attach_handler!()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.custom.pre",
          "/hooks/skill/custom/pre",
          "before-refresh-failure"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and
            metadata.skill_name == "before-refresh-failure"
      after
        80 ->
          false
      end
    end)

    assert :ok =
             LifecycleSubscriberTestRegistry.set_skills(registry, [
               %{module: JidoSkill.Observability.TestSkills.InvalidLifecycleHook}
             ])

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.custom.pre",
          "/hooks/skill/custom/pre",
          "after-refresh-failure"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and metadata.skill_name == "after-refresh-failure"
      after
        80 ->
          false
      end
    end)
  end

  test "does not subscribe disabled hook signal types until they are enabled and reloaded" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("disabled_hook_refresh")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    write_skill(local_root, "registry-base", "registry-base", "demo/base")

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SkillRegistry,
         [
           name: nil,
           bus_name: bus_name,
           global_path: global_root,
           local_path: local_root,
           hook_defaults: %{pre: %{}, post: %{}},
           permissions: %{"allow" => [], "deny" => [], "ask" => []}
         ]}
      )

    start_supervised!(
      {SkillLifecycleSubscriber, [name: nil, bus_name: bus_name, registry: registry]}
    )

    attach_handler!()

    write_skill(
      local_root,
      "registry-disabled",
      "registry-disabled",
      "demo/disabled",
      pre_signal_type: "skill/custom/disabled",
      pre_enabled: false
    )

    assert :ok = SkillRegistry.reload(registry)

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.custom.disabled",
            "/hooks/skill/custom/disabled",
            "disabled"
          )
      end,
      8,
      50
    )

    write_skill(
      local_root,
      "registry-disabled",
      "registry-disabled",
      "demo/disabled",
      pre_signal_type: "skill/custom/disabled",
      pre_enabled: true
    )

    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.custom.disabled",
          "/hooks/skill/custom/disabled",
          "enabled"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.disabled" and metadata.skill_name == "enabled"
      after
        80 ->
          false
      end
    end)
  end

  test "removes lifecycle subscription when registry hook signal type is removed" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("hook_remove_refresh")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    write_skill(local_root, "registry-base", "registry-base", "demo/base")

    write_skill(
      local_root,
      "registry-custom",
      "registry-custom",
      "demo/custom",
      pre_signal_type: "skill/custom/pre"
    )

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SkillRegistry,
         [
           name: nil,
           bus_name: bus_name,
           global_path: global_root,
           local_path: local_root,
           hook_defaults: %{pre: %{}, post: %{}},
           permissions: %{"allow" => [], "deny" => [], "ask" => []}
         ]}
      )

    start_supervised!(
      {SkillLifecycleSubscriber, [name: nil, bus_name: bus_name, registry: registry]}
    )

    attach_handler!()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.custom.pre",
          "/hooks/skill/custom/pre",
          "before-remove"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and metadata.skill_name == "before-remove"
      after
        80 ->
          false
      end
    end)

    File.rm_rf!(Path.join([local_root, "skills", "registry-custom"]))
    assert :ok = SkillRegistry.reload(registry)

    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.custom.pre",
          "/hooks/skill/custom/pre",
          "after-remove-transition"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, _metadata} ->
          drain_telemetry_messages()
          false
      after
        80 ->
          true
      end
    end)

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.custom.pre",
            "/hooks/skill/custom/pre",
            "after-remove"
          )
      end,
      6,
      80
    )
  end

  test "ignores non-signal messages" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    subscriber_pid =
      start_supervised!({SkillLifecycleSubscriber, [name: nil, bus_name: bus_name]})

    attach_handler!()
    send(subscriber_pid, :ignore_me)

    refute_receive {:telemetry, @telemetry_event, _measurements, _metadata}, 200
  end

  defp attach_handler! do
    handler_id = "telemetry-handler-#{System.unique_integer([:positive])}"

    assert :ok =
             :telemetry.attach(
               handler_id,
               @telemetry_event,
               &__MODULE__.handle_telemetry/4,
               self()
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  def handle_telemetry(event_name, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry, event_name, measurements, metadata})
  end

  defp publish_lifecycle_signal(bus_name, type, source, skill_name) do
    with {:ok, signal} <-
           Signal.new(
             type,
             %{"phase" => "pre", "skill_name" => skill_name, "route" => "demo/run"},
             source: source
           ),
         {:ok, _recorded} <- Bus.publish(bus_name, [signal]) do
      :ok
    else
      _ ->
        :error
    end
  end

  defp publish_registry_update_signal(bus_name) do
    with {:ok, signal} <- Signal.new("skill.registry.updated", %{}, source: "/skill_registry"),
         {:ok, _recorded} <- Bus.publish(bus_name, [signal]) do
      :ok
    else
      _ ->
        :error
    end
  end

  defp write_skill(root, dir_name, skill_name, route, opts \\ []) do
    skill_dir = Path.join([root, "skills", dir_name])
    File.mkdir_p!(skill_dir)

    pre_signal_type = Keyword.get(opts, :pre_signal_type)
    pre_enabled = Keyword.fetch(opts, :pre_enabled)

    hooks_block =
      case {pre_signal_type, pre_enabled} do
        {nil, :error} ->
          ""

        _ ->
          signal_type_line =
            case pre_signal_type do
              nil -> ""
              signal_type -> "      signal_type: \"#{signal_type}\"\n"
            end

          enabled_line =
            case pre_enabled do
              {:ok, value} -> "      enabled: #{value}\n"
              :error -> ""
            end

          "  hooks:\n    pre:\n#{signal_type_line}#{enabled_line}"
      end

    content = """
    ---
    name: #{skill_name}
    description: Subscriber registry test skill #{skill_name}
    version: 1.0.0
    jido:
      actions:
        - JidoSkill.Observability.TestActions.HookSignal
      router:
        - "#{route}": HookSignal
    #{hooks_block}---

    # #{skill_name}
    """

    File.write!(Path.join(skill_dir, "SKILL.md"), content)
  end

  defp tmp_dir(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    path = Path.join(System.tmp_dir!(), "jido_skill_#{prefix}_#{suffix}")

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp assert_eventually(fun, attempts \\ 25)
  defp assert_eventually(_fun, 0), do: flunk("condition did not become true")

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_unobserved_over_time(publish_fun, attempts, timeout_ms) do
    Enum.each(1..attempts, fn _ ->
      publish_fun.()
      refute_receive {:telemetry, @telemetry_event, %{count: 1}, _metadata}, timeout_ms
    end)
  end

  defp drain_telemetry_messages do
    receive do
      {:telemetry, @telemetry_event, _measurements, _metadata} ->
        drain_telemetry_messages()
    after
      0 ->
        :ok
    end
  end
end
