defmodule Mix.Tasks.Skill.Routes do
  @shortdoc "List active skill routes from the dispatcher"

  @moduledoc """
  Inspect active routes currently loaded in `SignalDispatcher`.

  ## Examples

      mix skill.routes
      mix skill.routes --reload --registry my_registry --dispatcher my_dispatcher --no-start-app
  """

  use Mix.Task

  alias Jido.Code.Skill.SkillRuntime.SignalDispatcher
  alias Jido.Code.Skill.SkillRuntime.SkillRegistry

  @switches [
    dispatcher: :string,
    registry: :string,
    reload: :boolean,
    start_app: :boolean,
    pretty: :boolean
  ]
  @aliases [d: :dispatcher, r: :registry]

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

    dispatcher = parse_dispatcher(Keyword.get(opts, :dispatcher, nil))
    registry = parse_registry(Keyword.get(opts, :registry, nil))
    start_app? = Keyword.get(opts, :start_app, true)
    reload? = Keyword.get(opts, :reload, false)
    pretty? = Keyword.get(opts, :pretty, true)

    if start_app? do
      Mix.Task.run("app.start")
    end

    if reload? do
      reload_registry!(registry)
      refresh_dispatcher!(dispatcher)
    end

    routes = routes!(dispatcher)

    print_json(
      %{
        "status" => "ok",
        "dispatcher" => inspect(dispatcher),
        "count" => length(routes),
        "routes" => routes
      },
      pretty?
    )
  end

  defp parse_dispatcher(nil), do: SignalDispatcher

  defp parse_dispatcher(dispatcher_name) when is_binary(dispatcher_name) do
    dispatcher_name
    |> String.trim()
    |> String.trim_leading(":")
    |> case do
      "" -> SignalDispatcher
      normalized -> to_existing_atom!(normalized, "--dispatcher")
    end
  end

  defp parse_dispatcher(_invalid), do: SignalDispatcher

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

  defp reload_registry!(registry) do
    :ok = SkillRegistry.reload(registry)
  rescue
    error ->
      Mix.raise(
        "Failed to reload skill registry #{inspect(registry)}: #{Exception.message(error)}"
      )
  catch
    :exit, reason ->
      Mix.raise("Failed to reload skill registry #{inspect(registry)}: #{inspect(reason)}")
  end

  defp refresh_dispatcher!(dispatcher) do
    :ok = SignalDispatcher.refresh(dispatcher)
  rescue
    error ->
      Mix.raise(
        "Failed to refresh skill dispatcher #{inspect(dispatcher)}: #{Exception.message(error)}"
      )
  catch
    :exit, reason ->
      Mix.raise("Failed to refresh skill dispatcher #{inspect(dispatcher)}: #{inspect(reason)}")
  end

  defp routes!(dispatcher) do
    SignalDispatcher.routes(dispatcher)
  rescue
    error ->
      Mix.raise(
        "Failed to read routes from skill dispatcher #{inspect(dispatcher)}: #{Exception.message(error)}"
      )
  catch
    :exit, reason ->
      Mix.raise(
        "Failed to read routes from skill dispatcher #{inspect(dispatcher)}: #{inspect(reason)}"
      )
  end

  defp to_existing_atom!(value, option) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError ->
      Mix.raise("#{option} must reference an existing atom name (got: #{inspect(value)})")
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
