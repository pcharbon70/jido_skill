defmodule JidoSkill.SkillRuntime.HookEmitterTest do
  use ExUnit.Case, async: false

  alias Jido.Signal.Bus
  alias JidoSkill.SkillRuntime.HookEmitter

  test "uses global pre hook and interpolates template values" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Jido.Signal.Bus, [name: bus_name, middleware: []]})

    assert {:ok, _sub_id} =
             Bus.subscribe(bus_name, "skill.pre",
               dispatch: {:pid, target: self(), delivery_mode: :async}
             )

    global_hooks = %{
      pre: %{
        enabled: true,
        signal_type: "skill/pre",
        bus: bus_name,
        data: %{
          "source" => "{{skill_name}}",
          "route_copy" => "{{route}}",
          "phase" => "template"
        }
      }
    }

    assert :ok = HookEmitter.emit_pre("pdf-processor", "pdf/extract/text", nil, global_hooks)

    assert_receive {:signal, signal}, 1_000
    assert signal.type == "skill.pre"
    assert signal.source == "/hooks/skill/pre"

    assert signal.data["source"] == "pdf-processor"
    assert signal.data["route_copy"] == "pdf/extract/text"
    assert signal.data["phase"] == "pre"
    assert is_binary(signal.data["timestamp"])
  end

  test "frontmatter enabled false disables hook emission" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Jido.Signal.Bus, [name: bus_name, middleware: []]})

    assert {:ok, _sub_id} =
             Bus.subscribe(bus_name, "skill.post",
               dispatch: {:pid, target: self(), delivery_mode: :async}
             )

    global_hooks = %{
      post: %{
        enabled: true,
        signal_type: "skill/post",
        bus: bus_name,
        data: %{"scope" => "global"}
      }
    }

    frontmatter_hooks = %{
      post: %{
        enabled: false
      }
    }

    assert :ok =
             HookEmitter.emit_post(
               "pdf-processor",
               "pdf/form/fill",
               "ok",
               frontmatter_hooks,
               global_hooks
             )

    refute_receive {:signal, _signal}, 200
  end

  test "frontmatter partially overrides global hook and keeps global defaults" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Jido.Signal.Bus, [name: bus_name, middleware: []]})

    assert {:ok, _sub_id} =
             Bus.subscribe(bus_name, "skill.pre",
               dispatch: {:pid, target: self(), delivery_mode: :async}
             )

    global_hooks = %{
      pre: %{
        enabled: true,
        signal_type: "skill/pre",
        bus: bus_name,
        data: %{
          "source" => "global",
          "route_template" => "{{route}}"
        }
      }
    }

    frontmatter_hooks = %{
      pre: %{
        data: %{
          "source" => "local"
        }
      }
    }

    assert :ok =
             HookEmitter.emit_pre(
               "pdf-processor",
               "pdf/extract/tables",
               frontmatter_hooks,
               global_hooks
             )

    assert_receive {:signal, signal}, 1_000
    assert signal.type == "skill.pre"
    assert signal.source == "/hooks/skill/pre"
    assert signal.data["source"] == "local"
    assert signal.data["route_template"] == "pdf/extract/tables"
  end

  test "frontmatter colon-prefixed bus publishes to atom bus names" do
    bus_name = :phase15_hook_bus
    start_supervised!({Jido.Signal.Bus, [name: bus_name, middleware: []]})

    assert {:ok, _sub_id} =
             Bus.subscribe(bus_name, "skill.pre",
               dispatch: {:pid, target: self(), delivery_mode: :async}
             )

    frontmatter_hooks = %{
      pre: %{
        enabled: true,
        signal_type: "skill/pre",
        bus: ":phase15_hook_bus",
        data: %{"origin" => "frontmatter"}
      }
    }

    assert :ok = HookEmitter.emit_pre("pdf-processor", "pdf/extract/text", frontmatter_hooks, %{})

    assert_receive {:signal, signal}, 1_000
    assert signal.type == "skill.pre"
    assert signal.source == "/hooks/skill/pre"
    assert signal.data["origin"] == "frontmatter"
    assert signal.data["skill_name"] == "pdf-processor"
  end

  test "hook source uses slash paths when signal type is dot-delimited" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Jido.Signal.Bus, [name: bus_name, middleware: []]})

    assert {:ok, _sub_id} =
             Bus.subscribe(bus_name, "skill.pre",
               dispatch: {:pid, target: self(), delivery_mode: :async}
             )

    global_hooks = %{
      pre: %{
        enabled: true,
        signal_type: "skill.pre",
        bus: bus_name,
        data: %{}
      }
    }

    assert :ok = HookEmitter.emit_pre("pdf-processor", "pdf/extract/text", nil, global_hooks)

    assert_receive {:signal, signal}, 1_000
    assert signal.type == "skill.pre"
    assert signal.source == "/hooks/skill/pre"
  end

  test "frontmatter enabled true can inherit signal type from disabled global hook" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Jido.Signal.Bus, [name: bus_name, middleware: []]})

    assert {:ok, _sub_id} =
             Bus.subscribe(bus_name, "skill.inherited.pre",
               dispatch: {:pid, target: self(), delivery_mode: :async}
             )

    global_hooks = %{
      pre: %{
        enabled: false,
        signal_type: "skill/inherited/pre",
        bus: bus_name,
        data: %{"scope" => "global"}
      }
    }

    frontmatter_hooks = %{
      pre: %{
        enabled: true,
        data: %{"scope" => "frontmatter"}
      }
    }

    assert :ok =
             HookEmitter.emit_pre(
               "inherit-enabled-skill",
               "demo/inherit",
               frontmatter_hooks,
               global_hooks
             )

    assert_receive {:signal, signal}, 1_000
    assert signal.type == "skill.inherited.pre"
    assert signal.source == "/hooks/skill/inherited/pre"
    assert signal.data["scope"] == "frontmatter"
    assert signal.data["skill_name"] == "inherit-enabled-skill"
  end

  test "frontmatter signal type alone does not override disabled global enablement" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Jido.Signal.Bus, [name: bus_name, middleware: []]})

    assert {:ok, _sub_id} =
             Bus.subscribe(bus_name, "skill.frontmatter.only",
               dispatch: {:pid, target: self(), delivery_mode: :async}
             )

    global_hooks = %{
      pre: %{
        enabled: false,
        signal_type: "skill/global/pre",
        bus: bus_name,
        data: %{}
      }
    }

    frontmatter_hooks = %{
      pre: %{
        signal_type: "skill/frontmatter/only",
        data: %{}
      }
    }

    assert :ok =
             HookEmitter.emit_pre(
               "inherit-disabled-skill",
               "demo/inherit",
               frontmatter_hooks,
               global_hooks
             )

    refute_receive {:signal, _signal}, 200
  end

  test "invalid signal_type is ignored without crashing" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Jido.Signal.Bus, [name: bus_name, middleware: []]})

    assert {:ok, _sub_id} =
             Bus.subscribe(bus_name, "skill.pre",
               dispatch: {:pid, target: self(), delivery_mode: :async}
             )

    global_hooks = %{
      pre: %{
        enabled: true,
        signal_type: 42,
        bus: bus_name,
        data: %{}
      }
    }

    assert :ok = HookEmitter.emit_pre("invalid-signal", "demo/invalid", nil, global_hooks)
    refute_receive {:signal, _signal}, 200
  end

  test "invalid bus is ignored without crashing" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Jido.Signal.Bus, [name: bus_name, middleware: []]})

    assert {:ok, _sub_id} =
             Bus.subscribe(bus_name, "skill.pre",
               dispatch: {:pid, target: self(), delivery_mode: :async}
             )

    global_hooks = %{
      pre: %{
        enabled: true,
        signal_type: "skill/pre",
        bus: 123,
        data: %{}
      }
    }

    assert :ok = HookEmitter.emit_pre("invalid-bus", "demo/invalid", nil, global_hooks)
    refute_receive {:signal, _signal}, 200
  end
end
