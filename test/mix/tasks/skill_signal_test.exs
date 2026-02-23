defmodule Mix.Tasks.Skill.SignalTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Jido.Code.Skill.SkillRuntime.SkillRegistry
  alias Jido.Signal.Bus
  alias Mix.Tasks.Skill.Signal

  setup do
    unique_suffix = Integer.to_string(System.unique_integer([:positive]))
    tmp_dir = Path.join(System.tmp_dir!(), "jido_skill_mix_task_signal_test_#{unique_suffix}")
    local_root = Path.join(tmp_dir, "local")
    global_root = Path.join(tmp_dir, "global")

    File.mkdir_p!(Path.join(local_root, "skills"))
    File.mkdir_p!(Path.join(global_root, "skills"))

    bus = "mix_task_skill_signal_bus_#{unique_suffix}"
    start_supervised!({Bus, [name: bus, middleware: []]})

    registry = unique_name("mix_task_skill_signal_registry")

    start_supervised!(
      {SkillRegistry,
       [
         name: registry,
         bus_name: bus,
         global_path: global_root,
         local_path: local_root,
         settings_path: Path.join(local_root, "settings.json"),
         hook_defaults: %{},
         permissions: %{allow: [], deny: [], ask: []}
       ]}
    )

    on_exit(fn ->
      Mix.Task.reenable("skill.signal")
      File.rm_rf!(tmp_dir)
    end)

    {:ok, bus: bus, registry: registry}
  end

  test "publishes a signal with explicit bus and returns summary payload", context do
    output =
      capture_io(fn ->
        Signal.run([
          "skill.pre",
          "--data",
          ~s({"skill_name":"pdf-processor","route":"pdf/extract/text"}),
          "--source",
          "/test/skill.signal",
          "--no-start-app",
          "--no-pretty",
          "--bus",
          context.bus
        ])
      end)

    payload = Jason.decode!(output)

    assert payload["status"] == "published"
    assert payload["bus"] == context.bus
    assert get_in(payload, ["signal", "type"]) == "skill.pre"
    assert get_in(payload, ["signal", "source"]) == "/test/skill.signal"
    assert get_in(payload, ["signal", "data", "skill_name"]) == "pdf-processor"
  end

  test "uses registry bus when --bus is omitted", context do
    output =
      capture_io(fn ->
        Signal.run([
          "custom.health.check",
          "--data",
          ~s({"status":"ok"}),
          "--no-start-app",
          "--no-pretty",
          "--registry",
          Atom.to_string(context.registry)
        ])
      end)

    payload = Jason.decode!(output)

    assert payload["status"] == "published"
    assert payload["bus"] == context.bus
    assert get_in(payload, ["signal", "type"]) == "custom.health.check"
    assert get_in(payload, ["signal", "data", "status"]) == "ok"
  end

  test "validates data must decode to map", context do
    assert_raise Mix.Error, ~r/--data must decode to a JSON object map/, fn ->
      capture_io(fn ->
        Signal.run([
          "skill.pre",
          "--data",
          ~s(["not","a","map"]),
          "--no-start-app",
          "--bus",
          context.bus
        ])
      end)
    end
  end

  test "validates unexpected positional arguments", context do
    assert_raise Mix.Error, ~r/Unexpected positional arguments/, fn ->
      capture_io(fn ->
        Signal.run([
          "skill.pre",
          "extra",
          "--no-start-app",
          "--bus",
          context.bus
        ])
      end)
    end
  end

  defp unique_name(prefix) do
    :"#{prefix}_#{System.unique_integer([:positive])}"
  end
end
