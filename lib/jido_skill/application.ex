defmodule JidoSkill.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    bus_name = JidoSkill.Config.signal_bus_name()

    children = [
      {Jido.Signal.Bus,
       [
         name: bus_name,
         middleware: JidoSkill.Config.signal_bus_middleware()
       ]},
      {JidoSkill.SkillRuntime.SkillRegistry,
       [
         bus_name: bus_name,
         global_path: JidoSkill.Config.global_path(),
         local_path: JidoSkill.Config.local_path(),
         settings_path: JidoSkill.Config.settings_path()
       ]},
      {JidoSkill.Observability.SkillLifecycleSubscriber, [bus_name: bus_name]}
    ]

    opts = [strategy: :one_for_one, name: JidoSkill.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
