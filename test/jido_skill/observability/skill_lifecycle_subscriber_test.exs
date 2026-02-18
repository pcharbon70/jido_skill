defmodule JidoSkill.Observability.SkillLifecycleSubscriberTest do
  use ExUnit.Case, async: false

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoSkill.Observability.SkillLifecycleSubscriber

  @telemetry_event [:jido_skill, :skill, :lifecycle]

  test "emits enriched telemetry for pre and post lifecycle signals" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})
    start_supervised!({SkillLifecycleSubscriber, [name: nil, bus_name: bus_name]})

    attach_handler!()

    {:ok, pre_signal} =
      Signal.new(
        "skill.pre",
        %{
          "phase" => "pre",
          "skill_name" => "pdf-processor",
          "route" => "pdf/extract/text"
        },
        source: "/hooks/skill.pre"
      )

    {:ok, post_signal} =
      Signal.new(
        "skill.post",
        %{
          "phase" => "post",
          "skill_name" => "pdf-processor",
          "route" => "pdf/extract/text",
          "status" => "error"
        },
        source: "/hooks/skill.post"
      )

    assert {:ok, _} = Bus.publish(bus_name, [pre_signal])
    assert {:ok, _} = Bus.publish(bus_name, [post_signal])

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, pre_metadata}, 1_000
    assert pre_metadata.type == "skill.pre"
    assert pre_metadata.bus == bus_name
    assert pre_metadata.phase == "pre"
    assert pre_metadata.skill_name == "pdf-processor"
    assert pre_metadata.route == "pdf/extract/text"
    assert pre_metadata.status == nil

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, post_metadata}, 1_000
    assert post_metadata.type == "skill.post"
    assert post_metadata.bus == bus_name
    assert post_metadata.phase == "post"
    assert post_metadata.skill_name == "pdf-processor"
    assert post_metadata.route == "pdf/extract/text"
    assert post_metadata.status == "error"
  end

  test "ignores non-signal messages" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    subscriber_pid =
      start_supervised!({SkillLifecycleSubscriber, [name: nil, bus_name: bus_name]})

    attach_handler!()
    send(subscriber_pid, :ignore_me)

    refute_receive {:telemetry, @telemetry_event, _measurements, _metadata}, 200
  end

  defp attach_handler! do
    handler_id = "telemetry-handler-#{System.unique_integer([:positive])}"

    assert :ok =
             :telemetry.attach(
               handler_id,
               @telemetry_event,
               &__MODULE__.handle_telemetry/4,
               self()
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  def handle_telemetry(event_name, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry, event_name, measurements, metadata})
  end
end
