defmodule JidoSkill.TestActions.ExtractPdfText do
end

defmodule JidoSkill.TestActions.ExtractPdfTables do
end

defmodule JidoSkill.SkillRuntime.SkillCompilerTest do
  use ExUnit.Case, async: true

  alias JidoSkill.SkillRuntime.Skill

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
          - JidoSkill.TestActions.ExtractPdfText
          - JidoSkill.TestActions.ExtractPdfTables
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
             JidoSkill.TestActions.ExtractPdfText,
             JidoSkill.TestActions.ExtractPdfTables
           ]

    assert metadata.router == [
             {"pdf/extract/text", JidoSkill.TestActions.ExtractPdfText},
             {"pdf/extract/tables", JidoSkill.TestActions.ExtractPdfTables}
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
          - JidoSkill.TestActions.ExtractPdfText
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

  defp tmp_dir(prefix) do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_skill_compiler_#{prefix}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
  end
end
