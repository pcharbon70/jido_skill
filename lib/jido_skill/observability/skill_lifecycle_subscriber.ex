defmodule JidoSkill.Observability.SkillLifecycleSubscriber do
  @moduledoc """
  Subscribes to skill lifecycle signals and emits telemetry.

  Phase 1 wires basic subscriptions so telemetry integration can be expanded
  in later phases.
  """

  use GenServer

  alias Jido.Signal.Bus

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    bus_name = Keyword.fetch!(opts, :bus_name)

    with {:ok, pre_sub} <- subscribe(bus_name, normalize_path("skill/pre")),
         {:ok, post_sub} <- subscribe(bus_name, normalize_path("skill/post")) do
      {:ok, %{bus_name: bus_name, subscriptions: [pre_sub, post_sub]}}
    else
      {:error, reason} -> {:stop, {:subscription_failed, reason}}
    end
  end

  @impl GenServer
  def handle_info({:signal, signal}, state) do
    emit_telemetry(signal)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_message, state), do: {:noreply, state}

  defp subscribe(bus_name, path) do
    Bus.subscribe(bus_name, path, dispatch: {:pid, target: self(), delivery_mode: :async})
  end

  defp normalize_path(path), do: String.replace(path, "/", ".")

  defp emit_telemetry(signal) do
    :telemetry.execute(
      [:jido_skill, :skill, :lifecycle],
      %{count: 1},
      %{type: signal.type, data: signal.data}
    )
  end
end
