defmodule JidoSkill.ApplicationRuntimeTest do
  use ExUnit.Case, async: false

  test "starts the phase 1 runtime children" do
    bus_name = JidoSkill.Config.signal_bus_name()

    assert {:ok, bus_pid} = Jido.Signal.Bus.whereis(bus_name)
    assert Process.alive?(bus_pid)

    assert registry_pid = Process.whereis(JidoSkill.SkillRuntime.SkillRegistry)
    assert Process.alive?(registry_pid)

    assert subscriber_pid = Process.whereis(JidoSkill.Observability.SkillLifecycleSubscriber)
    assert Process.alive?(subscriber_pid)
  end
end
