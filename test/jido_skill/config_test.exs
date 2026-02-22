defmodule Jido.Code.Skill.ConfigTest do
  use ExUnit.Case, async: true

  alias Jido.Code.Skill.Config

  test "returns default skill runtime paths" do
    assert String.ends_with?(Config.global_path(), ".jido_code")
    assert Config.local_path() == ".jido_code"
    assert Config.settings_path() == ".jido_code/settings.json"

    assert [global_skill_path, local_skill_path] = Config.skill_paths()
    assert String.ends_with?(global_skill_path, "/.jido_code/skills")
    assert local_skill_path == ".jido_code/skills"
  end
end
