defmodule JidoSkill.Observability.SkillLifecycleSubscriber do
  @moduledoc """
  Subscribes to skill lifecycle and permission signals and emits telemetry.

  Phase 23 refreshes lifecycle subscriptions from registry metadata so
  frontmatter-defined hook signal types remain observable after reloads.
  """

  use GenServer

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoSkill.SkillRuntime.SkillRegistry

  require Logger

  @default_hook_signal_types ["skill/pre", "skill/post"]
  @permission_blocked_signal_type "skill/permission/blocked"
  @registry_update_signal_type "skill/registry/updated"

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    if is_nil(name) do
      GenServer.start_link(__MODULE__, opts)
    else
      GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @impl GenServer
  def init(opts) do
    bus_name = Keyword.fetch!(opts, :bus_name)
    registry = Keyword.get(opts, :registry)
    configured_hook_signal_types = hook_signal_types(opts)
    cached_hook_defaults = init_hook_defaults(registry)

    subscription_paths =
      target_subscription_paths(configured_hook_signal_types, registry, cached_hook_defaults)

    with {:ok, subscriptions} <- subscribe_paths(bus_name, %{}, subscription_paths),
         {:ok, registry_subscription} <- subscribe_registry_updates(bus_name, registry) do
      {:ok,
       %{
         bus_name: bus_name,
         registry: registry,
         configured_hook_signal_types: configured_hook_signal_types,
         cached_hook_defaults: cached_hook_defaults,
         subscriptions: subscriptions,
         registry_subscription: registry_subscription
       }}
    else
      {:error, reason} ->
        {:stop, {:subscription_failed, reason}}

      {:error, reason, _subscriptions_after_failure, _paths_added_before_failure} ->
        {:stop, {:subscription_failed, reason}}
    end
  end

  @impl GenServer
  def handle_info(
        {:signal, %Signal{type: "skill.registry.updated"}},
        %{registry: registry} = state
      )
      when not is_nil(registry) do
    case refresh_subscriptions(state) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("failed to refresh lifecycle subscriptions: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:signal, signal}, state) do
    emit_telemetry(signal, state.bus_name)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_message, state), do: {:noreply, state}

  defp subscribe(bus_name, path) do
    Bus.subscribe(bus_name, path, dispatch: {:pid, target: self(), delivery_mode: :async})
  end

  defp subscribe_paths(bus_name, subscriptions, paths) do
    paths
    |> Enum.reduce_while({:ok, subscriptions, []}, fn path, {:ok, acc, added_paths} ->
      case subscribe(bus_name, path) do
        {:ok, subscription} ->
          {:cont, {:ok, Map.put(acc, path, subscription), [path | added_paths]}}

        {:error, reason} ->
          {:halt, {:error, {:subscribe_failed, path, reason}, acc, added_paths}}
      end
    end)
    |> case do
      {:ok, updated_subscriptions, _added_paths} ->
        {:ok, updated_subscriptions}

      {:error, reason, updated_subscriptions, added_paths} ->
        {:error, reason, updated_subscriptions, added_paths}
    end
  end

  defp hook_signal_types(opts) do
    fallback? = Keyword.get(opts, :fallback_to_default_hook_signal_types, true)

    case Keyword.fetch(opts, :hook_signal_types) do
      {:ok, signal_types} when is_list(signal_types) ->
        signal_types
        |> Enum.map(&normalize_configured_signal_type/1)
        |> Enum.reject(&is_nil/1)
        |> maybe_fallback_default_hook_signal_types(fallback?)

      {:ok, _invalid} ->
        @default_hook_signal_types

      :error ->
        @default_hook_signal_types
    end
  end

  defp maybe_fallback_default_hook_signal_types([], true), do: @default_hook_signal_types
  defp maybe_fallback_default_hook_signal_types([], false), do: []
  defp maybe_fallback_default_hook_signal_types(signal_types, _fallback?), do: signal_types

  defp normalize_configured_signal_type(type) when is_binary(type) do
    type
    |> String.trim()
    |> case do
      "" ->
        nil

      value ->
        if valid_configured_signal_type?(value) do
          value
        else
          nil
        end
    end
  end

  defp normalize_configured_signal_type(_invalid), do: nil

  defp valid_configured_signal_type?(type) do
    Regex.match?(~r/^[a-z0-9_]+(?:[\/.][a-z0-9_]+)*$/, type)
  end

  defp normalize_signal_type(type) when is_binary(type) do
    type
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_signal_type(_invalid), do: nil

  defp target_subscription_paths(configured_hook_signal_types, registry, hook_defaults) do
    registry_hook_signal_types = registry_hook_signal_types_for_init(registry, hook_defaults)
    build_target_subscription_paths(configured_hook_signal_types, registry_hook_signal_types)
  end

  defp target_subscription_paths_for_refresh(configured_hook_signal_types, registry, hook_defaults) do
    with {:ok, registry_hook_signal_types} <-
           registry_hook_signal_types_for_refresh(registry, hook_defaults) do
      {:ok, build_target_subscription_paths(configured_hook_signal_types, registry_hook_signal_types)}
    end
  end

  defp build_target_subscription_paths(configured_hook_signal_types, registry_hook_signal_types) do
    configured_hook_signal_types
    |> Kernel.++(registry_hook_signal_types)
    |> Kernel.++([@permission_blocked_signal_type])
    |> Enum.map(&normalize_path/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp subscribe_registry_updates(_bus_name, nil), do: {:ok, nil}

  defp subscribe_registry_updates(bus_name, _registry) do
    subscribe(bus_name, normalize_path(@registry_update_signal_type))
  end

  defp refresh_subscriptions(state) do
    {hook_defaults, cached_hook_defaults, hook_defaults_refresh_error} =
      resolve_refresh_hook_defaults(state.registry, state.cached_hook_defaults)

    log_hook_defaults_refresh_error(hook_defaults_refresh_error)

    with {:ok, target_paths} <-
           target_subscription_paths_for_refresh(
             state.configured_hook_signal_types,
             state.registry,
             hook_defaults
           ) do
      current_paths = Map.keys(state.subscriptions) |> MapSet.new()
      target_path_set = MapSet.new(target_paths)

      paths_to_remove = MapSet.difference(current_paths, target_path_set) |> MapSet.to_list()
      paths_to_add = MapSet.difference(target_path_set, current_paths) |> MapSet.to_list()

      case subscribe_paths(state.bus_name, state.subscriptions, paths_to_add) do
        {:ok, after_subscribe} ->
          after_sync = unsubscribe_paths(state.bus_name, after_subscribe, paths_to_remove)
          {:ok, %{state | subscriptions: after_sync, cached_hook_defaults: cached_hook_defaults}}

        {:error, reason, subscriptions_after_failure, paths_added_before_failure} ->
          _rolled_back =
            rollback_subscriptions(
              state.bus_name,
              subscriptions_after_failure,
              paths_added_before_failure
            )

          {:error, reason}
      end
    end
  end

  defp unsubscribe_paths(bus_name, subscriptions, paths) do
    Enum.reduce(paths, subscriptions, &unsubscribe_path(bus_name, &2, &1))
  end

  defp unsubscribe_path(bus_name, subscriptions, path) do
    case Map.pop(subscriptions, path) do
      {nil, updated} ->
        updated

      {subscription_id, updated} ->
        maybe_unsubscribe(bus_name, path, subscription_id)
        updated
    end
  end

  defp maybe_unsubscribe(bus_name, path, subscription_id) do
    case Bus.unsubscribe(bus_name, subscription_id) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "failed to unsubscribe lifecycle path #{path} (#{subscription_id}): #{inspect(reason)}"
        )
    end
  end

  defp rollback_subscriptions(bus_name, subscriptions, paths) do
    unsubscribe_paths(bus_name, subscriptions, paths)
  end

  defp init_hook_defaults(nil), do: %{}

  defp init_hook_defaults(registry) do
    case safe_hook_defaults(registry) do
      {:ok, hook_defaults} -> hook_defaults
      {:error, _reason} -> %{}
    end
  end

  defp resolve_refresh_hook_defaults(registry, current_hook_defaults) do
    case safe_hook_defaults(registry) do
      {:ok, hook_defaults} ->
        {hook_defaults, hook_defaults, nil}

      {:error, reason} ->
        {current_hook_defaults, current_hook_defaults, reason}
    end
  end

  defp log_hook_defaults_refresh_error(nil), do: :ok

  defp log_hook_defaults_refresh_error(reason) do
    Logger.warning(
      "failed to refresh lifecycle hook defaults; keeping cached defaults: #{inspect(reason)}"
    )
  end

  defp registry_hook_signal_types_for_init(nil, _hook_defaults), do: []

  defp registry_hook_signal_types_for_init(registry, hook_defaults) do
    case safe_list_skills(registry, :empty) do
      {:ok, skills} -> normalize_registry_hook_signal_types(skills, hook_defaults)
      {:error, _reason} -> []
    end
  end

  defp registry_hook_signal_types_for_refresh(nil, _hook_defaults), do: {:ok, []}

  defp registry_hook_signal_types_for_refresh(registry, hook_defaults) do
    with {:ok, skills} <- safe_list_skills(registry, :error) do
      {:ok, normalize_registry_hook_signal_types(skills, hook_defaults)}
    end
  end

  defp normalize_registry_hook_signal_types(skills, hook_defaults) do
    skills
    |> Enum.flat_map(&skill_hook_signal_types(&1, hook_defaults))
    |> Enum.map(&normalize_signal_type/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp safe_list_skills(registry, mode) do
    {:ok, SkillRegistry.list_skills(registry)}
  rescue
    error ->
      handle_registry_read_error({:list_skills_exception, error}, mode, [])
  catch
    :exit, reason ->
      handle_registry_read_error({:list_skills_exit, reason}, mode, [])

    kind, reason ->
      handle_registry_read_error({:list_skills_error, {kind, reason}}, mode, [])
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

  defp handle_registry_read_error(_reason, :empty, fallback), do: {:ok, fallback}
  defp handle_registry_read_error(reason, :error, _fallback),
    do: {:error, {:registry_read_failed, reason}}

  defp skill_hook_signal_types(%{module: module}, hook_defaults) when is_atom(module) do
    if function_exported?(module, :skill_metadata, 0) do
      module
      |> then(& &1.skill_metadata())
      |> Map.get(:hooks, %{})
      |> hook_signal_types_from_metadata(hook_defaults)
    else
      []
    end
  rescue
    _error ->
      []
  catch
    _kind, _reason ->
      []
  end

  defp skill_hook_signal_types(_skill, _hook_defaults), do: []

  defp hook_signal_types_from_metadata(hooks, hook_defaults) when is_map(hooks) do
    [:pre, :post]
    |> Enum.map(&hook_signal_type(hooks, hook_defaults, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp hook_signal_types_from_metadata(_hooks, _hook_defaults), do: []

  defp hook_signal_type(hooks, hook_defaults, key) do
    hook = map_get_optional(hooks, key)
    global_hook = map_get_optional(hook_defaults, key)

    case hook do
      map when is_map(map) ->
        if effective_hook_enabled?(map, global_hook) do
          map_get_optional(map, :signal_type) || map_get_optional(global_hook, :signal_type)
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp effective_hook_enabled?(hook, global_hook) do
    case map_get_optional(hook, :enabled) do
      true -> true
      false -> false
      nil -> hook_enabled?(global_hook)
    end
  end

  defp hook_enabled?(hook) do
    case map_get_optional(hook, :enabled) do
      false -> false
      _ -> true
    end
  end

  defp map_get_optional(map, key) when is_map(map) do
    cond do
      Map.has_key?(map, key) ->
        Map.get(map, key)

      Map.has_key?(map, Atom.to_string(key)) ->
        Map.get(map, Atom.to_string(key))

      true ->
        nil
    end
  end

  defp map_get_optional(_invalid, _key), do: nil

  defp normalize_path(path) when is_binary(path), do: String.replace(path, "/", ".")
  defp normalize_path(_invalid), do: nil

  defp emit_telemetry(signal, bus_name) do
    data = ensure_map(signal.data)

    :telemetry.execute(
      [:jido_skill, :skill, :lifecycle],
      %{count: 1},
      %{
        type: signal.type,
        source: signal_source(signal),
        data: data,
        bus: bus_name,
        timestamp: lifecycle_value(data, :timestamp),
        phase: lifecycle_value(data, :phase),
        skill_name: lifecycle_value(data, :skill_name),
        route: lifecycle_value(data, :route),
        status: lifecycle_value(data, :status),
        reason: lifecycle_value(data, :reason),
        tools: lifecycle_value(data, :tools)
      }
    )
  end

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}

  defp signal_source(%{source: source}) when is_binary(source), do: source
  defp signal_source(%{"source" => source}) when is_binary(source), do: source
  defp signal_source(_signal), do: nil

  defp lifecycle_value(data, key) do
    Map.get(data, key) || Map.get(data, Atom.to_string(key))
  end
end
