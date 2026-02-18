defmodule JidoSkill.Config do
  @moduledoc """
  Runtime configuration accessor for the skill runtime.

  Phase 1 keeps configuration reads centralized so later phases can add
  schema-backed loading and merge semantics without changing call sites.
  """

  @app :jido_skill

  @spec signal_bus_name() :: atom() | String.t()
  def signal_bus_name do
    Application.get_env(@app, :signal_bus_name, :jido_code_bus)
  end

  @spec signal_bus_middleware() :: keyword()
  def signal_bus_middleware do
    Application.get_env(@app, :signal_bus_middleware, default_signal_bus_middleware())
  end

  @spec global_path() :: String.t()
  def global_path do
    @app
    |> Application.get_env(:global_path, "~/.jido_code")
    |> expand_home()
  end

  @spec local_path() :: String.t()
  def local_path do
    Application.get_env(@app, :local_path, ".jido_code")
  end

  @spec settings_path() :: String.t()
  def settings_path do
    Application.get_env(@app, :settings_path, Path.join(local_path(), "settings.json"))
  end

  @spec skill_paths() :: [String.t()]
  def skill_paths do
    [
      Path.join(global_path(), "skills"),
      Path.join(local_path(), "skills")
    ]
  end

  defp default_signal_bus_middleware do
    [{Jido.Signal.Bus.Middleware.Logger, level: :debug}]
  end

  defp expand_home("~/" <> rest), do: Path.join(System.user_home!(), rest)
  defp expand_home(path), do: path
end
