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
      deps: deps()
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
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Database support (optional - user provides their own repo and adapter)
      {:ecto_sql, "~> 3.0", optional: true},
      # Test dependencies
      {:ecto_sqlite3, "~> 0.16", only: :test}
    ]
  end
end
