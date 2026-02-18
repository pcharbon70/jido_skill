defmodule JidoSkill.SkillRuntime.HookEmitter do
  @moduledoc """
  Emits optional pre/post skill lifecycle signals.

  This is a Phase 1 scaffold with the finalized public API and basic
  signal publishing behavior.
  """

  alias Jido.Signal
  alias Jido.Signal.Bus

  require Logger

  @spec emit_pre(module() | String.t(), String.t(), map() | nil, map() | nil) :: :ok
  def emit_pre(skill_name, route, frontmatter_hooks, global_hooks) do
    hook = resolve_hook(:pre, frontmatter_hooks, global_hooks)

    runtime_data = %{
      phase: "pre",
      skill_name: skill_name,
      route: route,
      timestamp: DateTime.utc_now()
    }

    emit(hook, runtime_data)
  end

  @spec emit_post(module() | String.t(), String.t(), String.t(), map() | nil, map() | nil) :: :ok
  def emit_post(skill_name, route, status, frontmatter_hooks, global_hooks) do
    hook = resolve_hook(:post, frontmatter_hooks, global_hooks)

    runtime_data = %{
      phase: "post",
      skill_name: skill_name,
      route: route,
      status: status,
      timestamp: DateTime.utc_now()
    }

    emit(hook, runtime_data)
  end

  defp emit(nil, _runtime_data), do: :ok
  defp emit(%{enabled: false}, _runtime_data), do: :ok

  defp emit(hook, runtime_data) do
    signal_type = hook |> Map.get(:signal_type) |> normalize_signal_type()
    data = Map.get(hook, :data, %{}) |> Map.merge(runtime_data)
    bus_name = hook |> Map.get(:bus, :jido_code_bus) |> normalize_bus_name()

    if is_nil(signal_type) do
      Logger.warning("hook configuration missing signal_type: #{inspect(hook)}")
      :ok
    else
      with {:ok, signal} <- Signal.new(signal_type, data, source: "/hooks/#{signal_type}"),
           {:ok, _recorded} <- Bus.publish(bus_name, [signal]) do
        :ok
      else
        {:error, reason} ->
          Logger.warning("failed to emit lifecycle hook signal: #{inspect(reason)}")
          :ok
      end
    end
  end

  defp resolve_hook(type, frontmatter_hooks, global_hooks) do
    Map.get(frontmatter_hooks || %{}, type) || Map.get(global_hooks || %{}, type)
  end

  defp normalize_bus_name(bus) when is_atom(bus), do: bus
  defp normalize_bus_name(":" <> bus), do: bus
  defp normalize_bus_name(bus), do: bus

  defp normalize_signal_type(nil), do: nil
  defp normalize_signal_type(type), do: String.replace(type, "/", ".")
end
