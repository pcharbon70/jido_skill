defmodule JidoSkill.SkillRuntime.SignalDispatcher do
  @moduledoc """
  Subscribes to compiled skill routes on the signal bus and dispatches matching
  signals to skill modules for execution.

  Phase 10 responsibilities:
  - subscribe to all discovered skill routes
  - refresh route subscriptions when the skill registry changes
  - execute generated instructions with `Jido.Exec`
  - run `transform_result/3` and publish emitted signals
  """

  use GenServer

  alias Jido.Instruction
  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoSkill.SkillRuntime.SkillRegistry

  require Logger

  @type route_handlers :: %{optional(String.t()) => [map()]}

  @type t :: %{
          bus_name: atom() | String.t(),
          registry: GenServer.server(),
          registry_subscription: String.t() | nil,
          route_subscriptions: %{optional(String.t()) => String.t()},
          route_handlers: route_handlers()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    if is_nil(name) do
      GenServer.start_link(__MODULE__, opts)
    else
      GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec routes() :: [String.t()]
  def routes, do: routes(__MODULE__)

  @spec routes(GenServer.server()) :: [String.t()]
  def routes(server), do: GenServer.call(server, :routes)

  @spec refresh() :: :ok
  def refresh, do: refresh(__MODULE__)

  @spec refresh(GenServer.server()) :: :ok
  def refresh(server), do: GenServer.call(server, :refresh)

  @impl GenServer
  def init(opts) do
    bus_name = Keyword.fetch!(opts, :bus_name)
    registry = Keyword.get(opts, :registry, SkillRegistry)

    initial_state = %{
      bus_name: bus_name,
      registry: registry,
      registry_subscription: nil,
      route_subscriptions: %{},
      route_handlers: %{}
    }

    with {:ok, registry_subscription} <-
           subscribe(bus_name, normalize_path("skill/registry/updated")),
         {:ok, refreshed_state} <-
           refresh_state(%{initial_state | registry_subscription: registry_subscription}) do
      {:ok, refreshed_state}
    else
      {:error, reason} ->
        {:stop, {:startup_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call(:routes, _from, state) do
    {:reply, state.route_handlers |> Map.keys() |> Enum.sort(), state}
  end

  @impl GenServer
  def handle_call(:refresh, _from, state) do
    case refresh_state(state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:signal, %Signal{type: "skill.registry.updated"}}, state) do
    case refresh_state(state) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning(
          "failed to refresh route subscriptions after registry update: #{inspect(reason)}"
        )

        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:signal, %Signal{} = signal}, state) do
    dispatch_signal(signal, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_message, state), do: {:noreply, state}

  defp refresh_state(state) do
    handlers = build_route_handlers(state.registry)
    target_routes = Map.keys(handlers)

    with {:ok, route_subscriptions} <-
           sync_route_subscriptions(
             state.bus_name,
             state.route_subscriptions,
             target_routes
           ) do
      {:ok,
       %{
         state
         | route_subscriptions: route_subscriptions,
           route_handlers: handlers
       }}
    end
  end

  defp build_route_handlers(registry) do
    raw_handlers =
      registry
      |> SkillRegistry.list_skills()
      |> Enum.reduce(%{}, fn skill, acc ->
        skill
        |> skill_routes()
        |> Enum.reduce(acc, fn route, route_acc ->
          normalized_route = normalize_path(route)
          Map.update(route_acc, normalized_route, [skill], &[skill | &1])
        end)
      end)

    Enum.into(raw_handlers, %{}, fn {route, skills} ->
      ordered_skills = Enum.sort_by(skills, &skill_priority/1)

      if length(ordered_skills) > 1 do
        skill_names = Enum.map_join(ordered_skills, ", ", &Map.get(&1, :name))

        Logger.warning(
          "multiple skills match route #{route}; using first match order: #{skill_names}"
        )
      end

      {route, ordered_skills}
    end)
  end

  defp skill_routes(%{module: module}) when is_atom(module) do
    if function_exported?(module, :skill_metadata, 0) do
      module.skill_metadata()
      |> Map.get(:router, [])
      |> Enum.map(fn {route, _action} -> route end)
    else
      []
    end
  rescue
    error ->
      Logger.warning("failed to load skill routes from #{inspect(module)}: #{inspect(error)}")
      []
  end

  defp skill_routes(_invalid), do: []

  defp skill_priority(skill) do
    scope_priority =
      case Map.get(skill, :scope) do
        :local -> 0
        _ -> 1
      end

    {scope_priority, Map.get(skill, :name, "")}
  end

  defp sync_route_subscriptions(bus_name, current_subscriptions, target_routes) do
    current_routes = Map.keys(current_subscriptions) |> MapSet.new()
    target_route_set = MapSet.new(target_routes)

    routes_to_remove = MapSet.difference(current_routes, target_route_set) |> MapSet.to_list()
    routes_to_add = MapSet.difference(target_route_set, current_routes) |> MapSet.to_list()

    unsubscribe_routes(bus_name, current_subscriptions, routes_to_remove)
    |> then(fn
      {:ok, after_unsubscribe} ->
        subscribe_routes(bus_name, after_unsubscribe, routes_to_add)

      {:error, reason} ->
        {:error, reason}
    end)
  end

  defp unsubscribe_routes(bus_name, subscriptions, routes) do
    Enum.reduce_while(routes, {:ok, subscriptions}, fn route, {:ok, acc} ->
      {:cont, {:ok, unsubscribe_route(bus_name, acc, route)}}
    end)
  end

  defp unsubscribe_route(bus_name, subscriptions, route) do
    case Map.pop(subscriptions, route) do
      {nil, new_subscriptions} ->
        new_subscriptions

      {subscription_id, new_subscriptions} ->
        case Bus.unsubscribe(bus_name, subscription_id) do
          :ok ->
            new_subscriptions

          {:error, reason} ->
            Logger.warning(
              "failed to unsubscribe route #{route} (#{subscription_id}): #{inspect(reason)}"
            )

            new_subscriptions
        end
    end
  end

  defp subscribe_routes(bus_name, subscriptions, routes) do
    Enum.reduce_while(routes, {:ok, subscriptions}, fn route, {:ok, acc} ->
      case subscribe(bus_name, route) do
        {:ok, subscription_id} ->
          {:cont, {:ok, Map.put(acc, route, subscription_id)}}

        {:error, reason} ->
          {:halt, {:error, {:route_subscribe_failed, route, reason}}}
      end
    end)
  end

  defp subscribe(bus_name, path) do
    Bus.subscribe(bus_name, path, dispatch: {:pid, target: self(), delivery_mode: :async})
  end

  defp dispatch_signal(signal, state) do
    handlers = Map.get(state.route_handlers, signal.type, [])
    global_hooks = safe_hook_defaults(state.registry)

    _dispatch_result =
      Enum.reduce_while(handlers, :unhandled, fn skill, _acc ->
        case dispatch_to_skill(skill, signal, global_hooks, state.bus_name) do
          :handled -> {:halt, :handled}
          :skip -> {:cont, :unhandled}
        end
      end)

    :ok
  end

  defp dispatch_to_skill(skill, signal, global_hooks, bus_name) do
    module = Map.get(skill, :module)
    skill_name = Map.get(skill, :name, inspect(module))

    case permission_status(skill) do
      :allowed ->
        dispatch_allowed_skill(module, skill_name, signal, global_hooks, bus_name)

      {:ask, tools} ->
        Logger.warning(
          "skill #{skill_name} requires approval for tools #{inspect(tools)}; skipping signal #{signal.type}"
        )

        :skip

      {:denied, tools} ->
        Logger.warning(
          "skill #{skill_name} denied by permissions for tools #{inspect(tools)}; skipping signal #{signal.type}"
        )

        :skip
    end
  end

  defp dispatch_allowed_skill(module, skill_name, signal, global_hooks, bus_name) do
    case safe_handle_signal(module, signal, global_hooks) do
      {:ok, %Instruction{} = instruction} ->
        result = Jido.Exec.run(instruction)
        run_transform_result(module, result, instruction, global_hooks, bus_name)
        :handled

      {:ok, other} ->
        Logger.warning(
          "skill #{skill_name} returned non-instruction payload from handle_signal: #{inspect(other)}"
        )

        :skip

      {:skip, _signal} ->
        :skip

      {:error, reason} ->
        Logger.warning(
          "skill #{skill_name} failed to handle signal #{signal.type}: #{inspect(reason)}"
        )

        :skip
    end
  end

  defp permission_status(skill) do
    Map.get(skill, :permission_status, :allowed)
  end

  defp safe_handle_signal(module, signal, global_hooks) when is_atom(module) do
    module.handle_signal(signal, global_hooks: global_hooks)
  rescue
    error ->
      {:error, {:handle_signal_exception, error}}
  catch
    kind, reason ->
      {:error, {:handle_signal_throw, kind, reason}}
  end

  defp safe_handle_signal(_module, _signal, _global_hooks), do: {:error, :invalid_skill_module}

  defp run_transform_result(module, result, instruction, global_hooks, bus_name) do
    case safe_transform_result(module, result, instruction, global_hooks) do
      {:ok, _transformed_result, emitted_signals} when is_list(emitted_signals) ->
        publish_emitted_signals(bus_name, emitted_signals)

      {:ok, _transformed_result, _invalid_emitted_signals} ->
        Logger.warning("skill #{inspect(module)} returned invalid emitted signal payload")

      {:error, reason} ->
        Logger.warning("skill #{inspect(module)} transform_result failed: #{inspect(reason)}")

      other ->
        Logger.warning(
          "skill #{inspect(module)} returned invalid transform_result: #{inspect(other)}"
        )
    end
  end

  defp safe_transform_result(module, result, instruction, global_hooks) do
    module.transform_result(result, instruction, global_hooks: global_hooks)
  rescue
    error ->
      {:error, {:transform_result_exception, error}}
  catch
    kind, reason ->
      {:error, {:transform_result_throw, kind, reason}}
  end

  defp publish_emitted_signals(_bus_name, []), do: :ok

  defp publish_emitted_signals(bus_name, signals) do
    {valid_signals, invalid_signals} = Enum.split_with(signals, &match?(%Signal{}, &1))

    if invalid_signals != [] do
      Logger.warning(
        "ignoring non-signal values emitted from transform_result: #{inspect(invalid_signals)}"
      )
    end

    case valid_signals do
      [] ->
        :ok

      to_publish ->
        case Bus.publish(bus_name, to_publish) do
          {:ok, _recorded} ->
            :ok

          {:error, reason} ->
            Logger.warning("failed publishing transform_result signals: #{inspect(reason)}")
            :ok
        end
    end
  end

  defp safe_hook_defaults(registry) do
    SkillRegistry.hook_defaults(registry)
  rescue
    _error ->
      %{}
  catch
    :exit, _reason ->
      %{}
  end

  defp normalize_path(path) when is_binary(path), do: String.replace(path, "/", ".")
  defp normalize_path(path), do: path
end
