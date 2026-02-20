defmodule JidoSkill.DispatcherTestActions.Notify do
  use Jido.Action,
    name: "dispatcher_notify",
    description: "Sends a message to a target process for dispatcher tests",
    schema: [value: [type: :string, required: false]]

  @notify_pid_key {__MODULE__, :notify_pid}

  @impl true
  def run(params, _context) do
    value = Map.get(params, :value) || Map.get(params, "value")
    notify_pid = :persistent_term.get(@notify_pid_key, nil)

    if is_pid(notify_pid), do: send(notify_pid, {:action_ran, value})
    {:ok, %{value: value}}
  end
end

defmodule JidoSkill.DispatcherTestSkills.ValidRoute do
  alias Jido.Instruction

  def skill_metadata do
    %{router: [{"demo/rollback", JidoSkill.DispatcherTestActions.Notify}]}
  end

  def handle_signal(signal, _opts) do
    Instruction.new(action: JidoSkill.DispatcherTestActions.Notify, params: signal.data)
  end

  def transform_result(result, _instruction, _opts), do: {:ok, result, []}
end

defmodule JidoSkill.DispatcherTestSkills.InvalidRoute do
  alias Jido.Instruction

  def skill_metadata do
    %{router: [{123, JidoSkill.DispatcherTestActions.Notify}]}
  end

  def handle_signal(signal, _opts) do
    Instruction.new(action: JidoSkill.DispatcherTestActions.Notify, params: signal.data)
  end

  def transform_result(result, _instruction, _opts), do: {:ok, result, []}
end

defmodule JidoSkill.DispatcherTestSkills.ValidRouteTwo do
  alias Jido.Instruction

  def skill_metadata do
    %{router: [{"demo/second", JidoSkill.DispatcherTestActions.Notify}]}
  end

  def handle_signal(signal, _opts) do
    Instruction.new(action: JidoSkill.DispatcherTestActions.Notify, params: signal.data)
  end

  def transform_result(result, _instruction, _opts), do: {:ok, result, []}
end

defmodule JidoSkill.DispatcherTestSkills.HookAwareRoute do
  alias Jido.Instruction
  alias JidoSkill.SkillRuntime.HookEmitter

  @route "demo/hook_one"
  @skill_name "hook-aware-one"

  def skill_metadata do
    %{router: [{@route, JidoSkill.DispatcherTestActions.Notify}]}
  end

  def handle_signal(signal, opts) do
    global_hooks = Keyword.get(opts, :global_hooks, %{})
    HookEmitter.emit_pre(@skill_name, @route, %{}, global_hooks)
    Instruction.new(action: JidoSkill.DispatcherTestActions.Notify, params: signal.data)
  end

  def transform_result(result, _instruction, opts) do
    global_hooks = Keyword.get(opts, :global_hooks, %{})
    HookEmitter.emit_post(@skill_name, @route, "ok", %{}, global_hooks)
    {:ok, result, []}
  end
end

defmodule JidoSkill.DispatcherTestSkills.HookAwareRouteTwo do
  alias Jido.Instruction
  alias JidoSkill.SkillRuntime.HookEmitter

  @route "demo/hook_two"
  @skill_name "hook-aware-two"

  def skill_metadata do
    %{router: [{@route, JidoSkill.DispatcherTestActions.Notify}]}
  end

  def handle_signal(signal, opts) do
    global_hooks = Keyword.get(opts, :global_hooks, %{})
    HookEmitter.emit_pre(@skill_name, @route, %{}, global_hooks)
    Instruction.new(action: JidoSkill.DispatcherTestActions.Notify, params: signal.data)
  end

  def transform_result(result, _instruction, opts) do
    global_hooks = Keyword.get(opts, :global_hooks, %{})
    HookEmitter.emit_post(@skill_name, @route, "ok", %{}, global_hooks)
    {:ok, result, []}
  end
end

defmodule JidoSkill.SkillRuntime.SignalDispatcherTestRegistry do
  use GenServer

  def start_link(opts) do
    state = %{
      skills: Keyword.get(opts, :skills, []),
      hook_defaults: Keyword.get(opts, :hook_defaults, %{}),
      hook_defaults_error: Keyword.get(opts, :hook_defaults_error),
      list_skills_error: Keyword.get(opts, :list_skills_error)
    }

    name = Keyword.get(opts, :name)

    if is_nil(name) do
      GenServer.start_link(__MODULE__, state)
    else
      GenServer.start_link(__MODULE__, state, name: name)
    end
  end

  def set_skills(server, skills), do: GenServer.call(server, {:set_skills, skills})
  def set_hook_defaults_error(server, value), do: GenServer.call(server, {:set_hook_defaults_error, value})
  def set_list_skills_error(server, value), do: GenServer.call(server, {:set_list_skills_error, value})

  @impl GenServer
  def init(state), do: {:ok, state}

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

