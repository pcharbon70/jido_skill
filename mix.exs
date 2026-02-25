defmodule Jido.Code.Skill.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_skill,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: "Skill-only runtime for Jido-based markdown skills with signal-first dispatch.",
      package: package(),
      source_url: "https://github.com/pcharbon70/jido_skill",
      homepage_url: "https://github.com/pcharbon70/jido_skill",
      docs: docs(),
      escript: escript(),
      dialyzer: [
        flags: [:error_handling, :underspecs, :unknown, :unmatched_returns],
        plt_add_apps: [:mix]
      ],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Code.Skill.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jido, "~> 2.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/pcharbon70/jido_skill",
        "Changelog" => "https://github.com/pcharbon70/jido_skill/blob/main/CHANGELOG.md"
      },
      files: ~w(lib docs .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "docs/user/README.md",
        "docs/developer/README.md"
      ]
    ]
  end

  defp escript do
    [
      main_module: Jido.Code.Skill.CLI,
      name: "skill",
      app: nil
    ]
  end
end
