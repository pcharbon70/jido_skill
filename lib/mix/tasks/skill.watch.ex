defmodule Mix.Tasks.Skill.Watch do
  @shortdoc "Watch skill signals on the Jido signal bus"

  @moduledoc """
  Subscribe to skill signal patterns from the terminal and stream events as JSON lines.

  By default this task subscribes to:

  - `skill.pre`
  - `skill.post`
  - `skill.permission.blocked`
  - `skill.registry.updated`

  ## Examples

      mix skill.watch
      mix skill.watch --pattern skill.pre --pattern skill.post --limit 20
      mix skill.watch --pattern skill.registry.updated --timeout 30000
  """

  use Mix.Task

  alias Jido.Code.Skill.Config
  alias Jido.Code.Skill.SkillRuntime.SkillRegistry
  alias Jido.Signal
  alias Jido.Signal.Bus

  @switches [
    pattern: :keep,
    bus: :string,
    registry: :string,
    timeout: :integer,
    limit: :integer,
    start_app: :boolean,
    pretty: :boolean
  ]
  @aliases [p: :pattern, b: :bus, r: :registry, t: :timeout, l: :limit]

  @default_patterns [
    "skill.pre",
    "skill.post",
    "skill.permission.blocked",
    "skill.registry.updated"
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches, aliases: @aliases)

    if positional != [] do
      Mix.raise("Unexpected positional arguments: #{Enum.join(positional, ", ")}")
    end

    if invalid != [] do
      invalid_flags =
        Enum.map_join(invalid, ", ", fn
          {key, _value} -> "--#{key}"
          key when is_atom(key) -> "--#{key}"
        end)

      Mix.raise("Unknown options: #{invalid_flags}")
    end

    start_app? = Keyword.get(opts, :start_app, true)
    pretty? = Keyword.get(opts, :pretty, true)
    registry = parse_registry(Keyword.get(opts, :registry, nil))
    bus = resolve_bus(Keyword.get(opts, :bus, nil), registry)
    patterns = parse_patterns(Keyword.get_values(opts, :pattern))
    timeout_ms = parse_timeout(Keyword.get(opts, :timeout, nil))
    limit = parse_limit(Keyword.get(opts, :limit, nil))

    if start_app? do
      Mix.Task.run("app.start")
    end

    case subscribe_patterns(bus, patterns) do
      {:ok, subscription_ids} ->
        try do
          print_json(
            %{
              "event" => "watch.started",
              "bus" => bus_to_string(bus),
              "patterns" => patterns,
              "timeout_ms" => timeout_ms,
              "limit" => limit
            },
            pretty?
          )

          {reason, count} = receive_loop(timeout_ms, limit, pretty?, 0, now_ms())

          print_json(
            %{
              "event" => "watch.completed",
              "reason" => reason,
              "count" => count
            },
            pretty?
          )
        after
          unsubscribe_all(bus, subscription_ids)
        end

      {:error, reason} ->
        Mix.raise("Failed to subscribe: #{inspect(reason)}")
    end
  end

  defp parse_registry(nil), do: SkillRegistry

  defp parse_registry(registry_name) when is_binary(registry_name) do
    registry_name
    |> String.trim()
    |> String.trim_leading(":")
    |> case do
      "" -> SkillRegistry
      normalized -> to_existing_atom!(normalized, "--registry")
    end
  end

  defp parse_registry(_invalid), do: SkillRegistry

  defp resolve_bus(nil, registry) do
    case safe_registry_bus_name(registry) do
      {:ok, bus_name} -> bus_name
      {:error, _reason} -> Config.signal_bus_name()
    end
  end

  defp resolve_bus(bus, _registry) when is_binary(bus) do
    bus
    |> normalize_optional_bus()
    |> case do
      nil -> Config.signal_bus_name()
      normalized -> normalized
    end
  end

  defp resolve_bus(bus, _registry) when is_atom(bus), do: bus
  defp resolve_bus(_invalid, _registry), do: Config.signal_bus_name()

  defp safe_registry_bus_name(registry) do
    {:ok, SkillRegistry.bus_name(registry)}
  rescue
    error ->
      {:error, {:exception, error}}
  catch
    :exit, reason ->
      {:error, {:exit, reason}}
  end

  defp normalize_optional_bus(bus) when is_binary(bus) do
    case String.trim(bus) do
      "" ->
        nil

      ":" <> atom_name ->
        to_existing_atom!(atom_name, "--bus")

      value ->
        case safe_to_existing_atom(value) do
          {:ok, atom_name} -> atom_name
          :error -> value
        end
    end
  end

  defp parse_patterns([]), do: @default_patterns

  defp parse_patterns(patterns) when is_list(patterns) do
    patterns
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> @default_patterns
      values -> values
    end
  end

  defp parse_timeout(nil), do: nil

  defp parse_timeout(timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0 do
    timeout_ms
  end

  defp parse_timeout(_timeout_ms), do: Mix.raise("--timeout must be a positive integer")

  defp parse_limit(nil), do: nil

  defp parse_limit(limit) when is_integer(limit) and limit > 0 do
    limit
  end

  defp parse_limit(_limit), do: Mix.raise("--limit must be a positive integer")

  defp subscribe_patterns(bus, patterns) do
    Enum.reduce_while(patterns, {:ok, []}, fn pattern, {:ok, subscription_ids} ->
      case Bus.subscribe(bus, pattern, dispatch: {:pid, target: self()}) do
        {:ok, subscription_id} ->
          {:cont, {:ok, [subscription_id | subscription_ids]}}

        {:error, reason} ->
          unsubscribe_all(bus, subscription_ids)
          {:halt, {:error, {:subscribe_failed, pattern, reason}}}
      end
    end)
    |> then(fn
      {:ok, subscription_ids} -> {:ok, Enum.reverse(subscription_ids)}
      {:error, reason} -> {:error, reason}
    end)
  end

  defp unsubscribe_all(_bus, []), do: :ok

  defp unsubscribe_all(bus, subscription_ids) do
    Enum.each(subscription_ids, fn subscription_id ->
      _ = Bus.unsubscribe(bus, subscription_id)
    end)
  end

  defp receive_loop(_timeout_ms, 0, _pretty?, count, _started_at), do: {"limit", count}

  defp receive_loop(timeout_ms, limit, pretty?, count, started_at) do
    case remaining_timeout(timeout_ms, started_at) do
      :timeout ->
        {"timeout", count}

      remaining ->
        receive do
          {:signal, %Signal{} = signal} ->
            print_json(
              %{
                "event" => "signal",
                "signal" => serialize_signal(signal)
              },
              pretty?
            )

            next_limit = decrement_limit(limit)
            receive_loop(timeout_ms, next_limit, pretty?, count + 1, started_at)
        after
          remaining ->
            {"timeout", count}
        end
    end
  end

  defp remaining_timeout(nil, _started_at), do: :infinity

  defp remaining_timeout(timeout_ms, started_at) when is_integer(timeout_ms) do
    elapsed = now_ms() - started_at
    remaining = timeout_ms - elapsed
    if remaining <= 0, do: :timeout, else: remaining
  end

  defp decrement_limit(nil), do: nil
  defp decrement_limit(limit) when is_integer(limit) and limit > 0, do: limit - 1

  defp serialize_signal(%Signal{} = signal) do
    %{
      "id" => signal.id,
      "type" => signal.type,
      "source" => signal.source,
      "data" => signal.data
    }
  end

  defp to_existing_atom!(value, option) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError ->
      Mix.raise("#{option} must reference an existing atom name (got: #{inspect(value)})")
  end

  defp safe_to_existing_atom(value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> :error
  end

  defp bus_to_string(bus) when is_atom(bus), do: Atom.to_string(bus)
  defp bus_to_string(bus), do: to_string(bus)

  defp print_json(payload, pretty?) do
    encoded =
      if pretty? do
        Jason.encode!(payload, pretty: true)
      else
        Jason.encode!(payload)
      end

    Mix.shell().info(encoded)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
