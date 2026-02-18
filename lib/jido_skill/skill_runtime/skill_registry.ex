defmodule JidoSkill.SkillRuntime.SkillRegistry do
  @moduledoc """
  Registry for loaded skill modules and hook defaults.

  Phase 1 intentionally ships discovery/loading as a no-op scaffold to
  establish supervision and API shape before parser/compiler work begins.
  """

  use GenServer

  alias Jido.Signal
  alias Jido.Signal.Bus

  require Logger

  @type hook_defaults :: %{optional(:pre) => map(), optional(:post) => map()}

  defstruct skills: %{},
            skill_paths: [],
            hook_defaults: %{},
            bus_name: :jido_code_bus,
            settings_path: nil,
            global_path: nil,
            local_path: nil

  @type t :: %__MODULE__{
          skills: map(),
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
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec get_skill(String.t()) :: module() | nil
  def get_skill(name), do: GenServer.call(__MODULE__, {:get_skill, name})

  @spec hook_defaults() :: hook_defaults()
  def hook_defaults, do: GenServer.call(__MODULE__, :hook_defaults)

  @spec reload() :: :ok
  def reload, do: GenServer.call(__MODULE__, :reload)

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
    # Phase 1 scaffold: discovery and compilation are implemented in later phases.
    %{state | skills: %{}}
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
