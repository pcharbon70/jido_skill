defmodule JidoSkill.SkillRuntime.HookEmitter do
  @moduledoc """
  Emits optional pre/post skill lifecycle signals.

  Phase 5 behavior:
  - resolves hooks with frontmatter-over-global precedence
  - honors `enabled: false` short-circuit behavior
  - interpolates template data values using runtime variables
  - publishes normalized signal types on `Jido.Signal.Bus`
  """

  alias Jido.Signal
  alias Jido.Signal.Bus

  require Logger

  @runtime_template_keys ~w[phase skill_name route status timestamp]

  @spec emit_pre(module() | String.t(), String.t(), map() | nil, map() | nil) :: :ok
  def emit_pre(skill_name, route, frontmatter_hooks, global_hooks) do
    hook = resolve_hook(:pre, frontmatter_hooks, global_hooks)

    runtime_data = %{
      "phase" => "pre",
      "skill_name" => normalize_skill_name(skill_name),
      "route" => route,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    emit(hook, runtime_data)
  end

  @spec emit_post(module() | String.t(), String.t(), String.t(), map() | nil, map() | nil) :: :ok
  def emit_post(skill_name, route, status, frontmatter_hooks, global_hooks) do
    hook = resolve_hook(:post, frontmatter_hooks, global_hooks)

    runtime_data = %{
      "phase" => "post",
      "skill_name" => normalize_skill_name(skill_name),
      "route" => route,
      "status" => status,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    emit(hook, runtime_data)
  end

  defp emit(nil, _runtime_data), do: :ok
  defp emit(%{enabled: false}, _runtime_data), do: :ok

  defp emit(hook, runtime_data) do
    configured_signal_type = Map.get(hook, :signal_type)
    signal_type = normalize_signal_type(configured_signal_type)
    source_signal_type = normalize_signal_source_type(configured_signal_type)
    bus_name = hook |> Map.get(:bus, :jido_code_bus) |> normalize_bus_name()

    payload =
      hook
      |> Map.get(:data, %{})
      |> interpolate_template(runtime_data)
      |> Map.merge(runtime_data)

    if is_nil(signal_type) do
      Logger.warning("hook configuration missing signal_type: #{inspect(hook)}")
      :ok
    else
      with {:ok, signal} <-
             Signal.new(signal_type, payload, source: "/hooks/#{source_signal_type}"),
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
    global = get_hook(global_hooks, type)
    frontmatter = get_hook(frontmatter_hooks, type)

    case {normalize_hook(global), normalize_hook(frontmatter)} do
      {nil, nil} -> nil
      {global_hook, nil} -> finalize_hook(global_hook)
      {global_hook, frontmatter_hook} -> merge_hooks(global_hook, frontmatter_hook)
    end
  end

  defp get_hook(nil, _type), do: nil

  defp get_hook(hooks, type) do
    Map.get(hooks, type) || Map.get(hooks, to_string(type))
  end

  defp normalize_hook(nil), do: nil

  defp normalize_hook(hook) when is_map(hook) do
    enabled = map_get_optional(hook, :enabled)
    signal_type = map_get_optional(hook, :signal_type)
    bus = map_get_optional(hook, :bus)

    data =
      hook
      |> map_get_optional(:data)
      |> fallback(map_get_optional(hook, :data_template))
      |> ensure_map()

    %{
      enabled: enabled,
      signal_type: signal_type,
      bus: bus,
      data: data
    }
  end

  defp merge_hooks(_global_hook, %{enabled: false}), do: %{enabled: false}

  defp merge_hooks(global_hook, frontmatter_hook) do
    merged = %{
      enabled:
        Map.get(frontmatter_hook, :enabled) |> fallback(Map.get(global_hook || %{}, :enabled)),
      signal_type:
        Map.get(frontmatter_hook, :signal_type)
        |> fallback(Map.get(global_hook || %{}, :signal_type)),
      bus: Map.get(frontmatter_hook, :bus) |> fallback(Map.get(global_hook || %{}, :bus)),
      data:
        Map.merge(Map.get(global_hook || %{}, :data, %{}), Map.get(frontmatter_hook, :data, %{}))
    }

    finalize_hook(merged)
  end

  defp interpolate_template(data, runtime_data) when is_map(data) do
    Enum.into(data, %{}, fn {key, value} ->
      {key, interpolate_value(value, runtime_data)}
    end)
  end

  defp interpolate_value(value, runtime_data) when is_binary(value) do
    Enum.reduce(@runtime_template_keys, value, fn key, acc ->
      String.replace(acc, "{{#{key}}}", Map.get(runtime_data, key, ""))
    end)
  end

  defp interpolate_value(value, _runtime_data), do: value

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_invalid), do: %{}

  defp finalize_hook(nil), do: nil
  defp finalize_hook(%{enabled: false}), do: %{enabled: false}

  defp finalize_hook(hook) do
    %{
      enabled: Map.get(hook, :enabled, true),
      signal_type: Map.get(hook, :signal_type),
      bus: Map.get(hook, :bus, :jido_code_bus),
      data: Map.get(hook, :data, %{})
    }
  end

  defp map_get_optional(map, key) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, Atom.to_string(key)) -> Map.get(map, Atom.to_string(key))
      true -> nil
    end
  end

  defp fallback(nil, default), do: default
  defp fallback(value, _default), do: value

  defp normalize_skill_name(skill_name) when is_binary(skill_name), do: skill_name

  defp normalize_skill_name(skill_name),
    do: skill_name |> to_string() |> String.trim_leading("Elixir.")

  defp normalize_bus_name(bus) when is_atom(bus), do: bus

  defp normalize_bus_name(":" <> bus) do
    case safe_to_existing_atom(bus) do
      {:ok, atom_bus} -> atom_bus
      :error -> bus
    end
  end

  defp normalize_bus_name(bus), do: bus

  defp normalize_signal_type(nil), do: nil
  defp normalize_signal_type(type), do: String.replace(type, "/", ".")

  defp normalize_signal_source_type(nil), do: nil
  defp normalize_signal_source_type(type), do: String.replace(type, ".", "/")

  defp safe_to_existing_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> :error
  end
end
