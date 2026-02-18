defmodule JidoSkill.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_skill,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      dialyzer: [
        flags: [:error_handling, :underspecs, :unknown, :unmatched_returns]
      ],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {JidoSkill.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jido, git: "https://github.com/agentjido/jido"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end
end
