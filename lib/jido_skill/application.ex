defmodule JidoSkill.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    case JidoSkill.Config.load_settings() do
      {:ok, settings} ->
        bus_name = settings.signal_bus.name
        hook_signal_types = [settings.hooks.pre.signal_type, settings.hooks.post.signal_type]

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
             hook_defaults: settings.hooks,
             permissions: settings.permissions
           ]},
          {JidoSkill.SkillRuntime.SignalDispatcher, [bus_name: bus_name]},
          {JidoSkill.Observability.SkillLifecycleSubscriber,
           [bus_name: bus_name, hook_signal_types: hook_signal_types]}
        ]

        opts = [strategy: :one_for_one, name: JidoSkill.Supervisor]
        Supervisor.start_link(children, opts)

      {:error, reason} ->
        {:error, {:invalid_settings, reason}}
    end
  end
end
