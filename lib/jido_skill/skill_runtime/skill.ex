defmodule JidoSkill.SkillRuntime.Skill do
  @moduledoc """
  Skill runtime contract scaffold.

  Phase 1 defines the callback surface and macro shape used by the next
  implementation phases.
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

      @doc false
      def skill_metadata do
        %{
          name: @skill_name,
          description: @skill_description,
          version: @skill_version,
          router: @skill_router,
          hooks: @skill_hooks
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

  @doc """
  Placeholder for markdown compilation in later phases.
  """
  @spec from_markdown(String.t()) :: {:error, :not_implemented}
  def from_markdown(_path), do: {:error, :not_implemented}
end
