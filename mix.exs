defmodule GrowthBook.MixProject do
  use Mix.Project

  @version "0.1.0"
  @repo_url "https://github.com/jeroenvisser101/growthbook-elixir"

  def project do
    [
      app: :growthbook,
      version: @version,
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),

      # Hex
      package: package(),
      description: "Elixir SDK for GrowthBook",

      # Docs
      name: "GrowthBook",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.27", only: :dev, runtime: false},
      {:jason, "~> 1.3", only: :test, runtime: false},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Jeroen Visser"],
      licenses: ["MIT"],
      links: %{"GitHub" => @repo_url}
    ]
  end

  defp docs do
    [
      main: "GrowthBook",
      logo: "logo.png",
      source_ref: "v#{@version}",
      source_url: @repo_url,
      groups_for_modules: [
        "Public API": [
          GrowthBook,
          GrowthBook.Config,
          GrowthBook.Context
        ],
        Experiments: [
          GrowthBook.Experiment,
          GrowthBook.ExperimentOverride,
          GrowthBook.ExperimentResult
        ],
        Features: [
          GrowthBook.Feature,
          GrowthBook.FeatureResult,
          GrowthBook.FeatureRule
        ],
        "Private API": [GrowthBook.Helpers, GrowthBook.Condition]
      ]
    ]
  end

  defp dialyzer do
    [
      plt_file:
        {:no_warn, ".dialyzer/elixir-#{System.version()}-erlang-otp-#{System.otp_release()}.plt"}
    ]
  end
end
