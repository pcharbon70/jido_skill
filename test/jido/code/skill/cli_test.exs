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

  test "routes list subcommand" do
    assert {:ok, "skill.list", ["--scope", "local"]} =
             CLI.resolve(["--skill", "list", "--scope", "local"])

    assert {:ok, "skill.list", ["--permission-status", "ask"]} =
             CLI.resolve(["--skill", "skill", "list", "--permission-status", "ask"])
  end

  test "routes reload subcommand" do
    assert {:ok, "skill.reload", ["--registry", "my_registry"]} =
             CLI.resolve(["--skill", "reload", "--registry", "my_registry"])

    assert {:ok, "skill.reload", ["--no-start-app"]} =
             CLI.resolve(["--skill", "skill", "reload", "--no-start-app"])
  end

  test "routes routes subcommand" do
    assert {:ok, "skill.routes", ["--reload"]} =
             CLI.resolve(["--skill", "routes", "--reload"])

    assert {:ok, "skill.routes", ["--dispatcher", "my_dispatcher"]} =
             CLI.resolve(["--skill", "skill", "routes", "--dispatcher", "my_dispatcher"])
  end

  test "routes watch subcommand" do
    assert {:ok, "skill.watch", ["--pattern", "skill.pre"]} =
             CLI.resolve(["--skill", "watch", "--pattern", "skill.pre"])

    assert {:ok, "skill.watch", ["--timeout", "1000"]} =
             CLI.resolve(["--skill", "skill", "watch", "--timeout", "1000"])
  end

  test "routes signal subcommand" do
    assert {:ok, "skill.signal", ["skill.pre", "--data", ~s({"value":"hello"})]} =
             CLI.resolve(["--skill", "signal", "skill.pre", "--data", ~s({"value":"hello"})])

    assert {:ok, "skill.signal", ["skill.post"]} =
             CLI.resolve(["--skill", "skill", "signal", "skill.post"])
  end

  test "supports running a skill literally named list using explicit run subcommand" do
    assert {:ok, "skill.run", ["list", "--route", "demo/route"]} =
             CLI.resolve(["--skill", "run", "list", "--route", "demo/route"])
  end

  test "supports running a skill literally named reload using explicit run subcommand" do
    assert {:ok, "skill.run", ["reload", "--route", "demo/route"]} =
             CLI.resolve(["--skill", "run", "reload", "--route", "demo/route"])
  end

  test "supports running a skill literally named routes using explicit run subcommand" do
    assert {:ok, "skill.run", ["routes", "--route", "demo/route"]} =
             CLI.resolve(["--skill", "run", "routes", "--route", "demo/route"])
  end

  test "supports running a skill literally named watch using explicit run subcommand" do
    assert {:ok, "skill.run", ["watch", "--route", "demo/route"]} =
             CLI.resolve(["--skill", "run", "watch", "--route", "demo/route"])
  end

  test "supports running a skill literally named signal using explicit run subcommand" do
    assert {:ok, "skill.run", ["signal", "--route", "demo/route"]} =
             CLI.resolve(["--skill", "run", "signal", "--route", "demo/route"])
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
