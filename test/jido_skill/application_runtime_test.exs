defmodule JidoSkill.ApplicationRuntimeTest do
  use ExUnit.Case, async: false

  alias Jido.Signal.Bus
  alias JidoSkill.Config
  alias JidoSkill.Observability.SkillLifecycleSubscriber
  alias JidoSkill.SkillRuntime.SignalDispatcher
  alias JidoSkill.SkillRuntime.SkillRegistry

  test "starts the phase 1 runtime children" do
    {:ok, settings} = Config.load_settings()
    bus_name = settings.signal_bus.name

    assert {:ok, bus_pid} = Bus.whereis(bus_name)
    assert Process.alive?(bus_pid)

    assert registry_pid = Process.whereis(SkillRegistry)
    assert Process.alive?(registry_pid)

    assert dispatcher_pid = Process.whereis(SignalDispatcher)
    assert Process.alive?(dispatcher_pid)

    assert subscriber_pid = Process.whereis(SkillLifecycleSubscriber)
    assert Process.alive?(subscriber_pid)
  end
end
