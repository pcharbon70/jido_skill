defmodule JidoSkillTest do
  use ExUnit.Case
  doctest JidoSkill

  test "greets the world" do
    assert JidoSkill.hello() == :world
  end
end
