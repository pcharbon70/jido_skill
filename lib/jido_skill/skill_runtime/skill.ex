defmodule JidoSkill.SkillRuntime.Skill do
  @moduledoc """
  Skill runtime contract and markdown compiler.

  Phase 4 implements frontmatter parsing and dynamic module compilation.
  """

  @callback mount(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback router(keyword()) :: [{String.t(), term()}]
  @callback handle_signal(term(), keyword()) :: {:ok, term()} | {:skip, term()} | {:error, term()}
  @callback transform_result(term(), term(), keyword()) ::
              {:ok, term(), list()} | {:error, term()}

  defmacro __using__(opts) do
    quote do
      @behaviour JidoSkill.SkillRuntime.Skill

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
      def handle_signal(signal, _skill_opts), do: {:skip, signal}

      @impl JidoSkill.SkillRuntime.Skill
      def transform_result(result, _action, _skill_opts), do: {:ok, result, []}

      defoverridable mount: 2, router: 1, handle_signal: 2, transform_result: 3
    end
  end

  @spec from_markdown(String.t()) :: {:ok, module()} | {:error, term()}
  def from_markdown(path) do
    with {:ok, content} <- File.read(path),
         {:ok, frontmatter, body} <- split_frontmatter(content),
         {:ok, parsed} <- parse_frontmatter(frontmatter),
         :ok <- validate_parsed(parsed),
         {:ok, normalized} <- normalize_parsed(parsed),
         module_name <- module_name_from_path(path),
         :ok <- ensure_actions_loaded(normalized.actions),
         :ok <- validate_router_actions(normalized.router, normalized.actions),
         {:ok, compiled_module} <- compile_module(module_name, normalized, body) do
      {:ok, compiled_module}
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
    case Regex.run(~r/^  (skill_module):\s*(.*?)\s*$/, line, capture: :all_but_first) do
      [key, value] ->
        {:ok, %{state | jido: Map.put(state.jido, key, strip_quotes(value)), mode: :jido}}

      _ ->
        {:ok, state}
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
         :ok <- required_version(parsed["version"]),
         :ok <- validate_jido(parsed["jido"]) do
      :ok
    end
  end

  defp validate_jido(nil), do: {:error, :missing_jido_section}

  defp validate_jido(jido) do
    actions = Map.get(jido, "actions", [])
    router = Map.get(jido, "router", [])

    cond do
      not is_list(actions) or actions == [] -> {:error, :missing_actions}
      not is_list(router) or router == [] -> {:error, :missing_router}
      true -> :ok
    end
  end

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
      enabled: Map.get(hook, "enabled", true),
      signal_type: Map.get(hook, "signal_type"),
      bus: Map.get(hook, "bus", ":jido_code_bus"),
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

  defp compile_module(module_name, normalized, body) do
    purge_module(module_name)

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

        def skill_documentation, do: @skill_body
        def allowed_tools, do: @allowed_tools
        def actions, do: unquote(escaped_actions)
      end

    case Module.create(module_name, quoted, Macro.Env.location(__ENV__)) do
      {:module, module, _binary, _term} -> {:ok, module}
      {:error, reason} -> {:error, {:module_compile_failed, reason}}
    end
  rescue
    error -> {:error, {:module_compile_exception, error}}
  end

  defp purge_module(module_name) do
    if Code.ensure_loaded?(module_name) do
      :code.purge(module_name)
      :code.delete(module_name)
    end

    :ok
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
