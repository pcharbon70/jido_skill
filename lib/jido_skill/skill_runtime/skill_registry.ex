defmodule JidoSkill.SkillRuntime.SkillRegistry do
  @moduledoc """
  Registry for discovered skill definitions and hook defaults.

  Phase 3 implements skill discovery and deterministic conflict handling:
  local skill definitions override global definitions when names collide.
  """

  use GenServer

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoSkill.SkillRuntime.Skill

  require Logger

  @type hook_defaults :: %{optional(:pre) => map(), optional(:post) => map()}

  @type skill_entry :: %{
          name: String.t(),
          description: String.t() | nil,
          version: String.t() | nil,
          path: String.t(),
          scope: :global | :local,
          module: module() | nil,
          loaded_at: DateTime.t()
        }

  defstruct skills: %{},
            skill_paths: [],
            hook_defaults: %{},
            bus_name: :jido_code_bus,
            settings_path: nil,
            global_path: nil,
            local_path: nil

  @type t :: %__MODULE__{
          skills: %{optional(String.t()) => skill_entry()},
          skill_paths: [String.t()],
          hook_defaults: hook_defaults(),
          bus_name: atom() | String.t(),
          settings_path: String.t() | nil,
          global_path: String.t() | nil,
          local_path: String.t() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    if is_nil(name) do
      GenServer.start_link(__MODULE__, opts)
    else
      GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec get_skill(String.t()) :: skill_entry() | nil
  def get_skill(name), do: get_skill(__MODULE__, name)

  @spec get_skill(GenServer.server(), String.t()) :: skill_entry() | nil
  def get_skill(server, name), do: GenServer.call(server, {:get_skill, name})

  @spec list_skills() :: [skill_entry()]
  def list_skills, do: list_skills(__MODULE__)

  @spec list_skills(GenServer.server()) :: [skill_entry()]
  def list_skills(server), do: GenServer.call(server, :list_skills)

  @spec hook_defaults() :: hook_defaults()
  def hook_defaults, do: hook_defaults(__MODULE__)

  @spec hook_defaults(GenServer.server()) :: hook_defaults()
  def hook_defaults(server), do: GenServer.call(server, :hook_defaults)

  @spec reload() :: :ok
  def reload, do: reload(__MODULE__)

  @spec reload(GenServer.server()) :: :ok
  def reload(server), do: GenServer.call(server, :reload)

  @impl GenServer
  def init(opts) do
    global_path = Keyword.get(opts, :global_path)
    local_path = Keyword.get(opts, :local_path)

    state = %__MODULE__{
      hook_defaults: Keyword.get(opts, :hook_defaults, %{}),
      bus_name: Keyword.get(opts, :bus_name, :jido_code_bus),
      settings_path: Keyword.get(opts, :settings_path),
      global_path: global_path,
      local_path: local_path,
      skill_paths: Keyword.get(opts, :skill_paths, skill_paths(global_path, local_path))
    }

    {:ok, load_all_skills(state)}
  end

  @impl GenServer
  def handle_call({:get_skill, name}, _from, state) do
    {:reply, Map.get(state.skills, name), state}
  end

  @impl GenServer
  def handle_call(:list_skills, _from, state) do
    list = state.skills |> Map.values() |> Enum.sort_by(& &1.name)
    {:reply, list, state}
  end

  @impl GenServer
  def handle_call(:hook_defaults, _from, state) do
    {:reply, state.hook_defaults, state}
  end

  @impl GenServer
  def handle_call(:reload, _from, state) do
    new_state = load_all_skills(%{state | skills: %{}})
    publish_registry_update(new_state)
    {:reply, :ok, new_state}
  end

  defp skill_paths(nil, nil), do: []

  defp skill_paths(global_path, local_path) do
    [global_path, local_path]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Path.join(&1, "skills"))
  end

  defp load_all_skills(state) do
    loaded_at = DateTime.utc_now()

    global_skills =
      state
      |> scope_root(:global)
      |> load_skills_from_root(:global, loaded_at)

    local_skills =
      state
      |> scope_root(:local)
      |> load_skills_from_root(:local, loaded_at)

    merged_skills = merge_skills(global_skills, local_skills)

    %{state | skills: merged_skills}
  end

  defp scope_root(state, :global), do: expand_root(state.global_path)
  defp scope_root(state, :local), do: expand_root(state.local_path)

  defp expand_root(nil), do: nil

  defp expand_root("~/" <> rest), do: Path.join(System.user_home!(), rest)
  defp expand_root(path), do: path

  defp load_skills_from_root(nil, _scope, _loaded_at), do: %{}

  defp load_skills_from_root(root, scope, loaded_at) do
    root
    |> skill_files()
    |> Enum.reduce(%{}, fn path, acc ->
      case parse_skill_file(path, scope, loaded_at) do
        {:ok, skill} ->
          case Map.fetch(acc, skill.name) do
            {:ok, existing} ->
              Logger.warning(
                "duplicate #{scope} skill name #{skill.name} encountered; " <>
                  "keeping #{existing.path} and ignoring #{path}"
              )

              acc

            :error ->
              Map.put(acc, skill.name, skill)
          end

        {:error, reason} ->
          Logger.warning("skipping skill file #{path}: #{inspect(reason)}")
          acc
      end
    end)
  end

  defp skill_files(root) do
    root
    |> Path.join("**/SKILL.md")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp parse_skill_file(path, scope, loaded_at) do
    with {:ok, module} <- Skill.from_markdown(path),
         metadata <- module.skill_metadata(),
         {:ok, name} <- required_metadata_field(metadata, :name) do
      {:ok,
       %{
         name: name,
         description: Map.get(metadata, :description),
         version: Map.get(metadata, :version),
         path: path,
         scope: scope,
         module: module,
         loaded_at: loaded_at
       }}
    end
  end

  defp required_metadata_field(metadata, key) do
    case Map.get(metadata, key) do
      nil -> {:error, {:missing_required_metadata_field, key}}
      "" -> {:error, {:missing_required_metadata_field, key}}
      value -> {:ok, value}
    end
  end

  defp merge_skills(global_skills, local_skills) do
    Map.merge(global_skills, local_skills, fn name, global_skill, local_skill ->
      Logger.info(
        "local skill #{name} from #{local_skill.path} overrides global skill from #{global_skill.path}"
      )

      local_skill
    end)
  end

  defp publish_registry_update(state) do
    payload = %{skills: Map.keys(state.skills), count: map_size(state.skills)}
    signal_type = normalize_signal_type("skill/registry/updated")

    with {:ok, signal} <-
           Signal.new(signal_type, payload, source: "/skill_registry"),
         {:ok, _recorded} <- Bus.publish(state.bus_name, [signal]) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("failed to publish skill registry update: #{inspect(reason)}")
        :ok
    end
  end

  defp normalize_signal_type(type), do: String.replace(type, "/", ".")
end
