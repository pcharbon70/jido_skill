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
    subscription_paths = target_subscription_paths(configured_hook_signal_types, registry)

    with {:ok, subscriptions} <- subscribe_paths(bus_name, %{}, subscription_paths),
         {:ok, registry_subscription} <- subscribe_registry_updates(bus_name, registry) do
      {:ok,
       %{
         bus_name: bus_name,
         registry: registry,
         configured_hook_signal_types: configured_hook_signal_types,
         subscriptions: subscriptions,
         registry_subscription: registry_subscription
       }}
    else
      {:error, reason} ->
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
    Enum.reduce_while(paths, {:ok, subscriptions}, fn path, {:ok, acc} ->
      case subscribe(bus_name, path) do
        {:ok, subscription} ->
          {:cont, {:ok, Map.put(acc, path, subscription)}}

        {:error, reason} ->
          {:halt, {:error, {:subscribe_failed, path, reason}}}
      end
    end)
  end

  defp hook_signal_types(opts) do
    case Keyword.get(opts, :hook_signal_types, @default_hook_signal_types) do
      signal_types when is_list(signal_types) ->
        signal_types
        |> Enum.map(&normalize_signal_type/1)
        |> Enum.reject(&is_nil/1)
        |> case do
          [] -> @default_hook_signal_types
          normalized -> normalized
        end

      _invalid ->
        @default_hook_signal_types
    end
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

  defp target_subscription_paths(configured_hook_signal_types, registry) do
    configured_hook_signal_types
    |> Kernel.++(registry_hook_signal_types(registry))
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
    target_paths = target_subscription_paths(state.configured_hook_signal_types, state.registry)
    current_paths = Map.keys(state.subscriptions) |> MapSet.new()
    target_path_set = MapSet.new(target_paths)

    paths_to_remove = MapSet.difference(current_paths, target_path_set) |> MapSet.to_list()
    paths_to_add = MapSet.difference(target_path_set, current_paths) |> MapSet.to_list()

    remaining_subscriptions =
      unsubscribe_paths(state.bus_name, state.subscriptions, paths_to_remove)

    case subscribe_paths(state.bus_name, remaining_subscriptions, paths_to_add) do
      {:ok, subscriptions} ->
        {:ok, %{state | subscriptions: subscriptions}}

      {:error, reason} ->
        {:error, reason}
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

  defp registry_hook_signal_types(nil), do: []

  defp registry_hook_signal_types(registry) do
    registry
    |> safe_list_skills()
    |> Enum.flat_map(&skill_hook_signal_types/1)
    |> Enum.map(&normalize_signal_type/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp safe_list_skills(registry) do
    SkillRegistry.list_skills(registry)
  rescue
    _error ->
      []
  catch
    :exit, _reason ->
      []
  end

  defp skill_hook_signal_types(%{module: module}) when is_atom(module) do
    if function_exported?(module, :skill_metadata, 0) do
      module
      |> then(& &1.skill_metadata())
      |> Map.get(:hooks, %{})
      |> hook_signal_types_from_metadata()
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

  defp skill_hook_signal_types(_skill), do: []

  defp hook_signal_types_from_metadata(hooks) when is_map(hooks) do
    [:pre, :post]
    |> Enum.map(&hook_signal_type(hooks, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp hook_signal_types_from_metadata(_hooks), do: []

  defp hook_signal_type(hooks, key) do
    hook = Map.get(hooks, key) || Map.get(hooks, Atom.to_string(key))

    case hook do
      map when is_map(map) ->
        Map.get(map, :signal_type) || Map.get(map, "signal_type")

      _ ->
        nil
    end
  end

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
