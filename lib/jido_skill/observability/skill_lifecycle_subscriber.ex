defmodule JidoSkill.Observability.SkillLifecycleSubscriber do
  @moduledoc """
  Subscribes to skill lifecycle and permission signals and emits telemetry.

  Phase 22 supports configurable lifecycle signal subscriptions derived from
  runtime hook settings.
  """

  use GenServer

  alias Jido.Signal.Bus

  @default_hook_signal_types ["skill/pre", "skill/post"]
  @permission_blocked_signal_type "skill/permission/blocked"

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

    lifecycle_paths =
      opts
      |> hook_signal_types()
      |> Enum.map(&normalize_path/1)
      |> Enum.reject(&is_nil/1)

    subscription_paths =
      lifecycle_paths
      |> Kernel.++([normalize_path(@permission_blocked_signal_type)])
      |> Enum.uniq()

    case subscribe_all(bus_name, subscription_paths) do
      {:ok, subscriptions} ->
        {:ok, %{bus_name: bus_name, subscriptions: subscriptions}}

      {:error, reason} ->
        {:stop, {:subscription_failed, reason}}
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

  defp subscribe_all(bus_name, paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, subscriptions} ->
      case subscribe(bus_name, path) do
        {:ok, subscription} ->
          {:cont, {:ok, [subscription | subscriptions]}}

        {:error, reason} ->
          {:halt, {:error, {:subscribe_failed, path, reason}}}
      end
    end)
    |> then(fn
      {:ok, subscriptions} -> {:ok, Enum.reverse(subscriptions)}
      {:error, reason} -> {:error, reason}
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
