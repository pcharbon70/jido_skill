defmodule JidoSkill.Contracts.SkillFrontmatterSchemaTest do
  use ExUnit.Case, async: true

  test "allows hyphenated router segments and validates skill_module format" do
    schema = load_schema!()

    assert get_in(schema, [
             "properties",
             "jido",
             "properties",
             "router",
             "items",
             "propertyNames",
             "pattern"
           ]) == "^[a-z0-9_-]+(?:/[a-z0-9_-]+)*$"

    assert get_in(schema, [
             "properties",
             "jido",
             "properties",
             "skill_module",
             "pattern"
           ]) == "^[A-Za-z_][A-Za-z0-9_.]*$"
  end

  test "keeps hook override fields optional" do
    schema = load_schema!()
    hook_override = get_in(schema, ["$defs", "hookOverride"])

    assert hook_override["type"] == "object"
    assert hook_override["additionalProperties"] == false
    refute Map.has_key?(hook_override, "required")
  end

  defp load_schema! do
    root = Path.expand("../../..", __DIR__)
    path = Path.join(root, "schemas/skill-frontmatter.schema.json")
    {:ok, content} = File.read(path)
    {:ok, schema} = Jason.decode(content)
    schema
  end
end
