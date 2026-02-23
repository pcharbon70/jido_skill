defmodule Mix.Tasks.Skill.Run do
  @shortdoc "Publish a skill route signal from the terminal"

  @moduledoc """
  Convenience task for invoking a loaded skill by name.

  This task resolves a skill from `SkillRegistry`, selects a route, and
  publishes the corresponding route signal to the configured bus.

  ## Examples

      mix skill.run pdf-processor --route pdf/extract/text --data '{"file":"report.pdf"}'
      mix skill.run pdf-processor --data '{"file":"report.pdf"}' --no-start-app
  """

  use Mix.Task

  alias Jido.Code.Skill.SkillRuntime.SkillRegistry
  alias Jido.Signal
  alias Jido.Signal.Bus

  @switches [
    route: :string,
    data: :string,
    source: :string,
    bus: :string,
    registry: :string,
    reload: :boolean,
    start_app: :boolean,
    pretty: :boolean
  ]
  @aliases [r: :route, d: :data, s: :source, b: :bus]

  @default_source "/mix/skill.run"

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

    skill_name = parse_skill_name(positional)
    registry = parse_registry(Keyword.get(opts, :registry, nil))
    start_app? = Keyword.get(opts, :start_app, true)
    reload? = Keyword.get(opts, :reload, false)
    pretty? = Keyword.get(opts, :pretty, true)
    data = decode_data!(Keyword.get(opts, :data, "{}"))
    source = parse_source(Keyword.get(opts, :source, @default_source))

    if start_app? do
      Mix.Task.run("app.start")
    end

    if reload? do
      SkillRegistry.reload(registry)
    end

    skill = fetch_skill!(registry, skill_name)
    route = resolve_route!(skill, Keyword.get(opts, :route, nil))
    bus = parse_bus(Keyword.get(opts, :bus, nil), registry)
    signal_type = normalize_route_signal_type(route)

    request_signal = Signal.new!(signal_type, data, source: source)

    case Bus.publish(bus, [request_signal]) do
      {:ok, _published} ->
        print_json(
          %{
            "status" => "published",
            "skill_name" => skill_name,
            "route" => route,
            "bus" => to_string(bus),
            "request" => serialize_signal(request_signal)
          },
          pretty?
        )

      {:error, reason} ->
        Mix.raise("Failed to publish skill signal: #{inspect(reason)}")
    end
  end

  defp parse_skill_name([skill_name | tail]) when is_binary(skill_name) do
    ensure_no_positional!(tail)

    skill_name
    |> String.trim()
    |> case do
      "" ->
        Mix.raise("<skill_name> is required")

      normalized ->
        if String.starts_with?(normalized, "-") do
          Mix.raise("<skill_name> is required")
        else
          normalized
        end
    end
  end

  defp parse_skill_name(_args), do: Mix.raise("Usage: mix skill.run <skill_name> [options]")

  defp ensure_no_positional!([]), do: :ok

  defp ensure_no_positional!(extra) do
    Mix.raise("Unexpected positional arguments: #{Enum.join(extra, ", ")}")
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

  defp fetch_skill!(registry, skill_name) do
    case SkillRegistry.get_skill(registry, skill_name) do
      nil ->
        available =
          SkillRegistry.list_skills(registry)
          |> Enum.map(& &1.name)
          |> Enum.sort()

        available_message =
          case available do
            [] -> "No skills are currently loaded."
            names -> "Available skills: #{Enum.join(names, ", ")}"
          end

        Mix.raise("Unknown skill #{inspect(skill_name)}. #{available_message}")

      skill ->
        skill
    end
  end

  defp resolve_route!(skill, route_value) do
    routes = skill_routes(skill)
    skill_name = Map.get(skill, :name, inspect(Map.get(skill, :module)))
    route = normalize_optional_route(route_value)

    case route do
      nil ->
        case routes do
          [] ->
            Mix.raise("Skill #{inspect(skill_name)} does not define any routes")

          [single] ->
            single

          many ->
            Mix.raise(
              "Skill #{inspect(skill_name)} has multiple routes; pass --route. " <>
                "Available routes: #{Enum.join(many, ", ")}"
            )
        end

      selected ->
        if selected in routes do
          selected
        else
          Mix.raise(
            "Route #{inspect(selected)} is not defined for skill #{inspect(skill_name)}. " <>
              "Available routes: #{Enum.join(routes, ", ")}"
          )
        end
    end
  end

  defp skill_routes(skill) do
    module = Map.get(skill, :module)

    if is_atom(module) and function_exported?(module, :skill_metadata, 0) do
      module
      |> then(& &1.skill_metadata())
      |> Map.get(:router, [])
      |> Enum.map(fn
        {route, _action} when is_binary(route) -> route
        _other -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()
      |> Enum.uniq()
    else
      []
    end
  rescue
    _error ->
      []
  end

  defp normalize_optional_route(nil), do: nil

  defp normalize_optional_route(route) when is_binary(route) do
    route
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> String.replace(normalized, ".", "/")
    end
  end

  defp normalize_optional_route(_invalid), do: nil

  defp parse_bus(nil, registry), do: SkillRegistry.bus_name(registry)

  defp parse_bus(bus, registry) when is_binary(bus) do
    bus
    |> normalize_optional_bus()
    |> case do
      nil -> SkillRegistry.bus_name(registry)
      normalized -> normalized
    end
  end

  defp parse_bus(bus, _registry) when is_atom(bus), do: bus
  defp parse_bus(_invalid, registry), do: SkillRegistry.bus_name(registry)

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

  defp normalize_route_signal_type(route) when is_binary(route),
    do: String.replace(route, "/", ".")

  defp serialize_signal(%Signal{} = signal) do
    %{
      "id" => signal.id,
      "type" => signal.type,
      "source" => signal.source,
      "data" => signal.data
    }
  end

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
