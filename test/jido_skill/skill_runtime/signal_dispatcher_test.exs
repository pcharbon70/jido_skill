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

defmodule JidoSkill.SkillRuntime.SignalDispatcherTest do
  use ExUnit.Case, async: false

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoSkill.SkillRuntime.SignalDispatcher
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
           hook_defaults: hook_defaults(bus_name)
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
           hook_defaults: hook_defaults(bus_name)
         ]}
      )

    dispatcher =
      start_supervised!({SignalDispatcher, [name: nil, bus_name: bus_name, registry: registry]})

    assert SignalDispatcher.routes(dispatcher) == ["demo.one"]

    {:ok, non_matching_signal} =
      Signal.new("demo.two", %{"value" => "before_reload"},
        source: "/test/signal"
      )

    assert {:ok, _recorded} = Bus.publish(bus_name, [non_matching_signal])
    refute_receive {:action_ran, "before_reload"}, 200

    create_skill(local_root, "dispatcher-two", "demo/two", bus_name)
    assert :ok = SkillRegistry.reload(registry)

    assert_eventually(fn ->
      "demo.two" in SignalDispatcher.routes(dispatcher)
    end)

    {:ok, matching_signal} =
      Signal.new("demo.two", %{"value" => "after_reload"},
        source: "/test/signal"
      )

    assert {:ok, _recorded} = Bus.publish(bus_name, [matching_signal])
    assert_receive {:action_ran, "after_reload"}, 1_000
  end

  defp create_skill(root, skill_name, route, bus_name) do
    skill_dir = Path.join([root, "skills", skill_name])
    File.mkdir_p!(skill_dir)

    content = """
    ---
    name: #{skill_name}
    description: Dispatcher test skill #{skill_name}
    version: 1.0.0
    jido:
      actions:
        - JidoSkill.DispatcherTestActions.Notify
      router:
        - "#{route}": Notify
      hooks:
        pre:
          enabled: true
          signal_type: "skill/pre"
          bus: "#{bus_name}"
          data:
            source: "#{skill_name}"
        post:
          enabled: true
          signal_type: "skill/post"
          bus: "#{bus_name}"
          data:
            source: "#{skill_name}"
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
end
