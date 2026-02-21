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

defmodule JidoSkill.Observability.TestSkills.InheritedLifecycleHook do
  def skill_metadata do
    %{
      hooks: %{
        pre: %{
          signal_type: "skill/inherit/pre"
        }
      }
    }
  end
end

defmodule JidoSkill.Observability.TestSkills.ExplicitLifecycleHook do
  def skill_metadata do
    %{
      hooks: %{
        pre: %{
          enabled: true,
          signal_type: "skill/explicit/pre"
        }
      }
    }
  end
end

defmodule JidoSkill.Observability.TestSkills.InheritGlobalSignalTypeLifecycleHook do
  def skill_metadata do
    %{
      hooks: %{
        pre: %{
          enabled: true
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
      hook_defaults: Keyword.get(opts, :hook_defaults, %{}),
      hook_defaults_error: Keyword.get(opts, :hook_defaults_error),
      list_skills_error: Keyword.get(opts, :list_skills_error),
      bus_name: Keyword.get(opts, :bus_name)
    }

    name = Keyword.get(opts, :name)

    if is_nil(name) do
      GenServer.start_link(__MODULE__, state)
    else
      GenServer.start_link(__MODULE__, state, name: name)
    end
  end

  def set_skills(server, skills), do: GenServer.call(server, {:set_skills, skills})
  def set_hook_defaults_error(server, value),
    do: GenServer.call(server, {:set_hook_defaults_error, value})
  def set_list_skills_error(server, value),
    do: GenServer.call(server, {:set_list_skills_error, value})

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call(:bus_name, _from, state) do
    {:reply, state.bus_name, state}
  end

  @impl GenServer
  def handle_call(:list_skills, _from, state) do
    case state.list_skills_error do
      nil ->
        {:reply, state.skills, state}

      {:invalid_return, value} ->
        {:reply, value, state}

      {:exit, reason} ->
        exit(reason)

      {:raise, error} ->
        raise error
    end
  end

  @impl GenServer
  def handle_call(:hook_defaults, _from, state) do
    case state.hook_defaults_error do
      nil ->
        {:reply, state.hook_defaults, state}

      {:invalid_return, value} ->
        {:reply, value, state}

      {:exit, reason} ->
        exit(reason)

      {:raise, error} ->
        raise error
    end
  end

  @impl GenServer
  def handle_call({:set_skills, skills}, _from, state) do
    {:reply, :ok, %{state | skills: skills}}
  end

  @impl GenServer
  def handle_call({:set_hook_defaults_error, value}, _from, state) do
    {:reply, :ok, %{state | hook_defaults_error: value}}
  end

  @impl GenServer
  def handle_call({:set_list_skills_error, value}, _from, state) do
    {:reply, :ok, %{state | list_skills_error: value}}
  end
end

defmodule JidoSkill.Observability.LifecycleSubscriberNthLookupVia do
  def whereis_name({registry, lookup_plan}) do
    {lookup_index, fail_lookup?} =
      Agent.get_and_update(lookup_plan, fn %{count: count, fail_on: fail_on} = state ->
        next = count + 1
        {{next, MapSet.member?(fail_on, next)}, %{state | count: next}}
      end)

    if fail_lookup? do
      raise ArgumentError, "simulated lifecycle registry lookup failure at call #{lookup_index}"
    end

    registry
  end

  def register_name(_name, _pid), do: :yes
  def unregister_name(_name), do: :ok

  def send({registry, _lookup_plan}, message) when is_pid(registry) do
    Kernel.send(registry, message)
    registry
  end

  def send(_name, _message), do: :badarg
end

defmodule JidoSkill.Observability.SkillLifecycleSubscriberTest do
  use ExUnit.Case, async: false

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoSkill.Observability.LifecycleSubscriberTestRegistry
  alias JidoSkill.Observability.SkillLifecycleSubscriber
  alias JidoSkill.SkillRuntime.SignalDispatcher
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

  test "permission-blocked telemetry stops after settings reload allows tools" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("permission_reload_allow")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_settings_path = Path.join(local_root, "settings.json")
    route = "demo/permission_telemetry"
    route_type = "demo.permission_telemetry"

    write_skill(
      local_root,
      "permission-telemetry-skill",
      "permission-telemetry-skill",
      route,
      allowed_tools: "Bash(git:*)"
    )

    write_settings(local_settings_path, %{
      "allow" => [],
      "deny" => [],
      "ask" => []
    })

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SkillRegistry,
         [
           name: nil,
           bus_name: bus_name,
           global_path: global_root,
           local_path: local_root,
           settings_path: local_settings_path,
           hook_defaults: %{
             pre: %{enabled: false},
             post: %{enabled: false}
           },
           permissions: %{
             "allow" => [],
             "deny" => [],
             "ask" => ["Bash(git:*)"]
           }
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    subscriber =
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

    assert Process.alive?(dispatcher)
    assert Process.alive?(subscriber)
    assert SignalDispatcher.routes(dispatcher) == [route_type]
    attach_handler!()

    assert :ok = publish_dispatch_signal(bus_name, route_type, "before-reload")

    assert_permission_blocked_telemetry(
      "permission-telemetry-skill",
      route,
      "ask",
      ["Bash(git:*)"]
    )

    write_settings(local_settings_path, %{
      "allow" => [],
      "deny" => [],
      "ask" => []
    })

    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      case :sys.get_state(dispatcher).route_handlers do
        %{^route_type => [handler | _]} ->
          handler.permission_status == :allowed

        _ ->
          false
      end
    end)

    drain_telemetry_messages()

    assert_unobserved_over_time(
      fn ->
        assert :ok = publish_dispatch_signal(bus_name, route_type, "after-reload")
      end,
      6,
      80
    )
  end

  test "permission-blocked telemetry remains when settings reload fails" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("permission_reload_invalid")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_settings_path = Path.join(local_root, "settings.json")
    route = "demo/permission_telemetry_invalid"
    route_type = "demo.permission_telemetry_invalid"

    write_skill(
      local_root,
      "permission-telemetry-invalid-skill",
      "permission-telemetry-invalid-skill",
      route,
      allowed_tools: "Bash(git:*)"
    )

    write_settings(local_settings_path, %{
      "allow" => [],
      "deny" => [],
      "ask" => ["Bash(git:*)"]
    })

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SkillRegistry,
         [
           name: nil,
           bus_name: bus_name,
           global_path: global_root,
           local_path: local_root,
           settings_path: local_settings_path,
           hook_defaults: %{
             pre: %{enabled: false},
             post: %{enabled: false}
           },
           permissions: %{
             "allow" => [],
             "deny" => [],
             "ask" => ["Bash(git:*)"]
           }
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    subscriber =
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

    assert Process.alive?(dispatcher)
    assert Process.alive?(subscriber)
    assert SignalDispatcher.routes(dispatcher) == [route_type]
    attach_handler!()

    assert :ok = publish_dispatch_signal(bus_name, route_type, "before-reload")

    assert_permission_blocked_telemetry(
      "permission-telemetry-invalid-skill",
      route,
      "ask",
      ["Bash(git:*)"]
    )

    File.write!(local_settings_path, "{invalid")
    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      case :sys.get_state(dispatcher).route_handlers do
        %{^route_type => [handler | _]} ->
          handler.permission_status == {:ask, ["Bash(git:*)"]}

        _ ->
          false
      end
    end)

    drain_telemetry_messages()
    assert :ok = publish_dispatch_signal(bus_name, route_type, "after-reload")

    assert_permission_blocked_telemetry(
      "permission-telemetry-invalid-skill",
      route,
      "ask",
      ["Bash(git:*)"]
    )
  end

  test "updates inherited lifecycle subscriptions after registry reload refreshes settings hook defaults" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("lifecycle_hook_defaults_reload")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_settings_path = Path.join(local_root, "settings.json")

    write_skill(
      local_root,
      "lifecycle-inherited-reload",
      "lifecycle-inherited-reload",
      "demo/lifecycle_inherited_reload",
      pre_enabled: true
    )

    write_settings(local_settings_path, %{"allow" => [], "deny" => [], "ask" => []},
      pre_enabled: true,
      pre_signal_type: "skill/inherited/reloaded"
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
           settings_path: local_settings_path,
           hook_defaults: %{
             pre: %{enabled: true, signal_type: "skill/inherited/cached"},
             post: %{enabled: false, signal_type: "skill/post"}
           },
           permissions: %{"allow" => [], "deny" => [], "ask" => []}
         ]}
      )

    subscriber =
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

    assert Process.alive?(subscriber)
    attach_handler!()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.inherited.cached",
          "/hooks/skill/inherited/cached",
          "before-reload"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.inherited.cached" and metadata.skill_name == "before-reload"
      after
        80 ->
          false
      end
    end)

    drain_telemetry_messages()

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.inherited.reloaded",
            "/hooks/skill/inherited/reloaded",
            "before-reload-reloaded"
          )
      end,
      6,
      60
    )

    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      state = :sys.get_state(subscriber)

      get_in(state.cached_hook_defaults, [:pre, :signal_type]) == "skill/inherited/reloaded" and
        Map.has_key?(state.subscriptions, "skill.inherited.reloaded") and
        not Map.has_key?(state.subscriptions, "skill.inherited.cached")
    end)

    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.inherited.reloaded",
          "/hooks/skill/inherited/reloaded",
          "after-reload"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.inherited.reloaded" and metadata.skill_name == "after-reload"
      after
        80 ->
          false
      end
    end)

    drain_telemetry_messages()

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.inherited.cached",
            "/hooks/skill/inherited/cached",
            "after-reload-cached"
          )
      end,
      6,
      60
    )
  end

  test "preserves inherited lifecycle subscriptions when registry settings reload fails" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("lifecycle_hook_defaults_reload_invalid")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_settings_path = Path.join(local_root, "settings.json")

    write_skill(
      local_root,
      "lifecycle-inherited-reload-invalid",
      "lifecycle-inherited-reload-invalid",
      "demo/lifecycle_inherited_reload_invalid",
      pre_enabled: true
    )

    write_settings(local_settings_path, %{"allow" => [], "deny" => [], "ask" => []},
      pre_enabled: true,
      pre_signal_type: "skill/inherited/reloaded"
    )

    cached_hook_defaults = %{
      pre: %{enabled: true, signal_type: "skill/inherited/cached"},
      post: %{enabled: false, signal_type: "skill/post"}
    }

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SkillRegistry,
         [
           name: nil,
           bus_name: bus_name,
           global_path: global_root,
           local_path: local_root,
           settings_path: local_settings_path,
           hook_defaults: cached_hook_defaults,
           permissions: %{"allow" => [], "deny" => [], "ask" => []}
         ]}
      )

    subscriber =
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

    assert Process.alive?(subscriber)
    attach_handler!()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.inherited.cached",
          "/hooks/skill/inherited/cached",
          "before-reload"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.inherited.cached" and metadata.skill_name == "before-reload"
      after
        80 ->
          false
      end
    end)

    File.write!(local_settings_path, "{invalid")
    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      state = :sys.get_state(subscriber)
      state.cached_hook_defaults == cached_hook_defaults
    end)

    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.inherited.cached",
          "/hooks/skill/inherited/cached",
          "after-reload"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.inherited.cached" and metadata.skill_name == "after-reload"
      after
        80 ->
          false
      end
    end)

    drain_telemetry_messages()

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.inherited.reloaded",
            "/hooks/skill/inherited/reloaded",
            "after-reload-reloaded"
          )
      end,
      6,
      60
    )
  end

  test "migrates lifecycle subscriptions to refreshed signal bus after registry settings reload" do
    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("lifecycle_signal_bus_reload")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_settings_path = Path.join(local_root, "settings.json")

    write_settings(local_settings_path, %{"allow" => [], "deny" => [], "ask" => []},
      signal_bus_name: reloaded_bus_name
    )

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})
    start_supervised!({Bus, [name: reloaded_bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SkillRegistry,
         [
           name: nil,
           bus_name: old_bus_name,
           global_path: global_root,
           local_path: local_root,
           settings_path: local_settings_path,
           hook_defaults: %{
             pre: %{enabled: true, signal_type: "skill/pre"},
             post: %{enabled: false, signal_type: "skill/post"}
           },
           permissions: %{"allow" => [], "deny" => [], "ask" => []}
         ]}
      )

    subscriber =
      start_supervised!(
        {SkillLifecycleSubscriber,
         [
           name: nil,
           bus_name: old_bus_name,
           registry: registry,
           refresh_bus_name: true,
           hook_signal_types: ["skill/pre"],
           fallback_to_default_hook_signal_types: false
         ]}
      )

    assert Process.alive?(subscriber)
    attach_handler!()

    initial_state = :sys.get_state(subscriber)
    initial_registry_subscription = initial_state.registry_subscription
    assert initial_state.bus_name == old_bus_name

    assert_eventually(fn ->
      :ok = publish_lifecycle_signal(old_bus_name, "skill.pre", "/hooks/skill/pre", "before-reload")

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.pre" and metadata.skill_name == "before-reload" and
            metadata.bus == old_bus_name
      after
        80 ->
          false
      end
    end)

    drain_telemetry_messages()
    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      state = :sys.get_state(subscriber)

      state.bus_name == reloaded_bus_name and
        state.registry_subscription != initial_registry_subscription and
        Map.has_key?(state.subscriptions, "skill.pre")
    end)

    drain_telemetry_messages()

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            old_bus_name,
            "skill.pre",
            "/hooks/skill/pre",
            "after-reload-old-bus"
          )
      end,
      6,
      80
    )

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          reloaded_bus_name,
          "skill.pre",
          "/hooks/skill/pre",
          "after-reload-new-bus"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.pre" and metadata.skill_name == "after-reload-new-bus" and
            metadata.bus == reloaded_bus_name
      after
        80 ->
          false
      end
    end)
  end

  test "preserves cached lifecycle bus subscriptions when migration to refreshed bus fails" do
    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("lifecycle_signal_bus_reload_invalid")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_settings_path = Path.join(local_root, "settings.json")

    write_settings(local_settings_path, %{"allow" => [], "deny" => [], "ask" => []},
      signal_bus_name: reloaded_bus_name
    )

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SkillRegistry,
         [
           name: nil,
           bus_name: old_bus_name,
           global_path: global_root,
           local_path: local_root,
           settings_path: local_settings_path,
           hook_defaults: %{
             pre: %{enabled: true, signal_type: "skill/pre"},
             post: %{enabled: false, signal_type: "skill/post"}
           },
           permissions: %{"allow" => [], "deny" => [], "ask" => []}
         ]}
      )

    subscriber =
      start_supervised!(
        {SkillLifecycleSubscriber,
         [
           name: nil,
           bus_name: old_bus_name,
           registry: registry,
           refresh_bus_name: true,
           hook_signal_types: ["skill/pre"],
           fallback_to_default_hook_signal_types: false
         ]}
      )

    assert Process.alive?(subscriber)
    attach_handler!()

    initial_state = :sys.get_state(subscriber)
    initial_registry_subscription = initial_state.registry_subscription
    assert initial_state.bus_name == old_bus_name

    assert_eventually(fn ->
      :ok = publish_lifecycle_signal(old_bus_name, "skill.pre", "/hooks/skill/pre", "before-reload")

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.pre" and metadata.skill_name == "before-reload" and
            metadata.bus == old_bus_name
      after
        80 ->
          false
      end
    end)

    drain_telemetry_messages()
    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      state = :sys.get_state(subscriber)

      state.bus_name == old_bus_name and
        state.registry_subscription == initial_registry_subscription and
        Map.has_key?(state.subscriptions, "skill.pre")
    end)

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          old_bus_name,
          "skill.pre",
          "/hooks/skill/pre",
          "after-reload-old-bus"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.pre" and metadata.skill_name == "after-reload-old-bus" and
            metadata.bus == old_bus_name
      after
        80 ->
          false
      end
    end)

    assert :error =
             publish_lifecycle_signal(
               reloaded_bus_name,
               "skill.pre",
               "/hooks/skill/pre",
               "after-reload-new-bus"
             )
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

  test "starts with base subscriptions when registry hook paths are invalid and recovers after refresh" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [skills: [%{module: JidoSkill.Observability.TestSkills.InvalidLifecycleHook}]]}
      )

    subscriber =
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

    assert Process.alive?(subscriber)
    attach_handler!()

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.custom.pre",
            "/hooks/skill/custom/pre",
            "before-recovery"
          )
      end,
      6,
      60
    )

    assert :ok =
             LifecycleSubscriberTestRegistry.set_skills(registry, [
               %{module: JidoSkill.Observability.TestSkills.ValidLifecycleHook}
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
          "after-recovery"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and metadata.skill_name == "after-recovery"
      after
        80 ->
          false
      end
    end)
  end

  test "starts when registry reads fail during init and recovers registry-derived subscriptions" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [
           skills: [%{module: JidoSkill.Observability.TestSkills.ValidLifecycleHook}],
           hook_defaults_error: {:invalid_return, :hook_defaults_unavailable},
           list_skills_error: {:invalid_return, :skills_unavailable}
         ]}
      )

    subscriber =
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

    assert Process.alive?(subscriber)
    attach_handler!()

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.custom.pre",
            "/hooks/skill/custom/pre",
            "before-read-recovery"
          )
      end,
      6,
      60
    )

    assert :ok = LifecycleSubscriberTestRegistry.set_hook_defaults_error(registry, nil)
    assert :ok = LifecycleSubscriberTestRegistry.set_list_skills_error(registry, nil)
    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.custom.pre",
          "/hooks/skill/custom/pre",
          "after-read-recovery"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and metadata.skill_name == "after-read-recovery"
      after
        80 ->
          false
      end
    end)
  end

  test "starts when initial list_skills raises and recovers registry-derived subscriptions" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    registry_name = :"lifecycle_raise_registry_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    _failing_registry =
      start_supervised!(%{
        id: {:lifecycle_raise_registry, System.unique_integer([:positive])},
        start:
          {LifecycleSubscriberTestRegistry, :start_link,
           [
             [
               name: registry_name,
               skills: [%{module: JidoSkill.Observability.TestSkills.ValidLifecycleHook}],
               list_skills_error: {:raise, RuntimeError.exception("skills_unavailable")}
             ]
           ]},
        restart: :temporary
      })

    subscriber =
      start_supervised!(
        {SkillLifecycleSubscriber,
         [
           name: nil,
           bus_name: bus_name,
           registry: registry_name,
           hook_signal_types: [],
           fallback_to_default_hook_signal_types: false
         ]}
      )

    assert Process.alive?(subscriber)
    attach_handler!()

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.custom.pre",
            "/hooks/skill/custom/pre",
            "before-list-skills-raise-recovery"
          )
      end,
      6,
      60
    )

    _recovered_registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [
           name: registry_name,
           skills: [%{module: JidoSkill.Observability.TestSkills.ValidLifecycleHook}]
         ]}
      )

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.custom.pre",
          "/hooks/skill/custom/pre",
          "after-list-skills-raise-recovery"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and
            metadata.skill_name == "after-list-skills-raise-recovery"
      after
        80 ->
          false
      end
    end)
  end

  test "starts without inherited lifecycle subscriptions when initial list_skills call raises call exceptions and recovers on refresh" do
    bus_name = "bus_#{System.unique_integer([:positive])}"

    recovered_hook_defaults = %{
      pre: %{enabled: true, signal_type: "skill/default/custom/pre"},
      post: %{enabled: true, signal_type: "skill/post"}
    }

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [
           skills: [%{module: JidoSkill.Observability.TestSkills.InheritGlobalSignalTypeLifecycleHook}],
           hook_defaults: recovered_hook_defaults
         ]}
      )

    lookup_plan =
      start_supervised!(
        {Agent, fn ->
          %{count: 0, fail_on: MapSet.new([2])}
        end}
      )

    exception_registry = {:via, JidoSkill.Observability.LifecycleSubscriberNthLookupVia, {registry, lookup_plan}}

    subscriber =
      start_supervised!(
        {SkillLifecycleSubscriber,
         [
           name: nil,
           bus_name: bus_name,
           registry: exception_registry,
           hook_signal_types: [],
           fallback_to_default_hook_signal_types: false
         ]}
      )

    assert Process.alive?(subscriber)
    attach_handler!()

    subscriber_state = :sys.get_state(subscriber)
    assert subscriber_state.cached_hook_defaults == recovered_hook_defaults

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.default.custom.pre",
            "/hooks/skill/default/custom/pre",
            "before-list-skills-call-exception-recovery"
          )
      end,
      6,
      60
    )

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.default.custom.pre",
          "/hooks/skill/default/custom/pre",
          "after-list-skills-call-exception-recovery"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.default.custom.pre" and
            metadata.skill_name == "after-list-skills-call-exception-recovery"
      after
        80 ->
          false
      end
    end)

    updated_state = :sys.get_state(subscriber)
    assert updated_state.cached_hook_defaults == recovered_hook_defaults
  end

  test "starts with base subscriptions when initial registry reference raises call exceptions and recovers registry-derived subscriptions" do
    bus_name = "bus_#{System.unique_integer([:positive])}"

    recovered_hook_defaults = %{
      pre: %{enabled: true, signal_type: "skill/default/custom/pre"},
      post: %{enabled: true, signal_type: "skill/post"}
    }

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    subscriber =
      start_supervised!(
        {SkillLifecycleSubscriber,
         [
           name: nil,
           bus_name: bus_name,
           registry: %{},
           hook_signal_types: [],
           fallback_to_default_hook_signal_types: false
         ]}
      )

    assert Process.alive?(subscriber)
    attach_handler!()

    subscriber_state = :sys.get_state(subscriber)
    assert subscriber_state.cached_hook_defaults == %{}

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.default.custom.pre",
            "/hooks/skill/default/custom/pre",
            "before-call-exception-recovery"
          )
      end,
      6,
      60
    )

    recovered_registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [
           skills: [%{module: JidoSkill.Observability.TestSkills.InheritGlobalSignalTypeLifecycleHook}],
           hook_defaults: recovered_hook_defaults
         ]}
      )

    :sys.replace_state(subscriber, fn state ->
      %{state | registry: recovered_registry}
    end)

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.default.custom.pre",
          "/hooks/skill/default/custom/pre",
          "after-call-exception-recovery"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.default.custom.pre" and
            metadata.skill_name == "after-call-exception-recovery"
      after
        80 ->
          false
      end
    end)

    updated_state = :sys.get_state(subscriber)
    assert updated_state.cached_hook_defaults == recovered_hook_defaults
  end

  test "starts without inherited lifecycle subscriptions when initial hook defaults fail and recovers on refresh" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [
           skills: [%{module: JidoSkill.Observability.TestSkills.InheritGlobalSignalTypeLifecycleHook}],
           hook_defaults: %{
             pre: %{enabled: true, signal_type: "skill/default/custom/pre"},
             post: %{enabled: true, signal_type: "skill/post"}
           },
           hook_defaults_error: {:invalid_return, :hook_defaults_unavailable}
         ]}
      )

    subscriber =
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

    assert Process.alive?(subscriber)
    attach_handler!()

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.default.custom.pre",
            "/hooks/skill/default/custom/pre",
            "before-hook-default-recovery"
          )
      end,
      6,
      60
    )

    assert :ok = LifecycleSubscriberTestRegistry.set_hook_defaults_error(registry, nil)
    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.default.custom.pre",
          "/hooks/skill/default/custom/pre",
          "after-hook-default-recovery"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.default.custom.pre" and
            metadata.skill_name == "after-hook-default-recovery"
      after
        80 ->
          false
      end
    end)
  end

  test "starts without inherited lifecycle subscriptions when initial hook defaults raises and recovers on refresh" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    registry_name = :"lifecycle_hook_raise_registry_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    _failing_registry =
      start_supervised!(%{
        id: {:lifecycle_hook_raise_registry, System.unique_integer([:positive])},
        start:
          {LifecycleSubscriberTestRegistry, :start_link,
           [
             [
               name: registry_name,
               skills: [%{module: JidoSkill.Observability.TestSkills.InheritGlobalSignalTypeLifecycleHook}],
               hook_defaults: %{
                 pre: %{enabled: true, signal_type: "skill/default/custom/pre"},
                 post: %{enabled: true, signal_type: "skill/post"}
               },
               hook_defaults_error: {:raise, RuntimeError.exception("hook_defaults_unavailable")}
             ]
           ]},
        restart: :temporary
      })

    subscriber =
      start_supervised!(
        {SkillLifecycleSubscriber,
         [
           name: nil,
           bus_name: bus_name,
           registry: registry_name,
           hook_signal_types: [],
           fallback_to_default_hook_signal_types: false
         ]}
      )

    assert Process.alive?(subscriber)
    attach_handler!()

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.default.custom.pre",
            "/hooks/skill/default/custom/pre",
            "before-hook-default-raise-recovery"
          )
      end,
      6,
      60
    )

    _recovered_registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [
           name: registry_name,
           skills: [%{module: JidoSkill.Observability.TestSkills.InheritGlobalSignalTypeLifecycleHook}],
           hook_defaults: %{
             pre: %{enabled: true, signal_type: "skill/default/custom/pre"},
             post: %{enabled: true, signal_type: "skill/post"}
           }
         ]}
      )

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.default.custom.pre",
          "/hooks/skill/default/custom/pre",
          "after-hook-default-raise-recovery"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.default.custom.pre" and
            metadata.skill_name == "after-hook-default-raise-recovery"
      after
        80 ->
          false
      end
    end)
  end

  test "starts without inherited lifecycle subscriptions when initial hook defaults call raises exceptions and recovers on refresh" do
    bus_name = "bus_#{System.unique_integer([:positive])}"

    recovered_hook_defaults = %{
      pre: %{enabled: true, signal_type: "skill/default/custom/pre"},
      post: %{enabled: true, signal_type: "skill/post"}
    }

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [
           skills: [%{module: JidoSkill.Observability.TestSkills.InheritGlobalSignalTypeLifecycleHook}],
           hook_defaults: recovered_hook_defaults
         ]}
      )

    lookup_plan =
      start_supervised!(
        {Agent, fn ->
          %{count: 0, fail_on: MapSet.new([1])}
        end}
      )

    exception_registry = {:via, JidoSkill.Observability.LifecycleSubscriberNthLookupVia, {registry, lookup_plan}}

    subscriber =
      start_supervised!(
        {SkillLifecycleSubscriber,
         [
           name: nil,
           bus_name: bus_name,
           registry: exception_registry,
           hook_signal_types: [],
           fallback_to_default_hook_signal_types: false
         ]}
      )

    assert Process.alive?(subscriber)
    attach_handler!()

    subscriber_state = :sys.get_state(subscriber)
    assert subscriber_state.cached_hook_defaults == %{}

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.default.custom.pre",
            "/hooks/skill/default/custom/pre",
            "before-hook-default-call-exception-recovery"
          )
      end,
      6,
      60
    )

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.default.custom.pre",
          "/hooks/skill/default/custom/pre",
          "after-hook-default-call-exception-recovery"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.default.custom.pre" and
            metadata.skill_name == "after-hook-default-call-exception-recovery"
      after
        80 ->
          false
      end
    end)

    updated_state = :sys.get_state(subscriber)
    assert updated_state.cached_hook_defaults == recovered_hook_defaults
  end

  test "starts when registry is unavailable during init and recovers registry-derived subscriptions" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    registry_name = :"lifecycle_registry_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    subscriber =
      start_supervised!(
        {SkillLifecycleSubscriber,
         [
           name: nil,
           bus_name: bus_name,
           registry: registry_name,
           hook_signal_types: [],
           fallback_to_default_hook_signal_types: false
         ]}
      )

    assert Process.alive?(subscriber)
    attach_handler!()

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.custom.pre",
            "/hooks/skill/custom/pre",
            "before-registry-start"
          )
      end,
      6,
      60
    )

    _registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [
           name: registry_name,
           skills: [%{module: JidoSkill.Observability.TestSkills.ValidLifecycleHook}]
         ]}
      )

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.custom.pre",
          "/hooks/skill/custom/pre",
          "after-registry-start"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and metadata.skill_name == "after-registry-start"
      after
        80 ->
          false
      end
    end)
  end

  test "preserves lifecycle subscriptions when registry becomes unavailable during refresh" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(%{
        id: {:lifecycle_test_registry, System.unique_integer([:positive])},
        start:
          {LifecycleSubscriberTestRegistry, :start_link,
           [[skills: [%{module: JidoSkill.Observability.TestSkills.ValidLifecycleHook}]]]},
        restart: :temporary
      })

    subscriber =
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
          "before-registry-down"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and metadata.skill_name == "before-registry-down"
      after
        80 ->
          false
      end
    end)

    ref = Process.monitor(registry)
    :ok = GenServer.stop(registry, :shutdown)
    assert_receive {:DOWN, ^ref, :process, ^registry, :shutdown}, 1_000

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    assert Process.alive?(subscriber)

    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.custom.pre",
          "/hooks/skill/custom/pre",
          "after-registry-down"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and metadata.skill_name == "after-registry-down"
      after
        80 ->
          false
      end
    end)
  end

  test "preserves lifecycle subscriptions when list_skills returns invalid data during refresh" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [skills: [%{module: JidoSkill.Observability.TestSkills.ValidLifecycleHook}]]}
      )

    subscriber =
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
          "before-invalid-registry"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and metadata.skill_name == "before-invalid-registry"
      after
        80 ->
          false
      end
    end)

    assert :ok =
             LifecycleSubscriberTestRegistry.set_list_skills_error(
               registry,
               {:invalid_return, :skills_unavailable}
             )

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    assert Process.alive?(subscriber)

    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.custom.pre",
          "/hooks/skill/custom/pre",
          "after-invalid-registry"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and metadata.skill_name == "after-invalid-registry"
      after
        80 ->
          false
      end
    end)
  end

  test "preserves lifecycle subscriptions when list_skills raises during refresh" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(%{
        id: {:lifecycle_raise_refresh_registry, System.unique_integer([:positive])},
        start:
          {LifecycleSubscriberTestRegistry, :start_link,
           [
             [skills: [%{module: JidoSkill.Observability.TestSkills.ValidLifecycleHook}]]
           ]},
        restart: :temporary
      })

    subscriber =
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
          "before-raise-registry"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and metadata.skill_name == "before-raise-registry"
      after
        80 ->
          false
      end
    end)

    assert :ok =
             LifecycleSubscriberTestRegistry.set_list_skills_error(
               registry,
               {:raise, RuntimeError.exception("skills_unavailable")}
             )

    ref = Process.monitor(registry)

    assert :ok = publish_registry_update_signal(bus_name)
    assert_receive {:DOWN, ^ref, :process, ^registry, _reason}, 1_000

    Process.sleep(50)
    assert Process.alive?(subscriber)

    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.custom.pre",
          "/hooks/skill/custom/pre",
          "after-raise-registry"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and metadata.skill_name == "after-raise-registry"
      after
        80 ->
          false
      end
    end)
  end

  test "preserves lifecycle subscriptions when list_skills call raises call exceptions during refresh" do
    bus_name = "bus_#{System.unique_integer([:positive])}"

    cached_hook_defaults = %{
      pre: %{enabled: true, signal_type: "skill/default/custom/pre"},
      post: %{enabled: true, signal_type: "skill/post"}
    }

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [
           skills: [%{module: JidoSkill.Observability.TestSkills.InheritGlobalSignalTypeLifecycleHook}],
           hook_defaults: cached_hook_defaults
         ]}
      )

    subscriber =
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
          "skill.default.custom.pre",
          "/hooks/skill/default/custom/pre",
          "before-call-exception-refresh"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.default.custom.pre" and
            metadata.skill_name == "before-call-exception-refresh"
      after
        80 ->
          false
      end
    end)

    :sys.replace_state(subscriber, fn state ->
      %{state | registry: %{}}
    end)

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    assert Process.alive?(subscriber)

    updated_state = :sys.get_state(subscriber)
    assert updated_state.cached_hook_defaults == cached_hook_defaults

    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.default.custom.pre",
          "/hooks/skill/default/custom/pre",
          "after-call-exception-refresh"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.default.custom.pre" and
            metadata.skill_name == "after-call-exception-refresh"
      after
        80 ->
          false
      end
    end)
  end

  test "preserves inherited lifecycle subscriptions and cached hook defaults when list_skills call raises call exceptions during refresh" do
    bus_name = "bus_#{System.unique_integer([:positive])}"

    cached_hook_defaults = %{
      pre: %{enabled: true, signal_type: "skill/default/custom/pre"},
      post: %{enabled: true, signal_type: "skill/post"}
    }

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [
           skills: [%{module: JidoSkill.Observability.TestSkills.InheritGlobalSignalTypeLifecycleHook}],
           hook_defaults: cached_hook_defaults
         ]}
      )

    subscriber =
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
          "skill.default.custom.pre",
          "/hooks/skill/default/custom/pre",
          "before-call-exception-refresh"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.default.custom.pre" and
            metadata.skill_name == "before-call-exception-refresh"
      after
        80 ->
          false
      end
    end)

    assert :ok =
             LifecycleSubscriberTestRegistry.set_skills(registry, [
               %{module: JidoSkill.Observability.TestSkills.ExplicitLifecycleHook}
             ])

    lookup_plan =
      start_supervised!(
        {Agent, fn ->
          %{count: 0, fail_on: MapSet.new([2, 4])}
        end}
      )

    exception_registry =
      {:via, JidoSkill.Observability.LifecycleSubscriberNthLookupVia, {registry, lookup_plan}}

    :sys.replace_state(subscriber, fn state ->
      %{state | registry: exception_registry}
    end)

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    assert Process.alive?(subscriber)

    updated_state = :sys.get_state(subscriber)
    assert updated_state.cached_hook_defaults == cached_hook_defaults

    drain_telemetry_messages()

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.explicit.pre",
            "/hooks/skill/explicit/pre",
            "new-hook-after-call-exception-refresh"
          )
      end,
      6,
      60
    )

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.default.custom.pre",
          "/hooks/skill/default/custom/pre",
          "old-hook-after-call-exception-refresh"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.default.custom.pre" and
            metadata.skill_name == "old-hook-after-call-exception-refresh"
      after
        80 ->
          false
      end
    end)

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    assert Process.alive?(subscriber)

    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.default.custom.pre",
          "/hooks/skill/default/custom/pre",
          "old-hook-after-call-exception-registry-update"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.default.custom.pre" and
            metadata.skill_name == "old-hook-after-call-exception-registry-update"
      after
        80 ->
          false
      end
    end)
  end

  test "preserves lifecycle subscriptions when hook defaults raises during refresh" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(%{
        id: {:lifecycle_hook_raise_refresh_registry, System.unique_integer([:positive])},
        start:
          {LifecycleSubscriberTestRegistry, :start_link,
           [[skills: [%{module: JidoSkill.Observability.TestSkills.ValidLifecycleHook}]]]},
        restart: :temporary
      })

    subscriber =
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
          "before-raise-hook-defaults"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and
            metadata.skill_name == "before-raise-hook-defaults"
      after
        80 ->
          false
      end
    end)

    assert :ok =
             LifecycleSubscriberTestRegistry.set_hook_defaults_error(
               registry,
               {:raise, RuntimeError.exception("hook_defaults_unavailable")}
             )

    ref = Process.monitor(registry)

    assert :ok = publish_registry_update_signal(bus_name)
    assert_receive {:DOWN, ^ref, :process, ^registry, _reason}, 1_000

    Process.sleep(50)
    assert Process.alive?(subscriber)

    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.custom.pre",
          "/hooks/skill/custom/pre",
          "after-raise-hook-defaults"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.custom.pre" and
            metadata.skill_name == "after-raise-hook-defaults"
      after
        80 ->
          false
      end
    end)
  end

  test "refreshes lifecycle subscriptions while keeping cached hook defaults when hook defaults call raises exceptions" do
    bus_name = "bus_#{System.unique_integer([:positive])}"

    cached_hook_defaults = %{
      pre: %{enabled: true, signal_type: "skill/default/custom/pre"},
      post: %{enabled: true, signal_type: "skill/post"}
    }

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [
           skills: [%{module: JidoSkill.Observability.TestSkills.InheritGlobalSignalTypeLifecycleHook}],
           hook_defaults: cached_hook_defaults
         ]}
      )

    subscriber =
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
          "skill.default.custom.pre",
          "/hooks/skill/default/custom/pre",
          "before-call-exception-hook-defaults-refresh"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.default.custom.pre" and
            metadata.skill_name == "before-call-exception-hook-defaults-refresh"
      after
        80 ->
          false
      end
    end)

    assert :ok =
             LifecycleSubscriberTestRegistry.set_skills(registry, [
               %{module: JidoSkill.Observability.TestSkills.ExplicitLifecycleHook}
             ])

    lookup_plan =
      start_supervised!(
        {Agent, fn ->
          %{count: 0, fail_on: MapSet.new([1, 3])}
        end}
      )

    exception_registry =
      {:via, JidoSkill.Observability.LifecycleSubscriberNthLookupVia, {registry, lookup_plan}}

    :sys.replace_state(subscriber, fn state ->
      %{state | registry: exception_registry}
    end)

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    assert Process.alive?(subscriber)

    updated_state = :sys.get_state(subscriber)
    assert updated_state.cached_hook_defaults == cached_hook_defaults

    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.explicit.pre",
          "/hooks/skill/explicit/pre",
          "after-call-exception-hook-defaults-refresh"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.explicit.pre" and
            metadata.skill_name == "after-call-exception-hook-defaults-refresh"
      after
        80 ->
          false
      end
    end)

    drain_telemetry_messages()

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.default.custom.pre",
            "/hooks/skill/default/custom/pre",
            "old-hook-after-call-exception-hook-defaults-refresh"
          )
      end,
      6,
      60
    )

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    assert Process.alive?(subscriber)

    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.explicit.pre",
          "/hooks/skill/explicit/pre",
          "after-call-exception-hook-defaults-registry-update"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.explicit.pre" and
            metadata.skill_name == "after-call-exception-hook-defaults-registry-update"
      after
        80 ->
          false
      end
    end)
  end

  test "refreshes explicit hooks while preserving inherited disable when hook defaults refresh fails" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {LifecycleSubscriberTestRegistry,
         [
           skills: [%{module: JidoSkill.Observability.TestSkills.InheritedLifecycleHook}],
           hook_defaults: %{
             pre: %{enabled: false, signal_type: "skill/pre"},
             post: %{enabled: true, signal_type: "skill/post"}
           }
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
            "skill.inherit.pre",
            "/hooks/skill/inherit/pre",
            "inherit-before"
          )
      end,
      6,
      60
    )

    assert :ok =
             LifecycleSubscriberTestRegistry.set_skills(registry, [
               %{module: JidoSkill.Observability.TestSkills.InheritedLifecycleHook},
               %{module: JidoSkill.Observability.TestSkills.ExplicitLifecycleHook}
             ])

    assert :ok =
             LifecycleSubscriberTestRegistry.set_hook_defaults_error(
               registry,
               {:invalid_return, :hook_defaults_unavailable}
             )

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    drain_telemetry_messages()

    assert_eventually(fn ->
      :ok =
        publish_lifecycle_signal(
          bus_name,
          "skill.explicit.pre",
          "/hooks/skill/explicit/pre",
          "explicit-after"
        )

      receive do
        {:telemetry, @telemetry_event, %{count: 1}, metadata} ->
          metadata.type == "skill.explicit.pre" and metadata.skill_name == "explicit-after"
      after
        80 ->
          false
      end
    end)

    drain_telemetry_messages()

    assert_unobserved_over_time(
      fn ->
        :ok =
          publish_lifecycle_signal(
            bus_name,
            "skill.inherit.pre",
            "/hooks/skill/inherit/pre",
            "inherit-after"
          )
      end,
      6,
      60
    )
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

  defp publish_dispatch_signal(bus_name, type, value) do
    with {:ok, signal} <- Signal.new(type, %{"value" => value}, source: "/test/dispatch"),
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

  defp assert_permission_blocked_telemetry(skill_name, route, reason, tools) do
    assert_receive {:telemetry, @telemetry_event, %{count: 1}, metadata}, 1_000

    assert metadata.type == "skill.permission.blocked"
    assert metadata.source == "/permissions/skill/permission/blocked"
    assert metadata.skill_name == skill_name
    assert metadata.route == route
    assert metadata.reason == reason
    assert metadata.tools == tools
    assert is_binary(metadata.timestamp)
  end

  defp write_skill(root, dir_name, skill_name, route, opts \\ []) do
    skill_dir = Path.join([root, "skills", dir_name])
    File.mkdir_p!(skill_dir)

    pre_signal_type = Keyword.get(opts, :pre_signal_type)
    pre_enabled = Keyword.fetch(opts, :pre_enabled)
    allowed_tools = Keyword.get(opts, :allowed_tools)
    allowed_tools_line = if is_nil(allowed_tools), do: "", else: "allowed-tools: #{allowed_tools}\n"

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
    #{allowed_tools_line}
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

  defp write_settings(path, permissions, opts \\ []) do
    pre_enabled = Keyword.get(opts, :pre_enabled, false)
    post_enabled = Keyword.get(opts, :post_enabled, false)
    pre_signal_type = Keyword.get(opts, :pre_signal_type, "skill/pre")
    post_signal_type = Keyword.get(opts, :post_signal_type, "skill/post")
    signal_bus_name = Keyword.get(opts, :signal_bus_name, "jido_code_bus") |> to_string()
    pre_bus = Keyword.get(opts, :pre_bus, ":jido_code_bus")
    post_bus = Keyword.get(opts, :post_bus, ":jido_code_bus")

    settings = %{
      "version" => "2.0.0",
      "signal_bus" => %{"name" => signal_bus_name, "middleware" => []},
      "permissions" => permissions,
      "hooks" => %{
        "pre" => %{
          "enabled" => pre_enabled,
          "signal_type" => pre_signal_type,
          "bus" => pre_bus,
          "data_template" => %{}
        },
        "post" => %{
          "enabled" => post_enabled,
          "signal_type" => post_signal_type,
          "bus" => post_bus,
          "data_template" => %{}
        }
      }
    }

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(settings))
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
