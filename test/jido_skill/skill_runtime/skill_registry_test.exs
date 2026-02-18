defmodule JidoSkill.SkillRuntime.SkillRegistryTest do
  use ExUnit.Case, async: false

  test "registry scaffold APIs work" do
    assert %{pre: pre_hook, post: post_hook} =
             JidoSkill.SkillRuntime.SkillRegistry.hook_defaults()

    assert is_map(pre_hook)
    assert is_map(post_hook)
    assert nil == JidoSkill.SkillRuntime.SkillRegistry.get_skill("missing-skill")
    assert :ok = JidoSkill.SkillRuntime.SkillRegistry.reload()
  end
end
