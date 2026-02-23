defmodule Mix.Tasks.Skill.Signal do
  @shortdoc "Publish a skill signal on the Jido signal bus"

  @moduledoc """
  Publish skill signals from the terminal.

  ## Examples

      mix skill.signal skill.pre --data '{"skill_name":"pdf-processor","route":"pdf/extract/text"}'
      mix skill.signal custom.health.check --data '{"status":"ok"}' --source /ops/health --no-pretty
  """

  use Mix.Task

  alias Jido.Code.Skill.Config
  alias Jido.Code.Skill.SkillRuntime.SkillRegistry
  alias Jido.Signal
  alias Jido.Signal.Bus

  @switches [
    data: :string,
    source: :string,
    bus: :string,
    registry: :string,
    start_app: :boolean,
    pretty: :boolean
  ]
  @aliases [d: :data, s: :source, b: :bus, r: :registry]

  @default_source "/mix/skill.signal"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches, aliases: @aliases)

    if invalid != [] do
      invalid_flags =
        Enum.map_join(invalid, ", ", fn
          {key, _value} -> "--#{key}"
          key when is_atom(key) -> "--#{key}"
        end)

      Mix.raise("Unknown options: #{invalid_flags}")
    end

    signal_type = parse_signal_type(positional)
    start_app? = Keyword.get(opts, :start_app, true)
    pretty? = Keyword.get(opts, :pretty, true)
    source = parse_source(Keyword.get(opts, :source, @default_source))
    data = decode_data!(Keyword.get(opts, :data, "{}"))
    registry = parse_registry(Keyword.get(opts, :registry, nil))
    bus = resolve_bus(Keyword.get(opts, :bus, nil), registry)

    if start_app? do
      Mix.Task.run("app.start")
    end

    request_signal = Signal.new!(signal_type, data, source: source)

    case Bus.publish(bus, [request_signal]) do
      {:ok, _published} ->
        print_json(
          %{
            "status" => "published",
            "bus" => bus_to_string(bus),
            "signal" => serialize_signal(request_signal)
          },
          pretty?
        )

      {:error, reason} ->
        Mix.raise("Failed to publish skill signal: #{inspect(reason)}")
    end
  end

  defp parse_signal_type([signal_type]) when is_binary(signal_type) do
    signal_type
    |> String.trim()
    |> case do
      "" -> Mix.raise("<signal_type> is required")
      normalized -> normalized
    end
  end

  defp parse_signal_type([signal_type | tail]) when is_binary(signal_type) do
    if String.trim(signal_type) == "" do
      Mix.raise("<signal_type> is required")
    end

    Mix.raise("Unexpected positional arguments: #{Enum.join(tail, ", ")}")
  end

  defp parse_signal_type(_args),
    do: Mix.raise("Usage: mix skill.signal <signal_type> [options]")

  defp parse_source(source) when is_binary(source) do
    source
    |> String.trim()
    |> case do
      "" -> @default_source
      normalized -> normalized
    end
  end

  defp parse_source(_invalid), do: @default_source

  defp decode_data!(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = decoded} ->
        decoded

      {:ok, other} ->
        Mix.raise("--data must decode to a JSON object map, got: #{inspect(other)}")

      {:error, reason} ->
        Mix.raise("Invalid --data JSON: #{Exception.message(reason)}")
    end
  end

  defp decode_data!(_invalid), do: Mix.raise("--data must be a JSON string")

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

  defp safe_to_existing_atom(value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> :error
  end

  defp to_existing_atom!(value, option) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError ->
      Mix.raise("#{option} must reference an existing atom name (got: #{inspect(value)})")
  end

  defp serialize_signal(%Signal{} = signal) do
    %{
      "id" => signal.id,
      "type" => signal.type,
      "source" => signal.source,
      "data" => signal.data
    }
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
end
