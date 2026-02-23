defmodule Jido.Code.Skill.CLITest do
  use ExUnit.Case, async: true

  alias Jido.Code.Skill.CLI

  test "routes shorthand invocation to skill.run when --skill is first" do
    assert {:ok, "skill.run", ["pdf-processor", "--route", "pdf/extract/text"]} =
             CLI.resolve(["--skill", "pdf-processor", "--route", "pdf/extract/text"])
  end

  test "routes explicit run subcommand" do
    assert {:ok, "skill.run", ["pdf-processor", "--data", ~s({"file":"report.pdf"})]} =
             CLI.resolve(["--skill", "run", "pdf-processor", "--data", ~s({"file":"report.pdf"})])
  end

  test "supports optional skill prefix before run subcommand" do
    assert {:ok, "skill.run", ["pdf-processor", "--route", "pdf/extract/text"]} =
             CLI.resolve([
               "--skill",
               "skill",
               "run",
               "pdf-processor",
               "--route",
               "pdf/extract/text"
             ])
  end

  test "rejects missing and invalid skill invocations" do
    assert {:error, :missing_command} = CLI.resolve([])
    assert {:error, :missing_command} = CLI.resolve(["--skill"])
    assert {:error, :missing_skill} = CLI.resolve(["--skill", "run"])
    assert {:error, :missing_skill} = CLI.resolve(["--skill", "--route", "pdf/extract/text"])
  end

  test "rejects invocations without --skill prefix" do
    assert {:error, :skill_prefix_required} = CLI.resolve(["pdf-processor", "--route", "a/b"])
    assert {:error, :skill_prefix_required} = CLI.resolve(["run", "pdf-processor"])
  end

  test "routes help inputs to usage" do
    assert {:error, :help} = CLI.resolve(["help"])
    assert {:error, :help} = CLI.resolve(["--help"])
    assert {:error, :help} = CLI.resolve(["-h"])
    assert {:error, :help} = CLI.resolve(["--skill", "--help"])
  end
end
