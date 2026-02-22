defmodule Jido.Code.Skill.Config.Settings do
  @moduledoc """
  Loads and validates runtime settings from global and local JSON files.

  Merge order: defaults <- global <- local.
  """

  alias Jido.Code.Skill.Config

  @type hook_config :: %{
          enabled: boolean(),
          signal_type: String.t(),
          bus: atom() | String.t(),
          data: map()
        }

  @type signal_bus_config :: %{
          name: atom() | String.t(),
          middleware: keyword()
        }

  @type t :: %{
          version: String.t(),
          signal_bus: signal_bus_config(),
          permissions: map(),
          hooks: %{pre: hook_config(), post: hook_config()}
        }

  @root_keys ~w(version signal_bus permissions hooks)
  @signal_bus_keys ~w(name middleware)
  @hook_keys ~w(enabled signal_type bus data_template)

  @spec load(keyword()) :: {:ok, t()} | {:error, term()}
  def load(opts \\ []) do
    global_path =
      Keyword.get(opts, :global_settings_path, Path.join(Config.global_path(), "settings.json"))

    local_path = Keyword.get(opts, :local_settings_path, Config.settings_path())

    with {:ok, global_settings} <- read_json_if_exists(global_path),
         {:ok, local_settings} <- read_json_if_exists(local_path) do
      merged = deep_merge(default_settings(), deep_merge(global_settings, local_settings))

      case validate(merged) do
        :ok -> normalize(merged)
        {:error, _reason} = error -> error
      end
    end
  end

  @spec validate(map()) :: :ok | {:error, term()}
  def validate(settings) when is_map(settings) do
    with :ok <- validate_allowed_keys(settings, @root_keys, :root),
         :ok <- validate_version(settings["version"]),
         :ok <- validate_signal_bus(settings["signal_bus"]),
         :ok <- validate_permissions(settings["permissions"]) do
      validate_hooks(settings["hooks"])
    end
  end

  def validate(_invalid), do: {:error, {:invalid_settings, :must_be_object}}

  defp read_json_if_exists(path) do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
          {:ok, _invalid} -> {:error, {:invalid_settings_file, path, :must_be_json_object}}
          {:error, reason} -> {:error, {:invalid_settings_file, path, {:invalid_json, reason}}}
        end

      {:error, :enoent} ->
        {:ok, %{}}

      {:error, reason} ->
        {:error, {:invalid_settings_file, path, reason}}
    end
  end

  defp validate_version(version) when is_binary(version) do
    if Regex.match?(~r/^\d+\.\d+\.\d+$/, version) do
      :ok
    else
      {:error, {:invalid_version, version}}
    end
  end

  defp validate_version(version), do: {:error, {:invalid_version, version}}

  defp validate_signal_bus(signal_bus) when is_map(signal_bus) do
    with :ok <- validate_allowed_keys(signal_bus, @signal_bus_keys, :signal_bus),
         :ok <- validate_bus_name(signal_bus["name"]) do
      validate_middleware(signal_bus["middleware"])
    end
  end

  defp validate_signal_bus(_invalid), do: {:error, {:invalid_signal_bus, :must_be_object}}

  defp validate_permissions(nil), do: :ok

  defp validate_permissions(permissions) when is_map(permissions) do
    allowed = MapSet.new(["allow", "deny", "ask"])

    with :ok <- validate_allowed_keys(permissions, MapSet.to_list(allowed), :permissions),
         :ok <- validate_permission_list(permissions["allow"], :allow),
         :ok <- validate_permission_list(permissions["deny"], :deny) do
      validate_permission_list(permissions["ask"], :ask)
    end
  end

  defp validate_permissions(_invalid), do: {:error, {:invalid_permissions, :must_be_object}}

  defp validate_permission_list(nil, _key), do: :ok

  defp validate_permission_list(list, key) when is_list(list) do
    if Enum.all?(list, &is_binary/1) do
      :ok
    else
      {:error, {:invalid_permissions, key, :must_be_string_list}}
    end
  end

  defp validate_permission_list(_invalid, key),
    do: {:error, {:invalid_permissions, key, :must_be_list}}

  defp validate_hooks(hooks) when is_map(hooks) do
    with :ok <- validate_allowed_keys(hooks, ["pre", "post"], :hooks),
         :ok <- validate_hook(hooks["pre"], :pre) do
      validate_hook(hooks["post"], :post)
    end
  end

  defp validate_hooks(_invalid), do: {:error, {:invalid_hooks, :must_be_object}}

  defp validate_hook(hook, key) when is_map(hook) do
    with :ok <- validate_allowed_keys(hook, @hook_keys, {:hook, key}),
         :ok <- validate_enabled(hook["enabled"], key),
         :ok <- validate_hook_signal_type(hook["signal_type"], key),
         :ok <- validate_hook_bus(hook["bus"], key) do
      validate_data_template(hook["data_template"], key)
    end
  end

  defp validate_hook(_invalid, key), do: {:error, {:invalid_hook, key, :must_be_object}}

  defp validate_enabled(value, _key) when is_boolean(value), do: :ok
  defp validate_enabled(value, key), do: {:error, {:invalid_hook, key, {:invalid_enabled, value}}}

  defp validate_hook_signal_type(value, _key)
       when is_binary(value) and value != "" do
    if Regex.match?(~r/^[a-z0-9_]+(?:\/[a-z0-9_]+)*$/, value) do
      :ok
    else
      {:error, {:invalid_hook, :signal_type_format}}
    end
  end

  defp validate_hook_signal_type(value, key),
    do: {:error, {:invalid_hook, key, {:invalid_signal_type, value}}}

  defp validate_hook_bus(value, _key) when is_atom(value), do: :ok

  defp validate_hook_bus(value, _key) when is_binary(value) do
    if Regex.match?(~r/^:?[A-Za-z_][A-Za-z0-9_]*$/, value) do
      :ok
    else
      {:error, {:invalid_hook, :bus_format}}
    end
  end

  defp validate_hook_bus(value, key), do: {:error, {:invalid_hook, key, {:invalid_bus, value}}}

  defp validate_data_template(nil, _key), do: :ok

  defp validate_data_template(template, _key) when is_map(template) do
    if Enum.all?(template, fn {_k, v} ->
         is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v)
       end) do
      :ok
    else
      {:error, {:invalid_hook, :data_template, :unsupported_value_type}}
    end
  end

  defp validate_data_template(_invalid, key),
    do: {:error, {:invalid_hook, key, :data_template_must_be_object}}

  defp validate_bus_name(name) when is_atom(name), do: :ok

  defp validate_bus_name(name) when is_binary(name) do
    if Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, name) do
      :ok
    else
      {:error, {:invalid_signal_bus_name, name}}
    end
  end

  defp validate_bus_name(name), do: {:error, {:invalid_signal_bus_name, name}}

  defp validate_middleware(list) when is_list(list) do
    if Enum.all?(list, &valid_middleware_entry?/1) do
      :ok
    else
      {:error, :invalid_signal_bus_middleware}
    end
  end

  defp validate_middleware(_invalid), do: {:error, :invalid_signal_bus_middleware}

  defp valid_middleware_entry?(entry) do
    is_map(entry) and is_binary(entry["module"]) and
      (is_map(entry["opts"]) or is_nil(entry["opts"]))
  end

  defp validate_allowed_keys(map, allowed_keys, scope) do
    allowed = MapSet.new(allowed_keys)

    unknown_keys =
      map
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(allowed, &1))

    case unknown_keys do
      [] -> :ok
      keys -> {:error, {:unknown_keys, scope, keys}}
    end
  end

  defp normalize(merged) do
    with {:ok, signal_bus} <- normalize_signal_bus(merged["signal_bus"]) do
      {:ok,
       %{
         version: merged["version"],
         signal_bus: signal_bus,
         permissions: merged["permissions"],
         hooks: %{
           pre: normalize_hook(merged["hooks"]["pre"]),
           post: normalize_hook(merged["hooks"]["post"])
         }
       }}
    end
  end

  defp normalize_signal_bus(signal_bus) do
    middleware =
      signal_bus["middleware"]
      |> Enum.map(fn middleware_entry ->
        module =
          middleware_entry["module"]
          |> String.trim_leading("Elixir.")
          |> String.split(".")
          |> Module.concat()

        opts = middleware_entry["opts"] |> normalize_opts()
        {module, opts}
      end)

    {:ok,
     %{
       name: normalize_bus_name(signal_bus["name"]),
       middleware: middleware
     }}
  rescue
    ArgumentError ->
      {:error, :invalid_signal_bus_middleware}
  end

  defp normalize_hook(hook) do
    %{
      enabled: hook["enabled"],
      signal_type: hook["signal_type"],
      bus: normalize_bus_name(hook["bus"]),
      data: hook["data_template"] || %{}
    }
  end

  defp normalize_bus_name(name) when is_atom(name), do: name

  defp normalize_bus_name(":" <> bus_name) do
    case safe_to_existing_atom(bus_name) do
      {:ok, atom_name} -> atom_name
      :error -> bus_name
    end
  end

  defp normalize_bus_name(name), do: name

  defp normalize_opts(nil), do: []

  defp normalize_opts(opts) do
    Enum.map(opts, fn {key, value} ->
      normalized_key =
        case key do
          "level" -> :level
          _ -> key
        end

      normalized_value =
        case value do
          "debug" -> :debug
          "info" -> :info
          "warning" -> :warning
          "error" -> :error
          _ -> value
        end

      {normalized_key, normalized_value}
    end)
  end

  defp default_settings do
    bus_name = Config.signal_bus_name()

    %{
      "version" => "2.0.0",
      "signal_bus" => %{
        "name" => bus_name,
        "middleware" =>
          Enum.map(Config.signal_bus_middleware(), fn {module, opts} ->
            %{
              "module" => Atom.to_string(module),
              "opts" =>
                Enum.into(opts, %{}, fn {k, v} ->
                  {Atom.to_string(k), normalize_default_opt(v)}
                end)
            }
          end)
      },
      "permissions" => %{
        "allow" => [],
        "deny" => [],
        "ask" => []
      },
      "hooks" => %{
        "pre" => %{
          "enabled" => true,
          "signal_type" => "skill/pre",
          "bus" => bus_name,
          "data_template" => %{}
        },
        "post" => %{
          "enabled" => true,
          "signal_type" => "skill/post",
          "bus" => bus_name,
          "data_template" => %{}
        }
      }
    }
  end

  defp normalize_default_opt(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_default_opt(value), do: value

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(_left, right), do: right

  defp safe_to_existing_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> :error
  end
end
