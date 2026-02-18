defmodule JidoSkill.Observability.SkillLifecycleSubscriber do
  @moduledoc """
  Subscribes to skill lifecycle and permission signals and emits telemetry.

  Phase 8 enriches telemetry metadata with lifecycle fields and bus context.
  """

  use GenServer

  alias Jido.Signal.Bus

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

    with {:ok, pre_sub} <- subscribe(bus_name, normalize_path("skill/pre")),
         {:ok, post_sub} <- subscribe(bus_name, normalize_path("skill/post")),
         {:ok, permission_sub} <- subscribe(bus_name, normalize_path("skill/permission/blocked")) do
      {:ok, %{bus_name: bus_name, subscriptions: [pre_sub, post_sub, permission_sub]}}
    else
      {:error, reason} -> {:stop, {:subscription_failed, reason}}
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

  defp normalize_path(path), do: String.replace(path, "/", ".")

  defp emit_telemetry(signal, bus_name) do
    data = ensure_map(signal.data)

    :telemetry.execute(
      [:jido_skill, :skill, :lifecycle],
      %{count: 1},
      %{
        type: signal.type,
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

  defp lifecycle_value(data, key) do
    Map.get(data, key) || Map.get(data, Atom.to_string(key))
  end
end
