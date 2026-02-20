defmodule JidoSkill.SkillRuntime.SignalDispatcher do
  @moduledoc """
  Subscribes to compiled skill routes on the signal bus and dispatches matching
  signals to skill modules for execution.

  Phase 10 responsibilities:
  - subscribe to all discovered skill routes
  - refresh route subscriptions when the skill registry changes
  - execute generated instructions with `Jido.Exec`
  - run `transform_result/3` and publish emitted signals
  - emit permission-blocked signals for `ask` and `denied` decisions
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
          hook_defaults: map(),
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
      hook_defaults: %{},
      route_subscriptions: %{},
      route_handlers: %{}
    }

    with {:ok, registry_subscription} <-
           subscribe(bus_name, normalize_path("skill/registry/updated")),
         {:ok, refreshed_state} <-
           init_state_with_route_fallback(%{
             initial_state
             | registry_subscription: registry_subscription
           }) do
      {:ok, refreshed_state}
    else
      {:error, reason} ->
        {:stop, {:startup_failed, reason}}
    end
  end

  defp init_state_with_route_fallback(state) do
    case refresh_state(state, :empty) do
      {:ok, refreshed_state} ->
        {:ok, refreshed_state}

      {:error, {:route_subscribe_failed, _route, _subscribe_reason} = reason} ->
        Logger.warning(
          "failed to initialize dispatcher route subscriptions; continuing with empty routes: #{inspect(reason)}"
        )

        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl GenServer
  def handle_call(:routes, _from, state) do
    {:reply, state.route_handlers |> Map.keys() |> Enum.sort(), state}
  end

  @impl GenServer
  def handle_call(:refresh, _from, state) do
    case refresh_state(state, :error) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:signal, %Signal{type: "skill.registry.updated"}}, state) do
    case refresh_state(state, :error) do
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

  defp refresh_state(state, mode) do
    with {:ok, handlers} <- build_route_handlers(state.registry, mode),
         target_routes = Map.keys(handlers),
         {:ok, route_subscriptions} <-
           sync_route_subscriptions(
             state.bus_name,
             state.route_subscriptions,
             target_routes
           ) do
      {hook_defaults, hook_defaults_refresh_error} =
        resolve_hook_defaults(state.registry, state.hook_defaults)

      log_hook_defaults_refresh_error(hook_defaults_refresh_error, mode)

      {:ok,
       %{
         state
         | hook_defaults: hook_defaults,
           route_subscriptions: route_subscriptions,
           route_handlers: handlers
       }}
    end
  end

  defp build_route_handlers(registry, mode) do
    with {:ok, skills} <- safe_list_skills(registry, mode) do
      raw_handlers =
        skills
        |> Enum.reduce(%{}, &accumulate_skill_routes/2)

      handlers =
        Enum.into(raw_handlers, %{}, fn {route, skills} ->
          {route, order_route_skills(route, skills)}
        end)

      {:ok, handlers}
    end
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

  defp accumulate_skill_routes(skill, route_handlers) do
    skill
    |> skill_routes()
    |> Enum.reduce(route_handlers, fn route, route_acc ->
      add_route_handler(route_acc, route, skill)
    end)
  end

  defp add_route_handler(route_handlers, route, skill) do
    normalized_route = normalize_path(route)
    Map.update(route_handlers, normalized_route, [skill], &[skill | &1])
  end

  defp skill_priority(skill) do
    scope_priority =
      case Map.get(skill, :scope) do
        :local -> 0
        _ -> 1
      end

    {scope_priority, Map.get(skill, :name, "")}
  end

  defp order_route_skills(route, skills) do
    ordered_skills = Enum.sort_by(skills, &skill_priority/1)
    log_route_conflict(route, ordered_skills)
    ordered_skills
  end

  defp log_route_conflict(route, ordered_skills) do
    if length(ordered_skills) > 1 do
      skill_names = Enum.map_join(ordered_skills, ", ", &Map.get(&1, :name))

      Logger.warning(
        "multiple skills match route #{route}; using first match order: #{skill_names}"
      )
    end
  end

  defp sync_route_subscriptions(bus_name, current_subscriptions, target_routes) do
    current_routes = Map.keys(current_subscriptions) |> MapSet.new()
    target_route_set = MapSet.new(target_routes)

    routes_to_remove = MapSet.difference(current_routes, target_route_set) |> MapSet.to_list()
    routes_to_add = MapSet.difference(target_route_set, current_routes) |> MapSet.to_list()

    case subscribe_routes(bus_name, current_subscriptions, routes_to_add) do
      {:ok, after_subscribe} ->
        after_sync = unsubscribe_routes(bus_name, after_subscribe, routes_to_remove)
        {:ok, after_sync}

      {:error, reason, subscriptions_after_failure, routes_added_before_failure} ->
        _rolled_back =
          rollback_route_subscriptions(
            bus_name,
            subscriptions_after_failure,
            routes_added_before_failure
          )

        {:error, reason}
    end
  end

  defp unsubscribe_routes(bus_name, subscriptions, routes) do
    Enum.reduce(routes, subscriptions, &unsubscribe_route(bus_name, &2, &1))
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
    routes
    |> Enum.reduce_while({:ok, subscriptions, []}, fn route, {:ok, acc, added_routes} ->
      case subscribe(bus_name, route) do
        {:ok, subscription_id} ->
          {:cont, {:ok, Map.put(acc, route, subscription_id), [route | added_routes]}}

        {:error, reason} ->
          {:halt, {:error, {:route_subscribe_failed, route, reason}, acc, added_routes}}
      end
    end)
    |> case do
      {:ok, updated_subscriptions, _added_routes} ->
        {:ok, updated_subscriptions}

      {:error, reason, updated_subscriptions, added_routes} ->
        {:error, reason, updated_subscriptions, added_routes}
    end
  end

  defp subscribe(bus_name, path) do
    Bus.subscribe(bus_name, path, dispatch: {:pid, target: self(), delivery_mode: :async})
  end

  defp rollback_route_subscriptions(bus_name, subscriptions, added_routes) do
    unsubscribe_routes(bus_name, subscriptions, added_routes)
  end

  defp dispatch_signal(signal, state) do
    handlers = Map.get(state.route_handlers, signal.type, [])
    global_hooks = Map.get(state, :hook_defaults, %{})

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
        emit_permission_blocked_signal(
          bus_name,
          skill_name,
          signal.type,
          "ask",
          tools
        )

        Logger.warning(
          "skill #{skill_name} requires approval for tools #{inspect(tools)}; skipping signal #{signal.type}"
        )

        :skip

      {:denied, tools} ->
        emit_permission_blocked_signal(
          bus_name,
          skill_name,
          signal.type,
          "denied",
          tools
        )

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

  defp emit_permission_blocked_signal(bus_name, skill_name, route, reason, tools) do
    source_signal_type = "skill/permission/blocked"
    signal_type = normalize_path("skill/permission/blocked")

    payload = %{
      "skill_name" => skill_name,
      "route" => normalize_route(route),
      "reason" => reason,
      "tools" => normalize_tools(tools),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    with {:ok, signal} <-
           Signal.new(signal_type, payload, source: "/permissions/#{source_signal_type}"),
         {:ok, _recorded} <- Bus.publish(bus_name, [signal]) do
      :ok
    else
      {:error, reason} ->
        Logger.warning(
          "failed to emit permission blocked signal for #{skill_name}: #{inspect(reason)}"
        )

        :ok
    end
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
    case GenServer.call(registry, :hook_defaults) do
      hook_defaults when is_map(hook_defaults) ->
        {:ok, hook_defaults}

      other ->
        {:error, {:hook_defaults_failed, {:invalid_result, other}}}
    end
  rescue
    error ->
      {:error, {:hook_defaults_failed, {:exception, error}}}
  catch
    :exit, reason ->
      {:error, {:hook_defaults_failed, {:exit, reason}}}

    kind, reason ->
      {:error, {:hook_defaults_failed, {kind, reason}}}
  end

  defp resolve_hook_defaults(registry, current_hook_defaults) do
    case safe_hook_defaults(registry) do
      {:ok, hook_defaults} ->
        {hook_defaults, nil}

      {:error, reason} ->
        {current_hook_defaults, reason}
    end
  end

  defp log_hook_defaults_refresh_error(nil, _mode), do: :ok

  defp log_hook_defaults_refresh_error(reason, :empty) do
    Logger.warning(
      "failed to load dispatcher hook defaults during startup; continuing with empty defaults: #{inspect(reason)}"
    )
  end

  defp log_hook_defaults_refresh_error(reason, :error) do
    Logger.warning(
      "failed to refresh hook defaults; keeping cached defaults: #{inspect(reason)}"
    )
  end

  defp safe_list_skills(registry, mode) do
    case GenServer.call(registry, :list_skills) do
      skills when is_list(skills) ->
        {:ok, skills}

      other ->
        handle_list_skills_read_error({:invalid_result, other}, mode, [])
    end
  rescue
    error ->
      handle_list_skills_read_error({:exception, error}, mode, [])
  catch
    :exit, reason ->
      handle_list_skills_read_error({:exit, reason}, mode, [])

    kind, reason ->
      handle_list_skills_read_error({kind, reason}, mode, [])
  end

  defp handle_list_skills_read_error(reason, :empty, fallback) do
    Logger.warning(
      "failed to load dispatcher routes during startup; continuing with empty routes: #{inspect(reason)}"
    )

    {:ok, fallback}
  end

  defp handle_list_skills_read_error(reason, :error, _fallback),
    do: {:error, {:list_skills_failed, reason}}

  defp normalize_route(route) when is_binary(route), do: String.replace(route, ".", "/")
  defp normalize_route(route), do: route

  defp normalize_tools(nil), do: []
  defp normalize_tools(tools) when is_list(tools), do: Enum.map(tools, &to_string/1)
  defp normalize_tools(tool), do: [to_string(tool)]

  defp normalize_path(path) when is_binary(path), do: String.replace(path, "/", ".")
  defp normalize_path(path), do: path
end
