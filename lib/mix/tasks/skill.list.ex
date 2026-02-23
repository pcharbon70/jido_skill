defmodule Mix.Tasks.Skill.List do
  @shortdoc "List discovered skills from the terminal"

  @moduledoc """
  Convenience task for inspecting loaded skills.

  This task reads skills from `SkillRegistry` and prints JSON output suitable
  for terminal and automation workflows.

  ## Examples

      mix skill.list
      mix skill.list --scope local --permission-status ask
      mix skill.list --reload --registry my_skill_registry --no-start-app
  """

  use Mix.Task

  alias Jido.Code.Skill.SkillRuntime.SkillRegistry

  @switches [
    scope: :string,
    permission_status: :string,
    registry: :string,
    reload: :boolean,
    start_app: :boolean,
    pretty: :boolean
  ]
  @aliases [s: :scope, p: :permission_status, r: :registry]

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
    reload? = Keyword.get(opts, :reload, false)
    pretty? = Keyword.get(opts, :pretty, true)
    scope = parse_scope(Keyword.get(opts, :scope, nil))

    permission_status_filter =
      parse_permission_status_filter(Keyword.get(opts, :permission_status, nil))

    if start_app? do
      Mix.Task.run("app.start")
    end

    if reload? do
      reload_registry!(registry)
    end

    skills =
      registry
      |> list_skills!()
      |> filter_by_scope(scope)
      |> filter_by_permission_status(permission_status_filter)

    print_json(
      %{
        "status" => "ok",
        "count" => length(skills),
        "filters" => %{
          "scope" => Atom.to_string(scope),
          "permission_status" =>
            case permission_status_filter do
              nil -> nil
              value -> Atom.to_string(value)
            end
        },
        "skills" => Enum.map(skills, &serialize_skill/1)
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

  defp parse_scope(nil), do: :all

  defp parse_scope(scope) when is_binary(scope) do
    scope
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> :all
      "all" -> :all
      "global" -> :global
      "local" -> :local
      other -> Mix.raise("--scope must be one of: all, global, local (got: #{inspect(other)})")
    end
  end

  defp parse_scope(_invalid), do: Mix.raise("--scope must be a string")

  defp parse_permission_status_filter(nil), do: nil

  defp parse_permission_status_filter(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" ->
        nil

      "allowed" ->
        :allowed

      "ask" ->
        :ask

      "denied" ->
        :denied

      other ->
        Mix.raise(
          "--permission-status must be one of: allowed, ask, denied (got: #{inspect(other)})"
        )
    end
  end

  defp parse_permission_status_filter(_invalid),
    do: Mix.raise("--permission-status must be a string")

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

  defp filter_by_scope(skills, :all), do: skills

  defp filter_by_scope(skills, scope) do
    Enum.filter(skills, fn skill ->
      Map.get(skill, :scope) == scope
    end)
  end

  defp filter_by_permission_status(skills, nil), do: skills

  defp filter_by_permission_status(skills, permission_status_filter) do
    Enum.filter(skills, fn skill ->
      permission_status(skill) == permission_status_filter
    end)
  end

  defp serialize_skill(skill) do
    %{
      "name" => Map.get(skill, :name),
      "description" => Map.get(skill, :description),
      "version" => Map.get(skill, :version),
      "scope" => Map.get(skill, :scope) |> to_string(),
      "path" => Map.get(skill, :path),
      "loaded_at" => format_loaded_at(Map.get(skill, :loaded_at)),
      "allowed_tools" => normalize_allowed_tools(Map.get(skill, :allowed_tools, [])),
      "permission_status" => serialize_permission_status(Map.get(skill, :permission_status)),
      "routes" => skill_routes(skill)
    }
  end

  defp format_loaded_at(%DateTime{} = loaded_at), do: DateTime.to_iso8601(loaded_at)
  defp format_loaded_at(_value), do: nil

  defp normalize_allowed_tools(tools) when is_list(tools), do: Enum.map(tools, &to_string/1)
  defp normalize_allowed_tools(_value), do: []

  defp serialize_permission_status(status) do
    %{
      "status" => Atom.to_string(permission_status(%{permission_status: status})),
      "tools" => permission_tools(status)
    }
  end

  defp permission_status(%{permission_status: :allowed}), do: :allowed
  defp permission_status(%{permission_status: {:ask, _tools}}), do: :ask
  defp permission_status(%{permission_status: {:denied, _tools}}), do: :denied
  defp permission_status(_skill), do: :allowed

  defp permission_tools({:ask, tools}) when is_list(tools), do: Enum.map(tools, &to_string/1)
  defp permission_tools({:denied, tools}) when is_list(tools), do: Enum.map(tools, &to_string/1)
  defp permission_tools(_status), do: []

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
