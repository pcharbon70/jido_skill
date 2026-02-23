defmodule Jido.Code.Skill.CLI do
  @moduledoc """
  Command-line entrypoint for skill operations.

  This module powers the `jido` escript so skill commands can be executed
  without prefixing every invocation with `mix`.
  """

  @project_app :jido_skill

  @usage """
  Usage:
    jido --skill <skill_name> [options]
    jido --skill run <skill_name> [options]
    jido --skill list [options]
    jido --skill reload [options]

  Notes:
  - `--skill` must be the first argument for skill CLI commands.
  - `jido --skill <skill_name> ...` is shorthand for `jido --skill run <skill_name> ...`.
  - To run a skill literally named `list`, use `jido --skill run list ...`.
  - To run a skill literally named `reload`, use `jido --skill run reload ...`.
  """

  @spec main([String.t()]) :: :ok | no_return()
  def main(args) do
    Mix.start()

    case resolve(args) do
      {:ok, task, task_args} ->
        run_task(task, task_args)

      {:error, _reason} ->
        Mix.shell().error(@usage)
        System.halt(1)
    end
  end

  @spec resolve([String.t()]) :: {:ok, String.t(), [String.t()]} | {:error, atom()}
  def resolve([]), do: {:error, :missing_command}
  def resolve([value]) when value in ["help", "--help", "-h"], do: {:error, :help}
  def resolve([value | _rest]) when value in ["help", "--help", "-h"], do: {:error, :help}
  def resolve(["--skill" | rest]), do: resolve_skill(rest)
  def resolve(_args), do: {:error, :skill_prefix_required}

  defp resolve_skill([]), do: {:error, :missing_command}
  defp resolve_skill([value]) when value in ["help", "--help", "-h"], do: {:error, :help}
  defp resolve_skill([value | _rest]) when value in ["help", "--help", "-h"], do: {:error, :help}
  defp resolve_skill(["skill" | rest]), do: resolve_skill(rest)
  defp resolve_skill(["list" | rest]), do: resolve_list(rest)
  defp resolve_skill(["reload" | rest]), do: resolve_reload(rest)
  defp resolve_skill(["run" | rest]), do: resolve_run(rest)
  defp resolve_skill([skill_name | rest]), do: resolve_run([skill_name | rest])

  defp resolve_list(args), do: {:ok, "skill.list", args}
  defp resolve_reload(args), do: {:ok, "skill.reload", args}

  defp resolve_run([skill_name | rest]) when is_binary(skill_name) do
    normalized = String.trim(skill_name)

    cond do
      normalized == "" ->
        {:error, :missing_skill}

      String.starts_with?(normalized, "-") ->
        {:error, :missing_skill}

      true ->
        {:ok, "skill.run", [normalized | rest]}
    end
  end

  defp resolve_run(_args), do: {:error, :missing_skill}

  defp find_project_root(path) when is_binary(path) do
    current = Path.expand(path)
    mix_file = Path.join(current, "mix.exs")

    if File.exists?(mix_file) do
      {:ok, current}
    else
      parent = Path.dirname(current)

      if parent == current do
        {:error, :no_mix_project}
      else
        find_project_root(parent)
      end
    end
  end

  defp run_task(task, task_args) do
    case find_project_root(File.cwd!()) do
      {:ok, root} ->
        Mix.Project.in_project(@project_app, root, fn _ ->
          Mix.Task.run(task, task_args)
        end)

      {:error, :no_mix_project} ->
        Mix.shell().error(
          "Could not locate a mix project (mix.exs) from #{File.cwd!()} or its parent directories"
        )

        System.halt(1)
    end
  end
end
