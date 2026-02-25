defmodule Jido.Code.Skill.DispatcherTestActions.Notify do
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

defmodule Jido.Code.Skill.DispatcherTestSkills.ValidRoute do
  alias Jido.Instruction

  def skill_metadata do
    %{router: [{"demo/rollback", Jido.Code.Skill.DispatcherTestActions.Notify}]}
  end

  def handle_signal(signal, _opts) do
    Instruction.new(action: Jido.Code.Skill.DispatcherTestActions.Notify, params: signal.data)
  end

  def transform_result(result, _instruction, _opts), do: {:ok, result, []}
end

defmodule Jido.Code.Skill.DispatcherTestSkills.InvalidRoute do
  alias Jido.Instruction

  def skill_metadata do
    %{router: [{123, Jido.Code.Skill.DispatcherTestActions.Notify}]}
  end

  def handle_signal(signal, _opts) do
    Instruction.new(action: Jido.Code.Skill.DispatcherTestActions.Notify, params: signal.data)
  end

  def transform_result(result, _instruction, _opts), do: {:ok, result, []}
end

defmodule Jido.Code.Skill.DispatcherTestSkills.ValidRouteTwo do
  alias Jido.Instruction

  def skill_metadata do
    %{router: [{"demo/second", Jido.Code.Skill.DispatcherTestActions.Notify}]}
  end

  def handle_signal(signal, _opts) do
    Instruction.new(action: Jido.Code.Skill.DispatcherTestActions.Notify, params: signal.data)
  end

  def transform_result(result, _instruction, _opts), do: {:ok, result, []}
end

defmodule Jido.Code.Skill.DispatcherTestSkills.HookAwareRoute do
  alias Jido.Code.Skill.SkillRuntime.HookEmitter
  alias Jido.Instruction

  @route "demo/hook_one"
  @skill_name "hook-aware-one"

  def skill_metadata do
    %{router: [{@route, Jido.Code.Skill.DispatcherTestActions.Notify}]}
  end

  def handle_signal(signal, opts) do
    global_hooks = Keyword.get(opts, :global_hooks, %{})
    HookEmitter.emit_pre(@skill_name, @route, %{}, global_hooks)
    Instruction.new(action: Jido.Code.Skill.DispatcherTestActions.Notify, params: signal.data)
  end

  def transform_result(result, _instruction, opts) do
    global_hooks = Keyword.get(opts, :global_hooks, %{})
    HookEmitter.emit_post(@skill_name, @route, "ok", %{}, global_hooks)
    {:ok, result, []}
  end
end

defmodule Jido.Code.Skill.DispatcherTestSkills.HookAwareRouteTwo do
  alias Jido.Code.Skill.SkillRuntime.HookEmitter
  alias Jido.Instruction

  @route "demo/hook_two"
  @skill_name "hook-aware-two"

  def skill_metadata do
    %{router: [{@route, Jido.Code.Skill.DispatcherTestActions.Notify}]}
  end

  def handle_signal(signal, opts) do
    global_hooks = Keyword.get(opts, :global_hooks, %{})
    HookEmitter.emit_pre(@skill_name, @route, %{}, global_hooks)
    Instruction.new(action: Jido.Code.Skill.DispatcherTestActions.Notify, params: signal.data)
  end

  def transform_result(result, _instruction, opts) do
    global_hooks = Keyword.get(opts, :global_hooks, %{})
    HookEmitter.emit_post(@skill_name, @route, "ok", %{}, global_hooks)
    {:ok, result, []}
  end
end

defmodule Jido.Code.Skill.SkillRuntime.SignalDispatcherTestRegistry do
  use GenServer

  def start_link(opts) do
    state = %{
      skills: Keyword.get(opts, :skills, []),
      hook_defaults: Keyword.get(opts, :hook_defaults, %{}),
      hook_defaults_error: Keyword.get(opts, :hook_defaults_error),
      list_skills_error: Keyword.get(opts, :list_skills_error),
      bus_name: Keyword.get(opts, :bus_name),
      bus_name_error: Keyword.get(opts, :bus_name_error)
    }

    name = Keyword.get(opts, :name)

    if is_nil(name) do
      GenServer.start_link(__MODULE__, state)
    else
      GenServer.start_link(__MODULE__, state, name: name)
    end
  end

  def set_skills(server, skills), do: GenServer.call(server, {:set_skills, skills})

  def set_bus_name(server, bus_name),
    do: GenServer.call(server, {:set_bus_name, bus_name})

  def set_bus_name_error(server, value),
    do: GenServer.call(server, {:set_bus_name_error, value})

  def set_hook_defaults_error(server, value),
    do: GenServer.call(server, {:set_hook_defaults_error, value})

  def set_list_skills_error(server, value),
    do: GenServer.call(server, {:set_list_skills_error, value})

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call(:bus_name, _from, state) do
    case state.bus_name_error do
      nil ->
        {:reply, state.bus_name, state}

      {:invalid_return, value} ->
        {:reply, value, state}

      {:exit, reason} ->
        exit(reason)

      {:raise, error} ->
        raise error
    end
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
  def handle_call({:set_bus_name, bus_name}, _from, state) do
    {:reply, :ok, %{state | bus_name: bus_name}}
  end

  @impl GenServer
  def handle_call({:set_bus_name_error, value}, _from, state) do
    {:reply, :ok, %{state | bus_name_error: value}}
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

defmodule Jido.Code.Skill.SkillRuntime.SignalDispatcherNthLookupVia do
  def whereis_name({registry, lookup_plan}) do
    {lookup_index, fail_lookup?, fail_mode} =
      Agent.get_and_update(lookup_plan, fn %{count: count, fail_on: fail_on} = state ->
        next = count + 1
        mode = Map.get(state, :fail_mode, :raise)
        {{next, MapSet.member?(fail_on, next), mode}, %{state | count: next}}
      end)

    if fail_lookup? do
      case fail_mode do
        :raise ->
          raise ArgumentError, "simulated registry lookup failure at call #{lookup_index}"

        :exit ->
          exit(:simulated_registry_lookup_exit)

        {:exit, reason} ->
          exit(reason)
      end
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

