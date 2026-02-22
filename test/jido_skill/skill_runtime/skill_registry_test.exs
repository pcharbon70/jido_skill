defmodule Jido.Code.Skill.SkillRuntime.SkillRegistryTest do
  use ExUnit.Case, async: false

  alias Jido.Code.Skill.SkillRuntime.SkillRegistry

  test "registry scaffold APIs work" do
    assert %{pre: pre_hook, post: post_hook} = SkillRegistry.hook_defaults()

    assert is_map(pre_hook)
    assert is_map(post_hook)
    assert nil == SkillRegistry.get_skill("missing-skill")
    assert :ok = SkillRegistry.reload()
  end
end
