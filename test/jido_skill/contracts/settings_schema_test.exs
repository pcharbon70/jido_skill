defmodule Jido.Code.Skill.Contracts.SettingsSchemaTest do
  use ExUnit.Case, async: true

  test "allows middleware opts to be object or null" do
    schema = load_schema!()

    assert get_in(schema, [
             "properties",
             "signal_bus",
             "properties",
             "middleware",
             "items",
             "properties",
             "opts",
             "type"
           ]) == ["object", "null"]
  end

  test "requires pre and post hooks in schema contract" do
    schema = load_schema!()

    assert get_in(schema, ["properties", "hooks", "required"]) == ["pre", "post"]
  end

  defp load_schema! do
    root = Path.expand("../../..", __DIR__)
    path = Path.join(root, "schemas/settings.schema.json")
    {:ok, content} = File.read(path)
    {:ok, schema} = Jason.decode(content)
    schema
  end
end
