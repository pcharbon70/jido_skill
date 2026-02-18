defmodule JidoSkill.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    with {:ok, settings} <- JidoSkill.Config.load_settings() do
      bus_name = settings.signal_bus.name

      children = [
        {Jido.Signal.Bus,
         [
           name: bus_name,
           middleware: settings.signal_bus.middleware
         ]},
        {JidoSkill.SkillRuntime.SkillRegistry,
         [
           bus_name: bus_name,
           global_path: JidoSkill.Config.global_path(),
           local_path: JidoSkill.Config.local_path(),
           settings_path: JidoSkill.Config.settings_path(),
           hook_defaults: settings.hooks
         ]},
        {JidoSkill.Observability.SkillLifecycleSubscriber, [bus_name: bus_name]}
      ]

      opts = [strategy: :one_for_one, name: JidoSkill.Supervisor]
      Supervisor.start_link(children, opts)
    else
      {:error, reason} ->
        {:error, {:invalid_settings, reason}}
    end
  end
end