defmodule JidoSkill.SkillRuntime.SignalDispatcherTest do
  use ExUnit.Case, async: false

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoSkill.SkillRuntime.SignalDispatcher
  alias JidoSkill.SkillRuntime.SignalDispatcherTestRegistry
  alias JidoSkill.SkillRuntime.SkillRegistry

  test "dispatches matching signals to skills and emits lifecycle hooks" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("dispatcher_exec")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    create_skill(local_root, "dispatcher-local", "demo/notify", bus_name)

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SkillRegistry,
         [
           name: nil,
           bus_name: bus_name,
           global_path: global_root,
           local_path: local_root,
           hook_defaults: hook_defaults(bus_name),
           permissions: default_permissions()
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.notify"]

    subscribe!(bus_name, "skill.pre")
    subscribe!(bus_name, "skill.post")

    {:ok, signal} =
      Signal.new(
        "demo.notify",
        %{"value" => "hello"},
        source: "/test/signal_dispatcher"
      )

    assert {:ok, _recorded} = Bus.publish(bus_name, [signal])

    assert_receive {:action_ran, "hello"}, 1_000

    assert_receive {:signal, pre_signal}, 1_000
    assert pre_signal.type == "skill.pre"
    assert pre_signal.data["skill_name"] == "dispatcher-local"
    assert pre_signal.data["route"] == "demo/notify"

    assert_receive {:signal, post_signal}, 1_000
    assert post_signal.type == "skill.post"
    assert post_signal.data["skill_name"] == "dispatcher-local"
    assert post_signal.data["route"] == "demo/notify"
    assert post_signal.data["status"] == "ok"
  end

  test "refreshes subscriptions when registry changes" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("dispatcher_refresh")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    create_skill(local_root, "dispatcher-one", "demo/one", bus_name)

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SkillRegistry,
         [
           name: nil,
           bus_name: bus_name,
           global_path: global_root,
           local_path: local_root,
           hook_defaults: hook_defaults(bus_name),
           permissions: default_permissions()
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.one"]

    {:ok, non_matching_signal} =
      Signal.new("demo.two", %{"value" => "before_reload"}, source: "/test/signal")

    assert {:ok, _recorded} = Bus.publish(bus_name, [non_matching_signal])
    refute_receive {:action_ran, "before_reload"}, 200

    create_skill(local_root, "dispatcher-two", "demo/two", bus_name)
    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      "demo.two" in SignalDispatcher.routes(dispatcher)
    end)

    {:ok, matching_signal} =
      Signal.new("demo.two", %{"value" => "after_reload"}, source: "/test/signal")

    assert {:ok, _recorded} = Bus.publish(bus_name, [matching_signal])
    assert_receive {:action_ran, "after_reload"}, 1_000
  end

  test "skips execution when skill permission status requires ask approval" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("dispatcher_permissions")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    create_skill(local_root, "dispatcher-ask", "demo/ask", bus_name, allowed_tools: "Bash(git:*)")

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SkillRegistry,
         [
           name: nil,
           bus_name: bus_name,
           global_path: global_root,
           local_path: local_root,
           hook_defaults: hook_defaults(bus_name),
           permissions: %{"allow" => [], "deny" => [], "ask" => ["Bash(git:*)"]}
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.ask"]
    subscribe!(bus_name, "skill.permission.blocked")

    {:ok, signal} = Signal.new("demo.ask", %{"value" => "blocked"}, source: "/test/permissions")
    assert {:ok, _recorded} = Bus.publish(bus_name, [signal])

    refute_receive {:action_ran, "blocked"}, 300
    assert_permission_blocked_signal("dispatcher-ask", "demo/ask", "ask", ["Bash(git:*)"])
  end

  test "skips execution and emits blocked signal when skill permissions are denied" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("dispatcher_denied")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    create_skill(
      local_root,
      "dispatcher-denied",
      "demo/denied",
      bus_name,
      allowed_tools: "Bash(rm:*)"
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
           hook_defaults: hook_defaults(bus_name),
           permissions: %{"allow" => [], "deny" => ["Bash(rm:*)"], "ask" => []}
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.denied"]
    subscribe!(bus_name, "skill.permission.blocked")

    {:ok, signal} =
      Signal.new("demo.denied", %{"value" => "blocked"}, source: "/test/permissions")

    assert {:ok, _recorded} = Bus.publish(bus_name, [signal])

    refute_receive {:action_ran, "blocked"}, 300
    assert_permission_blocked_signal("dispatcher-denied", "demo/denied", "denied", ["Bash(rm:*)"])
  end

  test "preserves existing route subscriptions when refresh fails adding new routes" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry, [skills: [valid_dispatcher_skill_entry()]]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "before_failure")
    assert_receive {:action_ran, "before_failure"}, 1_000

    assert :ok =
             SignalDispatcherTestRegistry.set_skills(registry, [invalid_dispatcher_skill_entry()])

    assert {:error, {:route_subscribe_failed, 123, _reason}} =
             SignalDispatcher.refresh(dispatcher)

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "after_failure")
    assert_receive {:action_ran, "after_failure"}, 1_000
  end

  test "preserves existing routes when registry becomes unavailable during refresh" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(%{
        id: {:dispatcher_test_registry, System.unique_integer([:positive])},
        start:
          {SignalDispatcherTestRegistry, :start_link, [[skills: [valid_dispatcher_skill_entry()]]]},
        restart: :temporary
      })

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "before_registry_down")
    assert_receive {:action_ran, "before_registry_down"}, 1_000

    ref = Process.monitor(registry)
    :ok = GenServer.stop(registry, :shutdown)
    assert_receive {:DOWN, ^ref, :process, ^registry, :shutdown}, 1_000

    assert {:error, {:list_skills_failed, _reason}} = SignalDispatcher.refresh(dispatcher)

    {:ok, registry_update} =
      Signal.new("skill.registry.updated", %{}, source: "/test/signal_dispatcher")

    assert {:ok, _recorded} = Bus.publish(bus_name, [registry_update])

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "after_registry_down")
    assert_receive {:action_ran, "after_registry_down"}, 1_000
  end

  test "starts with empty routes when initial list_skills read fails and recovers on refresh" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           skills: [valid_dispatcher_skill_entry()],
           list_skills_error: {:invalid_return, :skills_unavailable}
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == []

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "before_recovery")
    refute_receive {:action_ran, "before_recovery"}, 200

    assert :ok = SignalDispatcherTestRegistry.set_list_skills_error(registry, nil)
    assert :ok = SignalDispatcher.refresh(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "after_recovery")
    assert_receive {:action_ran, "after_recovery"}, 1_000
  end

  test "starts with empty routes when initial list_skills raises and recovers on refresh" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    registry_name = :"dispatcher_raise_registry_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    _failing_registry =
      start_supervised!(
        %{
          id: {:dispatcher_raise_registry, System.unique_integer([:positive])},
          start:
            {SignalDispatcherTestRegistry, :start_link,
             [
               [
                 name: registry_name,
                 skills: [valid_dispatcher_skill_entry()],
                 list_skills_error: {:raise, RuntimeError.exception("skills_unavailable")}
               ]
             ]},
          restart: :temporary
        }
      )

    dispatcher =
      start_supervised!(
        {SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry_name]}
      )

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == []

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "before_raise_recovery")
    refute_receive {:action_ran, "before_raise_recovery"}, 200

    _recovered_registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [name: registry_name, skills: [valid_dispatcher_skill_entry()]]}
      )

    assert :ok = publish_registry_update_signal(bus_name)

    assert_eventually(fn ->
      SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    end)

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "after_raise_recovery")
    assert_receive {:action_ran, "after_raise_recovery"}, 1_000
  end

  test "starts when registry is unavailable during init and recovers after registry starts" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    registry_name = :"dispatcher_registry_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    dispatcher =
      start_supervised!(
        {SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry_name]}
      )

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == []

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "before_registry_start")
    refute_receive {:action_ran, "before_registry_start"}, 200

    _registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           name: registry_name,
           skills: [valid_dispatcher_skill_entry()],
           hook_defaults: hook_defaults(bus_name)
         ]}
      )

    assert :ok = publish_registry_update_signal(bus_name)

    assert_eventually(fn ->
      SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    end)

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "after_registry_start")
    assert_receive {:action_ran, "after_registry_start"}, 1_000
  end

  test "starts with routes when initial hook defaults read fails and recovers hook emission on refresh" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    cached_hook_defaults = hook_defaults(bus_name)

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           skills: [hook_aware_dispatcher_skill_entry()],
           hook_defaults: cached_hook_defaults,
           hook_defaults_error: {:invalid_return, :hook_defaults_unavailable}
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_one"]

    subscribe!(bus_name, "skill.pre")
    subscribe!(bus_name, "skill.post")

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "before_recovery")
    assert_receive {:action_ran, "before_recovery"}, 1_000
    refute_receive {:signal, _hook_signal_before_recovery}, 200

    assert :ok = SignalDispatcherTestRegistry.set_hook_defaults_error(registry, nil)
    assert :ok = SignalDispatcher.refresh(dispatcher)

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "after_recovery")
    assert_receive {:action_ran, "after_recovery"}, 1_000
    assert_receive {:signal, pre_signal}, 1_000
    assert pre_signal.type == "skill.pre"
    assert pre_signal.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_signal}, 1_000
    assert post_signal.type == "skill.post"
    assert post_signal.data["route"] == "demo/hook_one"

    dispatcher_state = :sys.get_state(dispatcher)
    assert dispatcher_state.hook_defaults == cached_hook_defaults
  end

  test "starts with routes when initial hook defaults raises and recovers hook emission after registry restart" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    registry_name = :"dispatcher_hook_raise_registry_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    cached_hook_defaults = hook_defaults(bus_name)

    _failing_registry =
      start_supervised!(%{
        id: {:dispatcher_hook_raise_registry, System.unique_integer([:positive])},
        start:
          {SignalDispatcherTestRegistry, :start_link,
           [
             [
               name: registry_name,
               skills: [hook_aware_dispatcher_skill_entry()],
               hook_defaults: cached_hook_defaults,
               hook_defaults_error: {:raise, RuntimeError.exception("hook_defaults_unavailable")}
             ]
           ]},
        restart: :temporary
      })

    dispatcher =
      start_supervised!(
        {SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry_name]}
      )

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_one"]

    subscribe!(bus_name, "skill.pre")
    subscribe!(bus_name, "skill.post")

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "before_raise_recovery")
    assert_receive {:action_ran, "before_raise_recovery"}, 1_000
    refute_receive {:signal, _hook_signal_before_recovery}, 200

    _recovered_registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           name: registry_name,
           skills: [hook_aware_dispatcher_skill_entry()],
           hook_defaults: cached_hook_defaults
         ]}
      )

    assert :ok = publish_registry_update_signal(bus_name)

    assert_eventually(fn ->
      SignalDispatcher.routes(dispatcher) == ["demo.hook_one"]
    end)

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "after_raise_recovery")
    assert_receive {:action_ran, "after_raise_recovery"}, 1_000
    assert_receive {:signal, pre_signal}, 1_000
    assert pre_signal.type == "skill.pre"
    assert pre_signal.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_signal}, 1_000
    assert post_signal.type == "skill.post"
    assert post_signal.data["route"] == "demo/hook_one"

    dispatcher_state = :sys.get_state(dispatcher)
    assert dispatcher_state.hook_defaults == cached_hook_defaults
  end

  test "starts with empty routes when initial route subscription fails and recovers after registry update" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry, [skills: [invalid_dispatcher_skill_entry()]]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == []

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "before_recovery")
    refute_receive {:action_ran, "before_recovery"}, 200

    assert :ok = SignalDispatcherTestRegistry.set_skills(registry, [valid_dispatcher_skill_entry()])
    assert :ok = publish_registry_update_signal(bus_name)

    assert_eventually(fn ->
      SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    end)

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "after_recovery")
    assert_receive {:action_ran, "after_recovery"}, 1_000
  end

  test "preserves existing routes when list_skills returns invalid data during refresh" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry, [skills: [valid_dispatcher_skill_entry()]]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "before_invalid_registry")
    assert_receive {:action_ran, "before_invalid_registry"}, 1_000

    assert :ok =
             SignalDispatcherTestRegistry.set_list_skills_error(
               registry,
               {:invalid_return, :skills_unavailable}
             )

    assert {:error, {:list_skills_failed, {:invalid_result, :skills_unavailable}}} =
             SignalDispatcher.refresh(dispatcher)

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "after_invalid_registry")
    assert_receive {:action_ran, "after_invalid_registry"}, 1_000
  end

  test "refreshes routes while keeping cached hook defaults when hook defaults fail" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    cached_hook_defaults = hook_defaults(bus_name)

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           skills: [valid_dispatcher_skill_entry()],
           hook_defaults: cached_hook_defaults
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "before_hook_failure")
    assert_receive {:action_ran, "before_hook_failure"}, 1_000

    assert :ok =
             SignalDispatcherTestRegistry.set_skills(registry, [valid_dispatcher_skill_entry_two()])

    assert :ok =
             SignalDispatcherTestRegistry.set_hook_defaults_error(
               registry,
               {:exit, :hook_defaults_unavailable}
             )

    assert :ok = SignalDispatcher.refresh(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.second"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.second", "after_hook_failure")
    assert_receive {:action_ran, "after_hook_failure"}, 1_000

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "old_route")
    refute_receive {:action_ran, "old_route"}, 200

    dispatcher_state = :sys.get_state(dispatcher)
    assert dispatcher_state.hook_defaults == cached_hook_defaults
  end

  test "refreshes routes while preserving cached hook defaults on invalid hook defaults returns" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    cached_hook_defaults = hook_defaults(bus_name)

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           skills: [hook_aware_dispatcher_skill_entry()],
           hook_defaults: cached_hook_defaults
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_one"]

    subscribe!(bus_name, "skill.pre")
    subscribe!(bus_name, "skill.post")

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "before_invalid_hook_defaults")
    assert_receive {:action_ran, "before_invalid_hook_defaults"}, 1_000
    assert_receive {:signal, pre_signal}, 1_000
    assert pre_signal.type == "skill.pre"
    assert pre_signal.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_signal}, 1_000
    assert post_signal.type == "skill.post"
    assert post_signal.data["route"] == "demo/hook_one"

    assert :ok =
             SignalDispatcherTestRegistry.set_skills(registry, [hook_aware_dispatcher_skill_entry_two()])

    assert :ok =
             SignalDispatcherTestRegistry.set_hook_defaults_error(
               registry,
               {:invalid_return, :hook_defaults_unavailable}
             )

    assert :ok = SignalDispatcher.refresh(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_two"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_two", "after_invalid_hook_defaults")
    assert_receive {:action_ran, "after_invalid_hook_defaults"}, 1_000
    assert_receive {:signal, pre_signal_after}, 1_000
    assert pre_signal_after.type == "skill.pre"
    assert pre_signal_after.data["route"] == "demo/hook_two"
    assert_receive {:signal, post_signal_after}, 1_000
    assert post_signal_after.type == "skill.post"
    assert post_signal_after.data["route"] == "demo/hook_two"

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "old_route")
    refute_receive {:action_ran, "old_route"}, 200

    dispatcher_state = :sys.get_state(dispatcher)
    assert dispatcher_state.hook_defaults == cached_hook_defaults
  end

  test "uses cached global hook defaults when registry is unavailable" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("dispatcher_cached_hooks")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    create_skill(local_root, "dispatcher-cached-hooks", "demo/cached_hooks", bus_name,
      include_hooks: false
    )

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(%{
        id: {:dispatcher_skill_registry, System.unique_integer([:positive])},
        start:
          {SkillRegistry, :start_link,
           [
             [
               name: nil,
               bus_name: bus_name,
               global_path: global_root,
               local_path: local_root,
               hook_defaults: hook_defaults(bus_name),
               permissions: default_permissions()
             ]
           ]},
        restart: :temporary
      })

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.cached_hooks"]

    subscribe!(bus_name, "skill.pre")
    subscribe!(bus_name, "skill.post")

    assert :ok = publish_dispatch_signal(bus_name, "demo.cached_hooks", "before_registry_down")
    assert_receive {:action_ran, "before_registry_down"}, 1_000
    assert_receive {:signal, pre_signal}, 1_000
    assert pre_signal.type == "skill.pre"
    assert pre_signal.data["route"] == "demo/cached_hooks"
    assert_receive {:signal, post_signal}, 1_000
    assert post_signal.type == "skill.post"
    assert post_signal.data["route"] == "demo/cached_hooks"

    ref = Process.monitor(registry)
    :ok = GenServer.stop(registry, :shutdown)
    assert_receive {:DOWN, ^ref, :process, ^registry, :shutdown}, 1_000

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.cached_hooks"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.cached_hooks", "after_registry_down")
    assert_receive {:action_ran, "after_registry_down"}, 1_000
    assert_receive {:signal, pre_signal_after}, 1_000
    assert pre_signal_after.type == "skill.pre"
    assert pre_signal_after.data["route"] == "demo/cached_hooks"
    assert_receive {:signal, post_signal_after}, 1_000
    assert post_signal_after.type == "skill.post"
    assert post_signal_after.data["route"] == "demo/cached_hooks"
  end

  defp create_skill(root, skill_name, route, bus_name, opts \\ []) do
    skill_dir = Path.join([root, "skills", skill_name])
    File.mkdir_p!(skill_dir)
    allowed_tools = Keyword.get(opts, :allowed_tools)
    include_hooks = Keyword.get(opts, :include_hooks, true)

    hooks_block =
      if include_hooks do
        [
          "  hooks:",
          "    pre:",
          "      enabled: true",
          "      signal_type: \"skill/pre\"",
          "      bus: \"#{bus_name}\"",
          "      data:",
          "        source: \"#{skill_name}\"",
          "    post:",
          "      enabled: true",
          "      signal_type: \"skill/post\"",
          "      bus: \"#{bus_name}\"",
          "      data:",
          "        source: \"#{skill_name}\""
        ]
        |> Enum.join("\n")
      else
        ""
      end

    content = """
    ---
    name: #{skill_name}
    description: Dispatcher test skill #{skill_name}
    version: 1.0.0
    #{allowed_tools_line(allowed_tools)}
    jido:
      actions:
        - JidoSkill.DispatcherTestActions.Notify
      router:
        - "#{route}": Notify
    #{hooks_block}
    ---

    # #{skill_name}
    """

    File.write!(Path.join(skill_dir, "SKILL.md"), content)
  end

  defp subscribe!(bus_name, path) do
    assert {:ok, _subscription_id} =
             Bus.subscribe(bus_name, path,
               dispatch: {:pid, target: self(), delivery_mode: :async}
             )
  end

  defp hook_defaults(bus_name) do
    %{
      pre: %{enabled: true, signal_type: "skill/pre", bus: bus_name, data: %{}},
      post: %{enabled: true, signal_type: "skill/post", bus: bus_name, data: %{}}
    }
  end

  defp default_permissions do
    %{"allow" => [], "deny" => [], "ask" => []}
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

  defp set_notify_pid! do
    :persistent_term.put({JidoSkill.DispatcherTestActions.Notify, :notify_pid}, self())

    on_exit(fn ->
      :persistent_term.erase({JidoSkill.DispatcherTestActions.Notify, :notify_pid})
    end)
  end

  defp allowed_tools_line(nil), do: ""
  defp allowed_tools_line(value), do: "allowed-tools: #{value}"

  defp publish_dispatch_signal(bus_name, type, value) do
    with {:ok, signal} <- Signal.new(type, %{"value" => value}, source: "/test/signal"),
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

  defp valid_dispatcher_skill_entry do
    %{
      name: "valid-route-skill",
      scope: :local,
      module: JidoSkill.DispatcherTestSkills.ValidRoute,
      permission_status: :allowed
    }
  end

  defp invalid_dispatcher_skill_entry do
    %{
      name: "invalid-route-skill",
      scope: :local,
      module: JidoSkill.DispatcherTestSkills.InvalidRoute,
      permission_status: :allowed
    }
  end

  defp valid_dispatcher_skill_entry_two do
    %{
      name: "valid-route-skill-two",
      scope: :local,
      module: JidoSkill.DispatcherTestSkills.ValidRouteTwo,
      permission_status: :allowed
    }
  end

  defp hook_aware_dispatcher_skill_entry do
    %{
      name: "hook-aware-route-skill",
      scope: :local,
      module: JidoSkill.DispatcherTestSkills.HookAwareRoute,
      permission_status: :allowed
    }
  end

  defp hook_aware_dispatcher_skill_entry_two do
    %{
      name: "hook-aware-route-skill-two",
      scope: :local,
      module: JidoSkill.DispatcherTestSkills.HookAwareRouteTwo,
      permission_status: :allowed
    }
  end

  defp assert_permission_blocked_signal(skill_name, route, reason, tools) do
    assert_receive {:signal, blocked_signal}, 1_000

    assert blocked_signal.type == "skill.permission.blocked"
    assert blocked_signal.source == "/permissions/skill/permission/blocked"
    assert blocked_signal.data["skill_name"] == skill_name
    assert blocked_signal.data["route"] == route
    assert blocked_signal.data["reason"] == reason
    assert blocked_signal.data["tools"] == tools
    assert is_binary(blocked_signal.data["timestamp"])
  end
end
