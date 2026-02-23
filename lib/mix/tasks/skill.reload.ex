defmodule Mix.Tasks.Skill.Reload do
  @shortdoc "Reload skills and runtime settings from disk"

  @moduledoc """
  Convenience task for reloading the running `SkillRegistry`.

  This task re-reads skill markdown files and runtime settings, then prints
  a JSON summary of the refreshed registry state.

  ## Examples

      mix skill.reload
      mix skill.reload --registry my_skill_registry --no-start-app
  """

  use Mix.Task

  alias Jido.Code.Skill.SkillRuntime.SkillRegistry

  @switches [
    registry: :string,
    start_app: :boolean,
    pretty: :boolean
  ]
  @aliases [r: :registry]

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

    registry = parse_registry(Keyword.get(opts, :registry, nil))
    start_app? = Keyword.get(opts, :start_app, true)
    pretty? = Keyword.get(opts, :pretty, true)

    if start_app? do
      Mix.Task.run("app.start")
    end

    previous_bus_name = bus_name!(registry, "before reload")
    reload_registry!(registry)

    skills = list_skills!(registry)
    refreshed_bus_name = bus_name!(registry, "after reload")
    hooks = hook_defaults!(registry)

    print_json(
      %{
        "status" => "reloaded",
        "registry" => inspect(registry),
        "skills_count" => length(skills),
        "skills" => skills |> Enum.map(&Map.get(&1, :name)) |> Enum.sort(),
        "bus_name" => %{
          "before" => to_string(previous_bus_name),
          "after" => to_string(refreshed_bus_name)
        },
        "hooks" => %{
          "pre" => serialize_hook(Map.get(hooks, :pre)),
          "post" => serialize_hook(Map.get(hooks, :post))
        }
      },
      pretty?
    )
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

  defp list_skills!(registry) do
    SkillRegistry.list_skills(registry)
  rescue
    error ->
      Mix.raise("Failed to list skills from #{inspect(registry)}: #{Exception.message(error)}")
  catch
    :exit, reason ->
      Mix.raise("Failed to list skills from #{inspect(registry)}: #{inspect(reason)}")
  end

  defp bus_name!(registry, context) do
    SkillRegistry.bus_name(registry)
  rescue
    error ->
      Mix.raise(
        "Failed to read bus name #{context} for #{inspect(registry)}: #{Exception.message(error)}"
      )
  catch
    :exit, reason ->
      Mix.raise("Failed to read bus name #{context} for #{inspect(registry)}: #{inspect(reason)}")
  end

  defp hook_defaults!(registry) do
    SkillRegistry.hook_defaults(registry)
  rescue
    error ->
      Mix.raise(
        "Failed to read hook defaults from #{inspect(registry)}: #{Exception.message(error)}"
      )
  catch
    :exit, reason ->
      Mix.raise("Failed to read hook defaults from #{inspect(registry)}: #{inspect(reason)}")
  end

  defp serialize_hook(nil), do: nil

  defp serialize_hook(hook) when is_map(hook) do
    %{
      "enabled" => Map.get(hook, :enabled, true),
      "signal_type" => Map.get(hook, :signal_type),
      "bus" => normalize_hook_bus(Map.get(hook, :bus))
    }
  end

  defp serialize_hook(_invalid), do: nil

  defp normalize_hook_bus(nil), do: nil
  defp normalize_hook_bus(bus) when is_atom(bus), do: Atom.to_string(bus)
  defp normalize_hook_bus(bus) when is_binary(bus), do: bus
  defp normalize_hook_bus(bus), do: inspect(bus)

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
