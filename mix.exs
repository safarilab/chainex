defmodule Chainex.MixProject do
  use Mix.Project

  def project do
    [
      app: :chainex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      preferred_cli_env: [
        "test.integration": :test,
        "test.all": :test
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Aliases for convenience
  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test --exclude integration"],
      "test.integration": ["ecto.create --quiet", "ecto.migrate --quiet", "test --only integration"],
      "test.all": ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # HTTP client for LLM API calls
      {:req, "~> 0.4.0"},
      # JSON handling
      {:jason, "~> 1.4"},
      # Database support (optional - user provides their own repo and adapter)
      {:ecto_sql, "~> 3.0", optional: true},
      # Test dependencies
      {:ecto_sqlite3, "~> 0.16", only: :test},
      {:bypass, "~> 2.1", only: :test},
      # Development dependencies
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false}
    ]
  end
end
