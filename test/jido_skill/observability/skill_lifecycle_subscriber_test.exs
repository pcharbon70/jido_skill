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
        source: "/hooks/skill/pre"
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
        source: "/hooks/skill/post"
      )

    assert {:ok, _} = Bus.publish(bus_name, [pre_signal])
    assert {:ok, _} = Bus.publish(bus_name, [post_signal])

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, pre_metadata}, 1_000
    assert pre_metadata.type == "skill.pre"
    assert pre_metadata.source == "/hooks/skill/pre"
    assert pre_metadata.bus == bus_name
    assert pre_metadata.phase == "pre"
    assert pre_metadata.skill_name == "pdf-processor"
    assert pre_metadata.route == "pdf/extract/text"
    assert pre_metadata.status == nil

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, post_metadata}, 1_000
    assert post_metadata.type == "skill.post"
    assert post_metadata.source == "/hooks/skill/post"
    assert post_metadata.bus == bus_name
    assert post_metadata.phase == "post"
    assert post_metadata.skill_name == "pdf-processor"
    assert post_metadata.route == "pdf/extract/text"
    assert post_metadata.status == "error"
    assert post_metadata.reason == nil
    assert post_metadata.tools == nil
  end

  test "emits telemetry for permission-blocked signals" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})
    start_supervised!({SkillLifecycleSubscriber, [name: nil, bus_name: bus_name]})

    attach_handler!()

    {:ok, blocked_signal} =
      Signal.new(
        "skill.permission.blocked",
        %{
          "skill_name" => "dispatcher-ask",
          "route" => "demo/ask",
          "reason" => "ask",
          "tools" => ["Bash(git:*)"],
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        source: "/permissions/skill/permission/blocked"
      )

    assert {:ok, _} = Bus.publish(bus_name, [blocked_signal])

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, metadata}, 1_000
    assert metadata.type == "skill.permission.blocked"
    assert metadata.source == "/permissions/skill/permission/blocked"
    assert metadata.bus == bus_name
    assert metadata.phase == nil
    assert metadata.skill_name == "dispatcher-ask"
    assert metadata.route == "demo/ask"
    assert metadata.status == nil
    assert metadata.reason == "ask"
    assert metadata.tools == ["Bash(git:*)"]
  end

  test "subscribes to configured lifecycle signal types" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    start_supervised!(
      {SkillLifecycleSubscriber,
       [
         name: nil,
         bus_name: bus_name,
         hook_signal_types: ["skill/custom/pre", "skill/custom/post"]
       ]}
    )

    attach_handler!()

    {:ok, custom_pre_signal} =
      Signal.new(
        "skill.custom.pre",
        %{
          "phase" => "pre",
          "skill_name" => "custom-skill",
          "route" => "custom/run"
        },
        source: "/hooks/skill/custom/pre"
      )

    assert {:ok, _} = Bus.publish(bus_name, [custom_pre_signal])

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, metadata}, 1_000
    assert metadata.type == "skill.custom.pre"
    assert metadata.source == "/hooks/skill/custom/pre"
    assert metadata.skill_name == "custom-skill"

    {:ok, default_pre_signal} =
      Signal.new(
        "skill.pre",
        %{
          "phase" => "pre",
          "skill_name" => "default-skill",
          "route" => "default/run"
        },
        source: "/hooks/skill/pre"
      )

    assert {:ok, _} = Bus.publish(bus_name, [default_pre_signal])

    refute_receive {:telemetry, @telemetry_event, %{count: 1}, _default_metadata}, 200
  end

  test "falls back to default lifecycle subscriptions when configured list is empty" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    start_supervised!(
      {SkillLifecycleSubscriber, [name: nil, bus_name: bus_name, hook_signal_types: []]}
    )

    attach_handler!()

    {:ok, pre_signal} =
      Signal.new(
        "skill.pre",
        %{
          "phase" => "pre",
          "skill_name" => "fallback-skill",
          "route" => "fallback/run"
        },
        source: "/hooks/skill/pre"
      )

    assert {:ok, _} = Bus.publish(bus_name, [pre_signal])

    assert_receive {:telemetry, @telemetry_event, %{count: 1}, metadata}, 1_000
    assert metadata.type == "skill.pre"
    assert metadata.skill_name == "fallback-skill"
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