defmodule Jido.Code.Skill.SkillRuntime.SignalDispatcherTest do
  use ExUnit.Case, async: false

  alias Jido.Code.Skill.SkillRuntime.SignalDispatcher
  alias Jido.Code.Skill.SkillRuntime.SignalDispatcherTestRegistry
  alias Jido.Code.Skill.SkillRuntime.SkillRegistry
  alias Jido.Signal
  alias Jido.Signal.Bus

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

  test "updates permission decisions after registry reload refreshes settings permissions" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("dispatcher_permission_reload")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_settings_path = Path.join(local_root, "settings.json")

    create_skill(
      local_root,
      "dispatcher-ask-reload",
      "demo/ask_reload",
      bus_name,
      allowed_tools: "Bash(git:*)"
    )

    write_settings(local_settings_path, %{"allow" => [], "deny" => [], "ask" => []},
      signal_bus_name: bus_name
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
           hook_defaults: hook_defaults(bus_name),
           permissions: default_permissions()
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.ask_reload"]
    subscribe!(bus_name, "skill.permission.blocked")

    assert :ok = publish_dispatch_signal(bus_name, "demo.ask_reload", "before_reload")
    assert_receive {:action_ran, "before_reload"}, 1_000
    refute_receive {:signal, _blocked_before_reload}, 200

    write_settings(
      local_settings_path,
      %{
        "allow" => [],
        "deny" => [],
        "ask" => ["Bash(git:*)"]
      },
      signal_bus_name: bus_name
    )

    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      case :sys.get_state(dispatcher).route_handlers do
        %{"demo.ask_reload" => [handler | _]} ->
          handler.permission_status == {:ask, ["Bash(git:*)"]}

        _ ->
          false
      end
    end)

    assert :ok = publish_dispatch_signal(bus_name, "demo.ask_reload", "after_reload")
    refute_receive {:action_ran, "after_reload"}, 300

    assert_permission_blocked_signal(
      "dispatcher-ask-reload",
      "demo/ask_reload",
      "ask",
      ["Bash(git:*)"]
    )
  end

  test "preserves permission decisions when registry settings reload fails" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("dispatcher_permission_reload_invalid")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_settings_path = Path.join(local_root, "settings.json")

    create_skill(
      local_root,
      "dispatcher-ask-invalid-settings",
      "demo/ask_invalid",
      bus_name,
      allowed_tools: "Bash(git:*)"
    )

    write_settings(local_settings_path, %{"allow" => [], "deny" => [], "ask" => []},
      signal_bus_name: bus_name
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
           hook_defaults: hook_defaults(bus_name),
           permissions: %{"allow" => [], "deny" => [], "ask" => ["Bash(git:*)"]}
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.ask_invalid"]
    subscribe!(bus_name, "skill.permission.blocked")

    assert :ok = publish_dispatch_signal(bus_name, "demo.ask_invalid", "before_reload")
    refute_receive {:action_ran, "before_reload"}, 300

    assert_permission_blocked_signal(
      "dispatcher-ask-invalid-settings",
      "demo/ask_invalid",
      "ask",
      ["Bash(git:*)"]
    )

    File.write!(local_settings_path, "{invalid")
    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      case :sys.get_state(dispatcher).route_handlers do
        %{"demo.ask_invalid" => [handler | _]} ->
          handler.permission_status == {:ask, ["Bash(git:*)"]}

        _ ->
          false
      end
    end)

    assert :ok = publish_dispatch_signal(bus_name, "demo.ask_invalid", "after_reload")
    refute_receive {:action_ran, "after_reload"}, 300

    assert_permission_blocked_signal(
      "dispatcher-ask-invalid-settings",
      "demo/ask_invalid",
      "ask",
      ["Bash(git:*)"]
    )
  end

  test "updates inherited hook signal types after registry reload refreshes settings hook defaults" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("dispatcher_hook_defaults_reload")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_settings_path = Path.join(local_root, "settings.json")

    create_skill(
      local_root,
      "dispatcher-hook-defaults-reload",
      "demo/hook_defaults_reload",
      bus_name,
      include_hooks: false
    )

    write_settings(local_settings_path, default_permissions(),
      pre_signal_type: "skill/pre/reloaded",
      post_signal_type: "skill/post/reloaded",
      signal_bus_name: bus_name,
      pre_bus: bus_name,
      post_bus: bus_name
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
           hook_defaults: hook_defaults(bus_name),
           permissions: default_permissions()
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_defaults_reload"]

    subscribe!(bus_name, "skill.pre")
    subscribe!(bus_name, "skill.post")
    subscribe!(bus_name, "skill.pre.reloaded")
    subscribe!(bus_name, "skill.post.reloaded")

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_defaults_reload", "before_reload")
    assert_receive {:action_ran, "before_reload"}, 1_000
    assert_receive {:signal, pre_before_reload}, 1_000
    assert pre_before_reload.type == "skill.pre"
    assert pre_before_reload.data["route"] == "demo/hook_defaults_reload"
    assert_receive {:signal, post_before_reload}, 1_000
    assert post_before_reload.type == "skill.post"
    assert post_before_reload.data["route"] == "demo/hook_defaults_reload"

    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      hook_defaults = :sys.get_state(dispatcher).hook_defaults

      get_in(hook_defaults, [:pre, :signal_type]) == "skill/pre/reloaded" and
        get_in(hook_defaults, [:post, :signal_type]) == "skill/post/reloaded"
    end)

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_defaults_reload", "after_reload")
    assert_receive {:action_ran, "after_reload"}, 1_000
    assert_receive {:signal, pre_after_reload}, 1_000
    assert pre_after_reload.type == "skill.pre.reloaded"
    assert pre_after_reload.data["route"] == "demo/hook_defaults_reload"
    assert_receive {:signal, post_after_reload}, 1_000
    assert post_after_reload.type == "skill.post.reloaded"
    assert post_after_reload.data["route"] == "demo/hook_defaults_reload"
  end

  test "preserves cached inherited hook signal types when registry settings reload fails" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("dispatcher_hook_defaults_reload_invalid")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_settings_path = Path.join(local_root, "settings.json")

    create_skill(
      local_root,
      "dispatcher-hook-defaults-invalid-settings",
      "demo/hook_defaults_invalid",
      bus_name,
      include_hooks: false
    )

    write_settings(local_settings_path, default_permissions(),
      pre_signal_type: "skill/pre/reloaded",
      post_signal_type: "skill/post/reloaded",
      signal_bus_name: bus_name,
      pre_bus: bus_name,
      post_bus: bus_name
    )

    cached_hook_defaults = %{
      pre: %{enabled: true, signal_type: "skill/pre/cached", bus: bus_name, data: %{}},
      post: %{enabled: true, signal_type: "skill/post/cached", bus: bus_name, data: %{}}
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
           permissions: default_permissions()
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_defaults_invalid"]

    subscribe!(bus_name, "skill.pre.cached")
    subscribe!(bus_name, "skill.post.cached")
    subscribe!(bus_name, "skill.pre.reloaded")
    subscribe!(bus_name, "skill.post.reloaded")

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_defaults_invalid", "before_reload")
    assert_receive {:action_ran, "before_reload"}, 1_000
    assert_receive {:signal, pre_before_reload}, 1_000
    assert pre_before_reload.type == "skill.pre.cached"
    assert pre_before_reload.data["route"] == "demo/hook_defaults_invalid"
    assert_receive {:signal, post_before_reload}, 1_000
    assert post_before_reload.type == "skill.post.cached"
    assert post_before_reload.data["route"] == "demo/hook_defaults_invalid"

    File.write!(local_settings_path, "{invalid")
    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      hook_defaults = :sys.get_state(dispatcher).hook_defaults
      hook_defaults == cached_hook_defaults
    end)

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_defaults_invalid", "after_reload")
    assert_receive {:action_ran, "after_reload"}, 1_000
    assert_receive {:signal, pre_after_reload}, 1_000
    assert pre_after_reload.type == "skill.pre.cached"
    assert pre_after_reload.data["route"] == "demo/hook_defaults_invalid"
    assert_receive {:signal, post_after_reload}, 1_000
    assert post_after_reload.type == "skill.post.cached"
    assert post_after_reload.data["route"] == "demo/hook_defaults_invalid"
  end

  test "migrates route dispatch to refreshed signal bus after registry settings reload" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("dispatcher_signal_bus_reload")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_settings_path = Path.join(local_root, "settings.json")

    create_skill(
      local_root,
      "dispatcher-signal-bus-reload",
      "demo/signal_bus_reload",
      old_bus_name,
      include_hooks: false
    )

    write_settings(local_settings_path, default_permissions(),
      signal_bus_name: reloaded_bus_name,
      pre_bus: reloaded_bus_name,
      post_bus: reloaded_bus_name
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
           hook_defaults: hook_defaults(old_bus_name),
           permissions: default_permissions()
         ]}
      )

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: registry]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.signal_bus_reload"]
    assert :sys.get_state(dispatcher).bus_name == old_bus_name

    assert :ok = publish_dispatch_signal(old_bus_name, "demo.signal_bus_reload", "before_reload")
    assert_receive {:action_ran, "before_reload"}, 1_000

    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == reloaded_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.signal_bus_reload")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.signal_bus_reload",
               "after_reload_old_bus"
             )

    refute_receive {:action_ran, "after_reload_old_bus"}, 300

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.signal_bus_reload",
               "after_reload_new_bus"
             )

    assert_receive {:action_ran, "after_reload_new_bus"}, 1_000
  end

  test "preserves cached signal bus dispatch when migration to refreshed bus fails" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"
    root = tmp_dir("dispatcher_signal_bus_reload_invalid")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_settings_path = Path.join(local_root, "settings.json")

    create_skill(
      local_root,
      "dispatcher-signal-bus-invalid",
      "demo/signal_bus_invalid",
      old_bus_name,
      include_hooks: false
    )

    write_settings(local_settings_path, default_permissions(),
      signal_bus_name: reloaded_bus_name,
      pre_bus: reloaded_bus_name,
      post_bus: reloaded_bus_name
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
           hook_defaults: hook_defaults(old_bus_name),
           permissions: default_permissions()
         ]}
      )

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: registry]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.signal_bus_invalid"]
    assert :sys.get_state(dispatcher).bus_name == old_bus_name

    assert :ok = publish_dispatch_signal(old_bus_name, "demo.signal_bus_invalid", "before_reload")
    assert_receive {:action_ran, "before_reload"}, 1_000

    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == old_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.signal_bus_invalid")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.signal_bus_invalid",
               "after_reload_old_bus"
             )

    assert_receive {:action_ran, "after_reload_old_bus"}, 1_000

    assert :error =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.signal_bus_invalid",
               "after_reload_new_bus"
             )
  end

  test "starts route dispatch on refreshed bus during startup when refresh_bus_name is enabled" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})
    start_supervised!({Bus, [name: reloaded_bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [skills: [valid_dispatcher_skill_entry()], bus_name: reloaded_bus_name]}
      )

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: registry]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == reloaded_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "startup-refresh-old-bus"
             )

    refute_receive {:action_ran, "startup-refresh-old-bus"}, 300

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "startup-refresh-new-bus"
             )

    assert_receive {:action_ran, "startup-refresh-new-bus"}, 1_000
  end

  test "falls back to configured bus when startup migration target is unavailable and migrates after recovery" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [skills: [valid_dispatcher_skill_entry()], bus_name: reloaded_bus_name]}
      )

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: registry]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    assert :sys.get_state(dispatcher).bus_name == old_bus_name

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "before_startup_bus_recovery"
             )

    assert_receive {:action_ran, "before_startup_bus_recovery"}, 1_000

    start_supervised!({Bus, [name: reloaded_bus_name, middleware: []]})
    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == reloaded_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_startup_bus_recovery_old_bus"
             )

    refute_receive {:action_ran, "after_startup_bus_recovery_old_bus"}, 300

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_startup_bus_recovery_new_bus"
             )

    assert_receive {:action_ran, "after_startup_bus_recovery_new_bus"}, 1_000
  end

  test "keeps configured bus when bus_name lookup is invalid during startup and migrates after recovery" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})
    start_supervised!({Bus, [name: reloaded_bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           skills: [valid_dispatcher_skill_entry()],
           bus_name: reloaded_bus_name,
           bus_name_error: {:invalid_return, :invalid_bus_name}
         ]}
      )

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: registry]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    assert :sys.get_state(dispatcher).bus_name == old_bus_name

    assert :ok =
             publish_dispatch_signal(old_bus_name, "demo.rollback", "before_bus_name_recovery")

    assert_receive {:action_ran, "before_bus_name_recovery"}, 1_000

    assert :ok = SignalDispatcherTestRegistry.set_bus_name_error(registry, nil)
    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == reloaded_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_bus_name_recovery_old_bus"
             )

    refute_receive {:action_ran, "after_bus_name_recovery_old_bus"}, 300

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_bus_name_recovery_new_bus"
             )

    assert_receive {:action_ran, "after_bus_name_recovery_new_bus"}, 1_000
  end

  test "keeps configured bus when startup bus_name lookup stays invalid across refreshes and migrates after recovery" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})
    start_supervised!({Bus, [name: reloaded_bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           skills: [valid_dispatcher_skill_entry()],
           bus_name: reloaded_bus_name,
           bus_name_error: {:invalid_return, :invalid_bus_name}
         ]}
      )

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: registry]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    assert :sys.get_state(dispatcher).bus_name == old_bus_name

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "before_startup_invalid_repeated_refresh"
             )

    assert_receive {:action_ran, "before_startup_invalid_repeated_refresh"}, 1_000

    assert :ok = publish_registry_update_signal(old_bus_name)
    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == old_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_startup_invalid_repeated_refresh_old_bus"
             )

    assert_receive {:action_ran, "after_startup_invalid_repeated_refresh_old_bus"}, 1_000

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_startup_invalid_repeated_refresh_new_bus"
             )

    refute_receive {:action_ran, "after_startup_invalid_repeated_refresh_new_bus"}, 300

    assert :ok = SignalDispatcherTestRegistry.set_bus_name_error(registry, nil)
    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == reloaded_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_startup_invalid_recovery_old_bus"
             )

    refute_receive {:action_ran, "after_startup_invalid_recovery_old_bus"}, 300

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_startup_invalid_recovery_new_bus"
             )

    assert_receive {:action_ran, "after_startup_invalid_recovery_new_bus"}, 1_000
  end

  test "preserves cached signal bus dispatch when bus_name lookup stays invalid during refresh and migrates after recovery" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})
    start_supervised!({Bus, [name: reloaded_bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [skills: [valid_dispatcher_skill_entry()], bus_name: old_bus_name]}
      )

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: registry]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    assert :sys.get_state(dispatcher).bus_name == old_bus_name

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "before_repeated_invalid_bus_name_refresh"
             )

    assert_receive {:action_ran, "before_repeated_invalid_bus_name_refresh"}, 1_000

    assert :ok = SignalDispatcherTestRegistry.set_bus_name(registry, reloaded_bus_name)

    assert :ok =
             SignalDispatcherTestRegistry.set_bus_name_error(
               registry,
               {:invalid_return, :invalid_bus_name}
             )

    assert :ok = publish_registry_update_signal(old_bus_name)
    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == old_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_repeated_invalid_bus_name_refresh_old_bus"
             )

    assert_receive {:action_ran, "after_repeated_invalid_bus_name_refresh_old_bus"}, 1_000

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_repeated_invalid_bus_name_refresh_new_bus"
             )

    refute_receive {:action_ran, "after_repeated_invalid_bus_name_refresh_new_bus"}, 300

    assert :ok = SignalDispatcherTestRegistry.set_bus_name_error(registry, nil)
    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == reloaded_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_repeated_invalid_bus_name_recovery_old_bus"
             )

    refute_receive {:action_ran, "after_repeated_invalid_bus_name_recovery_old_bus"}, 300

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_repeated_invalid_bus_name_recovery_new_bus"
             )

    assert_receive {:action_ran, "after_repeated_invalid_bus_name_recovery_new_bus"}, 1_000
  end

  test "preserves cached signal bus dispatch when bus_name lookup raises during refresh" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})
    start_supervised!({Bus, [name: reloaded_bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [skills: [valid_dispatcher_skill_entry()], bus_name: old_bus_name]}
      )

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: registry]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    assert :sys.get_state(dispatcher).bus_name == old_bus_name

    assert :ok = publish_dispatch_signal(old_bus_name, "demo.rollback", "before_bus_name_raise")
    assert_receive {:action_ran, "before_bus_name_raise"}, 1_000

    assert :ok = SignalDispatcherTestRegistry.set_bus_name(registry, reloaded_bus_name)

    assert :ok =
             SignalDispatcherTestRegistry.set_bus_name_error(
               registry,
               {:raise, RuntimeError.exception("bus_name_failed")}
             )

    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == old_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_bus_name_raise_old_bus"
             )

    assert_receive {:action_ran, "after_bus_name_raise_old_bus"}, 1_000

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_bus_name_raise_new_bus"
             )

    refute_receive {:action_ran, "after_bus_name_raise_new_bus"}, 300
  end

  test "keeps configured bus when bus_name lookup raises call exceptions during startup and migrates after recovery" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})
    start_supervised!({Bus, [name: reloaded_bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           skills: [valid_dispatcher_skill_entry()],
           bus_name: reloaded_bus_name
         ]}
      )

    lookup_plan =
      start_supervised!(
        {Agent,
         fn ->
           %{count: 0, fail_on: MapSet.new([2])}
         end}
      )

    exception_registry =
      {:via, Jido.Code.Skill.SkillRuntime.SignalDispatcherNthLookupVia, {registry, lookup_plan}}

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: exception_registry]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    assert :sys.get_state(dispatcher).bus_name == old_bus_name

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "before_bus_name_call_exception_recovery"
             )

    assert_receive {:action_ran, "before_bus_name_call_exception_recovery"}, 1_000

    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == reloaded_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_bus_name_call_exception_recovery_old_bus"
             )

    refute_receive {:action_ran, "after_bus_name_call_exception_recovery_old_bus"}, 300

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_bus_name_call_exception_recovery_new_bus"
             )

    assert_receive {:action_ran, "after_bus_name_call_exception_recovery_new_bus"}, 1_000
  end

  test "keeps configured bus when startup bus_name lookup keeps raising call exceptions across refreshes and migrates after recovery" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})
    start_supervised!({Bus, [name: reloaded_bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           skills: [valid_dispatcher_skill_entry()],
           bus_name: reloaded_bus_name
         ]}
      )

    lookup_plan =
      start_supervised!(
        {Agent,
         fn ->
           %{count: 0, fail_on: MapSet.new([2, 5, 8])}
         end}
      )

    exception_registry =
      {:via, Jido.Code.Skill.SkillRuntime.SignalDispatcherNthLookupVia, {registry, lookup_plan}}

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: exception_registry]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    assert :sys.get_state(dispatcher).bus_name == old_bus_name

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "before_startup_call_exception_repeated_refresh"
             )

    assert_receive {:action_ran, "before_startup_call_exception_repeated_refresh"}, 1_000

    assert :ok = publish_registry_update_signal(old_bus_name)
    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == old_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_startup_call_exception_repeated_refresh_old_bus"
             )

    assert_receive {:action_ran, "after_startup_call_exception_repeated_refresh_old_bus"}, 1_000

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_startup_call_exception_repeated_refresh_new_bus"
             )

    refute_receive {:action_ran, "after_startup_call_exception_repeated_refresh_new_bus"}, 300

    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == reloaded_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_startup_call_exception_recovery_old_bus"
             )

    refute_receive {:action_ran, "after_startup_call_exception_recovery_old_bus"}, 300

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_startup_call_exception_recovery_new_bus"
             )

    assert_receive {:action_ran, "after_startup_call_exception_recovery_new_bus"}, 1_000
  end

  test "preserves cached signal bus dispatch when bus_name lookup raises call exceptions during refresh" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})
    start_supervised!({Bus, [name: reloaded_bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [skills: [valid_dispatcher_skill_entry()], bus_name: old_bus_name]}
      )

    lookup_plan =
      start_supervised!(
        {Agent,
         fn ->
           %{count: 0, fail_on: MapSet.new([5])}
         end}
      )

    exception_registry =
      {:via, Jido.Code.Skill.SkillRuntime.SignalDispatcherNthLookupVia, {registry, lookup_plan}}

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: exception_registry]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    assert :sys.get_state(dispatcher).bus_name == old_bus_name

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "before_bus_name_call_exception_refresh"
             )

    assert_receive {:action_ran, "before_bus_name_call_exception_refresh"}, 1_000

    assert :ok = SignalDispatcherTestRegistry.set_bus_name(registry, reloaded_bus_name)
    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == old_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_bus_name_call_exception_refresh_old_bus"
             )

    assert_receive {:action_ran, "after_bus_name_call_exception_refresh_old_bus"}, 1_000

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_bus_name_call_exception_refresh_new_bus"
             )

    refute_receive {:action_ran, "after_bus_name_call_exception_refresh_new_bus"}, 300
  end

  test "preserves cached signal bus dispatch when bus_name lookup keeps raising call exceptions during refresh and migrates after recovery" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})
    start_supervised!({Bus, [name: reloaded_bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [skills: [valid_dispatcher_skill_entry()], bus_name: old_bus_name]}
      )

    lookup_plan =
      start_supervised!(
        {Agent,
         fn ->
           %{count: 0, fail_on: MapSet.new([5, 8])}
         end}
      )

    exception_registry =
      {:via, Jido.Code.Skill.SkillRuntime.SignalDispatcherNthLookupVia, {registry, lookup_plan}}

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: exception_registry]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    assert :sys.get_state(dispatcher).bus_name == old_bus_name

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "before_repeated_bus_name_call_exception_refresh"
             )

    assert_receive {:action_ran, "before_repeated_bus_name_call_exception_refresh"}, 1_000

    assert :ok = SignalDispatcherTestRegistry.set_bus_name(registry, reloaded_bus_name)
    assert :ok = publish_registry_update_signal(old_bus_name)
    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == old_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_repeated_bus_name_call_exception_refresh_old_bus"
             )

    assert_receive {:action_ran, "after_repeated_bus_name_call_exception_refresh_old_bus"}, 1_000

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_repeated_bus_name_call_exception_refresh_new_bus"
             )

    refute_receive {:action_ran, "after_repeated_bus_name_call_exception_refresh_new_bus"}, 300

    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == reloaded_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_repeated_bus_name_call_exception_recovery_old_bus"
             )

    refute_receive {:action_ran, "after_repeated_bus_name_call_exception_recovery_old_bus"}, 300

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_repeated_bus_name_call_exception_recovery_new_bus"
             )

    assert_receive {:action_ran, "after_repeated_bus_name_call_exception_recovery_new_bus"}, 1_000
  end

  test "keeps configured bus when startup bus_name lookup keeps exiting across refreshes and migrates after recovery" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"
    registry_name = :"dispatcher_bus_name_exit_registry_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})
    start_supervised!({Bus, [name: reloaded_bus_name, middleware: []]})

    _registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           name: registry_name,
           skills: [valid_dispatcher_skill_entry()],
           bus_name: reloaded_bus_name,
           bus_name_error: {:exit, :bus_name_unavailable}
         ]}
      )

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: registry_name]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    assert :sys.get_state(dispatcher).bus_name == old_bus_name

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "before_startup_bus_name_exit_repeated_refresh"
             )

    assert_receive {:action_ran, "before_startup_bus_name_exit_repeated_refresh"}, 1_000

    assert :ok = publish_registry_update_signal(old_bus_name)
    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == old_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_startup_bus_name_exit_repeated_refresh_old_bus"
             )

    assert_receive {:action_ran, "after_startup_bus_name_exit_repeated_refresh_old_bus"}, 1_000

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_startup_bus_name_exit_repeated_refresh_new_bus"
             )

    refute_receive {:action_ran, "after_startup_bus_name_exit_repeated_refresh_new_bus"}, 300

    assert_eventually(fn ->
      try do
        SignalDispatcherTestRegistry.set_bus_name_error(registry_name, nil) == :ok
      catch
        :exit, _reason ->
          false
      end
    end)

    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == reloaded_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_startup_bus_name_exit_recovery_old_bus"
             )

    refute_receive {:action_ran, "after_startup_bus_name_exit_recovery_old_bus"}, 300

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_startup_bus_name_exit_recovery_new_bus"
             )

    assert_receive {:action_ran, "after_startup_bus_name_exit_recovery_new_bus"}, 1_000
  end

  test "preserves cached signal bus dispatch when bus_name lookup keeps exiting during refresh and migrates after recovery" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})
    start_supervised!({Bus, [name: reloaded_bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           skills: [valid_dispatcher_skill_entry()],
           bus_name: old_bus_name
         ]}
      )

    lookup_plan =
      start_supervised!(
        {Agent,
         fn ->
           %{count: 0, fail_on: MapSet.new([5, 8]), fail_mode: {:exit, :bus_name_unavailable}}
         end}
      )

    exception_registry =
      {:via, Jido.Code.Skill.SkillRuntime.SignalDispatcherNthLookupVia, {registry, lookup_plan}}

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: exception_registry]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    assert :sys.get_state(dispatcher).bus_name == old_bus_name

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "before_repeated_bus_name_exit_refresh"
             )

    assert_receive {:action_ran, "before_repeated_bus_name_exit_refresh"}, 1_000

    assert :ok = SignalDispatcherTestRegistry.set_bus_name(registry, reloaded_bus_name)

    assert :ok = publish_registry_update_signal(old_bus_name)
    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == old_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_repeated_bus_name_exit_refresh_old_bus"
             )

    assert_receive {:action_ran, "after_repeated_bus_name_exit_refresh_old_bus"}, 1_000

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_repeated_bus_name_exit_refresh_new_bus"
             )

    refute_receive {:action_ran, "after_repeated_bus_name_exit_refresh_new_bus"}, 300

    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == reloaded_bus_name and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_repeated_bus_name_exit_recovery_old_bus"
             )

    refute_receive {:action_ran, "after_repeated_bus_name_exit_recovery_old_bus"}, 300

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_repeated_bus_name_exit_recovery_new_bus"
             )

    assert_receive {:action_ran, "after_repeated_bus_name_exit_recovery_new_bus"}, 1_000
  end

  test "preserves cached registry subscription when bus_name lookup keeps exiting during refresh and rebinds after recovery" do
    set_notify_pid!()

    old_bus_name = "bus_#{System.unique_integer([:positive])}"
    reloaded_bus_name = "bus_#{System.unique_integer([:positive])}"

    start_supervised!({Bus, [name: old_bus_name, middleware: []]})
    start_supervised!({Bus, [name: reloaded_bus_name, middleware: []]})

    registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           skills: [valid_dispatcher_skill_entry()],
           bus_name: old_bus_name
         ]}
      )

    lookup_plan =
      start_supervised!(
        {Agent,
         fn ->
           %{count: 0, fail_on: MapSet.new([5, 8]), fail_mode: {:exit, :bus_name_unavailable}}
         end}
      )

    exception_registry =
      {:via, Jido.Code.Skill.SkillRuntime.SignalDispatcherNthLookupVia, {registry, lookup_plan}}

    dispatcher =
      start_supervised!(
        {SignalDispatcher,
         [name: nil, bus_name: old_bus_name, refresh_bus_name: true, registry: exception_registry]}
      )

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]

    initial_state = :sys.get_state(dispatcher)
    initial_registry_subscription = initial_state.registry_subscription
    assert initial_state.bus_name == old_bus_name
    refute is_nil(initial_registry_subscription)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "before_repeated_bus_name_exit_registry_subscription_refresh"
             )

    assert_receive {:action_ran, "before_repeated_bus_name_exit_registry_subscription_refresh"}, 1_000

    assert :ok = SignalDispatcherTestRegistry.set_bus_name(registry, reloaded_bus_name)
    assert :ok = publish_registry_update_signal(old_bus_name)
    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == old_bus_name and
        dispatcher_state.registry_subscription == initial_registry_subscription and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_repeated_bus_name_exit_registry_subscription_refresh_old_bus"
             )

    assert_receive {:action_ran, "after_repeated_bus_name_exit_registry_subscription_refresh_old_bus"},
                   1_000

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_repeated_bus_name_exit_registry_subscription_refresh_new_bus"
             )

    refute_receive {:action_ran, "after_repeated_bus_name_exit_registry_subscription_refresh_new_bus"},
                   300

    assert :ok = publish_registry_update_signal(old_bus_name)

    assert_eventually(fn ->
      dispatcher_state = :sys.get_state(dispatcher)

      dispatcher_state.bus_name == reloaded_bus_name and
        dispatcher_state.registry_subscription != initial_registry_subscription and
        Map.has_key?(dispatcher_state.route_subscriptions, "demo.rollback")
    end)

    assert :ok =
             publish_dispatch_signal(
               old_bus_name,
               "demo.rollback",
               "after_repeated_bus_name_exit_registry_subscription_recovery_old_bus"
             )

    refute_receive {:action_ran, "after_repeated_bus_name_exit_registry_subscription_recovery_old_bus"},
                   300

    assert :ok =
             publish_dispatch_signal(
               reloaded_bus_name,
               "demo.rollback",
               "after_repeated_bus_name_exit_registry_subscription_recovery_new_bus"
             )

    assert_receive {:action_ran, "after_repeated_bus_name_exit_registry_subscription_recovery_new_bus"},
                   1_000
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
          {SignalDispatcherTestRegistry, :start_link,
           [[skills: [valid_dispatcher_skill_entry()]]]},
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

  test "starts with empty routes when initial list_skills read keeps returning invalid data across refreshes and recovers on refresh" do
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
           list_skills_error: {:invalid_return, :skills_unavailable}
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == []
    assert :sys.get_state(dispatcher).hook_defaults == cached_hook_defaults

    subscribe!(bus_name, "skill.pre")
    subscribe!(bus_name, "skill.post")

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "before_repeated_invalid_list_skills_recovery"
             )

    refute_receive {:action_ran, "before_repeated_invalid_list_skills_recovery"}, 200
    refute_receive {:signal, _hook_signal_before_repeated_invalid_list_skills_recovery}, 200

    assert {:error, {:list_skills_failed, {:invalid_result, :skills_unavailable}}} =
             SignalDispatcher.refresh(dispatcher)

    assert SignalDispatcher.routes(dispatcher) == []

    assert :ok = publish_registry_update_signal(bus_name)

    assert_eventually(fn ->
      SignalDispatcher.routes(dispatcher) == []
    end)

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "after_repeated_invalid_list_skills_refresh"
             )

    refute_receive {:action_ran, "after_repeated_invalid_list_skills_refresh"}, 200
    refute_receive {:signal, _hook_signal_after_repeated_invalid_list_skills_refresh}, 200

    assert :ok = SignalDispatcherTestRegistry.set_list_skills_error(registry, nil)
    assert :ok = SignalDispatcher.refresh(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_one"]

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "after_repeated_invalid_list_skills_recovery"
             )

    assert_receive {:action_ran, "after_repeated_invalid_list_skills_recovery"}, 1_000
    assert_receive {:signal, pre_signal}, 1_000
    assert pre_signal.type == "skill.pre"
    assert pre_signal.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_signal}, 1_000
    assert post_signal.type == "skill.post"
    assert post_signal.data["route"] == "demo/hook_one"

    recovered_state = :sys.get_state(dispatcher)
    assert recovered_state.hook_defaults == cached_hook_defaults
  end

  test "starts with empty routes when initial list_skills raises and recovers on refresh" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    registry_name = :"dispatcher_raise_registry_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    _failing_registry =
      start_supervised!(%{
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
      })

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

  test "starts with empty routes when initial list_skills call raises call exceptions and recovers on refresh" do
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

    lookup_plan =
      start_supervised!(
        {Agent,
         fn ->
           %{count: 0, fail_on: MapSet.new([1])}
         end}
      )

    exception_registry =
      {:via, Jido.Code.Skill.SkillRuntime.SignalDispatcherNthLookupVia, {registry, lookup_plan}}

    dispatcher =
      start_supervised!(
        {SignalDispatcher, [name: nil, bus_name: bus_name, registry: exception_registry]}
      )

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == []

    dispatcher_state = :sys.get_state(dispatcher)
    assert dispatcher_state.hook_defaults == cached_hook_defaults

    subscribe!(bus_name, "skill.pre")
    subscribe!(bus_name, "skill.post")

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "before_list_skills_call_exception_recovery"
             )

    refute_receive {:action_ran, "before_list_skills_call_exception_recovery"}, 200
    refute_receive {:signal, _hook_signal_before_list_skills_call_exception_recovery}, 200

    assert :ok = SignalDispatcher.refresh(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_one"]

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "after_list_skills_call_exception_recovery"
             )

    assert_receive {:action_ran, "after_list_skills_call_exception_recovery"}, 1_000
    assert_receive {:signal, pre_signal}, 1_000
    assert pre_signal.type == "skill.pre"
    assert pre_signal.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_signal}, 1_000
    assert post_signal.type == "skill.post"
    assert post_signal.data["route"] == "demo/hook_one"

    recovered_state = :sys.get_state(dispatcher)
    assert recovered_state.hook_defaults == cached_hook_defaults
  end

  test "starts with empty routes when initial list_skills call keeps raising call exceptions across refreshes and recovers on refresh" do
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

    lookup_plan =
      start_supervised!(
        {Agent,
         fn ->
           %{count: 0, fail_on: MapSet.new([1, 3, 4])}
         end}
      )

    exception_registry =
      {:via, Jido.Code.Skill.SkillRuntime.SignalDispatcherNthLookupVia, {registry, lookup_plan}}

    dispatcher =
      start_supervised!(
        {SignalDispatcher, [name: nil, bus_name: bus_name, registry: exception_registry]}
      )

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == []
    assert :sys.get_state(dispatcher).hook_defaults == cached_hook_defaults

    subscribe!(bus_name, "skill.pre")
    subscribe!(bus_name, "skill.post")

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "before_repeated_list_skills_call_exception_recovery"
             )

    refute_receive {:action_ran, "before_repeated_list_skills_call_exception_recovery"}, 200

    refute_receive {:signal, _hook_signal_before_repeated_list_skills_call_exception_recovery},
                   200

    assert {:error, {:list_skills_failed, _reason}} = SignalDispatcher.refresh(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == []

    assert :ok = publish_registry_update_signal(bus_name)

    assert_eventually(fn ->
      SignalDispatcher.routes(dispatcher) == []
    end)

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "after_repeated_list_skills_call_exception_refresh"
             )

    refute_receive {:action_ran, "after_repeated_list_skills_call_exception_refresh"}, 200
    refute_receive {:signal, _hook_signal_after_repeated_list_skills_call_exception_refresh}, 200

    assert :ok = SignalDispatcher.refresh(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_one"]

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "after_repeated_list_skills_call_exception_recovery"
             )

    assert_receive {:action_ran, "after_repeated_list_skills_call_exception_recovery"}, 1_000
    assert_receive {:signal, pre_signal}, 1_000
    assert pre_signal.type == "skill.pre"
    assert pre_signal.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_signal}, 1_000
    assert post_signal.type == "skill.post"
    assert post_signal.data["route"] == "demo/hook_one"

    recovered_state = :sys.get_state(dispatcher)
    assert recovered_state.hook_defaults == cached_hook_defaults
  end

  test "starts with empty routes when initial list_skills call keeps exiting across refreshes and recovers on refresh" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    registry_name = :"dispatcher_list_skills_exit_registry_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    cached_hook_defaults = hook_defaults(bus_name)

    _registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           name: registry_name,
           skills: [hook_aware_dispatcher_skill_entry()],
           hook_defaults: cached_hook_defaults,
           list_skills_error: {:exit, :skills_unavailable}
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry_name]})

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == []
    assert :sys.get_state(dispatcher).hook_defaults == %{}

    subscribe!(bus_name, "skill.pre")
    subscribe!(bus_name, "skill.post")

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "before_repeated_startup_list_skills_exit_recovery"
             )

    refute_receive {:action_ran, "before_repeated_startup_list_skills_exit_recovery"}, 200
    refute_receive {:signal, _hook_signal_before_repeated_startup_list_skills_exit_recovery}, 200

    assert {:error, {:list_skills_failed, {:exit, _reason}}} = SignalDispatcher.refresh(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == []
    assert :sys.get_state(dispatcher).hook_defaults == %{}

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "after_first_repeated_startup_list_skills_exit_refresh"
             )

    refute_receive {:action_ran, "after_first_repeated_startup_list_skills_exit_refresh"}, 200
    refute_receive {:signal, _hook_signal_after_first_repeated_startup_list_skills_exit_refresh}, 200

    assert :ok = publish_registry_update_signal(bus_name)

    assert_eventually(fn ->
      SignalDispatcher.routes(dispatcher) == []
    end)

    assert :sys.get_state(dispatcher).hook_defaults == %{}

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "after_second_repeated_startup_list_skills_exit_refresh"
             )

    refute_receive {:action_ran, "after_second_repeated_startup_list_skills_exit_refresh"}, 200
    refute_receive {:signal, _hook_signal_after_second_repeated_startup_list_skills_exit_refresh}, 200

    assert_eventually(fn ->
      try do
        SignalDispatcherTestRegistry.set_list_skills_error(registry_name, nil) == :ok
      catch
        :exit, _reason ->
          false
      end
    end)

    assert :ok = SignalDispatcher.refresh(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_one"]

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "after_repeated_startup_list_skills_exit_recovery"
             )

    assert_receive {:action_ran, "after_repeated_startup_list_skills_exit_recovery"}, 1_000
    assert_receive {:signal, pre_signal}, 1_000
    assert pre_signal.type == "skill.pre"
    assert pre_signal.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_signal}, 1_000
    assert post_signal.type == "skill.post"
    assert post_signal.data["route"] == "demo/hook_one"

    recovered_state = :sys.get_state(dispatcher)
    assert recovered_state.hook_defaults == cached_hook_defaults
  end

  test "starts with empty routes when initial registry reference raises call exceptions and recovers on refresh" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    cached_hook_defaults = hook_defaults(bus_name)

    start_supervised!({Bus, [name: bus_name, middleware: []]})

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: %{}]})

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == []

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "before_exception_recovery")
    refute_receive {:action_ran, "before_exception_recovery"}, 200

    recovered_registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           skills: [valid_dispatcher_skill_entry()],
           hook_defaults: cached_hook_defaults
         ]}
      )

    :sys.replace_state(dispatcher, fn state ->
      %{state | registry: recovered_registry}
    end)

    assert :ok = SignalDispatcher.refresh(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]

    dispatcher_state = :sys.get_state(dispatcher)
    assert dispatcher_state.hook_defaults == cached_hook_defaults

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "after_exception_recovery")
    assert_receive {:action_ran, "after_exception_recovery"}, 1_000
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

  test "starts with routes when initial hook defaults call raises exceptions and recovers hook emission on refresh" do
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

    lookup_plan =
      start_supervised!(
        {Agent,
         fn ->
           %{count: 0, fail_on: MapSet.new([2])}
         end}
      )

    exception_registry =
      {:via, Jido.Code.Skill.SkillRuntime.SignalDispatcherNthLookupVia, {registry, lookup_plan}}

    dispatcher =
      start_supervised!(
        {SignalDispatcher, [name: nil, bus_name: bus_name, registry: exception_registry]}
      )

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_one"]

    dispatcher_state = :sys.get_state(dispatcher)
    assert dispatcher_state.hook_defaults == %{}

    subscribe!(bus_name, "skill.pre")
    subscribe!(bus_name, "skill.post")

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "before_exception_recovery")
    assert_receive {:action_ran, "before_exception_recovery"}, 1_000
    refute_receive {:signal, _hook_signal_before_exception_recovery}, 200

    assert :ok = SignalDispatcher.refresh(dispatcher)

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "after_exception_recovery")
    assert_receive {:action_ran, "after_exception_recovery"}, 1_000
    assert_receive {:signal, pre_signal}, 1_000
    assert pre_signal.type == "skill.pre"
    assert pre_signal.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_signal}, 1_000
    assert post_signal.type == "skill.post"
    assert post_signal.data["route"] == "demo/hook_one"

    recovered_state = :sys.get_state(dispatcher)
    assert recovered_state.hook_defaults == cached_hook_defaults
  end

  test "starts with routes when initial hook defaults call keeps raising exceptions across refreshes and recovers hook emission on refresh" do
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

    lookup_plan =
      start_supervised!(
        {Agent,
         fn ->
           %{count: 0, fail_on: MapSet.new([2, 4, 6])}
         end}
      )

    exception_registry =
      {:via, Jido.Code.Skill.SkillRuntime.SignalDispatcherNthLookupVia, {registry, lookup_plan}}

    dispatcher =
      start_supervised!(
        {SignalDispatcher, [name: nil, bus_name: bus_name, registry: exception_registry]}
      )

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_one"]
    assert :sys.get_state(dispatcher).hook_defaults == %{}

    subscribe!(bus_name, "skill.pre")
    subscribe!(bus_name, "skill.post")

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "before_repeated_startup_hook_failure"
             )

    assert_receive {:action_ran, "before_repeated_startup_hook_failure"}, 1_000
    refute_receive {:signal, _hook_signal_before_repeated_startup_hook_failure}, 200

    assert :ok = SignalDispatcher.refresh(dispatcher)
    assert :sys.get_state(dispatcher).hook_defaults == %{}

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "after_first_repeated_startup_hook_failure"
             )

    assert_receive {:action_ran, "after_first_repeated_startup_hook_failure"}, 1_000
    refute_receive {:signal, _hook_signal_after_first_repeated_startup_hook_failure}, 200

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    assert :sys.get_state(dispatcher).hook_defaults == %{}

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "after_second_repeated_startup_hook_failure"
             )

    assert_receive {:action_ran, "after_second_repeated_startup_hook_failure"}, 1_000
    refute_receive {:signal, _hook_signal_after_second_repeated_startup_hook_failure}, 200

    assert :ok = SignalDispatcher.refresh(dispatcher)

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "after_repeated_startup_hook_recovery"
             )

    assert_receive {:action_ran, "after_repeated_startup_hook_recovery"}, 1_000
    assert_receive {:signal, pre_signal}, 1_000
    assert pre_signal.type == "skill.pre"
    assert pre_signal.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_signal}, 1_000
    assert post_signal.type == "skill.post"
    assert post_signal.data["route"] == "demo/hook_one"

    recovered_state = :sys.get_state(dispatcher)
    assert recovered_state.hook_defaults == cached_hook_defaults
  end

  test "starts with routes when initial hook defaults read keeps returning invalid data across refreshes and recovers hook emission on refresh" do
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
    assert :sys.get_state(dispatcher).hook_defaults == %{}

    subscribe!(bus_name, "skill.pre")
    subscribe!(bus_name, "skill.post")

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "before_repeated_startup_hook_invalid_failure")
    assert_receive {:action_ran, "before_repeated_startup_hook_invalid_failure"}, 1_000
    refute_receive {:signal, _hook_signal_before_repeated_startup_hook_invalid_failure}, 200

    assert :ok = SignalDispatcher.refresh(dispatcher)
    assert :sys.get_state(dispatcher).hook_defaults == %{}

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "after_first_repeated_startup_hook_invalid_failure")
    assert_receive {:action_ran, "after_first_repeated_startup_hook_invalid_failure"}, 1_000
    refute_receive {:signal, _hook_signal_after_first_repeated_startup_hook_invalid_failure}, 200

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    assert :sys.get_state(dispatcher).hook_defaults == %{}

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "after_second_repeated_startup_hook_invalid_failure")
    assert_receive {:action_ran, "after_second_repeated_startup_hook_invalid_failure"}, 1_000
    refute_receive {:signal, _hook_signal_after_second_repeated_startup_hook_invalid_failure}, 200

    assert :ok = SignalDispatcherTestRegistry.set_hook_defaults_error(registry, nil)
    assert :ok = SignalDispatcher.refresh(dispatcher)

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "after_repeated_startup_hook_invalid_recovery")
    assert_receive {:action_ran, "after_repeated_startup_hook_invalid_recovery"}, 1_000
    assert_receive {:signal, pre_signal}, 1_000
    assert pre_signal.type == "skill.pre"
    assert pre_signal.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_signal}, 1_000
    assert post_signal.type == "skill.post"
    assert post_signal.data["route"] == "demo/hook_one"

    recovered_state = :sys.get_state(dispatcher)
    assert recovered_state.hook_defaults == cached_hook_defaults
  end

  test "starts with routes when initial hook defaults call keeps exiting across refreshes and recovers hook emission on refresh" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    registry_name = :"dispatcher_hook_exit_registry_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    cached_hook_defaults = hook_defaults(bus_name)

    _registry =
      start_supervised!(
        {SignalDispatcherTestRegistry,
         [
           name: registry_name,
           skills: [hook_aware_dispatcher_skill_entry()],
           hook_defaults: cached_hook_defaults,
           hook_defaults_error: {:exit, :hook_defaults_unavailable}
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry_name]})

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_one"]
    assert :sys.get_state(dispatcher).hook_defaults == %{}

    subscribe!(bus_name, "skill.pre")
    subscribe!(bus_name, "skill.post")

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "before_repeated_startup_hook_exit_failure")
    assert_receive {:action_ran, "before_repeated_startup_hook_exit_failure"}, 1_000
    refute_receive {:signal, _hook_signal_before_repeated_startup_hook_exit_failure}, 200

    assert :ok = SignalDispatcher.refresh(dispatcher)
    Process.sleep(50)
    assert :sys.get_state(dispatcher).hook_defaults == %{}

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "after_first_repeated_startup_hook_exit_failure")
    assert_receive {:action_ran, "after_first_repeated_startup_hook_exit_failure"}, 1_000
    refute_receive {:signal, _hook_signal_after_first_repeated_startup_hook_exit_failure}, 200

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)
    assert :sys.get_state(dispatcher).hook_defaults == %{}

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "after_second_repeated_startup_hook_exit_failure")
    assert_receive {:action_ran, "after_second_repeated_startup_hook_exit_failure"}, 1_000
    refute_receive {:signal, _hook_signal_after_second_repeated_startup_hook_exit_failure}, 200

    assert_eventually(fn ->
      try do
        SignalDispatcherTestRegistry.set_hook_defaults_error(registry_name, nil) == :ok
      catch
        :exit, _reason ->
          false
      end
    end)

    assert :ok = SignalDispatcher.refresh(dispatcher)

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "after_repeated_startup_hook_exit_recovery")
    assert_receive {:action_ran, "after_repeated_startup_hook_exit_recovery"}, 1_000
    assert_receive {:signal, pre_signal}, 1_000
    assert pre_signal.type == "skill.pre"
    assert pre_signal.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_signal}, 1_000
    assert post_signal.type == "skill.post"
    assert post_signal.data["route"] == "demo/hook_one"

    recovered_state = :sys.get_state(dispatcher)
    assert recovered_state.hook_defaults == cached_hook_defaults
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

    assert :ok =
             SignalDispatcherTestRegistry.set_skills(registry, [valid_dispatcher_skill_entry()])

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

  test "preserves existing routes when list_skills raises during refresh" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    registry =
      start_supervised!(%{
        id: {:dispatcher_raise_refresh_registry, System.unique_integer([:positive])},
        start:
          {SignalDispatcherTestRegistry, :start_link,
           [[skills: [valid_dispatcher_skill_entry()]]]},
        restart: :temporary
      })

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "before_raise_refresh")
    assert_receive {:action_ran, "before_raise_refresh"}, 1_000

    assert :ok =
             SignalDispatcherTestRegistry.set_list_skills_error(
               registry,
               {:raise, RuntimeError.exception("skills_unavailable")}
             )

    ref = Process.monitor(registry)

    assert {:error, {:list_skills_failed, {:exit, _reason}}} =
             SignalDispatcher.refresh(dispatcher)

    assert_receive {:DOWN, ^ref, :process, ^registry, _reason}, 1_000

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "after_raise_refresh")
    assert_receive {:action_ran, "after_raise_refresh"}, 1_000
  end

  test "preserves existing routes when list_skills call raises call exceptions during refresh" do
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

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "before_exception_refresh")
    assert_receive {:action_ran, "before_exception_refresh"}, 1_000

    :sys.replace_state(dispatcher, fn state ->
      %{state | registry: %{}}
    end)

    assert {:error, {:list_skills_failed, {:exception, %FunctionClauseError{}}}} =
             SignalDispatcher.refresh(dispatcher)

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "after_exception_refresh")
    assert_receive {:action_ran, "after_exception_refresh"}, 1_000
  end

  test "preserves hook-aware routes and cached hook defaults when list_skills call raises call exceptions during refresh" do
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

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "before_exception_refresh")
    assert_receive {:action_ran, "before_exception_refresh"}, 1_000
    assert_receive {:signal, pre_before_refresh}, 1_000
    assert pre_before_refresh.type == "skill.pre"
    assert pre_before_refresh.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_before_refresh}, 1_000
    assert post_before_refresh.type == "skill.post"
    assert post_before_refresh.data["route"] == "demo/hook_one"

    assert :ok =
             SignalDispatcherTestRegistry.set_skills(registry, [
               hook_aware_dispatcher_skill_entry_two()
             ])

    lookup_plan =
      start_supervised!(
        {Agent,
         fn ->
           %{count: 0, fail_on: MapSet.new([1, 2])}
         end}
      )

    exception_registry =
      {:via, Jido.Code.Skill.SkillRuntime.SignalDispatcherNthLookupVia, {registry, lookup_plan}}

    :sys.replace_state(dispatcher, fn state ->
      %{state | registry: exception_registry}
    end)

    assert {:error, {:list_skills_failed, {:exception, %ArgumentError{}}}} =
             SignalDispatcher.refresh(dispatcher)

    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_one"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "after_exception_refresh")
    assert_receive {:action_ran, "after_exception_refresh"}, 1_000
    assert_receive {:signal, pre_after_refresh}, 1_000
    assert pre_after_refresh.type == "skill.pre"
    assert pre_after_refresh.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_after_refresh}, 1_000
    assert post_after_refresh.type == "skill.post"
    assert post_after_refresh.data["route"] == "demo/hook_one"

    assert :ok =
             publish_dispatch_signal(bus_name, "demo.hook_two", "new_route_should_not_dispatch")

    refute_receive {:action_ran, "new_route_should_not_dispatch"}, 200

    dispatcher_state = :sys.get_state(dispatcher)
    assert dispatcher_state.hook_defaults == cached_hook_defaults

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_one"]

    assert :ok =
             publish_dispatch_signal(bus_name, "demo.hook_one", "after_exception_registry_update")

    assert_receive {:action_ran, "after_exception_registry_update"}, 1_000
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
             SignalDispatcherTestRegistry.set_skills(registry, [
               valid_dispatcher_skill_entry_two()
             ])

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

  test "refreshes routes while keeping cached hook defaults when hook defaults raises" do
    set_notify_pid!()

    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    cached_hook_defaults = hook_defaults(bus_name)

    registry =
      start_supervised!(%{
        id: {:dispatcher_hook_raise_refresh_registry, System.unique_integer([:positive])},
        start:
          {SignalDispatcherTestRegistry, :start_link,
           [[skills: [valid_dispatcher_skill_entry()], hook_defaults: cached_hook_defaults]]},
        restart: :temporary
      })

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.rollback"]
    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "before_raise_hook_failure")
    assert_receive {:action_ran, "before_raise_hook_failure"}, 1_000

    assert :ok =
             SignalDispatcherTestRegistry.set_skills(registry, [
               valid_dispatcher_skill_entry_two()
             ])

    assert :ok =
             SignalDispatcherTestRegistry.set_hook_defaults_error(
               registry,
               {:raise, RuntimeError.exception("hook_defaults_unavailable")}
             )

    ref = Process.monitor(registry)

    assert :ok = SignalDispatcher.refresh(dispatcher)
    assert_receive {:DOWN, ^ref, :process, ^registry, _reason}, 1_000
    assert SignalDispatcher.routes(dispatcher) == ["demo.second"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.second", "after_raise_hook_failure")
    assert_receive {:action_ran, "after_raise_hook_failure"}, 1_000

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "old_route")
    refute_receive {:action_ran, "old_route"}, 200

    dispatcher_state = :sys.get_state(dispatcher)
    assert dispatcher_state.hook_defaults == cached_hook_defaults

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.second"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.second", "after_raise_registry_update")
    assert_receive {:action_ran, "after_raise_registry_update"}, 1_000
  end

  test "refreshes routes while keeping cached hook defaults when hook defaults call raises exceptions" do
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

    assert :ok =
             publish_dispatch_signal(bus_name, "demo.rollback", "before_exception_hook_failure")

    assert_receive {:action_ran, "before_exception_hook_failure"}, 1_000

    assert :ok =
             SignalDispatcherTestRegistry.set_skills(registry, [
               valid_dispatcher_skill_entry_two()
             ])

    lookup_plan =
      start_supervised!(
        {Agent,
         fn ->
           %{count: 0, fail_on: MapSet.new([2, 4])}
         end}
      )

    exception_registry =
      {:via, Jido.Code.Skill.SkillRuntime.SignalDispatcherNthLookupVia, {registry, lookup_plan}}

    :sys.replace_state(dispatcher, fn state ->
      %{state | registry: exception_registry}
    end)

    assert :ok = SignalDispatcher.refresh(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.second"]

    assert :ok = publish_dispatch_signal(bus_name, "demo.second", "after_exception_hook_failure")
    assert_receive {:action_ran, "after_exception_hook_failure"}, 1_000

    assert :ok = publish_dispatch_signal(bus_name, "demo.rollback", "old_route")
    refute_receive {:action_ran, "old_route"}, 200

    dispatcher_state = :sys.get_state(dispatcher)
    assert dispatcher_state.hook_defaults == cached_hook_defaults

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.second"]

    assert :ok =
             publish_dispatch_signal(bus_name, "demo.second", "after_exception_registry_update")

    assert_receive {:action_ran, "after_exception_registry_update"}, 1_000
  end

  test "refreshes hook-aware routes while preserving cached hook defaults when hook defaults call raises call exceptions" do
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

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_one",
               "before_call_exception_hook_defaults_refresh"
             )

    assert_receive {:action_ran, "before_call_exception_hook_defaults_refresh"}, 1_000
    assert_receive {:signal, pre_before_refresh}, 1_000
    assert pre_before_refresh.type == "skill.pre"
    assert pre_before_refresh.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_before_refresh}, 1_000
    assert post_before_refresh.type == "skill.post"
    assert post_before_refresh.data["route"] == "demo/hook_one"

    assert :ok =
             SignalDispatcherTestRegistry.set_skills(registry, [
               hook_aware_dispatcher_skill_entry_two()
             ])

    lookup_plan =
      start_supervised!(
        {Agent,
         fn ->
           %{count: 0, fail_on: MapSet.new([2, 4])}
         end}
      )

    exception_registry =
      {:via, Jido.Code.Skill.SkillRuntime.SignalDispatcherNthLookupVia, {registry, lookup_plan}}

    :sys.replace_state(dispatcher, fn state ->
      %{state | registry: exception_registry}
    end)

    assert :ok = SignalDispatcher.refresh(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_two"]

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_two",
               "after_call_exception_hook_defaults_refresh"
             )

    assert_receive {:action_ran, "after_call_exception_hook_defaults_refresh"}, 1_000
    assert_receive {:signal, pre_after_refresh}, 1_000
    assert pre_after_refresh.type == "skill.pre"
    assert pre_after_refresh.data["route"] == "demo/hook_two"
    assert_receive {:signal, post_after_refresh}, 1_000
    assert post_after_refresh.type == "skill.post"
    assert post_after_refresh.data["route"] == "demo/hook_two"

    assert :ok = publish_dispatch_signal(bus_name, "demo.hook_one", "old_hook_after_refresh")
    refute_receive {:action_ran, "old_hook_after_refresh"}, 200

    dispatcher_state = :sys.get_state(dispatcher)
    assert dispatcher_state.hook_defaults == cached_hook_defaults

    assert :ok = publish_registry_update_signal(bus_name)
    Process.sleep(50)

    assert Process.alive?(dispatcher)
    assert SignalDispatcher.routes(dispatcher) == ["demo.hook_two"]

    assert :ok =
             publish_dispatch_signal(
               bus_name,
               "demo.hook_two",
               "after_call_exception_hook_defaults_registry_update"
             )

    assert_receive {:action_ran, "after_call_exception_hook_defaults_registry_update"}, 1_000
    assert_receive {:signal, pre_after_registry_update}, 1_000
    assert pre_after_registry_update.type == "skill.pre"
    assert pre_after_registry_update.data["route"] == "demo/hook_two"
    assert_receive {:signal, post_after_registry_update}, 1_000
    assert post_after_registry_update.type == "skill.post"
    assert post_after_registry_update.data["route"] == "demo/hook_two"
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

    assert :ok =
             publish_dispatch_signal(bus_name, "demo.hook_one", "before_invalid_hook_defaults")

    assert_receive {:action_ran, "before_invalid_hook_defaults"}, 1_000
    assert_receive {:signal, pre_signal}, 1_000
    assert pre_signal.type == "skill.pre"
    assert pre_signal.data["route"] == "demo/hook_one"
    assert_receive {:signal, post_signal}, 1_000
    assert post_signal.type == "skill.post"
    assert post_signal.data["route"] == "demo/hook_one"

    assert :ok =
             SignalDispatcherTestRegistry.set_skills(registry, [
               hook_aware_dispatcher_skill_entry_two()
             ])

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
        - Jido.Code.Skill.DispatcherTestActions.Notify
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

  defp write_settings(path, permissions, opts) do
    pre_signal_type = Keyword.get(opts, :pre_signal_type, "skill/pre")
    post_signal_type = Keyword.get(opts, :post_signal_type, "skill/post")
    pre_enabled = Keyword.get(opts, :pre_enabled, true)
    post_enabled = Keyword.get(opts, :post_enabled, true)
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

  defp set_notify_pid! do
    :persistent_term.put({Jido.Code.Skill.DispatcherTestActions.Notify, :notify_pid}, self())

    on_exit(fn ->
      :persistent_term.erase({Jido.Code.Skill.DispatcherTestActions.Notify, :notify_pid})
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
      module: Jido.Code.Skill.DispatcherTestSkills.ValidRoute,
      permission_status: :allowed
    }
  end

  defp invalid_dispatcher_skill_entry do
    %{
      name: "invalid-route-skill",
      scope: :local,
      module: Jido.Code.Skill.DispatcherTestSkills.InvalidRoute,
      permission_status: :allowed
    }
  end

  defp valid_dispatcher_skill_entry_two do
    %{
      name: "valid-route-skill-two",
      scope: :local,
      module: Jido.Code.Skill.DispatcherTestSkills.ValidRouteTwo,
      permission_status: :allowed
    }
  end

  defp hook_aware_dispatcher_skill_entry do
    %{
      name: "hook-aware-route-skill",
      scope: :local,
      module: Jido.Code.Skill.DispatcherTestSkills.HookAwareRoute,
      permission_status: :allowed
    }
  end

  defp hook_aware_dispatcher_skill_entry_two do
    %{
      name: "hook-aware-route-skill-two",
      scope: :local,
      module: Jido.Code.Skill.DispatcherTestSkills.HookAwareRouteTwo,
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
