defmodule JidoSkill.RuntimeDispatchActions.ExtractText do
end

defmodule JidoSkill.RuntimeDispatchActions.ExtractTables do
end

defmodule JidoSkill.SkillRuntime.SkillRuntimeDispatchTest do
  use ExUnit.Case, async: false

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoSkill.SkillRuntime.Skill

  test "handle_signal returns an instruction and emits pre hook for matching routes" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    subscribe!(bus_name, "skill.pre")

    path =
      write_skill_markdown(
        "dispatch_pre",
        """
        name: dispatch-pre
        description: Dispatch test
        version: 1.0.0
        jido:
          actions:
            - JidoSkill.RuntimeDispatchActions.ExtractText
          router:
            - "pdf/extract/text": ExtractText
          hooks:
            pre:
              enabled: true
              signal_type: "skill/pre"
              bus: "#{bus_name}"
              data:
                origin: "frontmatter"
        """
      )

    assert {:ok, module} = Skill.from_markdown(path)
    {:ok, signal} = Signal.new("pdf.extract.text", %{"file" => "report.pdf"}, source: "/tests")

    assert {:ok, instruction} = module.handle_signal(signal, global_hooks: %{})
    assert instruction.action == JidoSkill.RuntimeDispatchActions.ExtractText
    assert instruction.params == %{"file" => "report.pdf"}

    assert_receive {:signal, emitted}, 1_000
    assert emitted.type == "skill.pre"
    assert emitted.data["skill_name"] == "dispatch-pre"
    assert emitted.data["route"] == "pdf/extract/text"
    assert emitted.data["origin"] == "frontmatter"
  end

  test "handle_signal skips unmatched routes and emits no pre hook" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    subscribe!(bus_name, "skill.pre")

    path =
      write_skill_markdown(
        "dispatch_skip",
        """
        name: dispatch-skip
        description: Dispatch skip test
        version: 1.0.0
        jido:
          actions:
            - JidoSkill.RuntimeDispatchActions.ExtractText
          router:
            - "pdf/extract/text": ExtractText
          hooks:
            pre:
              enabled: true
              signal_type: "skill/pre"
              bus: "#{bus_name}"
        """
      )

    assert {:ok, module} = Skill.from_markdown(path)
    {:ok, signal} = Signal.new("pdf.extract.tables", %{}, source: "/tests")

    assert {:skip, ^signal} = module.handle_signal(signal, global_hooks: %{})
    refute_receive {:signal, _emitted}, 200
  end

  test "transform_result emits post hook with derived status" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    subscribe!(bus_name, "skill.post")

    path =
      write_skill_markdown(
        "dispatch_post",
        """
        name: dispatch-post
        description: Dispatch post test
        version: 1.0.0
        jido:
          actions:
            - JidoSkill.RuntimeDispatchActions.ExtractText
            - JidoSkill.RuntimeDispatchActions.ExtractTables
          router:
            - "pdf/extract/text": ExtractText
            - "pdf/extract/tables": ExtractTables
          hooks:
            post:
              enabled: true
              signal_type: "skill/post"
              bus: "#{bus_name}"
              data:
                source: "frontmatter"
        """
      )

    assert {:ok, module} = Skill.from_markdown(path)

    instruction =
      Jido.Instruction.new!(
        action: JidoSkill.RuntimeDispatchActions.ExtractTables,
        params: %{"file" => "report.pdf"}
      )

    assert {:ok, {:error, :failed}, []} =
             module.transform_result({:error, :failed}, instruction, [])

    assert_receive {:signal, emitted}, 1_000
    assert emitted.type == "skill.post"
    assert emitted.data["status"] == "error"
    assert emitted.data["route"] == "pdf/extract/tables"
    assert emitted.data["source"] == "frontmatter"
  end

  test "global hooks are used when frontmatter hooks are absent" do
    bus_name = "bus_#{System.unique_integer([:positive])}"
    start_supervised!({Bus, [name: bus_name, middleware: []]})

    subscribe!(bus_name, "skill.pre")

    path =
      write_skill_markdown(
        "dispatch_global_hooks",
        """
        name: dispatch-global-hooks
        description: Uses global hook defaults
        version: 1.0.0
        jido:
          actions:
            - JidoSkill.RuntimeDispatchActions.ExtractText
          router:
            - "pdf/extract/text": ExtractText
        """
      )

    global_hooks = %{
      pre: %{
        enabled: true,
        signal_type: "skill/pre",
        bus: bus_name,
        data: %{"origin" => "global"}
      }
    }

    assert {:ok, module} = Skill.from_markdown(path)
    {:ok, signal} = Signal.new("pdf.extract.text", %{}, source: "/tests")

    assert {:ok, _instruction} = module.handle_signal(signal, global_hooks: global_hooks)

    assert_receive {:signal, emitted}, 1_000
    assert emitted.type == "skill.pre"
    assert emitted.data["origin"] == "global"
    assert emitted.data["skill_name"] == "dispatch-global-hooks"
  end

  defp subscribe!(bus_name, signal_type) do
    assert {:ok, _subscription_id} =
             Bus.subscribe(bus_name, signal_type,
               dispatch: {:pid, target: self(), delivery_mode: :async}
             )
  end

  defp write_skill_markdown(prefix, frontmatter_body) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    tmp_dir = Path.join(System.tmp_dir!(), "jido_skill_dispatch_#{prefix}_#{suffix}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    path = Path.join(tmp_dir, "SKILL.md")

    File.write!(
      path,
      """
      ---
      #{String.trim(frontmatter_body)}
      ---

      # Runtime dispatch test
      """
    )

    path
  end
end
