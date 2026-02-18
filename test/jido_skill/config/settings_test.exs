defmodule JidoSkill.Config.SettingsTest do
  use ExUnit.Case, async: true

  alias JidoSkill.Config.Settings

  test "loads defaults when settings files are missing" do
    tmp_dir = tmp_dir()

    assert {:ok, settings} =
             Settings.load(
               global_settings_path: Path.join(tmp_dir, "global-settings.json"),
               local_settings_path: Path.join(tmp_dir, "local-settings.json")
             )

    assert settings.version == "2.0.0"
    assert settings.signal_bus.name == :jido_code_bus
    assert settings.hooks.pre.signal_type == "skill/pre"
    assert settings.hooks.post.signal_type == "skill/post"
  end

  test "merges global and local settings with local precedence" do
    tmp_dir = tmp_dir()
    global_path = Path.join(tmp_dir, "global-settings.json")
    local_path = Path.join(tmp_dir, "local-settings.json")

    global_settings = %{
      "version" => "2.0.0",
      "signal_bus" => %{"name" => "global_bus", "middleware" => []},
      "permissions" => %{"allow" => ["Read"], "deny" => [], "ask" => []},
      "hooks" => %{
        "pre" => %{
          "enabled" => true,
          "signal_type" => "skill/global_pre",
          "bus" => ":global_bus",
          "data_template" => %{"scope" => "global"}
        },
        "post" => %{
          "enabled" => true,
          "signal_type" => "skill/global_post",
          "bus" => ":global_bus",
          "data_template" => %{"scope" => "global"}
        }
      }
    }

    local_settings = %{
      "signal_bus" => %{"name" => "local_bus", "middleware" => []},
      "hooks" => %{
        "pre" => %{
          "enabled" => false,
          "signal_type" => "skill/local_pre",
          "bus" => ":local_bus",
          "data_template" => %{"scope" => "local"}
        },
        "post" => %{
          "enabled" => true,
          "signal_type" => "skill/local_post",
          "bus" => ":local_bus",
          "data_template" => %{"scope" => "local"}
        }
      }
    }

    File.write!(global_path, Jason.encode!(global_settings))
    File.write!(local_path, Jason.encode!(local_settings))

    assert {:ok, settings} =
             Settings.load(global_settings_path: global_path, local_settings_path: local_path)

    assert settings.signal_bus.name == "local_bus"
    assert settings.hooks.pre.enabled == false
    assert settings.hooks.pre.signal_type == "skill/local_pre"
    assert settings.hooks.post.signal_type == "skill/local_post"
    assert settings.hooks.pre.data["scope"] == "local"
  end

  test "rejects unknown root keys" do
    tmp_dir = tmp_dir()
    global_path = Path.join(tmp_dir, "global-settings.json")
    local_path = Path.join(tmp_dir, "local-settings.json")

    File.write!(global_path, Jason.encode!(%{"surprise" => true}))

    assert {:error, {:unknown_keys, :root, ["surprise"]}} =
             Settings.load(global_settings_path: global_path, local_settings_path: local_path)
  end

  test "rejects invalid hook signal type format" do
    tmp_dir = tmp_dir()
    global_path = Path.join(tmp_dir, "global-settings.json")
    local_path = Path.join(tmp_dir, "local-settings.json")

    invalid_settings = %{
      "version" => "2.0.0",
      "signal_bus" => %{"name" => "jido_code_bus", "middleware" => []},
      "permissions" => %{"allow" => [], "deny" => [], "ask" => []},
      "hooks" => %{
        "pre" => %{
          "enabled" => true,
          "signal_type" => "Skill/Bad",
          "bus" => ":jido_code_bus",
          "data_template" => %{}
        },
        "post" => %{
          "enabled" => true,
          "signal_type" => "skill/post",
          "bus" => ":jido_code_bus",
          "data_template" => %{}
        }
      }
    }

    File.write!(global_path, Jason.encode!(invalid_settings))

    assert {:error, {:invalid_hook, :signal_type_format}} =
             Settings.load(global_settings_path: global_path, local_settings_path: local_path)
  end

  defp tmp_dir do
    path =
      Path.join(System.tmp_dir!(), "jido_skill_settings_#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    path
  end
end
