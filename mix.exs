defmodule Chainex.MixProject do
  use Mix.Project

  def project do
    [
      app: :chainex,
      version: "0.1.3",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      preferred_cli_env: [
        "test.integration": :test,
        "test.all": :test
      ],

      # Docs
      name: "Chainex",
      description:
        "A powerful Elixir library for building LLM chains - the Elixir equivalent of LangChain",
      source_url: "https://github.com/safarilab/chainex",
      homepage_url: "https://github.com/safarilab/chainex",
      docs: [
        main: "getting_started",
        logo: "logo.png",
        extras: [
          "README.md",
          "CHANGELOG.md",
          "guides/getting_started.md",
          "guides/memory_guide.md",
          "guides/tools_guide.md",
          "guides/parsing_guide.md",
          "guides/error_handling_guide.md"
        ],
        groups_for_extras: [
          Guides: [
            "guides/getting_started.md",
            "guides/memory_guide.md",
            "guides/tools_guide.md",
            "guides/parsing_guide.md",
            "guides/error_handling_guide.md"
          ]
        ],
        groups_for_modules: [
          Core: [
            Chainex.Chain
          ],
          "LLM Providers": [
            Chainex.LLM,
            Chainex.LLM.Anthropic,
            Chainex.LLM.OpenAI,
            Chainex.LLM.Mock
          ],
          Memory: [
            Chainex.Memory,
            Chainex.Memory.Database
          ],
          Tools: [
            Chainex.Tool
          ],
          Utilities: [
            Chainex.Chain.Executor,
            Chainex.Chain.VariableResolver
          ]
        ]
      ],
      package: [
        name: "chainex",
        description:
          "A powerful Elixir library for building LLM chains - the Elixir equivalent of LangChain",
        licenses: ["MIT"],
        links: %{
          "GitHub" => "https://github.com/safarilab/chainex",
          "Documentation" => "https://hexdocs.pm/chainex"
        },
        maintainers: ["Reza Safari"],
        files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md logo.png)
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
      "test.integration": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "test --only integration"
      ],
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
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
