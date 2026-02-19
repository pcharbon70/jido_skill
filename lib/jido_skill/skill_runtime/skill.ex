defmodule JidoSkill.SkillRuntime.Skill do
  @moduledoc """
  Skill runtime contract and markdown compiler.

  Phase 6 adds default route dispatch and pre/post hook emission for
  compiled skill modules.
  """

  @callback mount(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback router(keyword()) :: [{String.t(), term()}]
  @callback handle_signal(term(), keyword()) :: {:ok, term()} | {:skip, term()} | {:error, term()}
  @callback transform_result(term(), term(), keyword()) ::
              {:ok, term(), list()} | {:error, term()}

  defmacro __using__(opts) do
    quote do
      @behaviour JidoSkill.SkillRuntime.Skill

      alias Jido.Instruction
      alias JidoSkill.SkillRuntime.HookEmitter

      @skill_name unquote(opts[:name])
      @skill_description unquote(opts[:description])
      @skill_version unquote(opts[:version])
      @skill_router unquote(opts[:router] || [])
      @skill_hooks unquote(opts[:hooks] || %{})
      @skill_actions unquote(opts[:actions] || [])

      @doc false
      def skill_metadata do
        %{
          name: @skill_name,
          description: @skill_description,
          version: @skill_version,
          router: @skill_router,
          hooks: @skill_hooks,
          actions: @skill_actions
        }
      end

      @impl JidoSkill.SkillRuntime.Skill
      def mount(context, _config), do: {:ok, context}

      @impl JidoSkill.SkillRuntime.Skill
      def router(_config), do: @skill_router

      @impl JidoSkill.SkillRuntime.Skill
      def handle_signal(signal, skill_opts) do
        case find_matching_route(signal, @skill_router) do
          nil ->
            {:skip, signal}

          {route, action} ->
            global_hooks = Keyword.get(skill_opts, :global_hooks, %{})

            :ok =
              HookEmitter.emit_pre(
                @skill_name,
                route,
                @skill_hooks,
                global_hooks
              )

            signal_data = extract_signal_data(signal)

            case Instruction.new(
                   action: action,
                   params: signal_data,
                   context: %{"jido_skill_route" => route}
                 ) do
              {:ok, instruction} -> {:ok, instruction}
              {:error, reason} -> {:error, {:instruction_build_failed, reason}}
            end
        end
      end

      @impl JidoSkill.SkillRuntime.Skill
      def transform_result(result, action, skill_opts) do
        global_hooks = Keyword.get(skill_opts, :global_hooks, %{})
        route = route_for_action(action, @skill_router)
        status = status_for_result(result)

        :ok =
          HookEmitter.emit_post(
            @skill_name,
            route,
            status,
            @skill_hooks,
            global_hooks
          )

        {:ok, result, []}
      end

      defp find_matching_route(signal, router) do
        normalized_signal_type =
          signal
          |> signal_type()
          |> normalize_route_path()

        Enum.find(router, fn {route, _action} ->
          normalize_route_path(route) == normalized_signal_type
        end)
      end

      defp signal_type(%{type: type}) when is_binary(type), do: type
      defp signal_type(%{"type" => type}) when is_binary(type), do: type
      defp signal_type(_signal), do: nil

      defp normalize_route_path(path) when is_binary(path), do: String.replace(path, ".", "/")
      defp normalize_route_path(_path), do: nil

      defp extract_signal_data(%{data: data}) when is_map(data), do: data
      defp extract_signal_data(%{"data" => data}) when is_map(data), do: data
      defp extract_signal_data(_signal), do: %{}

      defp route_for_action(%Instruction{} = instruction, router) do
        case instruction_route(instruction) do
          route when is_binary(route) and route != "" ->
            route

          _ ->
            route_for_action(instruction.action, router)
        end
      end

      defp route_for_action(action, router) do
        action_module = action_module(action)

        case Enum.find(router, fn {_route, candidate_action} ->
               candidate_action == action_module
             end) do
          {route, _candidate_action} -> route
          nil -> "unknown"
        end
      end

      defp action_module(%Instruction{action: action}), do: action
      defp action_module(action) when is_atom(action), do: action
      defp action_module(_action), do: nil

      defp instruction_route(%Instruction{context: context}) when is_map(context) do
        Map.get(context, "jido_skill_route") || Map.get(context, :jido_skill_route)
      end

      defp instruction_route(_instruction), do: nil

      defp status_for_result({:error, _reason}), do: "error"
      defp status_for_result(:error), do: "error"
      defp status_for_result(_result), do: "ok"

      defoverridable mount: 2, router: 1, handle_signal: 2, transform_result: 3
    end
  end

  @spec from_markdown(String.t()) :: {:ok, module()} | {:error, term()}
  def from_markdown(path) do
    with {:ok, content} <- File.read(path),
         {:ok, frontmatter, body} <- split_frontmatter(content),
         {:ok, parsed} <- parse_frontmatter(frontmatter),
         :ok <- validate_parsed(parsed),
         {:ok, module_name} <- resolve_module_name(parsed, path),
         {:ok, normalized} <- normalize_parsed(parsed),
         :ok <- ensure_actions_loaded(normalized.actions),
         :ok <- validate_router_actions(normalized.router, normalized.actions) do
      compile_module(module_name, normalized, body, path)
    end
  end

  defp split_frontmatter(content) do
    case Regex.named_captures(~r/\A---\s*\n(?<frontmatter>.*?)\n---\s*\n?(?<body>.*)\z/s, content) do
      %{"frontmatter" => frontmatter, "body" => body} -> {:ok, frontmatter, body}
      _ -> {:error, :missing_frontmatter}
    end
  end

  defp parse_frontmatter(frontmatter) do
    lines = String.split(frontmatter, "\n")

    initial = %{
      root: %{},
      jido: %{"actions" => [], "router" => [], "hooks" => %{}},
      mode: :root,
      hook_name: nil,
      in_data: false
    }

    result =
      Enum.reduce_while(lines, {:ok, initial}, fn line, {:ok, state} ->
        case parse_line(line, state) do
          {:ok, new_state} -> {:cont, {:ok, new_state}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, state} ->
        {:ok, Map.put(state.root, "jido", state.jido)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_line(line, state) do
    cond do
      blank_or_comment?(line) ->
        {:ok, state}

      Regex.match?(~r/^\S/, line) ->
        parse_root_line(line, %{state | mode: :root, hook_name: nil, in_data: false})

      Regex.match?(~r/^  \S/, line) ->
        parse_jido_line(line, %{state | in_data: false})

      Regex.match?(~r/^    \S/, line) ->
        parse_nested_line(line, state)

      Regex.match?(~r/^      \S/, line) ->
        parse_hook_property_line(line, state)

      Regex.match?(~r/^        \S/, line) ->
        parse_hook_data_line(line, state)

      true ->
        {:ok, state}
    end
  end

  defp parse_root_line(line, state) do
    case Regex.run(~r/^(name|description|version|allowed-tools|jido):\s*(.*?)\s*$/, line,
           capture: :all_but_first
         ) do
      ["jido", _] ->
        {:ok, %{state | mode: :jido}}

      [key, value] ->
        {:ok, %{state | root: Map.put(state.root, key, strip_quotes(value))}}

      _ ->
        {:error, {:invalid_frontmatter_line, line}}
    end
  end

  defp parse_jido_line("  actions:", state), do: {:ok, %{state | mode: :actions}}
  defp parse_jido_line("  router:", state), do: {:ok, %{state | mode: :router}}

  defp parse_jido_line("  hooks:", state),
    do: {:ok, %{state | mode: :hooks, hook_name: nil, in_data: false}}

  defp parse_jido_line(line, state) do
    case Regex.run(~r/^  ([A-Za-z0-9_]+):\s*(.*?)\s*$/, line, capture: :all_but_first) do
      ["skill_module", value] ->
        {:ok,
         %{state | jido: Map.put(state.jido, "skill_module", strip_quotes(value)), mode: :jido}}

      [key, _value] ->
        {:error, {:unknown_jido_key, key}}

      _ ->
        {:error, {:invalid_jido_line, line}}
    end
  end

  defp parse_nested_line(line, %{mode: :actions} = state) do
    case Regex.run(~r/^    -\s*(.+?)\s*$/, line, capture: :all_but_first) do
      [action] ->
        actions = state.jido["actions"] ++ [strip_quotes(action)]
        {:ok, put_in(state, [:jido, "actions"], actions)}

      _ ->
        {:error, {:invalid_action_line, line}}
    end
  end

  defp parse_nested_line(line, %{mode: :router} = state) do
    case Regex.run(~r/^    -\s*"?([^":]+)"?\s*:\s*(.+?)\s*$/, line, capture: :all_but_first) do
      [path, action_ref] ->
        router = state.jido["router"] ++ [{strip_quotes(path), strip_quotes(action_ref)}]
        {:ok, put_in(state, [:jido, "router"], router)}

      _ ->
        {:error, {:invalid_router_line, line}}
    end
  end

  defp parse_nested_line(line, %{mode: :hooks} = state) do
    case Regex.run(~r/^    (pre|post):\s*$/, line, capture: :all_but_first) do
      [hook_name] ->
        hooks = Map.put_new(state.jido["hooks"], hook_name, %{})

        {:ok,
         %{
           state
           | jido: Map.put(state.jido, "hooks", hooks),
             hook_name: hook_name,
             in_data: false
         }}

      _ ->
        {:error, {:invalid_hook_line, line}}
    end
  end

  defp parse_nested_line(_line, state), do: {:ok, state}

  defp parse_hook_property_line("      data:", %{mode: :hooks, hook_name: hook_name} = state)
       when is_binary(hook_name) do
    {:ok, %{state | in_data: true}}
  end

  defp parse_hook_property_line(line, %{mode: :hooks, hook_name: hook_name} = state)
       when is_binary(hook_name) do
    case Regex.run(~r/^      ([A-Za-z0-9_-]+):\s*(.*?)\s*$/, line, capture: :all_but_first) do
      [key, value] ->
        hooks =
          update_in(
            state.jido["hooks"],
            [hook_name],
            &Map.put(&1 || %{}, key, coerce_scalar(value))
          )

        {:ok, %{state | jido: Map.put(state.jido, "hooks", hooks), in_data: false}}

      _ ->
        {:error, {:invalid_hook_property_line, line}}
    end
  end

  defp parse_hook_property_line(_line, state), do: {:ok, state}

  defp parse_hook_data_line(line, %{mode: :hooks, hook_name: hook_name, in_data: true} = state)
       when is_binary(hook_name) do
    case Regex.run(~r/^        ([A-Za-z0-9_-]+):\s*(.*?)\s*$/, line, capture: :all_but_first) do
      [key, value] ->
        hooks =
          update_in(state.jido["hooks"], [hook_name], fn hook ->
            hook = hook || %{}
            data = Map.get(hook, "data", %{})
            Map.put(hook, "data", Map.put(data, key, coerce_scalar(value)))
          end)

        {:ok, %{state | jido: Map.put(state.jido, "hooks", hooks)}}

      _ ->
        {:error, {:invalid_hook_data_line, line}}
    end
  end

  defp parse_hook_data_line(_line, state), do: {:ok, state}

  defp validate_parsed(parsed) do
    with :ok <- required_string(parsed, "name"),
         :ok <- required_string(parsed, "description"),
         :ok <- required_version(parsed["version"]) do
      validate_jido(parsed["jido"])
    end
  end

  defp validate_jido(nil), do: {:error, :missing_jido_section}

  defp validate_jido(jido) do
    actions = Map.get(jido, "actions", [])
    router = Map.get(jido, "router", [])
    hooks = Map.get(jido, "hooks", %{})

    cond do
      not is_list(actions) or actions == [] -> {:error, :missing_actions}
      not is_list(router) or router == [] -> {:error, :missing_router}
      true -> validate_jido_details(jido, actions, router, hooks)
    end
  end

  defp validate_jido_details(jido, actions, router, hooks) do
    with :ok <- validate_allowed_jido_keys(jido),
         :ok <- validate_skill_module(Map.get(jido, "skill_module")),
         :ok <- validate_actions(actions),
         :ok <- validate_router(router) do
      validate_hooks_config(hooks)
    end
  end

  defp validate_allowed_jido_keys(jido) do
    allowed = MapSet.new(["skill_module", "actions", "router", "hooks"])

    unknown_keys =
      jido
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(allowed, &1))

    case unknown_keys do
      [] -> :ok
      keys -> {:error, {:unknown_jido_keys, keys}}
    end
  end

  defp validate_actions(actions) do
    invalid =
      Enum.reject(actions, fn action ->
        is_binary(action) and Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_.]*$/, action)
      end)

    case invalid do
      [] -> :ok
      entries -> {:error, {:invalid_action_entries, entries}}
    end
  end

  defp validate_skill_module(nil), do: :ok

  defp validate_skill_module(value) when is_binary(value) do
    if Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_.]*$/, value) do
      :ok
    else
      {:error, {:invalid_skill_module, value}}
    end
  end

  defp validate_skill_module(value), do: {:error, {:invalid_skill_module, value}}

  defp validate_router(router) do
    result =
      Enum.reduce_while(router, :ok, fn entry, :ok ->
        case validate_router_entry(entry) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end)

    case result do
      :ok -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp validate_router_entry({path, action_ref}) do
    cond do
      not (is_binary(path) and Regex.match?(~r/^[a-z0-9_-]+(?:\/[a-z0-9_-]+)*$/, path)) ->
        {:error, {:invalid_router_path, path}}

      not (is_binary(action_ref) and Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_.]*$/, action_ref)) ->
        {:error, {:invalid_router_action_ref, action_ref}}

      true ->
        :ok
    end
  end

  defp validate_router_entry(other), do: {:error, {:invalid_router_entry, other}}

  defp validate_hooks_config(hooks) when hooks in [%{}, nil], do: :ok

  defp validate_hooks_config(hooks) when is_map(hooks) do
    with :ok <- validate_hook_names(hooks) do
      validate_hook_entries(hooks)
    end
  end

  defp validate_hooks_config(other), do: {:error, {:invalid_hooks_config, other}}

  defp validate_hook_names(hooks) do
    allowed = MapSet.new(["pre", "post"])

    unknown =
      hooks
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(allowed, &1))

    case unknown do
      [] -> :ok
      keys -> {:error, {:unknown_hook_names, keys}}
    end
  end

  defp validate_hook_entries(hooks) do
    hooks
    |> Enum.reduce_while(:ok, fn {name, hook}, :ok ->
      case validate_hook_entry(name, hook) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      :ok -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp validate_hook_entry(name, hook) when is_map(hook) do
    with :ok <- validate_hook_keys(name, hook),
         :ok <- validate_hook_enabled(name, Map.get(hook, "enabled")),
         :ok <- validate_hook_signal_type(name, Map.get(hook, "signal_type")),
         :ok <- validate_hook_bus(name, Map.get(hook, "bus")) do
      validate_hook_data(name, Map.get(hook, "data"))
    end
  end

  defp validate_hook_entry(name, hook), do: {:error, {:invalid_hook_config, name, hook}}

  defp validate_hook_keys(name, hook) do
    allowed = MapSet.new(["enabled", "signal_type", "bus", "data"])

    unknown =
      hook
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(allowed, &1))

    case unknown do
      [] -> :ok
      keys -> {:error, {:unknown_hook_keys, name, keys}}
    end
  end

  defp validate_hook_enabled(_name, nil), do: :ok
  defp validate_hook_enabled(_name, value) when is_boolean(value), do: :ok
  defp validate_hook_enabled(name, value), do: {:error, {:invalid_hook_enabled, name, value}}

  defp validate_hook_signal_type(_name, nil), do: :ok

  defp validate_hook_signal_type(_name, value) when is_binary(value) do
    if Regex.match?(~r/^[a-z0-9_]+(?:\/[a-z0-9_]+)*$/, value) do
      :ok
    else
      {:error, {:invalid_hook_signal_type, value}}
    end
  end

  defp validate_hook_signal_type(name, value),
    do: {:error, {:invalid_hook_signal_type, name, value}}

  defp validate_hook_bus(_name, nil), do: :ok
  defp validate_hook_bus(_name, value) when is_atom(value), do: :ok

  defp validate_hook_bus(_name, value) when is_binary(value) do
    if Regex.match?(~r/^:?[A-Za-z_][A-Za-z0-9_]*$/, value) do
      :ok
    else
      {:error, {:invalid_hook_bus, value}}
    end
  end

  defp validate_hook_bus(name, value), do: {:error, {:invalid_hook_bus, name, value}}

  defp validate_hook_data(_name, nil), do: :ok

  defp validate_hook_data(_name, data) when is_map(data) do
    if Enum.all?(data, fn {_key, value} ->
         is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value)
       end) do
      :ok
    else
      {:error, :invalid_hook_data}
    end
  end

  defp validate_hook_data(name, value), do: {:error, {:invalid_hook_data, name, value}}

  defp required_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> :ok
      _ -> {:error, {:missing_required_field, key}}
    end
  end

  defp required_version(version) when is_binary(version) do
    if Regex.match?(~r/^\d+\.\d+\.\d+$/, version) do
      :ok
    else
      {:error, {:invalid_version, version}}
    end
  end

  defp required_version(version), do: {:error, {:invalid_version, version}}

  defp normalize_parsed(parsed) do
    actions = Map.get(parsed["jido"], "actions", [])

    with {:ok, action_modules, action_lookup} <- normalize_actions(actions),
         {:ok, router} <- normalize_router(parsed["jido"]["router"], action_lookup),
         {:ok, hooks} <- normalize_hooks(Map.get(parsed["jido"], "hooks", %{})) do
      {:ok,
       %{
         name: parsed["name"],
         description: parsed["description"],
         version: parsed["version"],
         allowed_tools: normalize_allowed_tools(Map.get(parsed, "allowed-tools", "")),
         actions: action_modules,
         router: router,
         hooks: hooks
       }}
    end
  end

  defp normalize_actions(actions) do
    result =
      Enum.reduce_while(actions, {:ok, [], %{}}, fn action_ref, {:ok, modules, lookup} ->
        case action_module_from_ref(action_ref) do
          {:ok, module} ->
            short = module |> Module.split() |> List.last()
            {:cont, {:ok, modules ++ [module], Map.put(lookup, short, module)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, modules, lookup} -> {:ok, modules, lookup}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_router(router_entries, action_lookup) do
    result =
      Enum.reduce_while(router_entries, {:ok, []}, fn {path, action_ref}, {:ok, acc} ->
        case resolve_router_action(action_ref, action_lookup) do
          {:ok, module} -> {:cont, {:ok, acc ++ [{path, module}]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, router} -> {:ok, router}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_router_action(action_ref, action_lookup) do
    cond do
      Map.has_key?(action_lookup, action_ref) ->
        {:ok, Map.fetch!(action_lookup, action_ref)}

      String.contains?(action_ref, ".") ->
        action_module_from_ref(action_ref)

      true ->
        {:error, {:unknown_router_action, action_ref}}
    end
  end

  defp normalize_hooks(hooks) do
    {:ok,
     %{
       pre: normalize_hook(Map.get(hooks, "pre")),
       post: normalize_hook(Map.get(hooks, "post"))
     }}
  end

  defp normalize_hook(nil), do: nil

  defp normalize_hook(hook) do
    %{
      enabled: Map.get(hook, "enabled"),
      signal_type: Map.get(hook, "signal_type"),
      bus: Map.get(hook, "bus"),
      data: Map.get(hook, "data", %{})
    }
  end

  defp ensure_actions_loaded(actions) do
    unresolved = Enum.reject(actions, &Code.ensure_loaded?/1)

    case unresolved do
      [] -> :ok
      modules -> {:error, {:unresolved_action_modules, modules}}
    end
  end

  defp validate_router_actions(router, actions) do
    action_set = MapSet.new(actions)

    unresolved =
      router
      |> Enum.map(fn {_path, action} -> action end)
      |> Enum.reject(&MapSet.member?(action_set, &1))

    case unresolved do
      [] -> :ok
      modules -> {:error, {:router_action_not_declared, modules}}
    end
  end

  defp compile_module(module_name, normalized, body, source_path) do
    with :ok <- purge_module(module_name, source_path) do
      escaped_actions = Macro.escape(normalized.actions)
      escaped_router = Macro.escape(normalized.router)
      escaped_hooks = Macro.escape(normalized.hooks)
      escaped_allowed_tools = Macro.escape(normalized.allowed_tools)

      quoted =
        quote do
          use JidoSkill.SkillRuntime.Skill,
            name: unquote(normalized.name),
            description: unquote(normalized.description),
            version: unquote(normalized.version),
            actions: unquote(escaped_actions),
            router: unquote(escaped_router),
            hooks: unquote(escaped_hooks)

          @allowed_tools unquote(escaped_allowed_tools)
          @skill_body unquote(body)
          @skill_source unquote(source_path)

          def skill_documentation, do: @skill_body
          def allowed_tools, do: @allowed_tools
          def actions, do: unquote(escaped_actions)
          def __jido_skill_compiled__, do: true
          def __jido_skill_source__, do: @skill_source
        end

      {:module, module, _binary, _term} =
        Module.create(module_name, quoted, Macro.Env.location(__ENV__))

      {:ok, module}
    end
  rescue
    error -> {:error, {:module_compile_exception, error}}
  end

  defp purge_module(module_name, source_path) do
    if Code.ensure_loaded?(module_name) do
      purge_loaded_module(module_name, source_path)
    else
      :ok
    end
  end

  defp purge_loaded_module(module_name, source_path) do
    case compiled_module_source(module_name) do
      {:ok, ^source_path} ->
        purge_existing_module(module_name)

      {:ok, existing_source} ->
        {:error, {:skill_module_conflict, module_name, existing_source}}

      :unknown ->
        purge_unknown_loaded_module(module_name)
    end
  end

  defp purge_unknown_loaded_module(module_name) do
    if generated_module_name?(module_name) do
      purge_existing_module(module_name)
    else
      {:error, {:skill_module_already_defined, module_name}}
    end
  end

  defp purge_existing_module(module_name) do
    :code.purge(module_name)
    :code.delete(module_name)
    :ok
  end

  defp compiled_module_source(module_name) do
    if function_exported?(module_name, :__jido_skill_compiled__, 0) and
         function_exported?(module_name, :__jido_skill_source__, 0) and
         module_name.__jido_skill_compiled__() == true do
      {:ok, module_name.__jido_skill_source__()}
    else
      :unknown
    end
  rescue
    _error ->
      :unknown
  catch
    _kind, _reason ->
      :unknown
  end

  defp generated_module_name?(module_name) when is_atom(module_name) do
    module_name
    |> Module.split()
    |> Enum.take(2) == ["JidoSkill", "CompiledSkills"]
  end

  defp action_module_from_ref(action_ref) when is_binary(action_ref) do
    if String.contains?(action_ref, ".") do
      module =
        action_ref
        |> String.trim()
        |> String.trim_leading("Elixir.")
        |> String.split(".")
        |> Module.concat()

      {:ok, module}
    else
      {:error, {:invalid_action_reference, action_ref}}
    end
  end

  defp normalize_allowed_tools(""), do: []

  defp normalize_allowed_tools(tools) when is_binary(tools) do
    tools
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp resolve_module_name(parsed, path) do
    case get_in(parsed, ["jido", "skill_module"]) do
      nil ->
        {:ok, module_name_from_path(path)}

      skill_module ->
        skill_module_from_ref(skill_module)
    end
  end

  defp skill_module_from_ref(skill_module) when is_binary(skill_module) do
    if Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_.]*$/, skill_module) do
      module =
        skill_module
        |> String.trim()
        |> String.trim_leading("Elixir.")
        |> String.split(".")
        |> Module.concat()

      {:ok, module}
    else
      {:error, {:invalid_skill_module, skill_module}}
    end
  end

  defp skill_module_from_ref(skill_module), do: {:error, {:invalid_skill_module, skill_module}}

  defp module_name_from_path(path) do
    hash =
      path
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 10)

    Module.concat([JidoSkill, CompiledSkills, "Skill#{hash}"])
  end

  defp strip_quotes(value) do
    value
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
    |> String.trim_leading("'")
    |> String.trim_trailing("'")
  end

  defp coerce_scalar(value) do
    value = strip_quotes(value)

    cond do
      value == "true" -> true
      value == "false" -> false
      Regex.match?(~r/^\d+$/, value) -> String.to_integer(value)
      true -> value
    end
  end

  defp blank_or_comment?(line) do
    trimmed = String.trim(line)
    trimmed == "" or String.starts_with?(trimmed, "#")
  end
end
