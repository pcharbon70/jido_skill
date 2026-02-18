defmodule JidoSkill.SkillRuntime.SkillRegistryTest do
  use ExUnit.Case, async: false

  test "registry scaffold APIs work" do
    assert %{} = JidoSkill.SkillRuntime.SkillRegistry.hook_defaults()
    assert nil == JidoSkill.SkillRuntime.SkillRegistry.get_skill("missing-skill")
    assert :ok = JidoSkill.SkillRuntime.SkillRegistry.reload()
  end
end
