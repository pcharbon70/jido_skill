defmodule JidoSkill.ConfigTest do
  use ExUnit.Case, async: true

  test "returns default skill runtime paths" do
    assert String.ends_with?(JidoSkill.Config.global_path(), ".jido_code")
    assert JidoSkill.Config.local_path() == ".jido_code"
    assert JidoSkill.Config.settings_path() == ".jido_code/settings.json"

    assert [global_skill_path, local_skill_path] = JidoSkill.Config.skill_paths()
    assert String.ends_with?(global_skill_path, "/.jido_code/skills")
    assert local_skill_path == ".jido_code/skills"
  end
end
