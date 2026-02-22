defmodule Jido.Code.SkillTest do
  use ExUnit.Case

  alias Jido.Code.Skill

  doctest Skill

  test "greets the world" do
    assert Skill.hello() == :world
  end
end
