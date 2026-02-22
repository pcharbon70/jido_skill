defmodule Jido.Code.Skill.TestActions.ExtractPdfText do
end

defmodule Jido.Code.Skill.TestActions.ExtractPdfTables do
end

defmodule Jido.Code.Skill.SkillRuntime.SkillCompilerTest do
  use ExUnit.Case, async: true

  alias Jido.Code.Skill.SkillRuntime.Skill

  test "compiles a valid skill markdown file into a runtime module" do
    tmp = tmp_dir("valid")
    path = Path.join(tmp, "SKILL.md")

    File.write!(
      path,
      """
      ---
      name: pdf-processor
      description: Extract text and tables from PDFs
      version: 1.2.0
      allowed-tools: Read, Write, Bash(python:*)
      jido:
        actions:
          - Jido.Code.Skill.TestActions.ExtractPdfText
          - Jido.Code.Skill.TestActions.ExtractPdfTables
        router:
          - "pdf/extract/text": ExtractPdfText
          - "pdf/extract/tables": ExtractPdfTables
        hooks:
          pre:
            enabled: true
            signal_type: "skill/pdf_processor/pre"
            bus: ":jido_code_bus"
            data:
              source: "skill_frontmatter"
          post:
            enabled: true
            signal_type: "skill/pdf_processor/post"
            bus: ":jido_code_bus"
            data:
              source: "skill_frontmatter"
      ---

      # PDF Processor

      Body docs.
      """
    )

    assert {:ok, module} = Skill.from_markdown(path)

    metadata = module.skill_metadata()
    assert metadata.name == "pdf-processor"
    assert metadata.version == "1.2.0"
    assert metadata.description == "Extract text and tables from PDFs"

    assert module.allowed_tools() == ["Read", "Write", "Bash(python:*)"]

    assert module.actions() == [
             Jido.Code.Skill.TestActions.ExtractPdfText,
             Jido.Code.Skill.TestActions.ExtractPdfTables
           ]

    assert metadata.router == [
             {"pdf/extract/text", Jido.Code.Skill.TestActions.ExtractPdfText},
             {"pdf/extract/tables", Jido.Code.Skill.TestActions.ExtractPdfTables}
           ]

    assert is_binary(module.skill_documentation())
    assert String.contains?(module.skill_documentation(), "# PDF Processor")
  end

  test "returns an error when required fields are missing" do
    tmp = tmp_dir("missing_required")
    path = Path.join(tmp, "SKILL.md")

    File.write!(
      path,
      """
      ---
      description: Missing name
      version: 1.0.0
      jido:
        actions:
          - Jido.Code.Skill.TestActions.ExtractPdfText
        router:
          - "pdf/extract/text": ExtractPdfText
      ---
      """
    )

    assert {:error, {:missing_required_field, "name"}} = Skill.from_markdown(path)
  end

  test "returns an error when action modules are unresolved" do
    tmp = tmp_dir("unresolved_action")
    path = Path.join(tmp, "SKILL.md")

    File.write!(
      path,
      """
      ---
      name: unresolved-skill
      description: Action module is missing
      version: 1.0.0
      jido:
        actions:
          - Missing.Module.Action
        router:
          - "skill/run": Action
      ---
      """
    )

    assert {:error, {:unresolved_action_modules, [Missing.Module.Action]}} =
             Skill.from_markdown(path)
  end

  test "returns an error when jido contains unknown keys" do
    tmp = tmp_dir("unknown_jido_keys")
    path = Path.join(tmp, "SKILL.md")

    File.write!(
      path,
      """
      ---
      name: bad-jido
      description: Unknown jido key
      version: 1.0.0
      jido:
        actions:
          - Jido.Code.Skill.TestActions.ExtractPdfText
        router:
          - "pdf/extract/text": ExtractPdfText
        command: "not-supported"
      ---
      """
    )

    assert {:error, {:unknown_jido_key, "command"}} = Skill.from_markdown(path)
  end

  test "returns an error for invalid router paths" do
    tmp = tmp_dir("invalid_router_path")
    path = Path.join(tmp, "SKILL.md")

    File.write!(
      path,
      """
      ---
      name: invalid-router
      description: Invalid route path
      version: 1.0.0
      jido:
        actions:
          - Jido.Code.Skill.TestActions.ExtractPdfText
        router:
          - "pdf/Extract/Text": ExtractPdfText
      ---
      """
    )

    assert {:error, {:invalid_router_path, "pdf/Extract/Text"}} = Skill.from_markdown(path)
  end

  test "accepts router paths with hyphenated segments" do
    tmp = tmp_dir("hyphen_router_path")
    path = Path.join(tmp, "SKILL.md")

    File.write!(
      path,
      """
      ---
      name: hyphen-router
      description: Supports hyphenated route segments
      version: 1.0.0
      jido:
        actions:
          - Jido.Code.Skill.TestActions.ExtractPdfText
        router:
          - "pdf/extract-text": ExtractPdfText
      ---
      """
    )

    assert {:ok, module} = Skill.from_markdown(path)

    assert module.skill_metadata().router == [
             {"pdf/extract-text", Jido.Code.Skill.TestActions.ExtractPdfText}
           ]
  end

  test "returns an error when hook contains unknown keys" do
    tmp = tmp_dir("unknown_hook_key")
    path = Path.join(tmp, "SKILL.md")

    File.write!(
      path,
      """
      ---
      name: invalid-hook
      description: Unknown hook key
      version: 1.0.0
      jido:
        actions:
          - Jido.Code.Skill.TestActions.ExtractPdfText
        router:
          - "pdf/extract/text": ExtractPdfText
        hooks:
          pre:
            enabled: true
            signal_type: "skill/pre"
            bus: ":jido_code_bus"
            source: "bad-key"
      ---
      """
    )

    assert {:error, {:unknown_hook_keys, "pre", ["source"]}} = Skill.from_markdown(path)
  end

  test "returns an error when hook signal_type is invalid" do
    tmp = tmp_dir("invalid_hook_signal_type")
    path = Path.join(tmp, "SKILL.md")

    File.write!(
      path,
      """
      ---
      name: invalid-hook-signal
      description: Invalid hook signal type
      version: 1.0.0
      jido:
        actions:
          - Jido.Code.Skill.TestActions.ExtractPdfText
        router:
          - "pdf/extract/text": ExtractPdfText
        hooks:
          post:
            enabled: true
            signal_type: "Skill/Post"
            bus: ":jido_code_bus"
      ---
      """
    )

    assert {:error, {:invalid_hook_signal_type, "Skill/Post"}} = Skill.from_markdown(path)
  end

  test "preserves missing hook fields for runtime global fallback" do
    tmp = tmp_dir("hook_fallback_fields")
    path = Path.join(tmp, "SKILL.md")

    File.write!(
      path,
      """
      ---
      name: hook-fallback
      description: Hook fallback test
      version: 1.0.0
      jido:
        actions:
          - Jido.Code.Skill.TestActions.ExtractPdfText
        router:
          - "pdf/extract/text": ExtractPdfText
        hooks:
          pre:
            data:
              source: "frontmatter"
      ---
      """
    )

    assert {:ok, module} = Skill.from_markdown(path)
    metadata = module.skill_metadata()

    assert metadata.hooks.pre.enabled == nil
    assert metadata.hooks.pre.signal_type == nil
    assert metadata.hooks.pre.bus == nil
    assert metadata.hooks.pre.data == %{"source" => "frontmatter"}
  end

  test "uses jido skill_module override when provided" do
    tmp = tmp_dir("skill_module_override")
    path = Path.join(tmp, "SKILL.md")

    module_ref = "Jido.Code.Skill.TestCompiledSkills.Skill#{System.unique_integer([:positive])}"
    module = module_ref |> String.split(".") |> Module.concat()

    File.write!(
      path,
      """
      ---
      name: module-override
      description: Uses explicit skill module
      version: 1.0.0
      jido:
        skill_module: #{module_ref}
        actions:
          - Jido.Code.Skill.TestActions.ExtractPdfText
        router:
          - "pdf/extract/text": ExtractPdfText
      ---
      """
    )

    assert {:ok, ^module} = Skill.from_markdown(path)
  end

  test "returns an error when skill_module format is invalid" do
    tmp = tmp_dir("invalid_skill_module")
    path = Path.join(tmp, "SKILL.md")

    File.write!(
      path,
      """
      ---
      name: invalid-skill-module
      description: Invalid skill module format
      version: 1.0.0
      jido:
        skill_module: "Jido.Code.Skill.Invalid-Module"
        actions:
          - Jido.Code.Skill.TestActions.ExtractPdfText
        router:
          - "pdf/extract/text": ExtractPdfText
      ---
      """
    )

    assert {:error, {:invalid_skill_module, "Jido.Code.Skill.Invalid-Module"}} =
             Skill.from_markdown(path)
  end

  test "returns an error when skill_module points at an existing runtime module" do
    tmp = tmp_dir("existing_runtime_module")
    path = Path.join(tmp, "SKILL.md")

    File.write!(
      path,
      """
      ---
      name: existing-runtime-module
      description: Should not override runtime modules
      version: 1.0.0
      jido:
        skill_module: Jido.Code.Skill.SkillRuntime.Skill
        actions:
          - Jido.Code.Skill.TestActions.ExtractPdfText
        router:
          - "pdf/extract/text": ExtractPdfText
      ---
      """
    )

    assert {:error, {:skill_module_already_defined, Jido.Code.Skill.SkillRuntime.Skill}} =
             Skill.from_markdown(path)
  end

  test "returns an error when explicit skill_module is reused by another source path" do
    tmp = tmp_dir("skill_module_conflict")

    shared_module_ref =
      "Jido.Code.Skill.TestCompiledSkills.Conflict#{System.unique_integer([:positive])}"

    shared_module = shared_module_ref |> String.split(".") |> Module.concat()
    path_one = Path.join(tmp, "one_SKILL.md")
    path_two = Path.join(tmp, "two_SKILL.md")

    File.write!(
      path_one,
      """
      ---
      name: skill-module-conflict-one
      description: First skill owns module
      version: 1.0.0
      jido:
        skill_module: #{shared_module_ref}
        actions:
          - Jido.Code.Skill.TestActions.ExtractPdfText
        router:
          - "pdf/extract/text": ExtractPdfText
      ---
      """
    )

    File.write!(
      path_two,
      """
      ---
      name: skill-module-conflict-two
      description: Second skill collides module
      version: 1.0.0
      jido:
        skill_module: #{shared_module_ref}
        actions:
          - Jido.Code.Skill.TestActions.ExtractPdfTables
        router:
          - "pdf/extract/tables": ExtractPdfTables
      ---
      """
    )

    assert {:ok, ^shared_module} = Skill.from_markdown(path_one)

    assert {:error, {:skill_module_conflict, ^shared_module, ^path_one}} =
             Skill.from_markdown(path_two)
  end

  test "allows recompiling explicit skill_module from the same source path" do
    tmp = tmp_dir("skill_module_recompile")
    path = Path.join(tmp, "SKILL.md")
    module_ref = "Jido.Code.Skill.TestCompiledSkills.Recompile#{System.unique_integer([:positive])}"
    module = module_ref |> String.split(".") |> Module.concat()

    File.write!(
      path,
      """
      ---
      name: skill-module-recompile
      description: Recompiles from same source path
      version: 1.0.0
      jido:
        skill_module: #{module_ref}
        actions:
          - Jido.Code.Skill.TestActions.ExtractPdfText
        router:
          - "pdf/extract/text": ExtractPdfText
      ---
      """
    )

    assert {:ok, ^module} = Skill.from_markdown(path)
    assert {:ok, ^module} = Skill.from_markdown(path)
  end

  defp tmp_dir(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    path = Path.join(System.tmp_dir!(), "jido_skill_compiler_#{prefix}_#{suffix}")

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
